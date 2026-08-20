import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/services/linked/token_client.dart';

import 'fakes/fake_token_server.dart';

void main() {
  group('TokenClient', () {
    late FakeTokenServer server;
    late TokenClient client;

    setUp(() async {
      server = await FakeTokenServer.start();
      client = TokenClient(baseUrl: server.baseUrl);
    });
    tearDown(() async {
      client.close();
      await server.close();
    });

    test('successful request returns a parsed TokenResponse', () async {
      server
        ..statusCode = 200
        ..responseBody = {
          'token': 'jwt-value',
          'identity': 'BRAVO-7#a1b2c3d4',
          'ttl_seconds': 300,
        };

      final response = await client.requestToken(roomId: 'ABCDEFGHIJKLMNOP', callsign: 'BRAVO-7');

      expect(response.token, 'jwt-value');
      expect(response.identity, 'BRAVO-7#a1b2c3d4');
      expect(response.ttl, const Duration(seconds: 300));
      expect(server.lastRequestBody, {
        'room_id': 'ABCDEFGHIJKLMNOP',
        'callsign': 'BRAVO-7',
        'event_token': null,
      });
    });

    test('passes event_token through when supplied', () async {
      server
        ..statusCode = 200
        ..responseBody = {'token': 't', 'identity': 'i#1', 'ttl_seconds': 60};

      await client.requestToken(roomId: 'ABCDEFGHIJKLMNOP', callsign: 'X', eventToken: 'keryx-evt.v1.aa.bb');

      expect(server.lastRequestBody?['event_token'], 'keryx-evt.v1.aa.bb');
    });

    test('maps a non-200 response to TokenRequestException with detail', () async {
      server
        ..statusCode = 403
        ..responseBody = {'detail': 'expired_event_token'};

      await expectLater(
        client.requestToken(roomId: 'ABCDEFGHIJKLMNOP', callsign: 'X'),
        throwsA(
          isA<TokenRequestException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.detail, 'detail', 'expired_event_token'),
        ),
      );
    });

    test('rate_limited (429) maps through as detail', () async {
      server
        ..statusCode = 429
        ..responseBody = {'detail': 'rate_limited'};

      await expectLater(
        client.requestToken(roomId: 'ABCDEFGHIJKLMNOP', callsign: 'X'),
        throwsA(isA<TokenRequestException>().having((e) => e.statusCode, 'statusCode', 429)),
      );
    });

    test('malformed success body throws TokenTransportException, not a crash', () async {
      server
        ..statusCode = 200
        ..malformedBody = true;

      await expectLater(
        client.requestToken(roomId: 'ABCDEFGHIJKLMNOP', callsign: 'X'),
        throwsA(isA<TokenTransportException>()),
      );
    });

    test('success body missing a required field throws TokenTransportException', () async {
      server
        ..statusCode = 200
        ..responseBody = {'token': 'jwt', 'identity': 'i#1'}; // missing ttl_seconds

      await expectLater(
        client.requestToken(roomId: 'ABCDEFGHIJKLMNOP', callsign: 'X'),
        throwsA(isA<TokenTransportException>()),
      );
    });

    test('unreachable host throws TokenTransportException, not a raw SocketException leak', () async {
      final unreachable = TokenClient(baseUrl: Uri.parse('http://127.0.0.1:1'));
      await expectLater(
        unreachable.requestToken(roomId: 'ABCDEFGHIJKLMNOP', callsign: 'X'),
        throwsA(isA<TokenTransportException>()),
      );
      unreachable.close();
    });
  });
}
