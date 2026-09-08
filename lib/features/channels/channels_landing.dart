import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/app_shell/radio_host_provider.dart';
import 'package:keryx/core/presentation/presentation.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart' show RadioPhase;
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/channel_selector/channel_selector_copy.dart';
import 'package:keryx/features/channel_selector/tune_coordinator.dart';

import 'channel_format.dart';
import 'channel_memory.dart';
import 'presentation_icons.dart';

/// Keys for widget tests — content order and field identity (UX-FR-002).
abstract final class ChannelsLandingKeys {
  static const Key brand = Key('channels.brand');
  static const Key connection = Key('channels.connection');
  static const Key currentCard = Key('channels.current-card');
  static const Key configuredMode = Key('channels.configured-mode');
  static const Key effectiveRoute = Key('channels.effective-route');
  static const Key actualStatus = Key('channels.actual-status');
  static const Key openTalk = Key('channels.open-talk');
  static const Key recentSection = Key('channels.recent-section');
  static const Key emptyMemory = Key('channels.empty-memory');
  static const Key selectChannel = Key('channels.select-channel');
  static const Key recallProgress = Key('channels.recall-progress');
  static const Key recallFeedback = Key('channels.recall-feedback');
  static const Key recallRetry = Key('channels.recall-retry');

  static Key recentEntry(int channel, int privacyCode) =>
      Key('channels.recent.$channel.$privacyCode');
}

/// Design §2.1 Channels landing — brand + connection, current-channel
/// card, Open Talk, recent recall, Select channel.
///
/// Reads TASK-046's [RadioViewState] projection and dispatches only
/// [RadioViewIntents]. Open Talk and Select channel are callbacks: Talk
/// is TASK-051's territory and the selector flow is TASK-050's; this
/// screen only launches them. Persistent navigation is supplied by the
/// caller (the TASK-048 shell already owns the bottom bar).
class ChannelsLanding extends ConsumerStatefulWidget {
  const ChannelsLanding({
    super.key,
    required this.onOpenTalk,
    required this.onSelectChannel,
    this.persistentNavigation,
    this.watchChannel,
  });

  /// One-tap shortcut onto the current channel (Design §2.1). Must not
  /// retune (UX-FR-005).
  final VoidCallback onOpenTalk;

  /// Launches TASK-050's selector / direct-tune flow. Must not retune
  /// itself — Cancel/Apply live on that screen.
  final VoidCallback onSelectChannel;

  /// Optional bottom bar so content-order tests can include persistent
  /// nav. Production leaves this null; [MobileAppShell] already paints
  /// the Channels/Settings bar around this body.
  final Widget? persistentNavigation;

  /// Test seam for Design §2.1's "no new background subscriptions to all
  /// 99 channels". Production omits it. This widget must not invoke it
  /// for any channel — presence on other channels is unauthorized, and
  /// current-channel roster is TASK-053's, not an online count here
  /// (UX-FR-008).
  final void Function(int channel)? watchChannel;

  @override
  ConsumerState<ChannelsLanding> createState() => _ChannelsLandingState();
}

class _ChannelsLandingState extends ConsumerState<ChannelsLanding> {
  StreamSubscription<RadioHostSnapshot>? _hostSub;
  RadioHostSnapshot _snapshot = const RadioHostSnapshot();

  /// Test seam copy. Never invoked — a 1–99 loop over this is the
  /// Design §2.1 prohibition the landing tests mutation-check.
  void Function(int channel)? _presenceSweep;

  /// TASK-067: routes the recall-tap through the same
  /// pending/success/failure/retry result-handling TASK-050 built for its
  /// own sheet, rather than discarding the `TuneResult` (TASK-049's
  /// review finding). Reuses [TuneCoordinator] directly — no second,
  /// independent implementation of UX-FR-009's four-state model.
  late final TuneCoordinator _coordinator;
  StreamSubscription<TuneOutcome>? _outcomeSub;
  RadioPhase _lastPhase = RadioPhase.off;
  TuneOutcome? _lastOutcome;

