import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/presentation/presentation.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart' show RadioPhase;
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/channels/channel_format.dart';
import 'package:keryx/features/channels/channel_memory.dart';

import 'channel_selector_copy.dart';
import 'channel_validation.dart';
import 'tune_coordinator.dart';

/// Keys for widget tests — content order and field identity.
abstract final class ChannelSelectorKeys {
  static const Key channelField = Key('channel-selector.channel-field');
  static const Key codeField = Key('channel-selector.code-field');
  static const Key applyButton = Key('channel-selector.apply');
  static const Key cancelButton = Key('channel-selector.cancel');
  static const Key retryButton = Key('channel-selector.retry');
  static const Key progress = Key('channel-selector.progress');
  static const Key feedback = Key('channel-selector.feedback');
  static const Key recentSection = Key('channel-selector.recent-section');
  static const Key emptyRecent = Key('channel-selector.empty-recent');
  static const Key currentChannel = Key('channel-selector.current-channel');
  static const Key pendingTarget = Key('channel-selector.pending-target');

  static Key recentEntry(int channel, int code) =>
      Key('channel-selector.recent.$channel.$code');
}

/// Design §2.3 — direct numeric entry plus the existing six-entry recall as
/// a separate section, over [TuneCoordinator]'s serialization/recovery
/// policy. Built fresh (ADR-001 §7 item 2), driven only by TASK-046's
/// projection/intents; owns no session, transport or floor engine of its
/// own. [host] is injected by the caller (the app-scoped composition root)
/// exactly as TASK-051's `TalkScreen` and TASK-049's `ChannelsLanding` are —
/// `lib/features/**` does not depend on `lib/app_shell/**`.
class ChannelSelectorScreen extends ConsumerStatefulWidget {
  const ChannelSelectorScreen({super.key, required this.host, this.onCancel});

  final RadioHost host;

  /// Invoked when the user cancels — a true no-op on the current channel
  /// (Design §2.3). Never invoked as a side effect of Apply.
  final VoidCallback? onCancel;

  @override
  ConsumerState<ChannelSelectorScreen> createState() =>
      _ChannelSelectorScreenState();
}

