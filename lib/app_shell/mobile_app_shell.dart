import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/presentation/connection_condition.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart' show RadioPhase, RadioState;
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/core/theme/ux_tokens.dart';

import 'channels_screen.dart';
import 'radio_host_provider.dart';
import 'shell_keys.dart';
import 'shell_routes.dart';
import 'stations_screen.dart';
import 'talk_screen.dart';

/// ADR-002 §2/§3 — the R2 Talk-first shell: a top app bar (wordmark,
/// connection indicator, overflow menu) and an icon-only tab strip (Talk ·
/// Channels · Stations) replace TASK-048's bottom `NavigationBar` and its
/// two Channels/Settings destinations. Settings and Radio controls move into
/// the overflow menu, pushed full-screen on the root navigator.
///
/// The host is still read — and, on that first read, constructed and
/// started — exactly once here, at application scope. Every destination
/// below only *consumes* it via [radioHostProvider]; none of them
/// constructs or disposes a session, floor engine, audio pipeline or
/// service controller of its own (Design §1: "[Talk's] presentation
/// lifecycle must not own the radio session"). Switching tabs, or
/// pushing/popping beneath any of them, never calls a host lifecycle
/// method (VT-001).
class MobileAppShell extends ConsumerStatefulWidget {
  const MobileAppShell({super.key});

  @override
  ConsumerState<MobileAppShell> createState() => _MobileAppShellState();
}

class _MobileAppShellState extends ConsumerState<MobileAppShell> {
  /// Talk is index 0 and the default on every launch, including the first
  /// (ADR-002 §2 O1) — no channel picker is forced; the stored/default
  /// channel is used as-is.
  int _index = 0;

  final List<GlobalKey<NavigatorState>> _branchKeys = <GlobalKey<NavigatorState>>[
    GlobalKey<NavigatorState>(debugLabel: 'talk-branch'),
    GlobalKey<NavigatorState>(debugLabel: 'channels-branch'),
    GlobalKey<NavigatorState>(debugLabel: 'stations-branch'),
  ];

  /// One observer per branch so a push/pop *inside* any nested [Navigator]
  /// triggers a rebuild here — otherwise the outer [PopScope]'s `canPop`
  /// would only ever reflect the tree's state as of the last tab switch,
  /// not the branch's live back-stack depth (round-1 rework finding: system
  /// back on a screen pushed inside a tab never reached the branch).
  late final List<_BranchPopObserver> _branchObservers =
      List<_BranchPopObserver>.generate(
    3,
    (_) => _BranchPopObserver(onChanged: () => setState(() {})),
  );

  /// Whether the *active* branch's own back stack has something to pop.
  /// Queried directly from its [NavigatorState] rather than cached, so it
  /// is always current at build time.
  bool get _activeBranchCanPop =>
      _branchKeys[_index].currentState?.canPop() ?? false;

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

  void _onTabTap(int index) {
    if (index == _index) {
      // Re-tapping the active tab pops that branch back to its root —
      // ordinary persistent-nav behaviour; never touches the host and
      // never retunes (UX-FR-005/007).
      _branchKeys[index].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _index = index);
  }

