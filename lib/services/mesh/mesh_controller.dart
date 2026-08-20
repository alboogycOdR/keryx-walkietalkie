import 'dart:async';
import 'dart:developer' as developer;

import 'package:keryx/core/floor/effects.dart';
import 'package:keryx/core/floor/floor_engine.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/services/signaling/peer_session.dart';
import 'package:keryx/services/signaling/signaling_envelope.dart';
import 'package:keryx/services/signaling/signaling_service.dart';

import 'floor_data_channel_transport.dart';
import 'mesh_connection.dart';
import 'rtc_adapter.dart';

/// Orchestrates the mesh: one [MeshConnection] per signaled [PeerSession],
/// the shared pre-published-muted local track, and PTT-grant → `enabled`
/// flip (TS §8.5 / FR-020). Consumes [SignalingService] (TASK-020) for
/// offer/answer/ICE relay and [FloorEngine] (TASK-022) for the local-track
/// gate; never invents a parallel signaling or floor-control path.
///
/// Glare-free offer/answer split mirrors [SignalingService]'s own
/// "lower peerId dials" rule: the lower peerId sends the WebRTC offer.
class MeshController {
  MeshController({
    required this.localPeerId,
    required RtcAdapter adapter,
    required SignalingService signaling,
    required FloorEngine floorEngine,
  }) : _adapter = adapter,
       _signaling = signaling,
       _floorEngine = floorEngine {
    _joinedSub = signaling.sessionsJoined.listen(_onPeerJoined);
    _departedSub = signaling.sessionsDeparted.listen(_onPeerDeparted);
    _signalSub = signaling.incomingSignals.listen(_onSignal);
    _effectsSub = _floorEngine.effects.listen(_onFloorEffect);
  }

  static const _logName = 'keryx.mesh';

  final String localPeerId;
  final RtcAdapter _adapter;
  final SignalingService _signaling;
  final FloorEngine _floorEngine;
  final MeshFloorTransport floorTransport = MeshFloorTransport();

  final Map<String, MeshConnection> _connections = <String, MeshConnection>{};
  RtcLocalAudioTrack? _localTrack;

  late final StreamSubscription<PeerSession> _joinedSub;
  late final StreamSubscription<PeerSession> _departedSub;
  late final StreamSubscription<SignalingEnvelope> _signalSub;
  late final StreamSubscription<FloorEffect> _effectsSub;

  bool _disposed = false;

  /// Whether the local track is currently gated open (PTT held).
  bool get isLocalTrackEnabled => _localTrack?.enabled ?? false;

  Future<void> _ensureLocalTrack() async {
    _localTrack ??= await _adapter.getLocalAudioTrack();
  }

  Future<void> _onPeerJoined(PeerSession session) async {
    if (_disposed) return;
    final peerId = session.peerId;
    if (_connections.containsKey(peerId)) return;
    try {
      await _ensureLocalTrack();
      final conn = await _openConnection(peerId);
      if (localPeerId.compareTo(peerId) < 0) {
        final offer = await conn.createOffer();
        _send(
          SignalingType.offer,
          peerId,
          {'sdp': offer.sdp},
        );
      }
      // Higher peerId waits for the remote offer via _onSignal.
    } on Object catch (error, stack) {
      developer.log(
        'mesh: failed to open connection to $peerId: $error',
        name: _logName,
        error: error,
        stackTrace: stack,
      );
    }
  }

  Future<MeshConnection> _openConnection(String peerId) async {
    final pc = await _adapter.createPeerConnection();
    final conn = MeshConnection(
      peerId: peerId,
      pc: pc,
      localTrack: _localTrack!,
      floorTransport: floorTransport,
      onLocalIceCandidate: (candidate) => _sendIce(peerId, candidate),
    );
    _connections[peerId] = conn;
    return conn;
  }

  void _onPeerDeparted(PeerSession session) {
    if (_disposed) return;
    final conn = _connections.remove(session.peerId);
    if (conn != null) unawaited(conn.close());
  }

