import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/identity/identity.dart'
    show IdentityRepository, IdentityStore;
import 'package:keryx/core/theme/ux_tokens.dart' show keryxUxThemeData;
import 'package:keryx/features/settings_panel/back_panel_screen.dart';

import 'app_shell/app_shell.dart';

/// TASK-048 — the app shell. Replaces the pre-redesign single-screen face
/// composition with [MobileAppShell]'s two persistent primary destinations
/// (Design §1; ADR-001 §3 item 1 supersedes PTS P1's "no bottom nav"
/// clause and §6.1's single-screen mandate).
///
/// Wraps its own [ProviderScope] so `KeryxApp` is self-contained and
/// bootable in isolation (`pumpWidget(const KeryxApp())`, no external
/// scope required) — `main.dart` doesn't need to supply one. Exactly one
/// `ProviderScope` exists anywhere in the tree (Technical §1/§2).
class KeryxApp extends StatelessWidget {
  const KeryxApp({super.key, this.identityStore});

  /// Test seam for [OnboardingGate]'s fresh-install check — production
  /// leaves this `null`, which lets `OnboardingGate` construct its own
  /// real `SecureIdentityStore()`-backed `IdentityRepository` (Technical
  /// §8). A real-composition test that needs to boot straight through to
  /// `MobileAppShell` (a keyed install) passes an in-memory store seeded
  /// with `IdentityRepository.privateKeySeedKey` instead of exercising the
  /// real `flutter_secure_storage` platform channel, which has no mock
  /// handler under `flutter test`.
  final IdentityStore? identityStore;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: _KeryxMaterialShell(identityStore: identityStore),
    );
  }
}

class _KeryxMaterialShell extends StatelessWidget {
  const _KeryxMaterialShell({this.identityStore});

  final IdentityStore? identityStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Keryx',
      debugShowCheckedModeBanner: false,
      // TASK-047's successor design tokens (Design §3.1: dark is the
      // default theme; §3 sets the light column too). This is the "final
      // wiring" site named in Technical §9 — Wave 4 screens read
      // `KeryxUxTokens.of(context)` / `Theme.of(context).extension` and
      // must never see a null extension under the real composition (only
      // `MaterialApp.theme` is wired; `darkTheme`/`themeMode` are left at
      // the builder's discretion and are not required by the spec text
      // above). The legacy `FaceScreen` below paints entirely from its own
      // hard-coded `KeryxTheme` statics, not `Theme.of(context)`, so this
      // swap does not touch its rendering.
      theme: keryxUxThemeData(),
      // v2 (TASK-093, Design §2.6): first launch routes through
      // `OnboardingGate` before the shell — a keyed install (including a
      // migrated v1 install) passes straight through to `MobileAppShell`.
      home: OnboardingGate(
        store: identityStore,
        identityRepository:
            identityStore == null ? null : IdentityRepository(identityStore!),
      ),
      // Route registration lives here and nowhere else (Technical §9).
      // `backPanelRouteName` stays registered — `MobileAppShell`'s own
      // Settings destination embeds `BackPanelScreen` directly rather than
      // pushing this route, but it is still reachable by name for whatever
      // still expects it.
      //
      // The dev-only `legacyFaceRouteName` registration (Technical §10) is
      // deleted by this task per its own Description: the debug legacy-face
      // route this shell no longer links from anywhere.
      routes: <String, WidgetBuilder>{
        backPanelRouteName: (context) => const BackPanelScreen(),
      },
    );
  }
}
