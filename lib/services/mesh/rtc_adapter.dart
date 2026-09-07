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
///
/// Incoming remote audio is observed through
/// [RtcPeerConnectionRemoteTracks] (`onRemoteAudioTrack`,
/// [remoteAudioTracks]) rather than members of this class. Existing test
/// fakes `implement` this interface and live outside TASK-065's
/// Owned_Paths; adding members here would break them at compile time.
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

/// One WebRTC stats report, reduced to the fields this adapter inspects.
/// Kept free of `package:flutter_webrtc` so unit tests can construct it.
class RtcStatsReport {
  const RtcStatsReport({required this.type, required this.values});

  /// WebRTC stats `type` (`inbound-rtp`, `media-source`, `outbound-rtp`, …).
  final String type;

  /// Member map. Keys of interest: `kind`, `audioLevel`, `trackIdentifier`.
  final Map<String, Object?> values;
}

/// RX amplitude from a remote audio track (Technical §5.3, UX-FR-027,
/// VT-015).
///
/// [RtcUnavailableAudioLevel] means no verified sample was present.
/// [RtcMeasuredAudioLevel] is only constructed from inbound-rtp
/// `audioLevel` (WebRTC stats spec, linear 0–1). Nothing in this module
/// synthesizes a level from `totalAudioEnergy`, jitter, packet loss, or
/// phase.
sealed class RtcAudioLevel {
  const RtcAudioLevel();

  static const RtcAudioLevel unavailable = RtcUnavailableAudioLevel();
}

/// No usable inbound-rtp `audioLevel` was present on this read.
final class RtcUnavailableAudioLevel extends RtcAudioLevel {
  const RtcUnavailableAudioLevel();

  @override
  bool operator ==(Object other) => other is RtcUnavailableAudioLevel;

  @override
  int get hashCode => (RtcUnavailableAudioLevel).hashCode;

  @override
  String toString() => 'RtcAudioLevel.unavailable';
}

/// A real inbound-rtp `audioLevel` in the spec's linear 0–1 range.
final class RtcMeasuredAudioLevel extends RtcAudioLevel {
  const RtcMeasuredAudioLevel(this.value)
    : assert(value >= 0 && value <= 1, 'WebRTC audioLevel is linear 0–1.');

  final double value;

  @override
  bool operator ==(Object other) =>
      other is RtcMeasuredAudioLevel && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'RtcAudioLevel.measured($value)';
}

/// Per-peer signal quality from this adapter. Always
/// [RtcSignalQuality.unavailable] — inbound-rtp jitter / packetsLost /
/// RTT are not a verified S-meter, and mapping them would be a proxy
/// under a measurement name (UX-FR-045, Technical §5.3).
sealed class RtcSignalQuality {
  const RtcSignalQuality();

  static const RtcSignalQuality unavailable = RtcUnavailableSignalQuality();
}

final class RtcUnavailableSignalQuality extends RtcSignalQuality {
  const RtcUnavailableSignalQuality();

  @override
  bool operator ==(Object other) => other is RtcUnavailableSignalQuality;

  @override
  int get hashCode => (RtcUnavailableSignalQuality).hashCode;

  @override
  String toString() => 'RtcSignalQuality.unavailable';
}

/// An incoming remote audio track surfaced by [RtcAdapter].
///
/// [enabled] mutes/unmutes local playback of this remote track (RX mute).
/// [setVolume] is the platform's native volume control. [readAudioLevel]
/// returns a measured inbound-rtp sample or unavailable — never a proxy.
class RtcRemoteAudioTrack {
  RtcRemoteAudioTrack({
    required this.id,
    bool enabled = true,
    bool muted = false,
    Future<RtcAudioLevel> Function()? readAudioLevel,
    Future<void> Function(double volume)? setVolume,
    void Function(bool enabled)? onEnabledChanged,
  }) : _enabled = enabled,
       _muted = muted,
       _readAudioLevel = readAudioLevel,
       _setVolume = setVolume,
       _onEnabledChanged = onEnabledChanged;

  /// Platform track id. Empty only when the platform supplied none.
  final String id;

  bool _enabled;
  final bool _muted;
  final Future<RtcAudioLevel> Function()? _readAudioLevel;
  final Future<void> Function(double volume)? _setVolume;
  final void Function(bool enabled)? _onEnabledChanged;

  /// Local playback enable. `false` mutes this remote track on this
  /// device; it does not affect the peer's TX path.
  bool get enabled => _enabled;

  set enabled(bool value) {
    _enabled = value;
    _onEnabledChanged?.call(value);
  }

