import 'dart:async';

/// Thin abstraction over the subset of `package:flutter_webrtc` this
/// package needs. Exists so [MeshConnection] / [MeshController] are unit
/// testable against a fake instead of a platform channel — mirrors the
/// [SignalingEndpoint] / [SignalingChannel] split in
/// `lib/services/signaling/signaling_channel.dart`.
///
/// The production implementation ([FlutterWebrtcAdapter]) is a thin
/// pass-through to `package:flutter_webrtc`; it is exercised on-device, not
/// by this package's unit tests (no platform channel in `flutter test`).
abstract class RtcAdapter {
  /// Capture the local microphone once. TS §8.5's "pre-published" trick
  /// only works if the *same* track object is added to every peer
  /// connection, so callers must call this once per app session and reuse
  /// the result — not once per peer.
  Future<RtcLocalAudioTrack> getLocalAudioTrack();

  /// One peer connection, LAN-only ICE (TS §8.3 step 2 — no STUN/TURN).
  Future<RtcPeerConnection> createPeerConnection();
}

/// The local microphone capture. `enabled=false` (muted) is the
/// pre-published state; PTT grant flips it to `true` (FR-020's ≤ 50 ms
/// attack — no renegotiation, no re-publish, just this flag).
abstract class RtcLocalAudioTrack {
  bool get enabled;

  set enabled(bool value);

  Future<void> dispose();
}

/// One peer connection to one remote peer.
abstract class RtcPeerConnection {
  /// Fired for every locally-gathered candidate; forward via
  /// [SignalingService.sendSignal].
  void Function(RtcIceCandidate candidate)? onIceCandidate;

  /// Fired when the remote peer opens the floor-control data channel
  /// (answerer side; the offerer creates it explicitly via
  /// [createDataChannel]).
  void Function(RtcDataChannel channel)? onDataChannel;

  void Function(RtcPeerConnectionState state)? onConnectionState;

  /// Add the shared local track, muted or not — [MeshConnection] controls
  /// `enabled` after this call, never re-adds.
  Future<void> addAudioTrack(RtcLocalAudioTrack track);

  /// Open the floor-control data channel. Only the offerer calls this;
  /// the answerer receives the mirror via [onDataChannel].
  Future<RtcDataChannel> createDataChannel(String label);

  /// Local SDP offer, already munged to the §8.1 Opus profile.
  Future<RtcSessionDescription> createOffer();

  /// Local SDP answer, already munged to the §8.1 Opus profile.
  Future<RtcSessionDescription> createAnswer();

  Future<void> setLocalDescription(RtcSessionDescription description);

  Future<void> setRemoteDescription(RtcSessionDescription description);

  Future<void> addIceCandidate(RtcIceCandidate candidate);

  Future<void> close();
}

enum RtcPeerConnectionState { connecting, connected, disconnected, failed, closed }

class RtcSessionDescription {
  const RtcSessionDescription({required this.sdp, required this.type});

  /// `offer` | `answer`.
  final String type;
  final String sdp;
}

class RtcIceCandidate {
  const RtcIceCandidate({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
}

/// One data-channel endpoint. [MeshFloorTransport] wraps this in
/// [FloorTransport].
abstract class RtcDataChannel {
  void Function(String text)? onMessage;
  void Function()? onOpen;
  void Function()? onClose;

  bool get isOpen;

  void send(String text);

  Future<void> close();
}
