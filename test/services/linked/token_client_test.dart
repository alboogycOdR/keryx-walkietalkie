import 'dart:convert';
import 'dart:io';

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

  group('TokenClient.resolveTokenUri', () {
    TokenClient clientFor(String url) => TokenClient(baseUrl: Uri.parse(url));

    test('origin-only base appends a single /token', () {
      final client = clientFor('https://relay.example');
      expect(client.resolveTokenUri().toString(), 'https://relay.example/token');
      client.close();
    });

    test('path prefix is preserved and /token is appended (TASK-024)', () {
      final client = clientFor('https://relay.example/api');
      expect(client.resolveTokenUri().toString(), 'https://relay.example/api/token');
      client.close();
    });

    test('trailing-slash prefix is preserved', () {
      final client = clientFor('https://relay.example/api/');
      expect(client.resolveTokenUri().toString(), 'https://relay.example/api/token');
      client.close();
    });

    test('base that already ends in /token is not double-appended', () {
      final client = clientFor('https://relay.example/token');
      expect(client.resolveTokenUri().toString(), 'https://relay.example/token');
      expect(client.resolveTokenUri().pathSegments, ['token']);
      client.close();
    });

    test('base that already ends in /token/ still has exactly one token segment', () {
      final client = clientFor('https://relay.example/token/');
      final uri = client.resolveTokenUri();
      expect(uri.pathSegments.where((s) => s.isNotEmpty).toList(), ['token']);
      client.close();
    });

    test('prefix whose last segment is not token still appends', () {
      final client = clientFor('https://relay.example/token-svc');
      expect(client.resolveTokenUri().toString(), 'https://relay.example/token-svc/token');
      client.close();
    });

    test('requestToken POSTs the resolved path (no double-append on /token base)', () async {
      final bound = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      String? postedPath;
      bound.listen((request) async {
        postedPath = request.uri.path;
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'token': 'jwt', 'identity': 'i#1', 'ttl_seconds': 60}),
        );
        await request.response.close();
      });
      addTearDown(() => bound.close(force: true));

      final base = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: bound.port,
        path: '/token',
      );
      final client = TokenClient(baseUrl: base);
      addTearDown(client.close);

      await client.requestToken(roomId: 'ABCDEFGHIJKLMNOP', callsign: 'X');
      expect(postedPath, '/token');
    });
  });
}
