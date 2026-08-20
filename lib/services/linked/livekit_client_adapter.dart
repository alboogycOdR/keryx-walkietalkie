import 'dart:async';

import 'package:livekit_client/livekit_client.dart' as lk;

import 'livekit_adapter.dart';

/// Production [LiveKitAdapter]: a thin pass-through to
/// `package:livekit_client`. Exercised on-device / against the live relay,
/// not by this package's unit suite (no network under `flutter test`) —
/// see `test/services/linked/fakes/fake_livekit_adapter.dart` for the fake
/// this package's own tests run against. Mirrors
/// `lib/services/mesh/rtc_adapter_flutter_webrtc.dart`'s role exactly.
class LiveKitClientAdapter implements LiveKitAdapter {
  const LiveKitClientAdapter();

  @override
  Future<LiveKitRoom> connect({required String url, required String jwt}) async {
    final room = lk.Room();
    await room.connect(url, jwt);
    return _LiveKitClientRoom(room);
  }
}

class _LiveKitClientRoom implements LiveKitRoom {
  _LiveKitClientRoom(this._room);

  final lk.Room _room;

  Stream<lk.RoomEvent> get _events => _room.events.streamCtrl.stream;

  @override
  Stream<LiveKitConnectionState> get connectionState => _events
      .where(
        (event) =>
            event is lk.RoomConnectedEvent ||
            event is lk.RoomReconnectedEvent ||
            event is lk.RoomReconnectingEvent ||
            event is lk.RoomResumingEvent ||
            event is lk.RoomDisconnectedEvent,
      )
      .map(_mapConnectionStateEvent);

  @override
  Stream<LiveKitConnectionQuality> get connectionQuality => _events
      .where((event) => event is lk.ParticipantConnectionQualityUpdatedEvent)
      .cast<lk.ParticipantConnectionQualityUpdatedEvent>()
      .where((event) => event.participant.sid == _room.localParticipant?.sid)
      .map((event) => _mapConnectionQuality(event.connectionQuality));

  @override
  Stream<List<int>> get incomingData => _events
      .where((event) => event is lk.DataReceivedEvent)
      .cast<lk.DataReceivedEvent>()
      .map((event) => event.data);

  @override
  Future<LiveKitLocalAudioTrack> publishMutedAudioTrack() async {
    final track = await lk.LocalAudioTrack.create();
    final participant = _room.localParticipant;
    if (participant == null) {
      throw StateError('publishMutedAudioTrack: room has no local participant yet');
    }
    await participant.publishAudioTrack(track);
    // TS §8.5: pre-published *muted*; PTT grant flips this flag, never
    // re-publishes.
    await track.mute();
    return _LiveKitClientLocalAudioTrack(track);
  }

  @override
  Future<void> sendData(List<int> bytes) async {
    final participant = _room.localParticipant;
    if (participant == null) return;
    await participant.publishData(bytes, reliable: true);
  }

  @override
  Future<void> disconnect() async {
    await _room.disconnect();
  }

  static LiveKitConnectionState _mapConnectionStateEvent(lk.RoomEvent event) => switch (event) {
    lk.RoomConnectedEvent() || lk.RoomReconnectedEvent() => LiveKitConnectionState.connected,
    lk.RoomReconnectingEvent() || lk.RoomResumingEvent() => LiveKitConnectionState.reconnecting,
    lk.RoomDisconnectedEvent() => LiveKitConnectionState.disconnected,
    _ => LiveKitConnectionState.disconnected,
  };

  static LiveKitConnectionQuality _mapConnectionQuality(lk.ConnectionQuality quality) =>
      switch (quality) {
        lk.ConnectionQuality.excellent => LiveKitConnectionQuality.excellent,
        lk.ConnectionQuality.good => LiveKitConnectionQuality.good,
        lk.ConnectionQuality.poor => LiveKitConnectionQuality.poor,
        lk.ConnectionQuality.lost => LiveKitConnectionQuality.lost,
        lk.ConnectionQuality.unknown => LiveKitConnectionQuality.unknown,
      };
}

class _LiveKitClientLocalAudioTrack implements LiveKitLocalAudioTrack {
  _LiveKitClientLocalAudioTrack(this._track);

  final lk.LocalAudioTrack _track;
  bool _enabled = false;

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    if (value) {
      unawaited(_track.unmute());
    } else {
      unawaited(_track.mute());
    }
  }
}
