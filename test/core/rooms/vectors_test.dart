import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/rooms/rooms.dart';

/// Frozen vectors. Independently computed with Python 3
/// `hmac` + `hashlib.scrypt` + `base64.b32encode` (RFC 4648
/// uppercase, padding stripped). Changing any value is a
/// protocol break.
///
/// Numbered message: `utf8("$region|$ch|$code")` with two-digit pads.
/// Keyed message: `b"PRV" + scrypt(passphrase, salt=b"KERYX.v1",
/// N=32768, r=8, p=1, dklen=32)`.
void main() {
  group('frozen numbered vectors', () {
    test('global CH 07 · 21', () {
      expect(
        deriveNumbered(region: 'global', channel: 7, code: 21),
        'M5MFIUI6TXTBOHBD',
      );
    });

    test('global CH 07 · 00 (open code still participates)', () {
      expect(
        deriveNumbered(region: 'global', channel: 7, code: 0),
        '5KE6UYJZEWK5KGWQ',
      );
    });

    test('global CH 01 · 00', () {
      expect(
        deriveNumbered(region: 'global', channel: 1, code: 0),
        'TPZHG3SHUYBRUWZ6',
      );
    });

    test('global CH 99 · 38', () {
      expect(
        deriveNumbered(region: 'global', channel: 99, code: 38),
        'TS26XNIDP3UZ7QWS',
      );
    });

    test('za-cpt CH 07 · 21 (region salt partitions)', () {
      expect(
        deriveNumbered(region: 'za-cpt', channel: 7, code: 21),
        'PNG6ZAKUDZOGNN2G',
      );
    });

    test('ZA-cpt CH 07 · 21 (region is case-sensitive)', () {
      expect(
        deriveNumbered(region: 'ZA-cpt', channel: 7, code: 21),
        '3LPPHLP25FNCYOXJ',
      );
    });

    test('sao-paulo CH 07 · 21', () {
      expect(
        deriveNumbered(region: 'sao-paulo', channel: 7, code: 21),
        'KBGZOI6GDCJ6Q5Y3',
      );
    });
  });

  group('frozen keyed vectors', () {
    test('correct horse battery staple', () {
      expect(
        deriveKeyed(passphrase: 'correct horse battery staple'),
        'MVYWVP2MCZADNKXN',
      );
    });

    test('secret', () {
      expect(deriveKeyed(passphrase: 'secret'), 'AUAW6KEXHGJU4XZB');
    });

    test('PRV (prefix collision does not short-circuit scrypt)', () {
      expect(deriveKeyed(passphrase: 'PRV'), 'RX22PZRMJTHBGGYA');
    });

    test('passphrase', () {
      expect(deriveKeyed(passphrase: 'passphrase'), 'IN2VAEMJRCPCO65E');
    });
  });
}