  @override
  void initState() {
    super.initState();
    // Design §2.1: do not subscribe presence for any channel. The
    // [ChannelsLanding.watchChannel] seam is a test recorder; it is
    // captured here and never invoked.
    _presenceSweep = widget.watchChannel;

    final RadioHost host = ref.read(radioHostProvider);
    _snapshot = host.current;
    _hostSub = host.changes.listen((RadioHostSnapshot snapshot) {
      if (!mounted) {
        return;
      }
      setState(() => _snapshot = snapshot);
    });

    _coordinator = TuneCoordinator(intents: RadioViewIntents(host));
    _outcomeSub = _coordinator.outcomes.listen((TuneOutcome outcome) {
      if (!mounted) return;
      setState(() => _lastOutcome = outcome);
    });
  }

  @override
  void dispose() {
    _presenceSweep = null;
    unawaited(_hostSub?.cancel());
    unawaited(_outcomeSub?.cancel());
    _coordinator.dispose();
    super.dispose();
  }

  void _onPhaseMaybeChanged(RadioPhase phase) {
    if (phase == _lastPhase) return;
    _lastPhase = phase;
    _coordinator.onPhaseChanged(phase);
  }

  void _tuneRecent(TunedChannel entry) {
    if (_coordinator.isBusy) return;
    setState(() => _lastOutcome = null);
    _coordinator.request(
      channel: entry.channel,
      code: entry.privacyCode,
      currentPhase: _lastPhase,
    );
  }

  void _retryRecall() {
    final TuneOutcome? outcome = _lastOutcome;
    if (outcome == null) return;
    setState(() => _lastOutcome = null);
    _coordinator.retry(outcome.target, currentPhase: _lastPhase);
  }

  @override
  Widget build(BuildContext context) {
    assert(identical(_presenceSweep, widget.watchChannel));
    final KeryxUxTokens tokens = KeryxUxTokens.of(context);
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const KeryxSettings();
    final radioState = ref.watch(radioStateProvider);
    _onPhaseMaybeChanged(radioState.phase);
    final view = RadioViewState.project(
      radioState: radioState,
      hostSnapshot: _snapshot,
      settings: settings,
    );
    final List<TunedChannel> memory = visibleChannelMemory(
      _snapshot.channelMemory,
    );
    final bool deferredForTx =
        _coordinator.pendingTarget != null &&
        (radioState.phase == RadioPhase.tx ||
            radioState.phase == RadioPhase.txRequest);

    return Scaffold(
      backgroundColor: tokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: tokens.surfaceBase,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        title: Text(
          'KERYX',
          key: ChannelsLandingKeys.brand,
          style: KeryxUxTypography.screenTitle.copyWith(
            color: tokens.textPrimary,
          ),
        ),
        actions: <Widget>[_ConnectionIndicator(view: view, tokens: tokens)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          KeryxUxSpacing.pageMargin,
          KeryxUxSpacing.grid,
          KeryxUxSpacing.pageMargin,
          KeryxUxSpacing.pageMargin,
        ),
        children: <Widget>[
          _CurrentChannelCard(
            view: view,
            tokens: tokens,
            onOpenTalk: widget.onOpenTalk,
          ),
          const SizedBox(height: KeryxUxSpacing.cardSpacing),
          _PrimaryActionButton(
            key: ChannelsLandingKeys.openTalk,
            label: 'Open Talk',
            icon: Icons.chat_bubble_outline,
            tokens: tokens,
            onPressed: widget.onOpenTalk,
          ),
          const SizedBox(height: KeryxUxSpacing.cardSpacing),
          if (_coordinator.isBusy)
            Padding(
              key: ChannelsLandingKeys.recallProgress,
              padding: const EdgeInsets.only(bottom: KeryxUxSpacing.controlGap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    deferredForTx
                        ? ChannelSelectorCopy.tuneQueuedDuringTx
                        : ChannelSelectorCopy.tuningInProgress,
                    style: KeryxUxTypography.secondary.copyWith(
                      color: tokens.stateWarning,
                    ),
                  ),
                  const SizedBox(height: KeryxUxSpacing.controlGap),
                  LinearProgressIndicator(color: tokens.actionPrimary),
                ],
              ),
            )
          else if (_lastOutcome != null)
            _RecallFeedback(
              key: ChannelsLandingKeys.recallFeedback,
              outcome: _lastOutcome!,
              tokens: tokens,
              onRetry: _retryRecall,
            ),
          _RecentSection(
            memory: memory,
            tokens: tokens,
            busy: _coordinator.isBusy,
            onTune: _tuneRecent,
          ),
          const SizedBox(height: KeryxUxSpacing.cardSpacing),
          _SecondaryActionButton(
            key: ChannelsLandingKeys.selectChannel,
            label: 'Select channel',
            icon: Icons.dialpad,
            tokens: tokens,
            onPressed: widget.onSelectChannel,
          ),
        ],
      ),
      bottomNavigationBar: widget.persistentNavigation,
    );
  }
}

