import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show compute;
import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/core/rooms/rooms.dart';
import 'package:keryx/core/state/radio_state.dart';

import 'link_monitor.dart';
import 'linked_floor_transport.dart';
import 'livekit_adapter.dart';
import 'token_client.dart';

const _logName = 'keryx.linked';

/// LINKED-path client (TS §8.4, KRX-052/KRX-055): derive `roomId` (TASK-007),
/// fetch a JWT from the token service (TASK-003), join the LiveKit room with
/// a pre-published muted track, and mirror the SAME `TransmitGranted`/
/// `EndTransmit`-driven `enabled` flip `MeshController` established for the
/// LOCAL mesh (`lib/services/mesh/mesh_controller.dart`) — this is the
/// second, not the first, implementation of that pattern.
///
/// Mirrors [MeshController]'s shape: constructed with an already-built
/// [FloorEngine] (host owns `localPeerId`/clock/TOT), subscribes to its
/// effects for grant mirroring, and separately exposes the concrete
/// [FloorTransport] ([floorTransport], built once a room is joined) for the
/// host to wire into that same engine — the host-level wiring that makes
/// those two line up is out of this task's scope, same as the mesh path's
/// current state (see the 2026-08-20 handover).
class LinkedController {
  LinkedController({
    required LiveKitAdapter adapter,
    required TokenClient tokenClient,
    required Uri relayUrl,
    required String callsign,
    required FloorEngine floorEngine,
    required void Function(RadioEvent event) dispatch,
    Duration linkMonitorInitialBackoff = const Duration(seconds: 1),
    Duration linkMonitorMaxBackoff = const Duration(seconds: 30),
    int linkMonitorMaxAttempts = 5,
  }) : _adapter = adapter,
       _tokenClient = tokenClient,
       _relayUrl = relayUrl,
       _callsign = callsign,
       _floorEngine = floorEngine,
       _dispatch = dispatch,
       _linkMonitorInitialBackoff = linkMonitorInitialBackoff,
       _linkMonitorMaxBackoff = linkMonitorMaxBackoff,
       _linkMonitorMaxAttempts = linkMonitorMaxAttempts {
    _effectsSub = _floorEngine.effects.listen(_onFloorEffect);
  }

  final LiveKitAdapter _adapter;
  final TokenClient _tokenClient;
  final Uri _relayUrl;
  final String _callsign;
  final FloorEngine _floorEngine;
  final void Function(RadioEvent event) _dispatch;
  // Exposed only so tests can drive LinkMonitor's give-up path without
  // waiting through real exponential-backoff delays; production callers
  // rely on the defaults above (matching LinkMonitor's own).
  final Duration _linkMonitorInitialBackoff;
  final Duration _linkMonitorMaxBackoff;
  final int _linkMonitorMaxAttempts;

  late final StreamSubscription<FloorEffect> _effectsSub;

  LiveKitRoom? _room;
  LiveKitLocalAudioTrack? _localTrack;
  LinkedFloorTransport? _floorTransport;
  LinkMonitor? _linkMonitor;
  bool _disposed = false;

  /// The LiveKit-backed [FloorTransport], available once [joinNumbered] /
  /// [joinKeyed] completes. `null` before joining or after [leave].
  LinkedFloorTransport? get floorTransport => _floorTransport;

  bool get isJoined => _room != null;

  /// Whether the local track is currently gated open (PTT held).
  bool get isLocalTrackEnabled => _localTrack?.enabled ?? false;

  /// Join by numbered channel + code (FR-043), deriving `roomId` per TS
  /// §8.7 (cheap HMAC — no isolate offload needed, unlike [joinKeyed]).
  ///
  /// Throws [ForceLocalOnlyException] without attempting a connection when
  /// [forceLocalOnly] is `true` (FR-046 — the TASK-008 setting must
  /// hard-disable this service).
  Future<void> joinNumbered({
    required String region,
    required int channel,
    required int code,
    String? eventToken,
    required bool forceLocalOnly,
  }) async {
    _guardForceLocalOnly(forceLocalOnly);
    final roomId = deriveNumbered(region: region, channel: channel, code: code);
    await _join(roomId, eventToken);
  }

