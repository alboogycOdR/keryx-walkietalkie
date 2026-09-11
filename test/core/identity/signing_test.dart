import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/identity.dart';

void main() {
  const method = 'POST';
  const path = '/v2/contacts/requests';
  const body = '{"to_pk":"abc"}';
  const ts = 1000000;

  group('signRequest / verifySignedRequest', () {
    test('a valid signature is accepted', () async {
      final keyPair = await IdentityKeyPair.generate();
      final headers = await signRequest(
        keyPair: keyPair,
        method: method,
        path: path,
        body: body,
        nowUnixSeconds: ts,
      );
      final result = await verifySignedRequest(
        headers: headers,
        method: method,
        path: path,
        body: body,
        nowUnixSeconds: ts + 5,
      );
      expect(result, isA<SignedRequestAccepted>());
    });

    test('a tampered body is rejected', () async {
      final keyPair = await IdentityKeyPair.generate();
      final headers = await signRequest(
        keyPair: keyPair,
        method: method,
        path: path,
        body: body,
        nowUnixSeconds: ts,
      );
      final result = await verifySignedRequest(
        headers: headers,
        method: method,
        path: path,
        body: '{"to_pk":"tampered"}',
        nowUnixSeconds: ts + 5,
      );
      expect(result, isA<SignedRequestRejected>());
      expect(
        (result as SignedRequestRejected).reason,
        SignedRequestRejection.badSignature,
      );
    });

    test('a stale timestamp is rejected', () async {
      final keyPair = await IdentityKeyPair.generate();
      final headers = await signRequest(
        keyPair: keyPair,
        method: method,
        path: path,
        body: body,
        nowUnixSeconds: ts,
      );
      final result = await verifySignedRequest(
        headers: headers,
        method: method,
        path: path,
        body: body,
        nowUnixSeconds: ts + signingWindowSeconds + 1,
      );
      expect(result, isA<SignedRequestRejected>());
      expect(
        (result as SignedRequestRejected).reason,
        SignedRequestRejection.staleTimestamp,
      );
    });

    test('a future timestamp beyond the window is also rejected', () async {
      final keyPair = await IdentityKeyPair.generate();
      final headers = await signRequest(
        keyPair: keyPair,
        method: method,
        path: path,
        body: body,
        nowUnixSeconds: ts,
      );
      final result = await verifySignedRequest(
        headers: headers,
        method: method,
        path: path,
        body: body,
        nowUnixSeconds: ts - signingWindowSeconds - 1,
      );
      expect(result, isA<SignedRequestRejected>());
      expect(
        (result as SignedRequestRejected).reason,
        SignedRequestRejection.staleTimestamp,
      );
    });

    test('the wrong key is rejected', () async {
      final keyPair = await IdentityKeyPair.generate();
      final wrongKeyPair = await IdentityKeyPair.generate();
      final headers = await signRequest(
        keyPair: keyPair,
        method: method,
        path: path,
        body: body,
        nowUnixSeconds: ts,
      );
      final headersWithWrongKey = SignedRequestHeaders(
        signatureBase64: headers.signatureBase64,
        publicKeyBase64: base64EncodePublicKey(wrongKeyPair),
        timestamp: headers.timestamp,
      );
      final result = await verifySignedRequest(
        headers: headersWithWrongKey,
        method: method,
        path: path,
        body: body,
        nowUnixSeconds: ts + 5,
      );
      expect(result, isA<SignedRequestRejected>());
      expect(
        (result as SignedRequestRejected).reason,
        SignedRequestRejection.badSignature,
      );
    });

    test('a different path fails as a tampered request', () async {
      final keyPair = await IdentityKeyPair.generate();
      final headers = await signRequest(
        keyPair: keyPair,
        method: method,
        path: path,
        body: body,
        nowUnixSeconds: ts,
      );
      final result = await verifySignedRequest(
        headers: headers,
        method: method,
        path: '/v2/groups',
        body: body,
        nowUnixSeconds: ts + 5,
      );
      expect(result, isA<SignedRequestRejected>());
    });

    test('toHeaders() exposes the three documented header names', () async {
      final keyPair = await IdentityKeyPair.generate();
      final headers = await signRequest(
        keyPair: keyPair,
        method: method,
        path: path,
        body: body,
        nowUnixSeconds: ts,
      );
      final map = headers.toHeaders();
      expect(map.keys, containsAll(<String>['X-Keryx-Sig', 'X-Keryx-Key', 'X-Keryx-Ts']));
    });
  });
}

String base64EncodePublicKey(IdentityKeyPair keyPair) =>
    base64Encode(keyPair.publicKey);
