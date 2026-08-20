import 'dart:async';

import 'package:keryx/services/mesh/rtc_adapter.dart';

/// In-memory [RtcAdapter] for unit tests. No real WebRTC negotiation — SDP
/// is an opaque marker string, ICE candidates never actually gather, and
/// [FakePeerConnection.close] never talks to a peer. Enough to exercise
/// [MeshConnection] / [MeshController] state machines deterministically.
class FakeRtcAdapter implements RtcAdapter {
  final List<FakeLocalAudioTrack> tracksCreated = [];
  final List<FakePeerConnection> connectionsCreated = [];

  @override
  Future<RtcLocalAudioTrack> getLocalAudioTrack() async {
    final track = FakeLocalAudioTrack();
    tracksCreated.add(track);
    return track;
  }

  @override
  Future<RtcPeerConnection> createPeerConnection() async {
    final pc = FakePeerConnection();
    connectionsCreated.add(pc);
    return pc;
  }
}

class FakeLocalAudioTrack implements RtcLocalAudioTrack {
  bool _enabled = false;
  bool disposed = false;

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) => _enabled = value;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class FakePeerConnection implements RtcPeerConnection {
  @override
  void Function(RtcIceCandidate candidate)? onIceCandidate;

  @override
  void Function(RtcDataChannel channel)? onDataChannel;

  @override
  void Function(RtcPeerConnectionState state)? onConnectionState;

  final List<RtcLocalAudioTrack> tracksAdded = [];
  FakeDataChannel? dataChannel;
  RtcSessionDescription? localDescription;
  RtcSessionDescription? remoteDescription;
  final List<RtcIceCandidate> remoteCandidatesAdded = [];
  bool closed = false;

  /// Test hook: fabricate an inbound data channel (answerer-side
  /// `onDataChannel` callback) as flutter_webrtc would fire it.
  void simulateRemoteDataChannel(FakeDataChannel channel) {
    onDataChannel?.call(channel);
  }

  @override
  Future<void> addAudioTrack(RtcLocalAudioTrack track) async {
    tracksAdded.add(track);
  }

  @override
  Future<RtcDataChannel> createDataChannel(String label) async {
    final channel = FakeDataChannel(label: label);
    dataChannel = channel;
    return channel;
  }

  @override
  Future<RtcSessionDescription> createOffer() async {
    return RtcSessionDescription(sdp: 'fake-offer-sdp', type: 'offer');
  }

  @override
  Future<RtcSessionDescription> createAnswer() async {
    return RtcSessionDescription(sdp: 'fake-answer-sdp', type: 'answer');
  }

  @override
  Future<void> setLocalDescription(RtcSessionDescription description) async {
    localDescription = description;
  }

  @override
  Future<void> setRemoteDescription(RtcSessionDescription description) async {
    remoteDescription = description;
  }

  @override
  Future<void> addIceCandidate(RtcIceCandidate candidate) async {
    remoteCandidatesAdded.add(candidate);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

class FakeDataChannel implements RtcDataChannel {
  FakeDataChannel({required this.label, bool open = true}) : _isOpen = open;

  final String label;
  final List<String> sent = [];
  bool _isOpen;

  @override
  void Function(String text)? onMessage;

  @override
  void Function()? onOpen;

  @override
  void Function()? onClose;

  @override
  bool get isOpen => _isOpen;

  set isOpen(bool value) {
    _isOpen = value;
    if (value) {
      onOpen?.call();
    } else {
      onClose?.call();
    }
  }

  @override
  void send(String text) {
    sent.add(text);
  }

  /// Test hook: simulate an inbound message from the remote peer.
  void deliver(String text) => onMessage?.call(text);

  @override
  Future<void> close() async {
    isOpen = false;
  }
}
