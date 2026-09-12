import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/features/my_code/keryx_id_link.dart';

void main() {
  late IdentityKeyPair keys;
  late KeryxIdLink link;

  setUp(() async {
    keys = await IdentityKeyPair.fromSeed(List<int>.filled(32, 7));
    link = KeryxIdLink(callsign: 'BEN', publicKey: keys.publicKey);
  });

  test('QR payload carries the public key and round-trips', () {
    final parsed = KeryxIdLink.parse(link.qrPayload);
    expect(parsed.callsign, 'BEN');
    expect(parsed.publicKey, keys.publicKey);
    expect(parsed.qrPayload, startsWith('keryx://id?'));
    expect(parsed.qrPayload, contains('v=1'));
    expect(parsed.qrPayload, contains('c=BEN'));
    expect(parsed.qrPayload, contains('k='));
  });

  test('share URL matches Technical §3.1', () {
    expect(
      link.shareUrl,
      'https://keryx.app/c/${link.callsign}-${link.shortCode}?k=${link.encodedKey}',
    );
    final parsed = KeryxIdLink.parse(link.shareUrl);
    expect(parsed.publicKey, keys.publicKey);
    expect(parsed.callsign, 'BEN');
  });

  test('display ID is callsign middle-dot short code', () {
    expect(link.displayId, 'BEN·${link.shortCode}');
    expect(link.shortCode.length, shortCodeLength);
  });

  test('tampered key in the QR is decoded as different bytes, locally', () {
    final original = link.qrPayload;
    final parsed = KeryxIdLink.parse(original);
    final tamperedKey = Uint8List.fromList(List<int>.filled(32, 9));
    final tampered = KeryxIdLink(callsign: 'BEN', publicKey: tamperedKey);
    expect(tampered.publicKey, isNot(parsed.publicKey));
    expect(
      () => KeryxIdLink.parse(original.replaceAll(parsed.encodedKey, '!!!')),
      throwsFormatException,
    );
  });

  test('rejects the wrong scheme and a short key', () {
    expect(
      () => KeryxIdLink.parse('https://example.com/x'),
      throwsFormatException,
    );
    expect(
      () => KeryxIdLink.parse('keryx://id?v=1&c=BEN&k=YQ'),
      throwsFormatException,
    );
  });
}
