import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/theme/ux_tokens.dart' show keryxUxThemeData;
import 'package:keryx/features/face/face.dart' show FaceScreen;
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
  const KeryxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProviderScope(
      child: _KeryxMaterialShell(),
    );
  }
}

class _KeryxMaterialShell extends StatelessWidget {
  const _KeryxMaterialShell();

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
      home: const MobileAppShell(),
      // Route registration lives here and nowhere else (Technical §9).
      // `backPanelRouteName` stays registered because the dev-only legacy
      // `FaceScreen` below still navigates to it by name (its own `⚙` key)
      // — `MobileAppShell`'s own Settings destination embeds
      // `BackPanelScreen` directly rather than pushing this route.
      //
      // `legacyFaceRouteName` (Technical §10) is registered only in debug
      // builds and is never linked from any widget in `lib/app_shell/**` —
      // it exists purely so the pre-redesign face stays reachable by name
      // during the migration; TASK-061 deletes both the legacy face and
      // this registration.
      routes: <String, WidgetBuilder>{
        backPanelRouteName: (context) => const BackPanelScreen(),
        if (kDebugMode) legacyFaceRouteName: (context) => const FaceScreen(),
      },
    );
  }
}
