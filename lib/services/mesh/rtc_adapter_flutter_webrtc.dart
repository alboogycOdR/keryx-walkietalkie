import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

import 'mesh_config.dart';
import 'opus_sdp.dart';
import 'rtc_adapter.dart';

/// Production [RtcAdapter]: a thin pass-through to `package:flutter_webrtc`.
/// Exercised on-device / by integration testing, not by this package's unit
/// suite (no platform channel under `flutter test`) — see
/// `test/services/mesh/fakes/fake_rtc_adapter.dart` for the fake this
/// package's own tests run against.
class FlutterWebrtcAdapter implements RtcAdapter {
  const FlutterWebrtcAdapter();

  @override
  Future<RtcLocalAudioTrack> getLocalAudioTrack() async {
    // ORCH-direct field fix (2026-09-06): the two-phone field test
    // (2026-08-23 handover) found peer discovery working but no audio
    // flowing on PTT. Nothing anywhere in this codebase ever configured
    // WebRTC's audio session/routing — flutter_webrtc's native engine can
    // default an unconfigured Android session to the earpiece at a very
    // low level (or leave AudioManager in MODE_NORMAL), which reads
    // exactly like "no audio" on a device this isn't held up to the ear
    // for. `manageAudioFocus: false` because `RadioForegroundService.kt`
    // already owns a AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK request with the
    // same VOICE_COMMUNICATION/SPEECH attributes — a second, conflicting
    // focus request from here (the `.communication` preset's default
    // `AudioFocusMode.gain`) would fight it. iOS has no earpiece-default
    // failure mode analogous to this (AVAudioSession routes voice-chat
    // audio to the speaker by default), so this is Android-only; a no-op
    // call on iOS is harmless (`WebRTC.platformIsAndroid` guards it).
    await webrtc.Helper.setAndroidAudioConfiguration(
      webrtc.AndroidAudioConfiguration(
        manageAudioFocus: false,
        androidAudioMode: webrtc.AndroidAudioMode.inCommunication,
        androidAudioStreamType: webrtc.AndroidAudioStreamType.voiceCall,
        androidAudioAttributesUsageType:
            webrtc.AndroidAudioAttributesUsageType.voiceCommunication,
        androidAudioAttributesContentType:
            webrtc.AndroidAudioAttributesContentType.speech,
      ),
    );
    // A hand-held walkie-talkie is meant to be heard without holding the
    // phone to the ear — force loudspeaker routing rather than trusting
    // whatever the (now-configured) communication mode defaults to.
    await webrtc.Helper.setSpeakerphoneOn(true);

    final stream = await webrtc.navigator.mediaDevices.getUserMedia({
      'audio': MeshConfig.audioConstraints,
      'video': false,
    });
    final tracks = stream.getAudioTracks();
    if (tracks.isEmpty) {
      throw StateError('getUserMedia returned no audio track');
    }
    return _FlutterWebrtcLocalAudioTrack(stream, tracks.first);
  }

  @override
  Future<RtcPeerConnection> createPeerConnection() async {
    final pc = await webrtc.createPeerConnection(<String, dynamic>{
      'iceServers': MeshConfig.iceServers,
      'sdpSemantics': 'unified-plan',
    });
    return _FlutterWebrtcPeerConnection(pc);
  }
}

class _FlutterWebrtcLocalAudioTrack implements RtcLocalAudioTrack {
  _FlutterWebrtcLocalAudioTrack(this._stream, this._track) {
    // Pre-published *muted* on capture (TS §8.5) — callers still control
    // `enabled` explicitly, but starting muted means a bug that forgets to
    // set it fails safe (silent), not loud.
    _track.enabled = false;
  }

  final webrtc.MediaStream _stream;
  final webrtc.MediaStreamTrack _track;

  webrtc.MediaStreamTrack get track => _track;

  @override
  bool get enabled => _track.enabled;

  @override
  set enabled(bool value) => _track.enabled = value;

  @override
  Future<void> dispose() async {
    await _track.stop();
    await _stream.dispose();
  }
}