  /// Join by keyed passphrase (FR-043). `deriveKeyed` is ~1–3s of
  /// scrypt-backed pure-Dart computation — TASK-007 follow-up (dd),
  /// MANDATORY: this runs off the UI isolate via [compute], never inline.
  Future<void> joinKeyed({
    required String passphrase,
    String? eventToken,
    required bool forceLocalOnly,
  }) async {
    _guardForceLocalOnly(forceLocalOnly);
    final roomId = await compute(_deriveKeyedOffUiIsolate, passphrase);
    await _join(roomId, eventToken);
  }

  /// Join a room whose `roomId` has already been derived (e.g. TASK-025's
  /// Event QR / `keryx://` deep-link flow decodes a `roomId` directly).
  /// This is the "join-by-derivation API" TASK-025 is expected to consume
  /// rather than re-deriving `roomId` itself.
  ///
  /// v2 (Technical §5.5): pass [roomSecret] (the group secret or 1:1
  /// X25519 shared secret [roomId] was itself derived from,
  /// `lib/core/rooms/derivation.dart`) to require LiveKit E2EE for this
  /// join. When supplied, [ForceLocalOnlyException] aside, the join fails
  /// with [LinkedE2eeUnavailableException] rather than silently falling
  /// back to plaintext if the adapter cannot actually encrypt — this
  /// controller never publishes an unencrypted track for a room a caller
  /// asked to be encrypted (V2-NFR-004).
  Future<void> joinRoomId({
    required String roomId,
    String? eventToken,
    required bool forceLocalOnly,
    List<int>? roomSecret,
  }) async {
    _guardForceLocalOnly(forceLocalOnly);
    await _join(roomId, eventToken, roomSecret: roomSecret);
  }

  void _guardForceLocalOnly(bool forceLocalOnly) {
    if (forceLocalOnly) {
      throw const ForceLocalOnlyException();
    }
  }

  Future<void> _join(String roomId, String? eventToken, {List<int>? roomSecret}) async {
    if (_disposed) throw StateError('LinkedController is disposed');
    final joined = await _connectAndPublish(roomId, eventToken, roomSecret: roomSecret);
    if (_disposed) {
      // dispose() landed while we were awaiting the token/connect/publish
      // chain — unwind rather than adopt a room onto a disposed controller
      // (would otherwise leak a live, published room forever).
      await joined.room.disconnect();
      return;
    }
    await leave(); // release any prior room before adopting the new one
    _room = joined.room;
    _localTrack = joined.track;
    _floorTransport = LinkedFloorTransport(joined.room);
    _linkMonitor = LinkMonitor(
      room: joined.room,
      dispatch: _dispatch,
      // A LiveKit JWT is short-lived (TS §8.4), so a real reconnect must
      // re-mint the token and re-join, not retry the stale one — this is
      // what makes FR-045's auto-fallback-to-LOCAL reachable in production
      // (a null/absent reconnect degrades to LOCAL via LinkMonitor's own
      // give-up path, but a genuinely reachable relay must actually retry).
      reconnect: () => _reconnectRoom(roomId, eventToken, roomSecret: roomSecret),
      initialBackoff: _linkMonitorInitialBackoff,
      maxBackoff: _linkMonitorMaxBackoff,
      maxAttempts: _linkMonitorMaxAttempts,
    );
  }

  /// Mints a fresh token and re-joins [roomId] from scratch (a LiveKit JWT
  /// is short-lived, so reusing the original token on a long outage would
  /// just fail again). Swaps the controller's live room/track/transport in
  /// on success; the caller ([LinkMonitor]) re-attaches its connection-state
  /// listener to the returned room.
  Future<LiveKitRoom> _reconnectRoom(
    String roomId,
    String? eventToken, {
    List<int>? roomSecret,
  }) async {
    final joined = await _connectAndPublish(roomId, eventToken, roomSecret: roomSecret);
    if (_disposed) {
      await joined.room.disconnect();
      throw StateError('LinkedController disposed during reconnect');
    }
    final oldRoom = _room;
    final oldTransport = _floorTransport;
    _room = joined.room;
    _localTrack = joined.track;
    _floorTransport = LinkedFloorTransport(joined.room);
    unawaited(oldTransport?.dispose());
    if (oldRoom != null && !identical(oldRoom, joined.room)) {
      unawaited(
        oldRoom.disconnect().catchError((Object error, StackTrace stack) {
          developer.log(
            'linked: disconnect of pre-reconnect room failed: $error',
            name: _logName,
            error: error,
            stackTrace: stack,
          );
        }),
      );
    }
    return joined.room;
  }

