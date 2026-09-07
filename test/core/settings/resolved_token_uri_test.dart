import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/settings/settings_model.dart';
import 'package:keryx/services/linked/token_client.dart';

/// Composes the two sides of the TASK-063 seam the same way
/// `RadioSessionController._startLinked` does: parse
/// [KeryxSettings.resolvedTokenServiceUrl] and hand it to [TokenClient].
/// Asserts the URI *TokenClient actually resolves*, not either input alone.
Uri resolvedByTokenClient(KeryxSettings settings) {
  final parsed = Uri.tryParse(settings.resolvedTokenServiceUrl) ?? Uri();
  final client = TokenClient(baseUrl: parsed);
  try {
    return client.resolveTokenUri();
  } finally {
    client.close();
  }
}

int tokenSegmentCount(Uri uri) =>
    uri.pathSegments.where((s) => s == 'token').length;

void main() {
  group('TokenClient ∘ KeryxSettings.resolvedTokenServiceUrl', () {
    test(
      'default settings (empty token URL, derived from relay) resolve to exactly one /token',
      () {
        const settings = KeryxSettings(
          relayUrl: 'wss://relay.example',
          tokenServiceUrl: '',
        );
        final uri = resolvedByTokenClient(settings);
        expect(uri.toString(), 'https://relay.example/token');
        expect(tokenSegmentCount(uri), 1);
      },
    );

    test(
      'derived URL from a relay with a path still has exactly one /token',
      () {
        const settings = KeryxSettings(
          relayUrl: 'wss://relay.example:7880/livekit',
          tokenServiceUrl: '',
        );
        final uri = resolvedByTokenClient(settings);
        expect(uri.toString(), 'https://relay.example:7880/token');
        expect(tokenSegmentCount(uri), 1);
      },
    );

    test('user-configured path prefix is retained in the resolved URI', () {
      const settings = KeryxSettings(
        relayUrl: 'wss://relay.example',
        tokenServiceUrl: 'https://relay.example/api',
      );
      final uri = resolvedByTokenClient(settings);
      expect(uri.toString(), 'https://relay.example/api/token');
      expect(uri.pathSegments, ['api', 'token']);
      expect(tokenSegmentCount(uri), 1);
    });

    test(
      'user-configured URL that already ends in /token is not double-appended',
      () {
        const settings = KeryxSettings(
          relayUrl: 'wss://relay.example',
          tokenServiceUrl: 'https://relay.example/token',
        );
        final uri = resolvedByTokenClient(settings);
        expect(uri.toString(), 'https://relay.example/token');
        expect(tokenSegmentCount(uri), 1);
      },
    );

    test(
      'origin-only token URL (TWO_PHONE_TEST §6 workaround) still resolves to /token',
      () {
        const settings = KeryxSettings(
          relayUrl: 'wss://relay.example',
          tokenServiceUrl: 'https://relay.example',
        );
        final uri = resolvedByTokenClient(settings);
        expect(uri.toString(), 'https://relay.example/token');
        expect(tokenSegmentCount(uri), 1);
      },
    );
  });
}