class _ChannelSelectorScreenState
    extends ConsumerState<ChannelSelectorScreen> {
  late final TuneCoordinator _coordinator;
  late final TextEditingController _channelController;
  late final TextEditingController _codeController;
  StreamSubscription<TuneOutcome>? _outcomeSub;

  RadioPhase _lastPhase = RadioPhase.off;
  TuneOutcome? _lastOutcome;

  @override
  void initState() {
    super.initState();
    _coordinator = TuneCoordinator(intents: RadioViewIntents(widget.host));
    _channelController = TextEditingController();
    _codeController = TextEditingController();
    _outcomeSub = _coordinator.outcomes.listen(_onOutcome);
    // Direct-entry fields start blank deliberately — this is entry, not a
    // pre-filled form; the authoritative current channel is shown
    // separately (see `ChannelSelectorKeys.currentChannel` in [build]),
    // read live off `radioStateProvider` on every frame.
  }

  @override
  void dispose() {
    unawaited(_outcomeSub?.cancel());
    _coordinator.dispose();
    _channelController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _onOutcome(TuneOutcome outcome) {
    if (!mounted) return;
    setState(() => _lastOutcome = outcome);
  }

  void _onPhaseMaybeChanged(RadioPhase phase) {
    if (phase == _lastPhase) return;
    _lastPhase = phase;
    _coordinator.onPhaseChanged(phase);
  }

  void _handleApply() {
    final int? channel = ChannelInputValidation.parseChannel(
      _channelController.text,
    );
    final int? code = ChannelInputValidation.parseCode(_codeController.text);
    if (channel == null || code == null) return; // Apply is disabled anyway.
    setState(() => _lastOutcome = null);
    _coordinator.request(
      channel: channel,
      code: code,
      currentPhase: _lastPhase,
    );
  }

  void _handleRecentTap(TunedChannel entry) {
    if (_coordinator.isBusy) return;
    setState(() {
      _lastOutcome = null;
      _channelController.text = ChannelInputValidation.twoDigit(entry.channel);
      _codeController.text = ChannelInputValidation.twoDigit(entry.privacyCode);
    });
    _coordinator.request(
      channel: entry.channel,
      code: entry.privacyCode,
      currentPhase: _lastPhase,
    );
  }

  void _handleRetry() {
    final outcome = _lastOutcome;
    if (outcome == null) return;
    setState(() => _lastOutcome = null);
    _coordinator.retry(outcome.target, currentPhase: _lastPhase);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = KeryxUxTokens.of(context);
    final radioState = ref.watch(radioStateProvider);
    _onPhaseMaybeChanged(radioState.phase);
    final settingsAsync = ref.watch(settingsProvider);
    final KeryxSettings? settings = settingsAsync.valueOrNull;

    final int? channelInput = ChannelInputValidation.parseChannel(
      _channelController.text,
    );
    final int? codeInput = ChannelInputValidation.parseCode(
      _codeController.text,
    );
    final bool canApply =
        channelInput != null && codeInput != null && !_coordinator.isBusy;

    final List<TunedChannel> recent = settings == null
        ? const <TunedChannel>[]
        : visibleChannelMemory(settings.channelMemory);

    final bool deferredForTx =
        _coordinator.pendingTarget != null &&
        (radioState.phase == RadioPhase.tx ||
            radioState.phase == RadioPhase.txRequest);

    return Scaffold(
      backgroundColor: tokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: tokens.surfaceBase,
        foregroundColor: tokens.textPrimary,
        title: const Text(ChannelSelectorCopy.title),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              ChannelSelectorCopy.currentChannelLabel,
              style: TextStyle(color: tokens.textSecondary, fontSize: 13),
            ),
            Text(
              formatChannelCode(radioState.channel, radioState.privacyCode),
              key: ChannelSelectorKeys.currentChannel,
              style: TextStyle(
                color: tokens.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            if (_coordinator.pendingTarget != null)
              Padding(
                key: ChannelSelectorKeys.pendingTarget,
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  deferredForTx
                      ? ChannelSelectorCopy.tuneQueuedDuringTx
                      : 'Requesting '
                            '${formatChannelCode(_coordinator.pendingTarget!.channel, _coordinator.pendingTarget!.privacyCode)}…',
                  style: TextStyle(color: tokens.stateWarning),
                ),
              ),
            if (_coordinator.isBusy)
              LinearProgressIndicator(
                key: ChannelSelectorKeys.progress,
                color: tokens.actionPrimary,
              ),
            if (_lastOutcome != null) _buildFeedback(tokens, _lastOutcome!),
            const SizedBox(height: 20),
            Text(
              ChannelSelectorCopy.directEntrySectionTitle,
              style: TextStyle(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ChannelSelectorKeys.channelField,
                    controller: _channelController,
                    enabled: !_coordinator.isBusy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: const InputDecoration(
                      labelText: ChannelSelectorCopy.channelFieldLabel,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: ChannelSelectorKeys.codeField,
                    controller: _codeController,
                    enabled: !_coordinator.isBusy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: const InputDecoration(
                      labelText: ChannelSelectorCopy.codeFieldLabel,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: ChannelSelectorKeys.cancelButton,
                    onPressed: widget.onCancel,
                    child: const Text(ChannelSelectorCopy.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: ChannelSelectorKeys.applyButton,
                    onPressed: canApply ? _handleApply : null,
                    child: const Text(ChannelSelectorCopy.apply),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              ChannelSelectorCopy.recentSectionTitle,
              key: ChannelSelectorKeys.recentSection,
              style: TextStyle(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (recent.isEmpty)
              Text(
                ChannelSelectorCopy.emptyRecent,
                key: ChannelSelectorKeys.emptyRecent,
                style: TextStyle(color: tokens.textSecondary),
              )
            else
              ...recent.map(
                (entry) => Card(
                  key: ChannelSelectorKeys.recentEntry(
                    entry.channel,
                    entry.privacyCode,
                  ),
                  color: tokens.surfaceCard,
                  child: ListTile(
                    enabled: !_coordinator.isBusy,
                    title: Text(
                      formatChannelCode(entry.channel, entry.privacyCode),
                      style: TextStyle(color: tokens.textPrimary),
                    ),
                    onTap: () => _handleRecentTap(entry),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedback(KeryxUxTokens tokens, TuneOutcome outcome) {
    final String message = switch (outcome.kind) {
      TuneOutcomeKind.success =>
        'Tuned to ${formatChannelCode(outcome.target.channel, outcome.target.privacyCode)}.',
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
      key: ChannelSelectorKeys.feedback,
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(child: Text(message, style: TextStyle(color: color))),
          if (outcome.kind == TuneOutcomeKind.retryableFailure)
            TextButton(
              key: ChannelSelectorKeys.retryButton,
              onPressed: _handleRetry,
              child: const Text(ChannelSelectorCopy.retry),
            ),
        ],
      ),
    );
  }
}
