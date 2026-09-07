import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/theme/ux_tokens.dart';

import 'fake_radio_host.dart';

/// TASK-048 — `MobileAppShell` acceptance criteria: single host mounted
/// once above the navigator, exactly two persistent destinations (Channels
/// default landing, Settings), and navigation alone never touches a host
/// lifecycle method (VT-001).
void main() {
  late FakeRadioHost host;

  Widget build({ThemeData? theme}) {
    host = FakeRadioHost();
    return ProviderScope(
      overrides: <Override>[
        radioHostProvider.overrideWithValue(host),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
      child: MaterialApp(theme: theme, home: const MobileAppShell()),
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

  testWidgets(
    'switching Channels branch to a pushed Talk, then to Settings and back, '
    'preserves the Channels branch stack instead of disposing it '
    '(UX-FR-005/007 — Review round 1 finding 2)',
    (tester) async {
      // `keryxUxThemeData()` is the exact theme value `lib/app.dart` wires
      // as `MaterialApp.theme` (Review round 1 finding 1) — `KeryxApp`
      // itself cannot be pumped directly in a widget test because its
      // internal `ProviderScope` has no override seam and its default
      // providers boot real platform I/O (secure storage, audio, radio
      // service) that no widget test in this repo runs unmocked (see e.g.
      // `test/features/face/face_screen_test.dart`'s `FakeSessionHost`);
      // this reproduces the real composition — same theme value, same
      // `MobileAppShell` widget tree — with the same fake-host seam every
      // other widget test in this file already uses.
      await tester.pumpWidget(build(theme: keryxUxThemeData()));
      await tester.pumpAndSettle();

      // Channels -> Talk (pushed onto the Channels branch's own Navigator).
      await tester.tap(find.text('Current: CH 1 · Code 0'));
      await tester.pumpAndSettle();
      expect(find.text('Talk'), findsWidgets);

      // Switch to the Settings destination — an `IndexedStack` must keep
      // the Channels branch (with Talk still pushed) alive rather than
      // disposing it, unlike a bare `[...][_index]` child would.
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      expect(find.text('Talk'), findsNothing);

      // Switch back to Channels: Talk must still be on that branch's
      // stack (not popped, not rebuilt from scratch).
      await tester.tap(find.text('Channels').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Talk'),
        findsWidgets,
        reason:
            'the Channels branch stack must survive a destination switch '
            '— Talk was pushed before switching away and must still be on '
            'top when switching back',
      );

      expect(host.startCalls, 1);
      expect(host.disposeCalls, 0);
    },
  );

  testWidgets(
    "KeryxUxTokens resolves non-null under the shell's real theme wiring "
    '(Review round 1 finding 1 — Technical §9 "final wiring")',
    (tester) async {
      await tester.pumpWidget(build(theme: keryxUxThemeData()));
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(NavigationBar));
      final KeryxUxTokens? tokens =
          Theme.of(context).extension<KeryxUxTokens>();
      expect(tokens, isNotNull);
      expect(
        tokens!.brightness,
        Brightness.dark,
        reason: 'dark is the default theme (Design §3.1)',
      );
      expect(tokens.palette.surfaceBase, KeryxUxPalette.dark.surfaceBase);
    },
  );
}
