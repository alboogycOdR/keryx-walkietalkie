import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/features/onboarding/onboarding_keys.dart';

import '../core/identity/memory_identity_store.dart';
import 'fake_radio_host.dart';

/// TASK-104 (C): the `registering` stage this task inserts between
/// create/restore and the shell — "make the onboarding sequence as
/// explicit as possible, with confirmations that it's been registered
/// after they choose the ID" (owner requirements 2026-09-13).
///
/// No relay configured here (`directoryBaseUriResolverProvider` returns
/// `null`, matching a hostless/empty `relayUrl`) so `identityEnrolmentProvider`
/// resolves to `notApplicable` immediately — this file exercises the gate's
/// own stage wiring, not the network state machine itself (that is
/// `directory_providers_test.dart`'s and `registration_step_test.dart`'s
/// job).
final _stubIdentity = DeviceIdentity(
  installUuid: '00000000-0000-4000-8000-000000000000',
  peerId: 'stub-peer',
  callsign: Callsign.parse('STUB-1'),
);

Widget _pumpTarget({IdentityStore? store}) {
  return ProviderScope(
    overrides: <Override>[
      radioHostProvider.overrideWithValue(FakeRadioHost()),
      settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      identityProvider.overrideWith((ref) async => _stubIdentity),
      directoryBaseUriResolverProvider.overrideWithValue((_) => null),
    ],
    child: MaterialApp(
      home: OnboardingGate(
        identityRepository: IdentityRepository(store ?? MemoryIdentityStore()),
        store: store ?? MemoryIdentityStore(),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'creating a new ID shows the registering step before the shell, and '
    'Continue reaches it',
    (tester) async {
      await tester.pumpWidget(_pumpTarget());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('shell.onboarding-chooser')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('shell.onboarding-create')));
      await tester.pumpAndSettle();

      expect(find.byKey(OnboardingKeys.callsignScreen), findsOneWidget);
      await tester.enterText(find.byKey(OnboardingKeys.callsignField), 'ALPHA1');
      await tester.tap(find.byKey(OnboardingKeys.continueButton));
      await tester.pumpAndSettle();

      expect(find.byKey(OnboardingKeys.phraseScreen), findsOneWidget);
      await tester.tap(find.byKey(OnboardingKeys.writtenDown));
      await tester.pumpAndSettle();

      // Registering stage — no relay configured, so the state resolves to
      // "unregistered" and Continue is immediately available.
      expect(find.byKey(const ValueKey('shell.registration-step')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('shell.registration-step-continue')));
      await tester.pumpAndSettle();

      // Reached the shell.
      expect(find.byKey(const ValueKey('shell.registration-step')), findsNothing);
      expect(find.byType(MobileAppShell), findsOneWidget);
    },
  );

  testWidgets(
    'a keyed install (existing identity) skips straight to the shell — no '
    'registering step for a restart',
    (tester) async {
      final store = MemoryIdentityStore(<String, String>{
        IdentityRepository.privateKeySeedKey:
            'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        IdentityRepository.callsignKey: 'BRAVO-7',
      });
      await tester.pumpWidget(_pumpTarget(store: store));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('shell.onboarding-chooser')), findsNothing);
      expect(find.byKey(const ValueKey('shell.registration-step')), findsNothing);
      expect(find.byType(MobileAppShell), findsOneWidget);
    },
  );
}
