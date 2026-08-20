import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/services/mesh/opus_sdp.dart';

const _offerNoFmtp = 'v=0\r\n'
    'o=- 1 1 IN IP4 127.0.0.1\r\n'
    's=-\r\n'
    't=0 0\r\n'
    'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
    'c=IN IP4 0.0.0.0\r\n'
    'a=rtpmap:111 opus/48000/2\r\n'
    'a=mid:0\r\n';

const _offerWithFmtpAndPtime = 'v=0\r\n'
    'o=- 1 1 IN IP4 127.0.0.1\r\n'
    's=-\r\n'
    't=0 0\r\n'
    'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
    'c=IN IP4 0.0.0.0\r\n'
    'a=rtpmap:111 opus/48000/2\r\n'
    'a=fmtp:111 minptime=10;useinbandfec=0\r\n'
    'a=ptime:60\r\n'
    'a=mid:0\r\n';

const _offerAudioThenVideo = 'v=0\r\n'
    'o=- 1 1 IN IP4 127.0.0.1\r\n'
    's=-\r\n'
    't=0 0\r\n'
    'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
    'c=IN IP4 0.0.0.0\r\n'
    'a=rtpmap:111 opus/48000/2\r\n'
    'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
    'c=IN IP4 0.0.0.0\r\n'
    'a=rtpmap:96 VP8/90000\r\n';

const _dataChannelOnlyOffer = 'v=0\r\n'
    'o=- 1 1 IN IP4 127.0.0.1\r\n'
    's=-\r\n'
    't=0 0\r\n'
    'm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n'
    'c=IN IP4 0.0.0.0\r\n';

void main() {
  group('OpusSdp.applyProfile', () {
    test('inserts fmtp + ptime when absent', () {
      final out = OpusSdp.applyProfile(_offerNoFmtp);
      expect(
        out,
        contains(
          'a=fmtp:111 useinbandfec=1;usedtx=0;maxaveragebitrate=24000;'
          'stereo=0;sprop-stereo=0',
        ),
      );
      expect(out, contains('a=ptime:20'));
      // fmtp/ptime land inside the audio section, before EOF here.
      final fmtpIdx = out.indexOf('a=fmtp:111');
      final rtpmapIdx = out.indexOf('a=rtpmap:111');
      expect(fmtpIdx, greaterThan(rtpmapIdx));
    });

    test('overrides an existing fmtp/ptime rather than duplicating', () {
      final out = OpusSdp.applyProfile(_offerWithFmtpAndPtime);
      expect(
        'a=fmtp:111'.allMatches(out).length,
        1,
        reason: 'must replace, not append, an existing fmtp line',
      );
      expect('a=ptime:'.allMatches(out).length, 1);
      expect(
        out,
        contains(
          'a=fmtp:111 useinbandfec=1;usedtx=0;maxaveragebitrate=24000;'
          'stereo=0;sprop-stereo=0',
        ),
      );
      expect(out, contains('a=ptime:20'));
      expect(out, isNot(contains('minptime=10')));
      expect(out, isNot(contains('a=ptime:60')));
    });

    test('places fmtp/ptime before the next m= section, not after', () {
      final out = OpusSdp.applyProfile(_offerAudioThenVideo);
      final lines = out.split('\r\n');
      final videoIdx = lines.indexWhere((l) => l.startsWith('m=video'));
      final fmtpIdx = lines.indexWhere((l) => l.startsWith('a=fmtp:111'));
      final ptimeIdx = lines.indexWhere((l) => l.startsWith('a=ptime:20'));
      expect(fmtpIdx, greaterThan(-1));
      expect(ptimeIdx, greaterThan(-1));
      expect(fmtpIdx, lessThan(videoIdx));
      expect(ptimeIdx, lessThan(videoIdx));
      // Video section must be untouched.
      expect(out, contains('a=rtpmap:96 VP8/90000'));
    });

    test('is a no-op when there is no audio/Opus section', () {
      final out = OpusSdp.applyProfile(_dataChannelOnlyOffer);
      expect(out, _dataChannelOnlyOffer);
    });

    test('respects custom profile parameters', () {
      final out = OpusSdp.applyProfile(
        _offerNoFmtp,
        maxBitrateBps: 16000,
        ptimeMs: 20,
        inBandFec: false,
        dtxOff: false,
      );
      expect(
        out,
        contains(
          'a=fmtp:111 useinbandfec=0;usedtx=1;maxaveragebitrate=16000;'
          'stereo=0;sprop-stereo=0',
        ),
      );
    });
  });
}
