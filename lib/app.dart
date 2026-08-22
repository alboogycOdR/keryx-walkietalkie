import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/features/face/face.dart';
import 'package:keryx/features/settings_panel/back_panel_screen.dart';

/// The app shell. No Material chrome — the radio face is the whole UI
/// (dark background, no app bar, no default Material theming that would
/// fight the face's own housing/glass materials).
///
/// Wraps its own [ProviderScope] so `KeryxApp` is self-contained and
/// bootable in isolation (`pumpWidget(const KeryxApp())`, no external
/// scope required) — `main.dart` no longer needs to supply one.
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
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const Scaffold(body: FaceScreen()),
      // `onSettings` (`FaceScreen`) navigates here by name — see
      // `back_panel_screen.dart`'s `backPanelRouteName` dartdoc for why
      // that screen itself stays host-agnostic (no `Navigator.push` call
      // inside `lib/features/settings_panel/**`).
      routes: <String, WidgetBuilder>{
        backPanelRouteName: (context) => const BackPanelScreen(),
      },
    );
  }
}