  /// Platform mute snapshot at construction. Not a level metric.
  bool get muted => _muted;

  /// Platform volume. Pass-through to flutter_webrtc `Helper.setVolume`
  /// (libwebrtc `AudioTrack.setVolume`, typically 0–10 with 1.0 = unity).
  /// Not rescaled — a rescale without a verified native range would be a
  /// proxy.
  Future<void> setVolume(double volume) async {
    final setter = _setVolume;
    if (setter == null) return;
    await setter(volume);
  }

  /// Inbound-rtp `audioLevel`, or unavailable. Absence of a reader is
  /// unavailable, not silence.
  Future<RtcAudioLevel> readAudioLevel() async {
    final reader = _readAudioLevel;
    if (reader == null) return const RtcUnavailableAudioLevel();
    return reader();
  }

  /// Always unavailable — see [RtcSignalQuality].
  RtcSignalQuality get signalQuality => const RtcUnavailableSignalQuality();
}

/// Reads inbound-rtp `audioLevel` (WebRTC stats spec, linear 0–1).
///
/// Returns [RtcAudioLevel.unavailable] when no matching inbound-rtp
/// report carries a parseable `audioLevel` in 0–1. Never synthesizes a
/// value from `totalAudioEnergy`, jitter, `packetsLost`, media-source
/// (local TX), or outbound-rtp (Technical §5.3; UX-FR-027/045; VT-015).
///
/// When [trackId] is set, a report whose `trackIdentifier` is present
/// and differs is skipped — another track's level is not a substitute.
RtcAudioLevel audioLevelFromInboundRtpStats(
  Iterable<RtcStatsReport> reports, {
  String? trackId,
}) {
  for (final report in reports) {
    if (report.type != 'inbound-rtp') continue;
    final values = report.values;
    final kind = values['kind'];
    if (kind != null && kind != 'audio') continue;
    if (trackId != null) {
      final ident = values['trackIdentifier'] ?? values['trackId'];
      if (ident != null && ident != trackId) continue;
    }
    final parsed = _parseLinearAudioLevel(values['audioLevel']);
    if (parsed == null) continue;
    return RtcMeasuredAudioLevel(parsed);
  }
  return const RtcUnavailableAudioLevel();
}

double? _parseLinearAudioLevel(Object? raw) {
  final double? n = switch (raw) {
    num v => v.toDouble(),
    String s => double.tryParse(s),
    _ => null,
  };
  if (n == null) return null;
  // Spec range is 0–1. Out-of-range is not a usable measurement; do not
  // rescale 0–10 or dB into the unit interval.
  if (n < 0 || n > 1) return null;
  return n;
}

/// Per-connection remote-track fan-out. Held beside the PC (Expando)
/// rather than as fields on [RtcPeerConnection] — see that class's
/// dartdoc.
class RtcRemoteTrackSurface {
  void Function(RtcRemoteAudioTrack track)? onRemoteAudioTrack;

  final List<RtcRemoteAudioTrack> tracks = <RtcRemoteAudioTrack>[];

  void deliver(RtcRemoteAudioTrack track) {
    tracks.add(track);
    onRemoteAudioTrack?.call(track);
  }
}

final Expando<RtcRemoteTrackSurface> _remoteTrackSurfaces =
    Expando<RtcRemoteTrackSurface>('keryx.RtcRemoteTrackSurface');

/// Remote-track surface for [pc]. Weakly keyed; collected with the PC.
RtcRemoteTrackSurface rtcRemoteTracks(RtcPeerConnection pc) =>
    _remoteTrackSurfaces[pc] ??= RtcRemoteTrackSurface();

/// Remote-track observation on any [RtcPeerConnection], including fakes
/// that `implement` the interface without declaring these members.
extension RtcPeerConnectionRemoteTracks on RtcPeerConnection {
  void Function(RtcRemoteAudioTrack track)? get onRemoteAudioTrack =>
      rtcRemoteTracks(this).onRemoteAudioTrack;

  set onRemoteAudioTrack(void Function(RtcRemoteAudioTrack track)? value) {
    rtcRemoteTracks(this).onRemoteAudioTrack = value;
  }

  List<RtcRemoteAudioTrack> get remoteAudioTracks =>
      rtcRemoteTracks(this).tracks;

  /// Record [track] and notify [onRemoteAudioTrack]. Production unified-plan
  /// `onTrack` wiring calls this; tests inject through it.
  void deliverRemoteAudioTrack(RtcRemoteAudioTrack track) {
    rtcRemoteTracks(this).deliver(track);
  }
}
