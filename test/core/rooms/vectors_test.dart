import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/rooms/rooms.dart';

/// Frozen keyed vectors. Independently computed with Python 3
/// `hmac` + `hashlib.scrypt` + `base64.b32encode` (RFC 4648
/// uppercase, padding stripped). Changing any value is a
/// protocol break.
///
/// Keyed message: `b"PRV" + scrypt(passphrase, salt=b"KERYX.v1",
/// N=32768, r=8, p=1, dklen=32)`.
void main() {
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
