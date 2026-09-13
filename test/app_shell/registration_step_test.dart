import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keryx/app_shell/directory_providers.dart';
import 'package:keryx/app_shell/registration_step.dart';
import 'package:keryx/services/directory/directory.dart' show DirectoryErrorCode;

/// A fixed, self-contained stand-in for [RegistrationStatusController] —
/// `build()` never touches `ref` (no real `identityEnrolmentProvider`/
/// `appForegroundProvider`), so these are pure widget tests of
/// [RegistrationStep]'s rendering and button wiring, independent of the
/// real state machine (that machine's own transitions are covered by
/// `directory_providers_test.dart`).
class _FakeRegistrationStatusController extends RegistrationStatusController {
  _FakeRegistrationStatusController(this._fixed);
  final RegistrationStatus _fixed;
  bool registerNowCalled = false;

  @override
  RegistrationStatus build() => _fixed;

  @override
  void registerNow() {
    registerNowCalled = true;
  }
}

Future<void> _pump(WidgetTester tester, RegistrationStatus status) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        registrationStatusProvider.overrideWith(
          () => _FakeRegistrationStatusController(status),
        ),
      ],
      child: MaterialApp(
        home: RegistrationStep(
          onContinue: () {},
          onBackToCallsign: () {},
        ),
      ),
    ),
  );
}

void main() {
  group('RegistrationStep', () {
    testWidgets('in progress shows a spinner and no button', (tester) async {
      await _pump(tester, const RegistrationInProgress());

      expect(find.byKey(const ValueKey('shell.registration-step-in-progress')), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('registered shows the confirmation and a Continue that '
        'calls onContinue', (tester) async {
      var continued = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            registrationStatusProvider.overrideWith(
              () => _FakeRegistrationStatusController(
                const RegistrationRegistered(callsign: 'JILO', shortCode: 'ab12'),
              ),
            ),
          ],
          child: MaterialApp(
            home: RegistrationStep(
              onContinue: () => continued = true,
              onBackToCallsign: () {},
            ),
          ),
        ),
      );

      expect(find.textContaining('JILO·ab12'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('shell.registration-step-continue')));
      await tester.pump();
      expect(continued, isTrue);
    });

    testWidgets('offline shows "continue anyway" and calls onContinue', (tester) async {
      var continued = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            registrationStatusProvider.overrideWith(
              () => _FakeRegistrationStatusController(
                RegistrationOffline(retryAt: DateTime.now()),
              ),
            ),
          ],
          child: MaterialApp(
            home: RegistrationStep(
              onContinue: () => continued = true,
              onBackToCallsign: () {},
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('shell.registration-step-offline')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('shell.registration-step-continue')));
      await tester.pump();
      expect(continued, isTrue);
    });

    testWidgets(
      'callsign_taken shows a named failure and Back calls onBackToCallsign, '
      'not onContinue',
      (tester) async {
        var continued = false;
        var backToCallsign = false;
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              registrationStatusProvider.overrideWith(
                () => _FakeRegistrationStatusController(
                  const RegistrationFailed(code: DirectoryErrorCode.callsignTaken),
                ),
              ),
            ],
            child: MaterialApp(
              home: RegistrationStep(
                onContinue: () => continued = true,
                onBackToCallsign: () => backToCallsign = true,
              ),
            ),
          ),
        );

        expect(find.byKey(const ValueKey('shell.registration-step-callsign-taken')), findsOneWidget);
        expect(find.byKey(const ValueKey('shell.registration-step-continue')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('shell.registration-step-back')));
        await tester.pump();
        expect(backToCallsign, isTrue);
        expect(continued, isFalse);
      },
    );

    testWidgets('a non-callsign_taken failure behaves like offline (continue '
        'anyway)', (tester) async {
      await _pump(tester, const RegistrationFailed(code: DirectoryErrorCode.unknown));
      expect(find.byKey(const ValueKey('shell.registration-step-offline')), findsOneWidget);
    });

    testWidgets('unregistered (no relay) shows Continue immediately', (tester) async {
      var continued = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            registrationStatusProvider.overrideWith(
              () => _FakeRegistrationStatusController(const RegistrationUnregistered()),
            ),
          ],
          child: MaterialApp(
            home: RegistrationStep(
              onContinue: () => continued = true,
              onBackToCallsign: () {},
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('shell.registration-step-unregistered')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('shell.registration-step-continue')));
      await tester.pump();
      expect(continued, isTrue);
    });

    testWidgets(
      'never blocks reaching Talk: a still-in-progress attempt times out '
      'into a continuable state',
      (tester) async {
        await _pump(tester, const RegistrationInProgress());
        expect(find.byKey(const ValueKey('shell.registration-step-in-progress')), findsOneWidget);

        // Advance past the internal timeout without a real 8 s wait.
        await tester.pump(const Duration(seconds: 9));

        expect(find.byKey(const ValueKey('shell.registration-step-offline')), findsOneWidget);
        expect(find.byKey(const ValueKey('shell.registration-step-continue')), findsOneWidget);
      },
    );
  });
}
