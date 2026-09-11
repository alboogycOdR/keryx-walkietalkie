import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show Hkdf, Hmac, SecretKey;

/// Thin abstraction over the subset of `package:livekit_client` this
/// package needs. Exists so [LinkedController] / [LinkMonitor] are unit
/// testable against a fake instead of a real relay connection — mirrors the
/// [RtcAdapter] split in `lib/services/mesh/rtc_adapter.dart`.
///
/// The production implementation ([LiveKitClientAdapter]) is a thin
/// pass-through to `package:livekit_client`; it is exercised on-device /
/// against the live relay, not by this package's unit tests (no network in
/// `flutter test`) — see `test/services/linked/fakes/fake_livekit_adapter.dart`
/// for the fake this package's own tests run against.
abstract class LiveKitAdapter {
  /// Connect to [url] (the relay's LiveKit endpoint) using the short-lived
  /// [jwt] minted by the token service (TASK-003) for one room. TS §8.4:
  /// "One LiveKit room per channel."
  ///
  /// v2 (Technical §5.5): when [e2eeKey] is supplied (the HKDF-derived key
  /// from [deriveE2eeKey]), the implementation must configure the room's
  /// `BaseKeyProvider` with it *before* connecting, so [LiveKitRoom.isEncrypted]
  /// is true once this returns. `null` keeps the room unencrypted (LOCAL's
  /// direct WebRTC path is already DTLS-SRTP and does not go through this
  /// adapter at all).
  Future<LiveKitRoom> connect({
    required String url,
    required String jwt,
    Uint8List? e2eeKey,
  });
}

/// HKDF-SHA256(roomSecret, info `keryx-e2ee-v1`) → 32-byte E2EE key
/// (Technical §5.5). [roomSecret] is the group's 32 random bytes or the
/// 1:1 room's X25519 shared secret — the same input `deriveGroupRoom`/
/// `deriveDirectRoom` (`lib/core/rooms/derivation.dart`) key the room ID
/// off, so knowing the room implies knowing this key and vice versa.
Future<Uint8List> deriveE2eeKey(List<int> roomSecret) async {
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final derived = await hkdf.deriveKey(
    secretKey: SecretKey(roomSecret),
    info: 'keryx-e2ee-v1'.codeUnits,
  );
  final bytes = await derived.extractBytes();
  return Uint8List.fromList(bytes);
}

/// One joined LiveKit room. [LinkedController] owns the pre-published
/// muted track and the data-message floor-control bridge through this.
abstract class LiveKitRoom {
  /// Connection-state transitions (connecting/connected/reconnecting/
  /// disconnected). [LinkMonitor] drives `NO LINK` / chirp events off this.
  Stream<LiveKitConnectionState> get connectionState;

  /// Aggregate connection-quality signal (TS §8.9 S-meter input). Emits
  /// on every quality update the SDK reports for the local participant.
  Stream<LiveKitConnectionQuality> get connectionQuality;

  /// Inbound data messages from any remote participant, already stripped
  /// to raw bytes — [LinkedFloorTransport] decodes them via [FloorCodec].
  Stream<List<int>> get incomingData;

  /// Publish the shared local audio track, muted (TS §8.5 pre-publish —
  /// same ≤ 50 ms attack design as LOCAL). Callers must call this once per
  /// room join and reuse the returned handle to flip `enabled`, never
  /// re-publish.
  Future<LiveKitLocalAudioTrack> publishMutedAudioTrack();

  /// Send a floor-control data message (reliable — floor-control messages
  /// must not silently drop) to every participant in the room.
  Future<void> sendData(List<int> bytes);

  /// Leave the room and release local resources. Idempotent.
  Future<void> disconnect();

  /// v2 (Technical §5.5): true once the room's frames are actually being
  /// encrypted with a key provider. [LinkedController] checks this — not
  /// merely "did I pass a key to connect()" — before publishing, so an
  /// adapter that silently drops E2EE is caught rather than trusted
  /// (V2-NFR-004's "a test proves the adapter refuses to publish without a
  /// key provider").
  bool get isEncrypted;
}

/// The local microphone's published-to-LiveKit handle. `enabled=false`
/// (muted) is the pre-published state; PTT grant flips it to `true` —
/// same flag-flip design as `RtcLocalAudioTrack` in the mesh path, no
/// renegotiation, no re-publish.
abstract class LiveKitLocalAudioTrack {
  bool get enabled;

  set enabled(bool value);
}

enum LiveKitConnectionState { connecting, connected, reconnecting, disconnected }

/// Coarse connection-quality bucket, mapped to S1–S9 by the telemetry tap.
enum LiveKitConnectionQuality { excellent, good, poor, lost, unknown }
