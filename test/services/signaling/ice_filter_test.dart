import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/services/signaling/signaling.dart';

void main() {
  group('isLanIceCandidate', () {
    test('allows host and mDNS, rejects srflx/relay/prflx', () {
      expect(
        isLanIceCandidate(
          'candidate:0 1 UDP 2122260223 10.0.0.8 54321 typ host',
        ),
        isTrue,
      );
      expect(
        isLanIceCandidate(
          'candidate:1 1 UDP 2122260223 abcdef.local 54321 typ host generation 0',
        ),
        isTrue,
      );
      expect(isLanIceCandidate('abcdef.local 9 typ host'), isTrue);
      expect(
        isLanIceCandidate(
          'candidate:2 1 UDP 1686052607 203.0.113.9 54321 typ srflx raddr 10.0.0.8 rport 54321',
        ),
        isFalse,
      );
      expect(
        isLanIceCandidate(
          'candidate:3 1 UDP 41819903 203.0.113.9 3478 typ relay raddr 10.0.0.8 rport 54321',
        ),
        isFalse,
      );
      expect(
        isLanIceCandidate(
          'candidate:4 1 UDP 1853755647 203.0.113.9 54321 typ prflx',
        ),
        isFalse,
      );
      expect(isLanIceCandidate('not a candidate'), isFalse);
    });
  });

  test('sanitizeSdp strips non-LAN a=candidate lines', () {
    const sdp =
        'v=0\n'
        'a=candidate:0 1 UDP 2122260223 10.0.0.8 9 typ host\n'
        'a=candidate:2 1 UDP 1686052607 203.0.113.9 9 typ srflx\n'
        'a=ice-pwd:abc\n';
    final cleaned = sanitizeSdp(sdp);
    expect(cleaned, contains('typ host'));
    expect(cleaned, isNot(contains('typ srflx')));
    expect(cleaned, contains('a=ice-pwd:abc'));
  });
}
