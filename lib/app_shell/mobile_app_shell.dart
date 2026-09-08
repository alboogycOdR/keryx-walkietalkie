import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/features/settings/settings_screen.dart';

import 'channels_screen.dart';
import 'radio_host_provider.dart';
import 'shell_keys.dart';

/// Technical §2's `MobileAppShell` — the two persistent primary
/// destinations (Design §1: "Use two persistent primary destinations:
/// Channels and Settings") mounted beneath the single, app-scoped
/// [RadioHost] this task hoists above the navigator (Technical §9).
///
/// TASK-052 swapped TASK-048's placeholder bodies for the real Wave-4
/// screens: Channels → [ChannelsLanding], Settings → [SettingsScreen],
/// with Talk / selector / Stations / Radio Controls / Event QR pushed
/// from this composition root.
///
/// The host is read — and, on that first read, constructed and started —
/// exactly once here, at application scope. Every destination below only
/// *consumes* it via [radioHostProvider]; none of them constructs or
/// disposes a session, floor engine, audio pipeline or service controller
/// of its own (Design §1: "[Talk's] presentation lifecycle must not own
/// the radio session"). Switching destinations, or pushing/popping beneath
/// either of them, never calls a host lifecycle method (VT-001).
class MobileAppShell extends ConsumerStatefulWidget {
  const MobileAppShell({super.key});

  @override
  ConsumerState<MobileAppShell> createState() => _MobileAppShellState();
}

class _MobileAppShellState extends ConsumerState<MobileAppShell> {
  int _index = 0;

  final List<GlobalKey<NavigatorState>> _branchKeys = <GlobalKey<NavigatorState>>[
    GlobalKey<NavigatorState>(debugLabel: 'channels-branch'),
    GlobalKey<NavigatorState>(debugLabel: 'settings-branch'),
  ];

  @override
  void initState() {
    super.initState();
    // Constructs the single app-scoped host on first read (a plain
    // `Provider`, kept alive for this widget's single `ProviderScope`) and
    // boots it exactly once, here, above every route. A microtask defers
    // the first dispatch past this frame's build — Riverpod forbids
    // mutating a provider mid-build — mirroring the pre-hoist
    // `FaceScreen.initState` this replaces (Technical §9).
    final host = ref.read(radioHostProvider);
    unawaited(Future.microtask(host.start));
  }

  void _onDestinationSelected(int index) {
    if (index == _index) {
      // Re-tapping the active destination pops that branch back to its
      // root — ordinary persistent-bottom-nav behaviour; never touches the
      // host and never retunes (UX-FR-005/007).
      _branchKeys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          _BranchNavigator(
            navigatorKey: _branchKeys[0],
            builder: (_) => const ChannelsScreen(),
          ),
          _BranchNavigator(
            navigatorKey: _branchKeys[1],
            builder: (_) => const SettingsScreen(key: ShellKeys.settings),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onDestinationSelected,
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.radio), label: 'Channels'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

/// A branch's own [Navigator] so that pushing e.g. Talk beneath Channels
/// never rebuilds or resets the Settings branch's state — each destination
/// keeps its own back stack, and switching between them via [IndexedStack]
/// keeps both mounted (state preserved) rather than disposing the inactive
/// one (UX-FR-005/007: the current channel stays identifiable regardless of
/// which branch/route is on top).
class _BranchNavigator extends StatelessWidget {
  const _BranchNavigator({required this.navigatorKey, required this.builder});

  final GlobalKey<NavigatorState> navigatorKey;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute: (settings) =>
          MaterialPageRoute<void>(builder: builder, settings: settings),
    );
  }
}
