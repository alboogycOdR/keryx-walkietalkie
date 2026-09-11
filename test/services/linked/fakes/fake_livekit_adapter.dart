import 'dart:async';
import 'dart:typed_data';

import 'package:keryx/services/linked/livekit_adapter.dart';

/// In-memory [LiveKitAdapter] for unit tests. No real relay connection —
/// `connect` just records the call and hands back a [FakeLiveKitRoom]
/// controllable by the test. Mirrors `test/services/mesh/fakes/fake_rtc_adapter.dart`.
class FakeLiveKitAdapter implements LiveKitAdapter {
  FakeLiveKitAdapter({this.onConnect});

  /// Optional hook so a test can throw (simulate a relay-unreachable
  /// connect failure) or return a specific [FakeLiveKitRoom] instance.
  final FakeLiveKitRoom Function(String url, String jwt, Uint8List? e2eeKey)? onConnect;

  final List<({String url, String jwt, Uint8List? e2eeKey})> connectCalls = [];
  FakeLiveKitRoom? lastRoom;

  @override
  Future<LiveKitRoom> connect({
    required String url,
    required String jwt,
    Uint8List? e2eeKey,
  }) async {
    connectCalls.add((url: url, jwt: jwt, e2eeKey: e2eeKey));
    // Default behaviour: a key provider that is actually given a key
    // encrypts, matching the production adapter — tests that want to
    // simulate an adapter which silently drops E2EE pass their own
    // [onConnect] returning `isEncrypted: false`.
    final room = onConnect != null
        ? onConnect!(url, jwt, e2eeKey)
        : FakeLiveKitRoom(isEncrypted: e2eeKey != null);
    lastRoom = room;
    return room;
  }
}

class FakeLiveKitRoom implements LiveKitRoom {
  FakeLiveKitRoom({this.isEncrypted = false});

  final _connectionState = StreamController<LiveKitConnectionState>.broadcast(sync: true);
  final _connectionQuality = StreamController<LiveKitConnectionQuality>.broadcast(sync: true);
  final _incomingData = StreamController<List<int>>.broadcast(sync: true);

  final List<List<int>> sent = [];
  FakeLiveKitLocalAudioTrack? publishedTrack;
  bool disconnected = false;
  bool disposedStreams = false;

  @override
  final bool isEncrypted;

  /// If set, [publishMutedAudioTrack] throws this instead of succeeding.
  Object? publishFailure;

  @override
  Stream<LiveKitConnectionState> get connectionState => _connectionState.stream;

  @override
  Stream<LiveKitConnectionQuality> get connectionQuality => _connectionQuality.stream;

  @override
  Stream<List<int>> get incomingData => _incomingData.stream;

  @override
  Future<LiveKitLocalAudioTrack> publishMutedAudioTrack() async {
    final failure = publishFailure;
    if (failure != null) throw failure;
    final track = FakeLiveKitLocalAudioTrack();
    publishedTrack = track;
    return track;
  }

  @override
  Future<void> sendData(List<int> bytes) async {
    sent.add(bytes);
  }

  @override
  Future<void> disconnect() async {
    disconnected = true;
  }

  void emitConnectionState(LiveKitConnectionState state) {
    if (!_connectionState.isClosed) _connectionState.add(state);
  }

  void emitConnectionQuality(LiveKitConnectionQuality quality) {
    if (!_connectionQuality.isClosed) _connectionQuality.add(quality);
  }

  /// Simulate an inbound data message from a remote participant.
  void deliverData(List<int> bytes) {
    if (!_incomingData.isClosed) _incomingData.add(bytes);
  }

  Future<void> disposeStreams() async {
    if (disposedStreams) return;
    disposedStreams = true;
    await _connectionState.close();
    await _connectionQuality.close();
    await _incomingData.close();
  }
}

class FakeLiveKitLocalAudioTrack implements LiveKitLocalAudioTrack {
  bool _enabled = false;
  final List<bool> enabledHistory = [];

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) {
    _enabled = value;
    enabledHistory.add(value);
  }
}