  Future<_JoinedRoom> _connectAndPublish(
    String roomId,
    String? eventToken, {
    List<int>? roomSecret,
  }) async {
    final tokenResponse = await _tokenClient.requestToken(
      roomId: roomId,
      callsign: _callsign,
      eventToken: eventToken,
    );
    final e2eeKey = roomSecret != null ? await deriveE2eeKey(roomSecret) : null;
    final room = await _adapter.connect(
      url: _relayUrl.toString(),
      jwt: tokenResponse.token,
      e2eeKey: e2eeKey,
    );
    if (e2eeKey != null && !room.isEncrypted) {
      // Never publish an unencrypted track for a room the caller asked to
      // be encrypted (V2-NFR-004) — refuse before publishMutedAudioTrack
      // is ever called, so no plaintext frame is ever at risk of going out.
      await room.disconnect();
      throw const LinkedE2eeUnavailableException();
    }
    final LiveKitLocalAudioTrack track;
    try {
      track = await room.publishMutedAudioTrack();
    } on Object {
      await room.disconnect();
      rethrow;
    }
    return _JoinedRoom(room, track);
  }

  void _onFloorEffect(FloorEffect effect) {
    if (effect is! DispatchRadio) return;
    final track = _localTrack;
    if (track == null) return;
    final event = effect.event;
    if (event is TransmitGranted) {
      track.enabled = true;
    } else if (event is EndTransmit) {
      track.enabled = false;
    }
  }

  /// Leave the current room, if any. Idempotent.
  Future<void> leave() async {
    _linkMonitor?.dispose();
    _linkMonitor = null;
    await _floorTransport?.dispose();
    _floorTransport = null;
    final room = _room;
    _room = null;
    _localTrack = null;
    if (room != null) {
      try {
        await room.disconnect();
      } on Object catch (error, stack) {
        developer.log('linked: disconnect on leave failed: $error', name: _logName, error: error, stackTrace: stack);
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _effectsSub.cancel();
    await leave();
  }
}

/// Top-level so it is eligible for `compute()` — must take exactly one
/// argument. Runs `deriveKeyed`'s scrypt stretch off the UI isolate.
String _deriveKeyedOffUiIsolate(String passphrase) =>
    deriveKeyed(passphrase: passphrase);

/// A freshly connected room plus its pre-published muted track — the pair
/// [_join] and [_reconnectRoom] both need to adopt onto the controller.
class _JoinedRoom {
  const _JoinedRoom(this.room, this.track);

  final LiveKitRoom room;
  final LiveKitLocalAudioTrack track;
}

/// FR-046: force-LOCAL-only must hard-disable the LINKED path. Thrown
/// before any network attempt — never a silent no-op.
class ForceLocalOnlyException implements Exception {
  const ForceLocalOnlyException();

  @override
  String toString() =>
      'ForceLocalOnlyException: force-LOCAL-only is enabled (FR-046); refusing to join a LINKED room';
}

/// v2 (Technical §5.5, V2-NFR-004): thrown when [LinkedController.joinRoomId]
/// was given a `roomSecret` (E2EE required) but the connected [LiveKitRoom]
/// reports [LiveKitRoom.isEncrypted] as `false` — the adapter could not, or
/// did not, actually enable encryption. The room is disconnected and no
/// audio track is ever published in this case.
class LinkedE2eeUnavailableException implements Exception {
  const LinkedE2eeUnavailableException();

  @override
  String toString() =>
      'LinkedE2eeUnavailableException: room secret supplied but the adapter '
      'did not enable E2EE (V2-NFR-004); refusing to publish';
}
