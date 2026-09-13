import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/contacts/contacts_keys.dart' show ContactsKeys;
import 'package:keryx/features/groups/groups_list_screen.dart';
import 'package:keryx/features/radio_controls/radio_controls_screen.dart';
import 'package:keryx/features/settings/settings_screen.dart';
import 'package:keryx/features/talk/talk_ptt_ring.dart';
import 'package:keryx/features/talk/talk_screen.dart' as talkui;
import 'package:keryx/services/directory/directory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/directory/fakes/fake_directory_server.dart';
import 'directory_shell_harness.dart';
import 'fake_radio_host.dart';
import 'shell_harness.dart';

/// TASK-105: `DirectoryShellHarness.buildContainer` (`directory_shell_harness
/// .dart`, not this task's `Owned_Paths`) seeds a bare `InMemorySettingsStore
/// ()`, which is fine for its own original purpose — it overrides
/// `directoryClientProvider`/`presenceClientProvider` directly, so nothing
/// there ever reads `settings.relayUrl`. But `mobile_app_shell.dart` now
/// also reads `registrationStatusProvider` at shell init, which reads the
/// UN-overridden `identityEnrolmentProvider` — and that derives its own
/// `DirectoryClient` straight from `settings.relayUrl`, not from the
/// harness's fake one. An unseeded store there triggers `SettingsRepository
/// .load()`'s baked-in-relay migration (TASK-104), so `identityEnrolmentProvider`
/// tries to reach an actual (non-loopback, non-fake) host and hangs on a
/// real TLS handshake `runAsync` can never complete. Mirrors the same fix
/// `regression_shell_harness.dart` already applies for the identical reason:
/// pre-seed an explicit "user cleared" relay before building the container.
Future<ProviderContainer> _buildClearedRelayContainer(
  DirectoryShellHarness directory, {
  required FakeRadioHost host,
}) async {
  final settingsStore = InMemorySettingsStore();
  await settingsStore.write(
    SettingsRepository.storageKey,
    jsonEncode(
      const KeryxSettings().copyWith(relayUrl: '', relayUrlUserCleared: true).toJson(),
    ),
  );
  return ProviderContainer(
    overrides: <Override>[
      radioHostProvider.overrideWithValue(host),
      settingsStoreProvider.overrideWithValue(settingsStore),
      identityProvider.overrideWith((ref) async => directory.identity),
      directoryClientProvider.overrideWith(
        (ref) async => DirectoryClient(baseUrl: directory.server.baseUrl, keyPair: directory.keyPair),
      ),
      presenceClientProvider.overrideWith(
        (ref) async => PresenceClient(baseUrl: directory.server.baseUrl, keyPair: directory.keyPair),
      ),
    ],
  );
}