  void _switchTo(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final KeryxUxTokens tokens = KeryxUxTokens.of(context);

    return PopScope(
      // System back is delivered to the *root* Navigator only — the
      // branches' nested `Navigator`s never see it on their own. So the
      // root `canPop` decision must first defer to whatever the active
      // branch can do: if it has a pushed route, this `PopScope` claims the
      // pop (`canPop: false`) and pops that branch itself; only when the
      // active branch is already at its root does tab logic apply — switch
      // a non-Talk tab back to Talk, or (on the Talk root) let the platform
      // have it (ADR-002 §3 A1).
      canPop: _index == 0 && !_activeBranchCanPop,
      onPopInvokedWithResult: (bool didPop, void result) {
        if (didPop) return;
        if (_activeBranchCanPop) {
          _branchKeys[_index].currentState?.pop();
        } else {
          setState(() => _index = 0);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: tokens.surfaceBase,
          foregroundColor: tokens.textPrimary,
          elevation: 0,
          title: Text(
            'KERYX',
            style: KeryxUxTypography.screenTitle.copyWith(
              color: tokens.textPrimary,
            ),
          ),
          actions: <Widget>[
            const _ConnectionIndicator(),
            _OverflowMenu(
              onOpenRadioControls: () => ShellRoutes.openRadioControls(
                context,
                ref.read(radioHostProvider),
              ),
              onOpenSettings: () => ShellRoutes.openSettings(context),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(
              KeryxUxSpacing.minTarget + 1,
            ),
            child: _TabStrip(index: _index, onTap: _onTabTap, tokens: tokens),
          ),
        ),
        body: IndexedStack(
          index: _index,
          children: <Widget>[
            _BranchNavigator(
              navigatorKey: _branchKeys[0],
              observer: _branchObservers[0],
              builder: (_) => TalkScreen(
                onSwitchToStations: () => _switchTo(2),
              ),
            ),
            _BranchNavigator(
              navigatorKey: _branchKeys[1],
              observer: _branchObservers[1],
              builder: (_) => ChannelsScreen(
                onSwitchToTalk: () => _switchTo(0),
              ),
            ),
            _BranchNavigator(
              navigatorKey: _branchKeys[2],
              observer: _branchObservers[2],
              builder: (_) => const StationsScreen(),
            ),
          ],
        ),
      ),
    );
  }
}

/// A branch's own [Navigator] so that pushing e.g. the selector beneath
/// Channels never rebuilds or resets the Talk/Stations branches' state —
/// each destination keeps its own back stack, and switching between them
/// via [IndexedStack] keeps all three mounted (state preserved) rather than
/// disposing the inactive ones (UX-FR-005/007: the current channel stays
/// identifiable regardless of which branch/route is on top). There is no
/// `PageView`/`TabBarView` anywhere in this shell, so a horizontal drag —
/// including one that starts on the PTT — has no swipe gesture to be
/// recognised as (ADR-002 §3 A1).
class _BranchNavigator extends StatelessWidget {
  const _BranchNavigator({
    required this.navigatorKey,
    required this.builder,
    required this.observer,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final WidgetBuilder builder;
  final NavigatorObserver observer;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      observers: <NavigatorObserver>[observer],
      onGenerateRoute: (settings) =>
          MaterialPageRoute<void>(builder: builder, settings: settings),
    );
  }
}

/// Notifies [MobileAppShell] whenever its branch's back stack depth might
/// have changed, so the outer [PopScope]'s `canPop` (which depends on
/// [_MobileAppShellState._activeBranchCanPop]) is recomputed on the next
/// frame rather than staying pinned to the depth at the last tab switch.
class _BranchPopObserver extends NavigatorObserver {
  _BranchPopObserver({required this.onChanged});

  final VoidCallback onChanged;

