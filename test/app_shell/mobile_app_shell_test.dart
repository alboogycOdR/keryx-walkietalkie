import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/core/settings/settings_repository.dart';

import 'fake_radio_host.dart';

/// TASK-048 — `MobileAppShell` acceptance criteria: single host mounted
/// once above the navigator, exactly two persistent destinations (Channels
/// default landing, Settings), and navigation alone never touches a host
/// lifecycle method (VT-001).
void main() {
  late FakeRadioHost host;

  Widget build() {
    host = FakeRadioHost();
    return ProviderScope(
      overrides: <Override>[
        radioHostProvider.overrideWithValue(host),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
      child: const MaterialApp(home: MobileAppShell()),
    );
  }

  testWidgets('Channels is the default landing destination (UX-D01)', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.text('Channels'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('exactly two persistent destinations exist — no third for an '
      'unimplemented surface (UX-D01/UX-D02)', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDestination), findsNWidgets(2));
    expect(find.text('Settings'), findsWidgets);
    // No fabricated third destination (e.g. a Contacts tab — UX-D02).
    expect(find.text('Contacts'), findsNothing);
  });

  testWidgets('the host is constructed and started exactly once on mount', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(host.startCalls, 1);
    expect(host.disposeCalls, 0);
  });

  testWidgets(
    'Channels -> Talk -> Settings -> Talk causes zero additional host '
    'start/dispose/tune calls (VT-001)',
    (tester) async {
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(host.startCalls, 1);

      // Channels -> Talk.
      await tester.tap(find.text('Current: CH 1 · Code 0'));
      await tester.pumpAndSettle();
      expect(find.text('Talk'), findsWidgets);

      // Talk -> back to Channels.
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Channels -> Settings.
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();

      // Settings -> back to Channels branch -> Talk again.
      await tester.tap(find.text('Channels').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Current: CH 1 · Code 0'));
      await tester.pumpAndSettle();
      expect(find.text('Talk'), findsWidgets);

      expect(host.startCalls, 1, reason: 'navigation must never re-start the host');
      expect(host.disposeCalls, 0, reason: 'navigation must never dispose the host');
      expect(host.tuneCalls, isEmpty, reason: 'navigation alone must never retune');
    },
  );

  testWidgets('re-tapping the active destination pops its branch to root '
      'without touching the host', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Current: CH 1 · Code 0'));
    await tester.pumpAndSettle();
    expect(find.text('Talk'), findsWidgets);

    // Re-tap Channels (already-active branch's own destination) to pop.
    await tester.tap(find.text('Channels').last);
    await tester.pumpAndSettle();

    expect(find.text('Talk'), findsNothing);
    expect(host.startCalls, 1);
    expect(host.disposeCalls, 0);
  });

  testWidgets('legacy face route is not linked from any shell destination', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.byTooltip(legacyFaceRouteName), findsNothing);
    expect(find.text(legacyFaceRouteName), findsNothing);
  });
}
