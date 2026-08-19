import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/rooms/scrypt_stretch.dart';

/// RFC 7914 Appendix B test vectors. These prove the in-tree scrypt
/// matches the RFC, independently of the roomId vectors.
void main() {
  test('RFC 7914 vector: empty P/S, N=16, r=1, p=1, dkLen=64', () {
    final dk = scrypt(
      utf8.encode(''),
      utf8.encode(''),
      n: 16,
      r: 1,
      p: 1,
      dkLen: 64,
    );
    expect(
      _hex(dk),
      '77d6576238657b203b19ca42c18a0497'
      'f16b4844e3074ae8dfdffa3fede21442'
      'fcd0069ded0948f8326a753a0fc81f17'
      'e8d3e0fb2e0d3628cf35e20c38d18906',
    );
  });

  test('RFC 7914 vector: pleaseletmein / SodiumChloride, N=16384', () {
    final dk = scrypt(
      utf8.encode('pleaseletmein'),
      utf8.encode('SodiumChloride'),
      n: 16384,
      r: 8,
      p: 1,
      dkLen: 64,
    );
    expect(
      _hex(dk),
      '7023bdcb3afd7348461c06cd81fd38eb'
      'fda8fbba904f8e3ea9b543f6545da1f2'
      'd5432955613f0fcf62d49705242a9af9'
      'e61e85dc0d651e40dfcf017b45575887',
    );
  });

  test('production stretch of "secret" matches independent hashlib.scrypt', () {
    expect(
      _hex(stretchPassphrase('secret')),
      'a7430bc805bd670d3a4b12be7357e713'
      '03515a71e9864f7bd966347ecb82c9c9',
    );
  });
}

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
