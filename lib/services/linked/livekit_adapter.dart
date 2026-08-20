import 'dart:async';

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
  Future<LiveKitRoom> connect({required String url, required String jwt});
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
