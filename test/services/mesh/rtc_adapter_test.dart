import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:keryx/services/mesh/rtc_adapter.dart';
import 'package:keryx/services/mesh/rtc_adapter_flutter_webrtc.dart';

import 'fakes/fake_rtc_adapter.dart';

void main() {
  group('RtcPeerConnectionRemoteTracks (fake adapter)', () {
    test('consumer observes tracks delivered on FakeRtcAdapter PCs', () async {
      final FakeRtcAdapter adapter = FakeRtcAdapter();
      final RtcPeerConnection pc = await adapter.createPeerConnection();
      final List<RtcRemoteAudioTrack> seen = <RtcRemoteAudioTrack>[];
      pc.onRemoteAudioTrack = seen.add;

      final RtcRemoteAudioTrack track = RtcRemoteAudioTrack(id: 'peer-b-audio');
      pc.deliverRemoteAudioTrack(track);

      expect(seen, hasLength(1));
      expect(seen.single.id, 'peer-b-audio');
      expect(pc.remoteAudioTracks, <RtcRemoteAudioTrack>[track]);
    });

    test('late observer still sees tracks already delivered', () async {
      final FakeRtcAdapter adapter = FakeRtcAdapter();
      final RtcPeerConnection pc = await adapter.createPeerConnection();
      pc.deliverRemoteAudioTrack(RtcRemoteAudioTrack(id: 'early'));
      expect(
        pc.remoteAudioTracks.map((RtcRemoteAudioTrack t) => t.id),
        <String>['early'],
      );
    });
  });

  group('handleFlutterWebrtcTrackEvent (implementation wiring)', () {
    test('audio onTrack is forwarded as RtcRemoteAudioTrack', () {
      final List<RtcRemoteAudioTrack> seen = <RtcRemoteAudioTrack>[];
      final _FakePlatformTrack platform = _FakePlatformTrack(
        id: 'remote-1',
        kind: 'audio',
        enabled: true,
        muted: false,
      );

      handleFlutterWebrtcTrackEvent(
        webrtc.RTCTrackEvent(streams: <webrtc.MediaStream>[], track: platform),
        emit: seen.add,
      );

      expect(seen, hasLength(1));
      expect(seen.single.id, 'remote-1');
      expect(seen.single.enabled, isTrue);
      expect(seen.single.muted, isFalse);
    });

    test('video onTrack is ignored', () {
      final List<RtcRemoteAudioTrack> seen = <RtcRemoteAudioTrack>[];
      handleFlutterWebrtcTrackEvent(
        webrtc.RTCTrackEvent(
          streams: <webrtc.MediaStream>[],
          track: _FakePlatformTrack(id: 'v1', kind: 'video'),
        ),
        emit: seen.add,
      );
      expect(seen, isEmpty);
    });

    test('enabled setter is wired to the platform track (RX mute)', () {
      final List<RtcRemoteAudioTrack> seen = <RtcRemoteAudioTrack>[];
      final _FakePlatformTrack platform = _FakePlatformTrack(
        id: 'remote-1',
        kind: 'audio',
      );
      handleFlutterWebrtcTrackEvent(
        webrtc.RTCTrackEvent(streams: <webrtc.MediaStream>[], track: platform),
        emit: seen.add,
      );

      seen.single.enabled = false;
      expect(platform.enabled, isFalse);
      seen.single.enabled = true;
      expect(platform.enabled, isTrue);
    });

    test(
      'null receiver makes readAudioLevel unavailable, not a proxy',
      () async {
        final List<RtcRemoteAudioTrack> seen = <RtcRemoteAudioTrack>[];
        handleFlutterWebrtcTrackEvent(
          webrtc.RTCTrackEvent(
            streams: <webrtc.MediaStream>[],
            track: _FakePlatformTrack(id: 'remote-1', kind: 'audio'),
          ),
          emit: seen.add,
        );
        expect(await seen.single.readAudioLevel(), RtcAudioLevel.unavailable);
        expect(seen.single.signalQuality, RtcSignalQuality.unavailable);
      },
    );
  });

  group('audioLevelFromInboundRtpStats (honesty)', () {
    test('inbound-rtp audioLevel is measured', () {
      expect(
        audioLevelFromInboundRtpStats(<RtcStatsReport>[
          const RtcStatsReport(
            type: 'inbound-rtp',
            values: <String, Object?>{'kind': 'audio', 'audioLevel': 0.42},
          ),
        ]),
        const RtcMeasuredAudioLevel(0.42),
      );
    });

    test('audioLevel 0.0 is measured silence, not unavailable', () {
      expect(
        audioLevelFromInboundRtpStats(<RtcStatsReport>[
          const RtcStatsReport(
            type: 'inbound-rtp',
            values: <String, Object?>{'kind': 'audio', 'audioLevel': 0.0},
          ),
        ]),
        const RtcMeasuredAudioLevel(0.0),
      );
    });

    test('missing audioLevel is unavailable, not a proxy', () {
      expect(
        audioLevelFromInboundRtpStats(<RtcStatsReport>[
          const RtcStatsReport(
            type: 'inbound-rtp',
            values: <String, Object?>{'kind': 'audio'},
          ),
        ]),
        RtcAudioLevel.unavailable,
      );
    });

    test('totalAudioEnergy without audioLevel is unavailable', () {
      expect(
        audioLevelFromInboundRtpStats(<RtcStatsReport>[
          const RtcStatsReport(
            type: 'inbound-rtp',
            values: <String, Object?>{
              'kind': 'audio',
              'totalAudioEnergy': 12.5,
            },
          ),
        ]),
        RtcAudioLevel.unavailable,
      );
    });

    test('jitter and packetsLost are not a measured level', () {
      expect(
        audioLevelFromInboundRtpStats(<RtcStatsReport>[
          const RtcStatsReport(
            type: 'inbound-rtp',
            values: <String, Object?>{
              'kind': 'audio',
              'jitter': 0.003,
              'packetsLost': 2,
            },
          ),
        ]),
        RtcAudioLevel.unavailable,
      );
    });

    test('media-source audioLevel is local TX and is not treated as RX', () {
      expect(
        audioLevelFromInboundRtpStats(<RtcStatsReport>[
          const RtcStatsReport(
            type: 'media-source',
            values: <String, Object?>{'kind': 'audio', 'audioLevel': 0.9},
          ),
        ]),
        RtcAudioLevel.unavailable,
      );
    });

    test('outbound-rtp audioLevel is TX and is not treated as RX', () {
      expect(
        audioLevelFromInboundRtpStats(<RtcStatsReport>[
          const RtcStatsReport(
            type: 'outbound-rtp',
            values: <String, Object?>{'kind': 'audio', 'audioLevel': 0.8},
          ),
        ]),
        RtcAudioLevel.unavailable,
      );
    });

    test('another track\'s audioLevel is not a substitute', () {
      expect(
        audioLevelFromInboundRtpStats(<RtcStatsReport>[
          const RtcStatsReport(
            type: 'inbound-rtp',
            values: <String, Object?>{
              'kind': 'audio',
              'trackIdentifier': 'other',
              'audioLevel': 0.7,
            },
          ),
        ], trackId: 'wanted'),
        RtcAudioLevel.unavailable,
      );
    });

    test('matching trackIdentifier is used', () {
      expect(
        audioLevelFromInboundRtpStats(<RtcStatsReport>[
          const RtcStatsReport(
            type: 'inbound-rtp',
            values: <String, Object?>{
              'kind': 'audio',
              'trackIdentifier': 'wanted',
              'audioLevel': 0.3,
            },
          ),
        ], trackId: 'wanted'),
        const RtcMeasuredAudioLevel(0.3),
      );
    });

    test('out-of-range audioLevel is unavailable, not rescaled', () {
      expect(
        audioLevelFromInboundRtpStats(<RtcStatsReport>[
          const RtcStatsReport(
            type: 'inbound-rtp',
            values: <String, Object?>{'kind': 'audio', 'audioLevel': 4.0},
          ),
        ]),
        RtcAudioLevel.unavailable,
      );
    });

    test('inbound-rtp video kind is ignored', () {
      expect(
        audioLevelFromInboundRtpStats(<RtcStatsReport>[
          const RtcStatsReport(
            type: 'inbound-rtp',
            values: <String, Object?>{'kind': 'video', 'audioLevel': 0.5},
          ),
        ]),
        RtcAudioLevel.unavailable,
      );
    });
  });

  group('RtcRemoteAudioTrack', () {
    test(
      'readAudioLevel without a reader is unavailable, not silence',
      () async {
        final RtcRemoteAudioTrack track = RtcRemoteAudioTrack(id: 't');
        expect(await track.readAudioLevel(), RtcAudioLevel.unavailable);
      },
    );

    test('injected reader can return a measured value', () async {
      final RtcRemoteAudioTrack track = RtcRemoteAudioTrack(
        id: 't',
        readAudioLevel: () async => const RtcMeasuredAudioLevel(0.5),
      );
      expect(await track.readAudioLevel(), const RtcMeasuredAudioLevel(0.5));
    });

    test('signalQuality is always unavailable', () {
      expect(
        RtcRemoteAudioTrack(id: 't').signalQuality,
        RtcSignalQuality.unavailable,
      );
    });

    test('setVolume is a pass-through, not a rescaled proxy', () async {
      final List<double> seen = <double>[];
      final RtcRemoteAudioTrack track = RtcRemoteAudioTrack(
        id: 't',
        setVolume: (double v) async => seen.add(v),
      );
      await track.setVolume(1.0);
      await track.setVolume(10.0);
      expect(seen, <double>[1.0, 10.0]);
    });
  });
}

class _FakePlatformTrack extends webrtc.MediaStreamTrack {
  _FakePlatformTrack({
    required this.id,
    required this.kind,
    bool enabled = true,
    this.muted = false,
  }) : _enabled = enabled;

  @override
  final String? id;

  @override
  final String? kind;

  @override
  String? get label => '';

  bool _enabled;

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool b) => _enabled = b;

  @override
  final bool? muted;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