  void _notify() {
    // Observer callbacks fire mid-navigation transition; defer the
    // `setState` to the next microtask so it never collides with the
    // framework's own build/layout pass for the same frame.
    scheduleMicrotask(onChanged);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _notify();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _notify();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _notify();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _notify();
}

/// Icon-only tab strip under the app bar (ADR-002 §3 A1): Talk (mic),
/// Channels (radio), Stations (groups); each a 48 dp target with a semantic
/// label and an accent underline on the active tab. No swipe — see
/// [_BranchNavigator]'s dartdoc.
class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.index, required this.onTap, required this.tokens});

  final int index;
  final ValueChanged<int> onTap;
  final KeryxUxTokens tokens;

  static const List<(IconData, String, Key)> _tabs = <(IconData, String, Key)>[
    (Icons.mic, 'Talk', ShellKeys.tabTalk),
    (Icons.radio, 'Channels', ShellKeys.tabChannels),
    (Icons.groups, 'Stations', ShellKeys.tabStations),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: KeryxUxSpacing.minTarget,
          child: Row(
            children: List<Widget>.generate(_tabs.length, (int i) {
              final (IconData icon, String label, Key key) = _tabs[i];
              final bool selected = i == index;
              final Color color =
                  selected ? tokens.actionPrimary : tokens.textSecondary;
              return Expanded(
                child: Semantics(
                  label: label,
                  button: true,
                  selected: selected,
                  child: Tooltip(
                    message: label,
                    child: InkWell(
                      key: key,
                      onTap: () => onTap(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(icon, color: color),
                          const SizedBox(height: 4),
                          AnimatedContainer(
                            duration: KeryxUxMotion.stateMax,
                            height: 2,
                            width: 24,
                            color: selected ? tokens.actionPrimary : Colors.transparent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        Divider(height: 1, color: tokens.textSecondary.withValues(alpha: 0.2)),
      ],
    );
  }
}

/// App-bar connection indicator dot (ADR-002 §3 A1: "a connection indicator
/// dot (healthy vs degraded, with semantic label)"). Reads `RadioState` and
/// settings directly — the full `RadioHostSnapshot` subscription every
/// screen (Channels/Talk/Stations) already owns is not needed for this: a
/// [ConnectionCondition] only ever depends on the configured mode and the
/// live route/degraded fields already on `RadioState`.
class _ConnectionIndicator extends ConsumerWidget {
  const _ConnectionIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final KeryxUxTokens tokens = KeryxUxTokens.of(context);
    final RadioState radioState = ref.watch(radioStateProvider);
    final KeryxSettings settings =
        ref.watch(settingsProvider).valueOrNull ?? const KeryxSettings();
    final ConnectionCondition connection = ConnectionCondition(
      configuredMode: settings.mode,
      effectiveRoute: radioState.mode,
      degraded:
          radioState.isNoLink || radioState.phase == RadioPhase.linkDegraded,
    );
    final bool healthy = !connection.degraded;
    // Healthy vs degraded must be visually distinguishable on its own —
    // colour is a redundant cue (Design §3.2), not the only one, but it
    // must still actually carry it. `stateRx`/`stateWarning` are the
    // palette's own "receiving" (green) and "warning" (amber) tokens, far
    // enough apart in hue to read as distinct at 10 dp (round-1 rework
    // finding: `actionPrimary` vs `stateWarning` were ~8° apart and
    // indistinguishable). Unresolved/connecting state is neither yet —
    // it renders the neutral PTT-ring colour instead of claiming healthy.
    final Color color = !connection.isResolved
        ? tokens.pttNeutralRing
        : healthy
            ? tokens.stateRx
            : tokens.stateWarning;
    final String status = !connection.isResolved
        ? 'connecting'
        : healthy
            ? 'healthy'
            : 'degraded';

    return Semantics(
      label: 'Connection $status, ${connection.routeLabel}',
      child: Padding(
        key: ShellKeys.connectionIndicator,
        padding: const EdgeInsets.symmetric(
          horizontal: KeryxUxSpacing.controlGap,
        ),
        child: Center(
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ),
      ),
    );
  }
}

/// App-bar overflow menu — Radio controls and Settings (ADR-002 §3 A1),
/// pushed full-screen on the root navigator (this build context, not a
/// branch's — the app bar sits outside every [_BranchNavigator]).
class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({
    required this.onOpenRadioControls,
    required this.onOpenSettings,
  });

  final VoidCallback onOpenRadioControls;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_OverflowAction>(
      key: ShellKeys.overflowMenu,
      tooltip: 'More',
      onSelected: (_OverflowAction action) {
        switch (action) {
          case _OverflowAction.radioControls:
            onOpenRadioControls();
          case _OverflowAction.settings:
            onOpenSettings();
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<_OverflowAction>>[
        const PopupMenuItem<_OverflowAction>(
          key: ShellKeys.overflowRadioControls,
          value: _OverflowAction.radioControls,
          child: Text('Radio controls'),
        ),
        const PopupMenuItem<_OverflowAction>(
          key: ShellKeys.overflowSettings,
          value: _OverflowAction.settings,
          child: Text('Settings'),
        ),
      ],
    );
  }
}

enum _OverflowAction { radioControls, settings }
