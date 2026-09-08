import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/floor/floor.dart' show FloorEngine;
import 'package:keryx/core/presentation/presentation.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/core/state/radio_state.dart' show RadioMode, RadioPhase;
import 'package:keryx/core/theme/ux_tokens.dart';

import 'talk_copy.dart';
import 'talk_latch_state.dart';
import 'talk_ptt_disc.dart';

/// The successor Talk screen (Design §2.2) — the primary communication
/// surface and, per the intake, the single most safety-critical screen in
/// the wave. Built fresh against TASK-046's projection/intents; owns no
/// session, floor engine, audio pipeline or service controller of its own
/// (Design §1: "Talk is a dedicated route... but its presentation lifecycle
/// must not own the radio session").
///
/// [host] is injected by the caller (the app-scoped composition root,
/// `lib/app_shell/**`) rather than read from an ambient provider defined in
/// this module — `lib/features/**` does not depend on `lib/app_shell/**`
/// (the dependency runs the other way: the shell composes features). Tests
/// in `test/features/talk/**` inject a `FakeRadioHost` the same way.
class TalkScreen extends ConsumerStatefulWidget {
  const TalkScreen({super.key, required this.host});

  final RadioHost host;

  @override
  ConsumerState<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends ConsumerState<TalkScreen>
    with WidgetsBindingObserver {
  StreamSubscription<RadioHostSnapshot>? _hostSub;
  late RadioHostSnapshot _snapshot;

  /// True between an accepted hold-start and its matching hold-end — the
  /// "am I the reason the floor is (or should be) held" bookkeeping VT-011/
  /// VT-012 exercise. Never itself a second source of truth for
  /// `RadioPhase` — only governs whether *this* screen still owes the host
  /// a release call.
  bool _holding = false;

  /// A deliberate latch is UI-owned (Technical §4's dartdoc on
  /// `RadioHost.releaseLatch`) — there is no `RadioHost` operation to
  /// *acquire* one, only to release it. Engaging a latch is simply this
  /// screen choosing not to send the ordinary release when the hold ends;
  /// [RadioViewState.project] takes this flag as a caller-supplied
  /// argument (TASK-046's Review_Findings: TASK-050/051 are "on the hook
  /// for actually tracking it").
  ///
  /// Backed by [TalkLatchState], keyed on [widget.host]'s identity, **not**
  /// a plain field on this [State] — round-1 review found a widget-local
  /// bool dies with the widget on route unmount, so a latched transmission
  /// survived at the engine (correctly) but lost its only UI release
  /// affordance the moment the screen was remounted (`TalkLatchState`'s own
  /// dartdoc has the full incident). This getter, not a cached field, so it
  /// always reflects the persistent holder even across this State's own
  /// disposal/recreation.
  bool get _latched => TalkLatchState.of(widget.host);

  FloorEngine? _lastFloorEngine;
  bool _wasPermissionDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _snapshot = widget.host.current;
    _lastFloorEngine = _snapshot.floorEngine;
    _wasPermissionDenied = _snapshot.micPermissionDenied;
    _hostSub = widget.host.changes.listen(_onSnapshot);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_hostSub?.cancel());
    // VT-012: route unmount during a hold releases an ordinary hold safely
    // and creates no latch. A deliberate latch survives navigation
    // (Technical §4) — only an un-latched hold is released here.
    _releaseOrdinaryHoldIfOwed();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // VT-012: app backgrounding releases an ordinary hold safely.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _releaseOrdinaryHoldIfOwed();
    }
  }

  void _onSnapshot(RadioHostSnapshot snapshot) {
    final bool permissionJustDenied =
        !_wasPermissionDenied && snapshot.micPermissionDenied;
    final bool engineReplaced =
        _lastFloorEngine != null &&
        !identical(_lastFloorEngine, snapshot.floorEngine);
    _lastFloorEngine = snapshot.floorEngine;
    _wasPermissionDenied = snapshot.micPermissionDenied;
    if (!mounted) return;
    setState(() => _snapshot = snapshot);
    // VT-012: permission loss and engine replacement each release an
    // ordinary hold safely.
    if (permissionJustDenied || engineReplaced) {
      _releaseOrdinaryHoldIfOwed();
    }
  }

  /// Releases exactly one ordinary hold this screen still owes the host —
  /// idempotent (a second call after `_holding` is already false is a
  /// no-op), and never touches a deliberate latch.
  void _releaseOrdinaryHoldIfOwed() {
    if (!_holding) return;
    _holding = false;
    if (_latched) return;
    widget.host.releasePtt();
  }

  void _handleHoldStart(RadioViewIntents intents) {
    if (_holding) return; // VT-011: duplicate/late start is a no-op.
    setState(() => _holding = true);
    intents.press();
  }

  void _handleHoldEnd(RadioViewIntents intents) {
    if (!_holding) return; // VT-011: duplicate pointer-up/cancel is a no-op.
    setState(() => _holding = false);
    if (_latched) return; // Latch keeps the floor open; no release sent.
    intents.release();
  }

  void _engageLatch() {
    if (!_holding || _latched) return;
    setState(() => TalkLatchState.engage(widget.host));
  }

  void _releaseLatch(RadioViewIntents intents) {
    if (!_latched) return;
    setState(() => TalkLatchState.release(widget.host));
    intents.releaseLatch();
  }

  @override
  Widget build(BuildContext context) {
    final intents = RadioViewIntents(widget.host);
    final radioState = ref.watch(radioStateProvider);
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.valueOrNull;

    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final viewState = RadioViewState.project(
      radioState: radioState,
      hostSnapshot: _snapshot,
      settings: settings,
      latched: _latched,
    );

    final tokens = KeryxUxTokens.of(context);

    // UX-FR-029: no live transmit action while booting, permission-denied,
    // powered off or lacking a usable floor engine.
    final bool ptteEnabled =
        viewState.phase != RadioPhase.off &&
        viewState.phase != RadioPhase.boot &&
        !viewState.permissionDenied &&
        _snapshot.floorEngine != null;

    final _DiscTreatment treatment = _treatmentFor(viewState);
    // Design §4's catalogue table: "Requesting" is Pending/amber, not the
    // Ready row's Primary blue — and within the idle bucket, Off/Boot/
    // Tuning are their own "Neutral disabled"/"Neutral progress"/"Progress"
    // treatments, distinct from Ready's blue (round-1 review BLOCKING 3a).
    final Color discColor = switch (treatment) {
      _DiscTreatment.tx => tokens.stateTx,
      _DiscTreatment.rx => tokens.stateRx,
      _DiscTreatment.requesting => tokens.stateWarning,
      _DiscTreatment.idle => _idleColorFor(viewState.phase, tokens),
    };
    final String statusLine = _statusLineFor(viewState, treatment);

    return Scaffold(
      backgroundColor: tokens.surfaceBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Header(
                channel: viewState.channel,
                privacyCode: viewState.privacyCode,
                tokens: tokens,
              ),
              const SizedBox(height: 12),
              _ConnectionLine(viewState: viewState, tokens: tokens),
              const SizedBox(height: 8),
              for (final cue in viewState.activeOverlayCues)
                _OverlayCueChip(cue: cue, tokens: tokens),
              const SizedBox(height: 16),
              Text(
                statusLine,
                key: const Key('keryx-talk-status-line'),
                textAlign: TextAlign.center,
                style: KeryxUxTypography.sectionTitle.copyWith(
                  color: tokens.textPrimary,
                ),
              ),
              const Spacer(),
              Center(
                child: TalkPttDisc(
                  enabled: ptteEnabled,
                  showsTx: treatment == _DiscTreatment.tx,
                  label: statusLine,
                  icon: _iconFor(treatment, viewState.phase),
                  color: discColor,
                  onColor: tokens.palette.contrastingOn(discColor),
                  onHoldStart: () => _handleHoldStart(intents),
                  onHoldEnd: () => _handleHoldEnd(intents),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TalkPttToggleAlternative(
                  enabled: ptteEnabled,
                  active: _holding,
                  onHoldStart: () => _handleHoldStart(intents),
                  onHoldEnd: () => _handleHoldEnd(intents),
                ),
              ),
              const SizedBox(height: 16),
              _SecondaryActionRow(
                latched: _latched,
                canLatch: _holding && !_latched && viewState.phase == RadioPhase.tx,
                onLatch: _engageLatch,
                onUnlatch: () => _releaseLatch(intents),
                stationCountLabel: _rosterLabel(viewState.rosterCount),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Idle-bucket phases (off/boot/idle/tuning/linkDegraded) share one
  // `_DiscTreatment` but Design §4 gives each its own icon/colour — so both
  // resolve off `RadioPhase.cue` (`radio_phase_presentation.dart`, the same
  // catalogue source of truth `RadioViewState.phaseCue` exposes) rather than
  // a second, hand-duplicated mapping.
  static IconData _iconFor(_DiscTreatment treatment, RadioPhase phase) =>
      switch (treatment) {
        _DiscTreatment.tx => Icons.mic,
        _DiscTreatment.rx => Icons.volume_up,
        _DiscTreatment.requesting => _iconForCueId('pending'),
        _DiscTreatment.idle => _iconForCueId(phase.cue.iconId),
      };

  /// Design §4: Off/Boot/Tuning/No-link are each their own neutral/warning
  /// treatment, not Ready's Primary blue — only [RadioPhase.idle] itself
  /// earns the blue "Hold to talk" treatment.
  static Color _idleColorFor(RadioPhase phase, KeryxUxTokens tokens) =>
      switch (phase) {
        RadioPhase.idle => tokens.actionPrimary,
        RadioPhase.linkDegraded => tokens.stateWarning,
        _ => tokens.textSecondary,
      };

  /// Resolves a [PresentationCue.iconId]/[OverlayCues] semantic key to a
  /// concrete glyph — the icon-mapping table `presentation_cue.dart`'s own
  /// dartdoc says belongs at "a screen's icon-mapping table", deliberately
  /// kept framework-agnostic upstream (Design §3.4: "a consistent icon
  /// family").
  static IconData _iconForCueId(String iconId) => switch (iconId) {
    'power_off' => Icons.power_settings_new,
    'hourglass' => Icons.hourglass_empty,
    'mic_none' => Icons.mic_none,
    'tune' => Icons.tune,
    'pending' => Icons.pending_outlined,
    'mic' => Icons.mic,
    'volume_up' => Icons.volume_up,
    'wifi_off' => Icons.wifi_off,
    'block' => Icons.block,
    'lock' => Icons.lock,
    'warning' => Icons.priority_high,
    'mic_off' => Icons.mic_off,
    'error' => Icons.error_outline,
    _ => Icons.circle,
  };

  /// Design §4's per-row colour for the 5 overlay cues — a single hardcoded
  /// warning colour (round-1 review non-blocking (iii)) collapsed
  /// "Transmission locked" (Red) and "Emergency active" (Orange priority)
  /// into the same amber as "Channel busy"/"Service fault", losing the
  /// colour half of the catalogue's redundant label+icon+colour cue for
  /// exactly the two rows Design §2.5/§4 call out as needing their own
  /// distinct treatment.
  static Color _overlayColorFor(PresentationCue cue, KeryxUxTokens tokens) =>
      switch (cue.iconId) {
        'lock' => tokens.stateTx, // Latched: "Red + explicit release".
        'warning' => tokens.stateEmergency, // Emergency: "Orange priority".
        _ => tokens.stateWarning, // Denied/busy, permission, service fault.
      };

  static _DiscTreatment _treatmentFor(RadioViewState viewState) {
    if (viewState.latched || viewState.phase == RadioPhase.tx) {
      return _DiscTreatment.tx;
    }
    if (viewState.phase == RadioPhase.rxActive) return _DiscTreatment.rx;
    if (viewState.phase == RadioPhase.txRequest) {
      return _DiscTreatment.requesting;
    }
    return _DiscTreatment.idle;
  }

  static String _statusLineFor(
    RadioViewState viewState,
    _DiscTreatment treatment,
  ) {
    // Design §2.2/§5: "A disconnected screen must not show 'Ready.'" — the
    // happy-path idle copy is gated behind connection health.
    if (viewState.connection.degraded) return TalkCopy.connectionLost;
    // Round-1 review non-blocking (ii): a permission-denied screen showed
    // the generic "Hold to talk" status line (disc merely disabled) instead
    // of naming the reason — Design §5's own persistent-actionable-message
    // copy belongs on the status line, not only the overlay chip above it.
    if (viewState.permissionDenied) return TalkCopy.microphonePermissionRequired;
    return switch (treatment) {
      _DiscTreatment.tx => viewState.latched
          ? TalkCopy.transmissionLocked
          : TalkCopy.transmitting,
      _DiscTreatment.rx =>
        viewState.receivingLabel ?? TalkCopy.someoneIsSpeaking,
      _DiscTreatment.requesting => TalkCopy.requestingChannel,
      _DiscTreatment.idle => switch (viewState.phase) {
        RadioPhase.off => 'Radio off',
        RadioPhase.boot => 'Starting radio',
        RadioPhase.tuning => 'Changing channel',
        // Design §5's literal idle copy is the two sentences together:
        // "Channel clear. Hold to talk." — `TalkCopy.holdToTalk` itself
        // stays period-free since it doubles as Design §4's bare catalogue
        // label for the Ready row.
        _ => '${TalkCopy.channelClear} ${TalkCopy.holdToTalk}.',
      },
    };
  }

  static String _rosterLabel(RosterCount count) => switch (count) {
    KnownRosterCount(:final count) =>
      count == 0 ? TalkCopy.noOtherStationsVisible : '$count stations',
    UnavailableRosterCount() => TalkCopy.rosterUnavailable,
  };
}

enum _DiscTreatment { idle, requesting, tx, rx }

class _Header extends StatelessWidget {
  const _Header({
    required this.channel,
    required this.privacyCode,
    required this.tokens,
  });

  final int channel;
  final int privacyCode;
  final KeryxUxTokens tokens;

  @override
  Widget build(BuildContext context) {
    final String channelLabel = channel.toString().padLeft(2, '0');
    final String codeLabel = privacyCode.toString().padLeft(2, '0');
    return Row(
      children: <Widget>[
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            key: const Key('keryx-talk-back'),
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back, color: tokens.textPrimary),
          ),
        ),
        Expanded(
          child: Text(
            'CH $channelLabel · $codeLabel',
            key: const Key('keryx-talk-channel-label'),
            style: KeryxUxTypography.screenTitle.copyWith(
              color: tokens.textPrimary,
            ),
          ),
        ),
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            key: const Key('keryx-talk-picker'),
            tooltip: TalkCopy.openChannelPicker,
            onPressed: () {
              // Navigation to TASK-050's selector is wired by the shell
              // composition root; this screen only exposes the affordance.
            },
            icon: Icon(Icons.dialpad, color: tokens.textSecondary),
          ),
        ),
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            key: const Key('keryx-talk-stations'),
            tooltip: TalkCopy.openStations,
            onPressed: () {
              // Navigation to TASK-053's roster is wired by the shell
              // composition root; this screen only exposes the affordance.
            },
            icon: Icon(Icons.groups_outlined, color: tokens.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _ConnectionLine extends StatelessWidget {
  const _ConnectionLine({required this.viewState, required this.tokens});

  final RadioViewState viewState;
  final KeryxUxTokens tokens;

  static String _modeLabel(RadioMode mode) => switch (mode) {
    RadioMode.local => 'LOCAL',
    RadioMode.linked => 'LINKED',
    RadioMode.auto => 'AUTO',
  };

  @override
  Widget build(BuildContext context) {
    final condition = viewState.connection;
    return Row(
      key: const Key('keryx-talk-connection-line'),
      children: <Widget>[
        Icon(
          condition.degraded ? Icons.wifi_off : Icons.wifi,
          size: 16,
          color: condition.degraded ? tokens.stateWarning : tokens.textSecondary,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            // UX-FR-002/Technical §7: configured preference and effective
            // route are kept as distinct, never-conflated fields.
            'Configured ${_modeLabel(condition.configuredMode)} '
            '· Route ${_modeLabel(condition.effectiveRoute)}'
            '${condition.degraded ? ' · ${TalkCopy.connectionLost}' : ''}',
            style: KeryxUxTypography.secondary.copyWith(
              color: tokens.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _OverlayCueChip extends StatelessWidget {
  const _OverlayCueChip({required this.cue, required this.tokens});

  final PresentationCue cue;
  final KeryxUxTokens tokens;

  @override
  Widget build(BuildContext context) {
    final Color color = _TalkScreenState._overlayColorFor(cue, tokens);
    return Padding(
      key: Key('keryx-talk-overlay-${cue.iconId}'),
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: <Widget>[
          Icon(
            _TalkScreenState._iconForCueId(cue.iconId),
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            cue.label,
            style: KeryxUxTypography.compact.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _SecondaryActionRow extends StatelessWidget {
  const _SecondaryActionRow({
    required this.latched,
    required this.canLatch,
    required this.onLatch,
    required this.onUnlatch,
    required this.stationCountLabel,
  });

  final bool latched;
  final bool canLatch;
  final VoidCallback onLatch;
  final VoidCallback onUnlatch;
  final String stationCountLabel;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: <Widget>[
        SizedBox(
          height: 48,
          child: latched
              ? OutlinedButton.icon(
                  key: const Key('keryx-talk-unlatch'),
                  onPressed: onUnlatch,
                  icon: const Icon(Icons.lock_open),
                  label: const Text(TalkCopy.releaseTransmission),
                )
              : OutlinedButton.icon(
                  key: const Key('keryx-talk-latch'),
                  onPressed: canLatch ? onLatch : null,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text(TalkCopy.lockTransmission),
                ),
        ),
        SizedBox(
          height: 48,
          child: Center(
            child: Text(
              stationCountLabel,
              key: const Key('keryx-talk-station-count'),
            ),
          ),
        ),
      ],
    );
  }
}