class _ConnectionIndicator extends StatelessWidget {
  const _ConnectionIndicator({required this.view, required this.tokens});

  final RadioViewState view;
  final KeryxUxTokens tokens;

  @override
  Widget build(BuildContext context) {
    final bool degraded = view.connection.degraded;
    final String label = actualConnectionLabel(view.connection);
    final Color color = degraded ? tokens.stateWarning : tokens.actionPrimary;
    final IconData icon = degraded
        ? Icons.wifi_off_outlined
        : Icons.wifi_outlined;

    return Semantics(
      label: 'Connection $label',
      child: Padding(
        key: ChannelsLandingKeys.connection,
        padding: const EdgeInsets.symmetric(
          horizontal: KeryxUxSpacing.pageMargin,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color, size: 20),
            const SizedBox(width: KeryxUxSpacing.controlGap),
            Text(
              label,
              style: KeryxUxTypography.secondary.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentChannelCard extends StatelessWidget {
  const _CurrentChannelCard({
    required this.view,
    required this.tokens,
    required this.onOpenTalk,
  });

  final RadioViewState view;
  final KeryxUxTokens tokens;
  final VoidCallback onOpenTalk;

  @override
  Widget build(BuildContext context) {
    final String channelLabel = formatChannelCode(
      view.channel,
      view.privacyCode,
    );
    final String configured =
        'Configured ${radioModeLabel(view.connection.configuredMode)}';
    final String effective =
        'Effective ${radioModeLabel(view.connection.effectiveRoute)}';
    final String status = view.connection.degraded
        ? 'Status Connection lost'
        : 'Status ${view.phaseCue.label}';
    final Color statusColor = view.connection.degraded
        ? tokens.stateWarning
        : view.phaseCue.label == 'Transmitting'
        ? tokens.stateTx
        : view.phaseCue.label == 'Receiving'
        ? tokens.stateRx
        : tokens.actionPrimary;

    return Material(
      key: ChannelsLandingKeys.currentCard,
      color: tokens.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KeryxUxSpacing.grid),
        side: BorderSide(color: tokens.borderDefault),
      ),
      child: InkWell(
        onTap: onOpenTalk,
        borderRadius: BorderRadius.circular(KeryxUxSpacing.grid),
        // Same destination as the explicit "Open Talk" button below, but a
        // screen reader has no other cue that tapping this whole card does
        // the same thing (Design §5; TASK-057).
        child: Semantics(
          button: true,
          label: 'Current channel $channelLabel, open Talk',
          // TASK-057 round 2 (non-blocking finding 4): without this the
          // card's own child text (channel label, configured/effective
          // mode, status) is still individually announced after the
          // composite label above — a duplicated announcement. Matches the
          // pattern already used on Settings' stepper-value fix.
          excludeSemantics: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: KeryxUxSpacing.minTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.all(KeryxUxSpacing.cardSpacing),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    channelLabel,
                    style: KeryxUxTypography.sectionTitle.copyWith(
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: KeryxUxSpacing.controlGap),
                  Text(
                    configured,
                    key: ChannelsLandingKeys.configuredMode,
                    style: KeryxUxTypography.body.copyWith(
                      color: tokens.textPrimary,
                    ),
                  ),
                  Text(
                    effective,
                    key: ChannelsLandingKeys.effectiveRoute,
                    style: KeryxUxTypography.body.copyWith(
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: KeryxUxSpacing.controlGap),
                  Row(
                    children: <Widget>[
                      Icon(
                        iconForPresentation(view.phaseCue.iconId),
                        color: statusColor,
                        size: 20,
                      ),
                      const SizedBox(width: KeryxUxSpacing.controlGap),
                      Expanded(
                        child: Text(
                          status,
                          key: ChannelsLandingKeys.actualStatus,
                          style: KeryxUxTypography.secondary.copyWith(
                            color: tokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentSection extends StatelessWidget {
  const _RecentSection({
    required this.memory,
    required this.tokens,
    required this.onTune,
    this.busy = false,
  });

  final List<TunedChannel> memory;
  final KeryxUxTokens tokens;
  final ValueChanged<TunedChannel> onTune;

  /// TASK-067: a pending recall retune blocks a competing tap (matches the
  /// standard TASK-050's own sheet set — Design §2.3's "prevents competing
  /// tune actions").
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ChannelsLandingKeys.recentSection,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Recent channels',
          style: KeryxUxTypography.sectionTitle.copyWith(
            color: tokens.textPrimary,
          ),
        ),
        const SizedBox(height: KeryxUxSpacing.controlGap),
        if (memory.isEmpty)
          Text(
            'No recently tuned channels.',
            key: ChannelsLandingKeys.emptyMemory,
            style: KeryxUxTypography.body.copyWith(color: tokens.textSecondary),
          )
        else
          for (final TunedChannel entry in memory)
            _RecentTile(
              entry: entry,
              tokens: tokens,
              onTune: onTune,
              busy: busy,
            ),
      ],
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.entry,
    required this.tokens,
    required this.onTune,
    this.busy = false,
  });

  final TunedChannel entry;
  final KeryxUxTokens tokens;
  final ValueChanged<TunedChannel> onTune;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final String label = formatChannelCode(entry.channel, entry.privacyCode);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: KeryxUxSpacing.minTarget),
      child: ListTile(
        key: ChannelsLandingKeys.recentEntry(entry.channel, entry.privacyCode),
        contentPadding: EdgeInsets.zero,
        enabled: !busy,
        leading: Icon(Icons.history, color: tokens.textSecondary),
        title: Text(
          label,
          style: KeryxUxTypography.body.copyWith(color: tokens.textPrimary),
        ),
        onTap: busy ? null : () => onTune(entry),
      ),
    );
  }
}

/// TASK-067: renders the recall tap's terminal [TuneOutcome] — a
/// failed/unavailable outcome is visibly represented, with a real Retry
/// path, instead of the `unawaited(...)` discard TASK-049's review flagged.
/// Mirrors `ChannelSelectorScreen._buildFeedback` (TASK-050) so the same
/// four-state model reads identically from either entry point.
class _RecallFeedback extends StatelessWidget {
  const _RecallFeedback({
    super.key,
    required this.outcome,
    required this.tokens,
    required this.onRetry,
  });

  final TuneOutcome outcome;
  final KeryxUxTokens tokens;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final String message = switch (outcome.kind) {
      TuneOutcomeKind.success =>
        'Tuned to '
            '${formatChannelCode(outcome.target.channel, outcome.target.privacyCode)}.',
      TuneOutcomeKind.invalid => ChannelSelectorCopy.tuneInvalid,
      TuneOutcomeKind.cancelled => ChannelSelectorCopy.tuneCancelled,
      TuneOutcomeKind.retryableFailure => ChannelSelectorCopy.tuneFailed,
    };
    final Color color = outcome.kind == TuneOutcomeKind.success
        ? tokens.stateRx
        : outcome.kind == TuneOutcomeKind.retryableFailure
        ? tokens.stateEmergency
        : tokens.stateWarning;
    return Padding(
      padding: const EdgeInsets.only(bottom: KeryxUxSpacing.controlGap),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              message,
              style: KeryxUxTypography.secondary.copyWith(color: color),
            ),
          ),
          if (outcome.kind == TuneOutcomeKind.retryableFailure)
            TextButton(
              key: ChannelsLandingKeys.recallRetry,
              onPressed: onRetry,
              child: const Text(ChannelSelectorCopy.retry),
            ),
        ],
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.tokens,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final KeryxUxTokens tokens;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: KeryxUxSpacing.minTarget),
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label, style: KeryxUxTypography.body),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(KeryxUxSpacing.minTarget),
          backgroundColor: tokens.actionPrimary,
          foregroundColor: tokens.palette.contrastingOn(tokens.actionPrimary),
        ),
      ),
    );
  }
}

class _SecondaryActionButton extends StatelessWidget {
  const _SecondaryActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.tokens,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final KeryxUxTokens tokens;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: KeryxUxSpacing.minTarget),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: tokens.textPrimary),
        label: Text(
          label,
          style: KeryxUxTypography.body.copyWith(color: tokens.textPrimary),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(KeryxUxSpacing.minTarget),
          side: BorderSide(color: tokens.borderDefault),
          foregroundColor: tokens.textPrimary,
        ),
      ),
    );
  }
}