class _FlutterWebrtcPeerConnection implements RtcPeerConnection {
  _FlutterWebrtcPeerConnection(this._pc) {
    _pc.onIceCandidate = (webrtc.RTCIceCandidate candidate) {
      final c = candidate.candidate;
      if (c == null || c.isEmpty) return; // end-of-candidates marker
      onIceCandidate?.call(
        RtcIceCandidate(
          candidate: c,
          sdpMid: candidate.sdpMid,
          sdpMLineIndex: candidate.sdpMLineIndex,
        ),
      );
    };
    _pc.onDataChannel = (webrtc.RTCDataChannel channel) {
      onDataChannel?.call(_FlutterWebrtcDataChannel(channel));
    };
    _pc.onConnectionState = (webrtc.RTCPeerConnectionState state) {
      onConnectionState?.call(_mapState(state));
    };
  }

  final webrtc.RTCPeerConnection _pc;

  @override
  void Function(RtcIceCandidate candidate)? onIceCandidate;

  @override
  void Function(RtcDataChannel channel)? onDataChannel;

  @override
  void Function(RtcPeerConnectionState state)? onConnectionState;

  @override
  Future<void> addAudioTrack(RtcLocalAudioTrack track) async {
    final local = track as _FlutterWebrtcLocalAudioTrack;
    await _pc.addTrack(local.track, local._stream);
  }

  @override
  Future<RtcDataChannel> createDataChannel(String label) async {
    final init = webrtc.RTCDataChannelInit()..ordered = true;
    final channel = await _pc.createDataChannel(label, init);
    return _FlutterWebrtcDataChannel(channel);
  }

  @override
  Future<RtcSessionDescription> createOffer() async {
    final offer = await _pc.createOffer();
    final munged = OpusSdp.applyProfile(offer.sdp ?? '');
    return RtcSessionDescription(sdp: munged, type: offer.type ?? 'offer');
  }

  @override
  Future<RtcSessionDescription> createAnswer() async {
    final answer = await _pc.createAnswer();
    final munged = OpusSdp.applyProfile(answer.sdp ?? '');
    return RtcSessionDescription(sdp: munged, type: answer.type ?? 'answer');
  }

  @override
  Future<void> setLocalDescription(RtcSessionDescription description) {
    return _pc.setLocalDescription(
      webrtc.RTCSessionDescription(description.sdp, description.type),
    );
  }

  @override
  Future<void> setRemoteDescription(RtcSessionDescription description) {
    return _pc.setRemoteDescription(
      webrtc.RTCSessionDescription(description.sdp, description.type),
    );
  }

  @override
  Future<void> addIceCandidate(RtcIceCandidate candidate) {
    return _pc.addCandidate(
      webrtc.RTCIceCandidate(
        candidate.candidate,
        candidate.sdpMid,
        candidate.sdpMLineIndex,
      ),
    );
  }

  @override
  Future<void> close() => _pc.close();

  static RtcPeerConnectionState _mapState(webrtc.RTCPeerConnectionState state) {
    switch (state) {
      case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
      case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateNew:
        return RtcPeerConnectionState.connecting;
      case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return RtcPeerConnectionState.connected;
      case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return RtcPeerConnectionState.disconnected;
      case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        return RtcPeerConnectionState.failed;
      case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        return RtcPeerConnectionState.closed;
    }
  }
}

class _FlutterWebrtcDataChannel implements RtcDataChannel {
  _FlutterWebrtcDataChannel(this._channel) {
    _channel.onMessage = (webrtc.RTCDataChannelMessage message) {
      if (!message.isBinary) onMessage?.call(message.text);
    };
    _channel.onDataChannelState = (webrtc.RTCDataChannelState state) {
      if (state == webrtc.RTCDataChannelState.RTCDataChannelOpen) {
        _isOpen = true;
        onOpen?.call();
      } else if (state == webrtc.RTCDataChannelState.RTCDataChannelClosed) {
        _isOpen = false;
        onClose?.call();
      }
    };
  }

  final webrtc.RTCDataChannel _channel;
  bool _isOpen = false;

  @override
  void Function(String text)? onMessage;

  @override
  void Function()? onOpen;

  @override
  void Function()? onClose;

  @override
  bool get isOpen => _isOpen;

  @override
  void send(String text) {
    _channel.send(webrtc.RTCDataChannelMessage(text));
  }

  @override
  Future<void> close() => _channel.close();
}
