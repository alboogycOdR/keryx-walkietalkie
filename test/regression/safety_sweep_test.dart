import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/directory_providers.dart';
import 'package:keryx/core/settings/settings_model.dart';

/// TASK-095 / Verification §7 + V2-NFR-005 safety sweep.
///
/// Static contracts the client can prove without a live network:
/// no contacts permission, no analytics SDK, HttpClient call sites are
/// the token service and directory (whose hosts come from the configured
/// relay), identity links only encode `keryx.app`, and both voice paths
/// pre-publish muted then re-mute on release.
void main() {
  const contactsPermissions = <String>[
    'READ_CONTACTS',
    'WRITE_CONTACTS',
    'GET_ACCOUNTS',
    'READ_PHONE_NUMBERS',
    'READ_PHONE_STATE',
    'READ_CALL_LOG',
    'READ_SMS',
  ];

  const analyticsTokens = <String>[
    'firebase_analytics',
    'firebase_crashlytics',
    'mixpanel',
    'amplitude',
    'sentry',
    'posthog',
    'appsflyer',
    'adjust',
  ];

  test('V2-NFR-005: Android manifests request no contacts permission', () {
    for (final String path in <String>[
      'android/app/src/main/AndroidManifest.xml',
      'android/app/src/debug/AndroidManifest.xml',
      'android/app/src/profile/AndroidManifest.xml',
    ]) {
      final String text = File(path).readAsStringSync();
      for (final String perm in contactsPermissions) {
        expect(
          text.contains(perm),
          isFalse,
          reason: '$path must not request android.permission.$perm',
        );
      }
    }
  });

  test('V2-NFR-005: pubspec.yaml declares no analytics SDK', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync().toLowerCase();
    for (final String token in analyticsTokens) {
      expect(
        pubspec.contains(token),
        isFalse,
        reason: 'pubspec.yaml must not depend on $token',
      );
    }
  });

  test(
    'network-host allowlist: dart:io HttpClient() lives only on token + directory',
    () {
      final ctor = RegExp(r'\bHttpClient\s*\(');
      final List<String> httpClientFiles = <String>[];
      for (final File file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (ctor.hasMatch(file.readAsStringSync())) {
          httpClientFiles.add(file.path.replaceAll('\\', '/'));
        }
      }
      expect(
        httpClientFiles,
        unorderedEquals(<String>[
          'lib/services/linked/token_client.dart',
          'lib/services/directory/directory_client.dart',
        ]),
      );
    },
  );

  test(
    'network-host allowlist: dart:io WebSocket.connect is presence + LAN only',
    () {
      final List<String> wsFiles = <String>[];
      for (final File file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (file.readAsStringSync().contains('WebSocket.connect')) {
          wsFiles.add(file.path.replaceAll('\\', '/'));
        }
      }
      expect(
        wsFiles,
        unorderedEquals(<String>[
          'lib/services/directory/presence_transport.dart',
          'lib/services/signaling/io_signaling_endpoint.dart',
        ]),
        reason:
            'internet WebSocket = directory presence; LAN WebSocket = '
            'direct signaling. Anything else is an unexpected host.',
      );
    },
  );

  test(
    'network-host allowlist: hardcoded https hosts in lib/ are only keryx.app',
    () {
      final hostLiteral = RegExp(
        r'https://([A-Za-z0-9.-]+)',
        caseSensitive: false,
      );
      final Set<String> hosts = <String>{};

      for (final File file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        for (final String line in file.readAsLinesSync()) {
          final String trimmed = line.trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) {
            continue;
          }
          for (final Match m in hostLiteral.allMatches(line)) {
            hosts.add(m.group(1)!.toLowerCase());
          }
        }
      }

      expect(
        hosts,
        equals(<String>{'keryx.app'}),
        reason:
            'unexpected hardcoded hosts $hosts — only keryx.app (ID share '
            'links) may be baked in; relay/token/directory hosts come from '
            'settings; LAN peers come from discovery',
      );
      expect(
        File('lib/features/my_code/keryx_id_link.dart').readAsStringSync(),
        contains("host: 'keryx.app'"),
      );
    },
  );

  test(
    'directory origin is derived from the configured relay, not a third host',
    () {
      expect(
        directoryBaseUri('wss://relay.example.test/livekit'),
        Uri.parse('https://relay.example.test/v2'),
      );
      expect(directoryBaseUri(''), isNull);
      expect(KeryxSettings.relayUrlDefault, isA<String>());
      expect(KeryxSettings.tokenServiceUrlDefault, isA<String>());
    },
  );

  test(
    'mic is muted before publish and after release (linked + mesh source)',
    () {
      final String linked =
          File('lib/services/linked/linked_controller.dart').readAsStringSync();
      final String mesh =
          File('lib/services/mesh/mesh_controller.dart').readAsStringSync();

      expect(
        linked.contains('publishMutedAudioTrack()'),
        isTrue,
        reason: 'LinkedController must pre-publish a muted track (§8.5)',
      );
      expect(linked.contains('event is TransmitGranted'), isTrue);
      expect(linked.contains('track.enabled = true'), isTrue);
      expect(linked.contains('event is EndTransmit'), isTrue);
      expect(linked.contains('track.enabled = false'), isTrue);
      expect(
        mesh.contains('pre-published-muted'),
        isTrue,
        reason: 'MeshController must document the muted-publish contract',
      );
      expect(mesh.contains('event is TransmitGranted'), isTrue);
      expect(mesh.contains('track.enabled = true'), isTrue);
      expect(mesh.contains('event is EndTransmit'), isTrue);
      expect(mesh.contains('track.enabled = false'), isTrue);
    },
  );
}