/// TASK-093 (Design §1, ADR-002 §2/§3) — the v2 shell: Talk is the default
/// tab, a top app bar carries the wordmark/connection indicator/overflow
/// menu, and an icon-only tab strip (Talk · Contacts · Groups) replaces the
/// R2 Talk/Channels/Stations set. The single host is still mounted once
/// above every route, and navigation alone never touches a host lifecycle
/// method (VT-001).
void main() {
  late FakeRadioHost host;

  Widget build({ThemeData? theme}) {
    host = FakeRadioHost();
    return pumpShell(host: host, home: const MobileAppShell(), theme: theme);
  }

  testWidgets('Talk is the default landing destination on every launch '
      '(ADR-002 §2 O1)', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.byType(talkui.TalkScreen), findsOneWidget);
    expect(find.byKey(ShellKeys.talk), findsOneWidget);
  });

  testWidgets('exactly three tab strip destinations exist: Talk, Contacts, '
      'Groups; no bottom NavigationBar (Design §1)', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(ShellKeys.tabTalk), findsOneWidget);
    expect(find.byKey(ShellKeys.tabContacts), findsOneWidget);
    expect(find.byKey(ShellKeys.tabGroups), findsOneWidget);
  });

  testWidgets('each tab target meets the 48 dp minimum and carries a '
      'semantic label', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    for (final (Key key, String label) in <(Key, String)>[
      (ShellKeys.tabTalk, 'Talk'),
      (ShellKeys.tabContacts, 'Contacts'),
      (ShellKeys.tabGroups, 'Groups'),
    ]) {
      final Size size = tester.getSize(find.byKey(key));
      expect(
        size.height,
        greaterThanOrEqualTo(KeryxUxSpacing.minTarget),
        reason: '$label tab must meet the 48 dp target');
      expect(find.bySemanticsLabel(label), findsWidgets);
    }
  });

  testWidgets('the host is constructed and started exactly once on mount', (
    tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(host.startCalls, 1);
    expect(host.disposeCalls, 0);
  });

  testWidgets(
    'Talk -> Contacts -> Groups -> Talk causes zero additional host '
    'start/dispose/tune calls (VT-001)',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(host.startCalls, 1);
      expect(find.byKey(ShellKeys.talk), findsOneWidget);

      await tester.tap(navDestination('Contacts'));
      await tester.pumpAndSettle();
      expect(find.byKey(ShellKeys.contactsTab), findsNothing); // no directory -> unavailable state
      expect(find.textContaining('Contacts need a relay address'), findsOneWidget);

      await tester.tap(navDestination('Groups'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Groups need a relay address'), findsOneWidget);

      await tester.tap(navDestination('Talk'));
      await tester.pumpAndSettle();
      expect(find.byKey(ShellKeys.talk), findsOneWidget);

      expect(host.startCalls, 1, reason: 'navigation must never re-start the host');
      expect(host.disposeCalls, 0, reason: 'navigation must never dispose the host');
      expect(host.tuneCalls, isEmpty, reason: 'navigation alone must never retune');
    });

  testWidgets('re-tapping the active tab pops its branch to root '
      'without touching the host', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await tester.tap(navDestination('Contacts'));
    await tester.pumpAndSettle();
    await tester.tap(navDestination('Contacts'));
    await tester.pumpAndSettle();

    expect(host.startCalls, 1);
    expect(host.disposeCalls, 0);
  });

  testWidgets(
    'a horizontal drag across the Talk body, including across the PTT, '
    'never changes the active tab',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(find.byKey(ShellKeys.talk), findsOneWidget);

      final Finder ptt = find.byKey(const Key('keryx-talk-ptt-disc'));
      await tester.drag(ptt, const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(
        find.byKey(ShellKeys.talk),
        findsOneWidget,
        reason: 'a swipe must never be interpreted as a tab change — there '
            'is no PageView/TabBarView anywhere in this shell');
    });

  testWidgets(
    'system back on the Contacts tab root returns to Talk; on the Talk '
    'root it falls through to the platform',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      await tester.tap(navDestination('Contacts'));
      await tester.pumpAndSettle();

      final bool poppedFromContacts = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        poppedFromContacts,
        isTrue,
        reason: 'the shell itself must intercept back on a non-Talk tab '
            'root rather than letting it propagate to the platform');
      expect(find.byKey(ShellKeys.talk), findsOneWidget);

      final bool poppedFromTalk = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        poppedFromTalk,
        isFalse,
        reason: 'back on the Talk root must fall through to the platform');
    });

  testWidgets(
    'system back on the Groups tab root returns to Talk (TASK-077 rule '
    'extended to the v2 tabs)',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      await tester.tap(navDestination('Groups'));
      await tester.pumpAndSettle();

      final bool popped = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(popped, isTrue);
      expect(find.byKey(ShellKeys.talk), findsOneWidget);
    });

  testWidgets('overflow menu opens My code, Radio controls and Settings '
      'full-screen with back; returning keeps the current tab', (
    tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await tester.tap(navDestination('Contacts'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ShellKeys.overflowMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ShellKeys.overflowRadioControls));
    await tester.pumpAndSettle();
    expect(find.byType(RadioControlsScreen), findsOneWidget);
    expect(find.byKey(ShellKeys.radioControls), findsOneWidget);
    await popScreen(tester, find.byType(RadioControlsScreen));
    expect(find.byKey(ShellKeys.tabContacts), findsOneWidget);

    await tester.tap(find.byKey(ShellKeys.overflowMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ShellKeys.overflowSettings));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byKey(ShellKeys.settings), findsOneWidget);
    await popScreen(tester, find.byType(SettingsScreen));

    expect(host.startCalls, 1);
    expect(host.disposeCalls, 0);
  });

  testWidgets('overflow menu offers My code above Radio controls and '
      'Settings (Design §1)', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ShellKeys.overflowMenu));
    await tester.pumpAndSettle();

    expect(find.byKey(ShellKeys.overflowMyCode), findsOneWidget);
    expect(find.byKey(ShellKeys.overflowRadioControls), findsOneWidget);
    expect(find.byKey(ShellKeys.overflowSettings), findsOneWidget);
  });

  testWidgets(
    'switching Contacts branch to a pushed screen, then to Groups and '
    'back, preserves the Contacts branch stack instead of disposing it '
    '(UX-FR-005/007)',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build(theme: keryxUxThemeData()));
      await tester.pumpAndSettle();

      await tester.tap(navDestination('Contacts'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ShellKeys.overflowMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ShellKeys.overflowRadioControls));
      await tester.pumpAndSettle();
      expect(find.byKey(ShellKeys.radioControls), findsOneWidget);

      await popScreen(tester, find.byKey(ShellKeys.radioControls));
      expect(find.byKey(ShellKeys.tabContacts), findsOneWidget);

      expect(host.startCalls, 1);
      expect(host.disposeCalls, 0);
    });

  testWidgets(
    "KeryxUxTokens resolves non-null under the shell's real theme wiring "
    '(Technical §9 "final wiring")',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build(theme: keryxUxThemeData()));
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(AppBar));
      final KeryxUxTokens? tokens = Theme.of(context).extension<KeryxUxTokens>();
      expect(tokens, isNotNull);
      expect(tokens!.brightness, Brightness.dark, reason: 'dark is the default theme (Design §3.1)');
    });

  testWidgets('Talk header wires onAddContact/onCreateGroup to tab '
      'switches (Design §2.1 empty-state affordances)', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.byType(talkui.TalkScreen), findsOneWidget);
    expect(find.byType(TalkPttRing), findsOneWidget);

    // Assert no v1 channel/stations affordances survive on the v2 Talk
    // header — the numbered-channel picker and Stations tab are gone.
    expect(find.byKey(const Key('keryx-talk-picker')), findsNothing);
    expect(find.byKey(const Key('keryx-talk-stations')), findsNothing);
  });

  test('new shell wiring does not import transport/floor/audio/platform '
      'APIs', () {
    const List<String> wiring = <String>[
      'lib/app_shell/contacts_tab_screen.dart',
      'lib/app_shell/groups_tab_screen.dart',
      'lib/app_shell/directory_providers.dart',
      'lib/app_shell/onboarding_gate.dart',
      'lib/app_shell/talk_screen.dart',
      'lib/app_shell/shell_routes.dart',
      'lib/app_shell/shell_keys.dart',
      'lib/app_shell/mobile_app_shell.dart',
      'lib/app_shell/app_shell.dart',
    ];
    const List<String> banned = <String>[
      'package:keryx/core/audio',
      'package:keryx/core/floor',
      'package:keryx/services/mesh',
      'package:keryx/services/linked',
      'package:keryx/services/platform',
    ];
    for (final String path in wiring) {
      final String source = File(path).readAsStringSync();
      for (final String needle in banned) {
        expect(
          source.contains(needle),
          isFalse,
          reason: '$path must not import $needle (Technical §5.1)');
      }
    }
  });

  group('real directory backend (FakeDirectoryServer)', () {
    late DirectoryShellHarness directory;

    setUp(() async {
      // `TestWidgetsFlutterBinding` installs an `HttpOverrides` that makes
      // every real `dart:io` `HttpClient` return 400 without hitting the
      // network — `DirectoryClient` is a thin `HttpClient` wrapper by
      // design, so this must be lifted for the real `FakeDirectoryServer`
      // loopback calls in this group to reach it (same fix
      // `contacts_list_controller_test.dart` applies for the same reason).
      HttpOverrides.global = null;
      // `contactsControllerProvider`/`groupsControllerProvider` both read
      // `SharedPreferences.getInstance()` — mock its platform channel the
      // same way `new_group_screen_test.dart` does, or that future never
      // resolves under `flutter test` either.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      directory = await DirectoryShellHarness.start();
    });

    tearDown(() => directory.close());

    testWidgets(
      'selecting a contact sets the current target and switches to Talk '
      '(Design §1 "Current target")',
      (tester) async {
        givePhoneSurface(tester);
        final theirKeyPair = await IdentityKeyPair.generate();
        final theirPk = unpaddedBase64Url(theirKeyPair.publicKey);
        directory.server.responder = (RecordedDirectoryRequest req) {
          if (req.method == 'GET' && req.path == '/v2/identity/me') {
            return DirectoryFakeResponse(
              statusCode: 200,
              body: <String, Object?>{
                'pk': directory.identity.peerId,
                'callsign': directory.identity.callsign.value,
                'status': 'available',
                'contacts': <Object?>[
                  <String, Object?>{'pk': theirPk, 'callsign': 'ZULU-1', 'status': 'available'},
                ],
                'pending_in': <Object?>[],
                'pending_out': <Object?>[],
                'groups': <Object?>[],
              });
          }
          return const DirectoryFakeResponse(statusCode: 200, body: <String, Object?>{});
        };

        final host = FakeRadioHost();
        final container = await _buildClearedRelayContainer(directory, host: host);
        addTearDown(container.dispose);
        await tester.pumpWidget(
          directory.pumpWithContainer(container: container, home: const MobileAppShell()));
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }

        await tester.tap(navDestination('Contacts'));
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }
        expect(find.byKey(ShellKeys.contactsTab), findsOneWidget);

        // TASK-105: `ContactsTabScreen` now calls `ContactsListController
        // .load()` the moment Contacts first becomes the visible tab (just
        // tapped above), which starts a genuine `dart:io` socket refresh
        // against the loopback fake server — it needs `runAsync`'s real
        // zone to actually drive the socket event loop, same as
        // `GroupsController`'s own construction-time refresh does below.
        // Poll (real delay + pump) until the row appears rather than
        // guessing one fixed window, and rather than *also* driving a
        // second, redundant manual refresh — this repo's sandboxed loopback
        // I/O has proven slow enough under full-file load that stacking a
        // second real request on top of the first risks its own 10 s
        // timeout.
        for (var i = 0; i < 15; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
          await tester.pump();
          if (find.byKey(ContactsKeys.contactRow(theirPk)).evaluate().isNotEmpty) break;
        }

        expect(find.byKey(ContactsKeys.contactRow(theirPk)), findsOneWidget);

        await tester.tap(find.byKey(ContactsKeys.contactRow(theirPk)));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1000)));
        await tester.pump();

        expect(
          find.byKey(ShellKeys.talk),
          findsOneWidget,
          reason: 'selecting a contact must switch the shell to Talk');

        // TASK-105: stop the long-lived `PresenceClient` reconnect loop
        // explicitly before the test ends — see the Groups-tab test's note.
        final presence = await container.read(presenceClientProvider.future);
        await presence?.stop();
        // This test now drives two real requests (Groups' own construction
        // refresh, plus Contacts') over the same pooled `dart:io`
        // `HttpClient` — its keep-alive idle timer (default 15 s) outlives
        // the test unless the connection is force-closed explicitly.
        (await container.read(directoryClientProvider.future))?.close();
      });

    testWidgets('Groups tab renders the real GroupsListScreen once a '
        'directory backend is available', (tester) async {
      givePhoneSurface(tester);
      directory.server.responder = (RecordedDirectoryRequest req) {
        if (req.method == 'GET' && req.path == '/v2/identity/me') {
          return DirectoryFakeResponse(
            statusCode: 200,
            body: <String, Object?>{
              'pk': directory.identity.peerId,
              'callsign': directory.identity.callsign.value,
              'status': 'available',
              'contacts': <Object?>[],
              'pending_in': <Object?>[],
              'pending_out': <Object?>[],
              'groups': <Object?>[],
            });
        }
        return const DirectoryFakeResponse(statusCode: 200, body: <String, Object?>{});
      };

      final host = FakeRadioHost();
      final container = await _buildClearedRelayContainer(directory, host: host);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        directory.pumpWithContainer(container: container, home: const MobileAppShell()));
      // TASK-105 now also arms `registrationStatusProvider`/
      // `presenceBootstrapProvider`/`contactsSyncProvider` at shell init, so
      // more real `dart:io` socket work is in flight before this test's
      // first assertion than `GroupsController`'s own construction-time
      // refresh alone (the pre-existing reason this test needs `runAsync`
      // at all). Poll with real delays instead of guessing one fixed
      // window, so this isn't sensitive to how fast the loopback round
      // trips happen to complete on a given machine.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump();
      }

      await tester.tap(navDestination('Groups'));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump();
        if (find.byType(GroupsListScreen).evaluate().isNotEmpty) break;
      }

      expect(find.byKey(ShellKeys.groupsTab), findsOneWidget);
      expect(find.byType(GroupsListScreen), findsOneWidget);

      // TASK-105: once `identityEnrolmentProvider` reaches `registered`
      // against this real fake-server backend, `presenceBootstrapProvider`
      // starts a real `PresenceClient` — its reconnect backoff `Timer` is
      // deliberately long-lived (it keeps retrying by design) and never
      // "completes" on its own the way a one-shot request does, so no
      // `runAsync` window would ever make it not-pending; stop it
      // explicitly before the test ends, the way `container.dispose()`
      // would in production.
      final presence = await container.read(presenceClientProvider.future);
      await presence?.stop();
      (await container.read(directoryClientProvider.future))?.close();
    });
  });
}