  Future<void> _onSignal(SignalingEnvelope envelope) async {
    if (_disposed) return;
    final peerId = envelope.from;
    try {
      switch (envelope.type) {
        case SignalingType.offer:
          await _onOffer(peerId, envelope);
        case SignalingType.answer:
          await _onAnswer(peerId, envelope);
        case SignalingType.iceCandidate:
          await _onIceCandidate(peerId, envelope);
        case SignalingType.hello:
        case SignalingType.helloOk:
          break; // handshake — SignalingService's own concern
      }
    } on Object catch (error, stack) {
      developer.log(
        'mesh: signal handling failed from $peerId (${envelope.type.wire}): $error',
        name: _logName,
        error: error,
        stackTrace: stack,
      );
    }
  }

  Future<void> _onOffer(String peerId, SignalingEnvelope envelope) async {
    final sdp = envelope.sdp;
    if (sdp == null) return;
    await _ensureLocalTrack();
    var conn = _connections[peerId];
    conn ??= await _openConnection(peerId);
    final answer = await conn.createAnswer(
      RtcSessionDescription(sdp: sdp, type: 'offer'),
    );
    _send(SignalingType.answer, peerId, {'sdp': answer.sdp});
  }

  Future<void> _onAnswer(String peerId, SignalingEnvelope envelope) async {
    final sdp = envelope.sdp;
    final conn = _connections[peerId];
    if (sdp == null || conn == null) return;
    await conn.acceptAnswer(RtcSessionDescription(sdp: sdp, type: 'answer'));
  }

  Future<void> _onIceCandidate(
    String peerId,
    SignalingEnvelope envelope,
  ) async {
    final candidate = envelope.candidate;
    final conn = _connections[peerId];
    if (candidate == null || conn == null) return;
    final mid = envelope.payload['sdpMid'];
    final lineIndex = envelope.payload['sdpMLineIndex'];
    await conn.addRemoteIceCandidate(
      RtcIceCandidate(
        candidate: candidate,
        sdpMid: mid is String ? mid : null,
        sdpMLineIndex: lineIndex is num ? lineIndex.toInt() : null,
      ),
    );
  }

  void _sendIce(String peerId, RtcIceCandidate candidate) {
    _send(SignalingType.iceCandidate, peerId, {
      'candidate': candidate.candidate,
      if (candidate.sdpMid != null) 'sdpMid': candidate.sdpMid,
      if (candidate.sdpMLineIndex != null)
        'sdpMLineIndex': candidate.sdpMLineIndex,
    });
  }

  void _send(
    SignalingType type,
    String to,
    Map<String, Object?> payload,
  ) {
    final sent = _signaling.sendSignal(
      SignalingEnvelope(
        type: type,
        from: localPeerId,
        to: to,
        payload: payload,
      ),
    );
    if (!sent) {
      developer.log(
        'mesh: sendSignal(${type.wire} -> $to) dropped (no session)',
        name: _logName,
      );
    }
  }

  /// TS §8.5: "the audio track is pre-published muted on channel join; PTT
  /// grant flips `enabled=true`." [FloorEngine] never touches media itself
  /// — it only emits [DispatchRadio] effects; this is the sole place that
  /// flips [_localTrack]'s `enabled` flag, on the grant/end boundary
  /// (`EndTransmit` covers both a normal release and a TOT cut, since
  /// `FloorEngine._endLocalTx` emits it for both).
  void _onFloorEffect(FloorEffect effect) {
    if (effect is! DispatchRadio) return;
    final event = effect.event;
    if (event is TransmitGranted) {
      final track = _localTrack;
      if (track != null) track.enabled = true;
    } else if (event is EndTransmit) {
      final track = _localTrack;
      if (track != null) track.enabled = false;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _joinedSub.cancel();
    await _departedSub.cancel();
    await _signalSub.cancel();
    await _effectsSub.cancel();
    for (final conn in _connections.values) {
      await conn.close();
    }
    _connections.clear();
    await floorTransport.dispose();
    await _localTrack?.dispose();
    _localTrack = null;
  }
}
