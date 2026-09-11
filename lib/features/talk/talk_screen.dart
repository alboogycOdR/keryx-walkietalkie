import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/floor/floor.dart' show FloorEngine;
import 'package:keryx/core/presentation/presentation.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/core/state/radio_state.dart' show RadioPhase;
import 'package:keryx/core/theme/ux_tokens.dart';

import 'talk_channel_card.dart';
import 'talk_copy.dart';
import 'talk_latch_state.dart';
import 'talk_ptt_ring.dart';

/// The successor Talk screen (Design §2.2, amended by ADR-002 §3 A2/A3/A4)
/// — the primary communication surface and, per the intake, the single most
/// safety-critical screen in the wave. Built fresh against TASK-046's
/// projection/intents; owns no session, floor engine, audio pipeline or
/// service controller of its own (Design §1: "Talk is a dedicated route...
/// but its presentation lifecycle must not own the radio session").
///
/// TASK-074 recomposes this screen to ADR-002 A2's content order — channel
/// card; overlay banners; flexible space; PTT ring; status text below the
/// ring; a contextual latch/release control — and deletes the pre-ADR-002
/// header/disc/toggle presentation. **All hold/latch/lifecycle safety
/// logic below is unchanged from the pre-ADR-002 screen** (VT-010–VT-015);
/// only the widget tree this state drives has changed.
///
/// [host] is injected by the caller (the app-scoped composition root,
/// `lib/app_shell/**`) rather than read from an ambient provider defined in
/// this module — `lib/features/**` does not depend on `lib/app_shell/**`
/// (the dependency runs the other way: the shell composes features). Tests
/// in `test/features/talk/**` inject a `FakeRadioHost` the same way.
class TalkScreen extends ConsumerStatefulWidget {
  const TalkScreen({
    super.key,
    required this.host,
    this.onOpenPicker,
    this.onOpenStations,
    this.onOpenRadioControls,
  });

  final RadioHost host;

  /// Real navigation callback for the channel card's picker affordance
  /// (TASK-050's selector). `null` in tests/stand-ins that don't exercise
  /// navigation — the button still renders, per Design §2.2's "offers a
  /// clear channel picker", but is a no-op rather than throwing.
  final VoidCallback? onOpenPicker;

  /// Real navigation callback for the channel card's Stations affordance
  /// (TASK-053's roster). See [onOpenPicker]'s dartdoc.
  final VoidCallback? onOpenStations;

  /// Real navigation callback for the channel card's Radio Controls
  /// affordance (TASK-054). ADR-002 §3 A2: rendered **only when non-null**
  /// — omitted entirely rather than merely disabled when absent.
  final VoidCallback? onOpenRadioControls;

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
  bool _autoReleasePosted = false;

  /// ADR-002 A7: the denied flash is presentation-only. The reducer keeps
  /// `isTransmitDenied` until the next radio event; this timer is what
  /// returns the ring to Ready when nobody else is on the channel.
  static const Duration _deniedFlashDuration = Duration(milliseconds: 1500);
  Timer? _deniedFlashTimer;
  bool _flashExpired = false;

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
    _deniedFlashTimer?.cancel();
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
    // TASK-074 carry: a latch after pointer-up is a false TX — the
    // ordinary release has already gone, so locking would paint
    // "Transmission locked" without a live grant. Both the control and
    // this handler require an in-progress hold plus a current TX phase.
    final RadioPhase phase = ref.read(radioStateProvider).phase;
    if (!_holding || _latched || phase != RadioPhase.tx) return;
    setState(() => TalkLatchState.engage(widget.host));
  }

  void _releaseLatch([RadioViewIntents? intents]) {
    if (!_latched) return;
    TalkLatchState.release(widget.host);
    (intents ?? RadioViewIntents(widget.host)).releaseLatch();
    if (mounted) setState(() {});
  }

  /// TASK-081 rework: a leftover latch after the reducer leaves TX (TOT,
  /// EndTransmit, or LinkDegraded) must also release the floor. Clearing
  /// only the UI flag left a LINKED latched TX open through reconnect with
  /// no Release control (`TalkLatchState` dartdoc). Releasing an already
  /// idle engine is a no-op. Must not run as a mutation inside [build].
  void _releaseLeftoverLatchIfPhaseLeftTx(RadioPhase phase) {
    if (phase == RadioPhase.tx) return;
    _releaseLatch();
  }

  /// Rising edge of `isTransmitDenied` starts (or restarts) the 1.5 s
  /// presentation timer. A falling edge cancels it. Does not [setState]
  /// on the edge — the [radioStateProvider] watch already rebuilds.
  void _syncDeniedFlashTimer({
    required bool wasDenied,
    required bool nowDenied,
  }) {
    if (nowDenied && !wasDenied) {
      _deniedFlashTimer?.cancel();
      _flashExpired = false;
      _deniedFlashTimer = Timer(_deniedFlashDuration, () {
        if (!mounted) return;
        setState(() => _flashExpired = true);
      });
      return;
    }
    if (!nowDenied && wasDenied) {
      _deniedFlashTimer?.cancel();
      _deniedFlashTimer = null;
      _flashExpired = false;
    }
  }

  bool _flashIsShowing(RadioViewState viewState) =>
      viewState.deniedFlash && !_flashExpired;

  @override
  Widget build(BuildContext context) {
    final intents = RadioViewIntents(widget.host);
    final radioState = ref.watch(radioStateProvider);
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.valueOrNull;

    ref.listen(radioStateProvider, (previous, next) {
      _releaseLeftoverLatchIfPhaseLeftTx(next.phase);
      _syncDeniedFlashTimer(
        wasDenied: previous?.isTransmitDenied ?? false,
        nowDenied: next.isTransmitDenied,
      );
    });

    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Remount while already out of TX (e.g. LinkDegraded while Talk was
    // off-stage) never fires [ref.listen]; catch it after this frame.
    if (_latched && radioState.phase != RadioPhase.tx && !_autoReleasePosted) {
      _autoReleasePosted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoReleasePosted = false;
        if (!mounted) return;
        _releaseLeftoverLatchIfPhaseLeftTx(ref.read(radioStateProvider).phase);
      });
    }

    final viewState = RadioViewState.project(
      radioState: radioState,
      hostSnapshot: _snapshot,
      settings: settings,
      latched:
          TalkLatchState.of(widget.host) && radioState.phase == RadioPhase.tx,
    );

    final tokens = KeryxUxTokens.of(context);

    // UX-FR-029: no live transmit action while booting, permission-denied,
    // powered off or lacking a usable floor engine.
    final bool ptteEnabled =
        viewState.phase != RadioPhase.off &&
        viewState.phase != RadioPhase.boot &&
        !viewState.permissionDenied &&
        _snapshot.floorEngine != null;

    final TalkPttRingTreatment treatment = _treatmentFor(viewState);
    final bool reducedMotion = MediaQuery.disableAnimationsOf(context);
    final (String primaryLine, String secondaryLine) = _statusLinesFor(
      viewState,
      treatment,
    );
    final Iterable<PresentationCue> overlayCues = _overlayCuesFor(viewState);
    final String semanticStatus = secondaryLine.isEmpty
        ? primaryLine
        : '$primaryLine $secondaryLine';

    // Latch may be engaged only while this screen still owes the hold
    // *and* TX is granted. After pointer-up the ordinary release has
    // already been sent; showing Lock then lets a tap paint a false TX.
    final bool canLatch =
        _holding && !_latched && viewState.phase == RadioPhase.tx;

    // ADR-002 A7: card + banners stay at the top; the ring, status and
    // latch row are centred in the remaining height. A two-child render
    // object (not SliverFillRemaining — TalkPttRing's LayoutBuilder cannot
    // report intrinsics) sizes to max(viewport, children) so the
    // SingleChildScrollView still scrolls at text scale 2.0 / landscape.
    const EdgeInsets pagePadding = EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 12,
    );
    final Widget topGroup = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (Navigator.of(context).canPop())
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                key: const Key('keryx-talk-back'),
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(Icons.arrow_back, color: tokens.textPrimary),
              ),
            ),
          ),
        TalkChannelCard(
          channel: viewState.channel,
          privacyCode: viewState.privacyCode,
          connection: viewState.connection,
          stationCountLabel: _rosterLabel(viewState.rosterCount),
          onOpenPicker: widget.onOpenPicker,
          onOpenStations: widget.onOpenStations,
          onOpenRadioControls: widget.onOpenRadioControls,
        ),
        const SizedBox(height: 8),
        for (final cue in overlayCues)
          _OverlayCueChip(cue: cue, tokens: tokens),
      ],
    );
    final Widget pttGroup = Column(
      key: const Key('keryx-talk-ptt-cluster'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: TalkPttRing(
            enabled: ptteEnabled,
            treatment: treatment,
            meterLevel: viewState.meterLevel,
            reducedMotion: reducedMotion,
            semanticStatus: semanticStatus,
            ringColor: _ringColorFor(treatment, tokens),
            faceColor: tokens.pttFace,
            glyphColor: tokens.palette.contrastingOn(tokens.pttFace),
            neutralRingColor: tokens.pttNeutralRing,
            onHoldStart: () => _handleHoldStart(intents),
            onHoldEnd: () => _handleHoldEnd(intents),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          primaryLine,
          key: const Key('keryx-talk-status-line'),
          textAlign: TextAlign.center,
          style: KeryxUxTypography.sectionTitle.copyWith(
            color: tokens.textPrimary,
          ),
        ),
        if (secondaryLine.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              secondaryLine,
              key: const Key('keryx-talk-status-secondary'),
              textAlign: TextAlign.center,
              style: KeryxUxTypography.secondary.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          ),
        const SizedBox(height: 16),
        _ContextualLatchRow(
          latched: viewState.latched,
          canLatch: canLatch,
          onLatch: _engageLatch,
          onUnlatch: () => _releaseLatch(intents),
        ),
      ],
    );
    return Scaffold(
      backgroundColor: tokens.surfaceBase,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double minContentHeight =
                (constraints.maxHeight - pagePadding.vertical).clamp(
                  0.0,
                  double.infinity,
                );
            return SingleChildScrollView(
              padding: pagePadding,
              child: _TalkBody(
                minHeight: minContentHeight,
                top: topGroup,
                bottom: pttGroup,
              ),
            );
          },
        ),
      ),
    );
  }

  /// ADR-002 §3 A3's ring-treatment mapping. A currently granted/latched
  /// TX always takes precedence over a transient denied flash (Design §4:
  /// "A denied flash cannot override a currently granted TX") — the flash
  /// only reaches [TalkPttRingTreatment.deniedFlash] when there is no
  /// active grant to protect, matching [OverlayCues.deniedFlash]'s own
  /// independent-overlay rendering above the ring. After [_deniedFlashDuration]
  /// the presentation expires even if the reducer flag is still set (A7).
  TalkPttRingTreatment _treatmentFor(RadioViewState viewState) {
    if (viewState.latched) return TalkPttRingTreatment.latched;
    if (viewState.phase == RadioPhase.tx) return TalkPttRingTreatment.tx;
    if (viewState.phase == RadioPhase.rxActive) {
      return TalkPttRingTreatment.rx;
    }
    if (viewState.phase == RadioPhase.txRequest) {
      return TalkPttRingTreatment.requesting;
    }
    if (_flashIsShowing(viewState)) return TalkPttRingTreatment.deniedFlash;
    if (viewState.phase == RadioPhase.idle) {
      return TalkPttRingTreatment.ready;
    }
    // Off/Boot/Tuning/No-link (ADR-002 A3: "Off/Boot/No link/Tuning:
    // neutral, dimmed").
    return TalkPttRingTreatment.neutral;
  }

  static Color _ringColorFor(
    TalkPttRingTreatment treatment,
    KeryxUxTokens tokens,
  ) => switch (treatment) {
    TalkPttRingTreatment.tx || TalkPttRingTreatment.latched => tokens.stateTx,
    TalkPttRingTreatment.rx => tokens.stateRx,
    TalkPttRingTreatment.requesting ||
    TalkPttRingTreatment.ready => tokens.actionPrimary,
    TalkPttRingTreatment.deniedFlash ||
    TalkPttRingTreatment.neutral => tokens.pttNeutralRing,
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

  /// Design §2.2/§5's primary/secondary status-text split — the primary
  /// line carries the state's headline copy (callsign speaking /
  /// catalogue label), the secondary line carries the supporting
  /// instruction ("Hold to talk") only where the catalogue defines one.
  /// "A disconnected screen must not show 'Ready'" is preserved by gating
  /// the happy-path idle copy behind connection health, same as before.
  static (String, String) _statusLinesFor(
    RadioViewState viewState,
    TalkPttRingTreatment treatment,
  ) {
    if (viewState.connection.degraded) {
      return (TalkCopy.connectionLost, '');
    }
    // Round-1 review non-blocking (ii): a permission-denied screen showed
    // the generic "Hold to talk" status line (disc merely disabled) instead
    // of naming the reason — Design §5's own persistent-actionable-message
    // copy belongs on the status line, not only the overlay chip above it.
    if (viewState.permissionDenied) {
      return (TalkCopy.microphonePermissionRequired, '');
    }
    return switch (treatment) {
      TalkPttRingTreatment.tx || TalkPttRingTreatment.latched => (
        viewState.latched ? TalkCopy.transmissionLocked : TalkCopy.transmitting,
        '',
      ),
      TalkPttRingTreatment.rx => (
        viewState.receivingLabel ?? TalkCopy.someoneIsSpeaking,
        '',
      ),
      TalkPttRingTreatment.requesting => (TalkCopy.requestingChannel, ''),
      TalkPttRingTreatment.deniedFlash => (_denyCopy(viewState), ''),
      TalkPttRingTreatment.ready => (
        TalkCopy.channelClear,
        TalkCopy.holdToTalk,
      ),
      TalkPttRingTreatment.neutral => (_neutralPhaseLabel(viewState.phase), ''),
    };
  }

  /// ADR-002 A7: empty LOCAL roster is not "busy"; contention still is.
  static String _denyCopy(RadioViewState viewState) {
    if (viewState.rosterCount case KnownRosterCount(count: 0)) {
      return TalkCopy.noOtherStationsOnChannel;
    }
    return TalkCopy.channelBusy;
  }

  Iterable<PresentationCue> _overlayCuesFor(RadioViewState viewState) sync* {
    for (final PresentationCue cue in viewState.activeOverlayCues) {
      if (cue == OverlayCues.deniedFlash) {
        if (!_flashIsShowing(viewState)) continue;
        final String label = _denyCopy(viewState);
        yield label == cue.label
            ? cue
            : PresentationCue(label: label, iconId: cue.iconId);
      } else {
        yield cue;
      }
    }
  }

  static String _neutralPhaseLabel(RadioPhase phase) => switch (phase) {
    RadioPhase.off => 'Radio off',
    RadioPhase.boot => 'Starting radio',
    RadioPhase.tuning => 'Changing channel',
    _ => phase.cue.label,
  };

  static String _rosterLabel(RosterCount count) => switch (count) {
    KnownRosterCount(:final count) =>
      count == 0 ? TalkCopy.noOtherStationsVisible : '$count stations',
    UnavailableRosterCount() => TalkCopy.rosterUnavailable,
  };
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

/// ADR-002 §3 A4's contextual row: a labelled lock control only while TX is
/// granted and not latched, a labelled "Release" control while latched,
/// nothing otherwise. Replaces the pre-ADR-002 `_SecondaryActionRow`, which
/// also carried the station-count affordance — that now lives on
/// [TalkChannelCard].
class _ContextualLatchRow extends StatelessWidget {
  const _ContextualLatchRow({
    required this.latched,
    required this.canLatch,
    required this.onLatch,
    required this.onUnlatch,
  });

  final bool latched;
  final bool canLatch;
  final VoidCallback onLatch;
  final VoidCallback onUnlatch;

  @override
  Widget build(BuildContext context) {
    if (!latched && !canLatch) {
      return const SizedBox.shrink();
    }
    return Center(
      child: SizedBox(
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
                onPressed: onLatch,
                icon: const Icon(Icons.lock_outline),
                label: const Text(TalkCopy.lockTransmission),
              ),
      ),
    );
  }
}

/// Pins [top] to the start and centres [bottom] in leftover height.
/// Grows past [minHeight] when the children do not fit so a parent
/// [SingleChildScrollView] can scroll instead of overflowing.
class _TalkBody extends MultiChildRenderObjectWidget {
  _TalkBody({
    required this.minHeight,
    required Widget top,
    required Widget bottom,
  }) : super(children: <Widget>[top, bottom]);

  final double minHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTalkBody(minHeight: minHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderTalkBody renderObject) {
    renderObject.minHeight = minHeight;
  }
}

class _TalkBodyParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderTalkBody extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TalkBodyParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TalkBodyParentData> {
  _RenderTalkBody({required double minHeight}) : _minHeight = minHeight;

  double _minHeight;
  set minHeight(double value) {
    if (_minHeight == value) return;
    _minHeight = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TalkBodyParentData) {
      child.parentData = _TalkBodyParentData();
    }
  }

  @override
  void performLayout() {
    final BoxConstraints childConstraints = BoxConstraints(
      minWidth: constraints.maxWidth,
      maxWidth: constraints.maxWidth,
    );
    final RenderBox top = firstChild!;
    final RenderBox bottom = childAfter(top)!;
    top.layout(childConstraints, parentUsesSize: true);
    bottom.layout(childConstraints, parentUsesSize: true);
    final double contentH = top.size.height + bottom.size.height;
    final double height = math.max(_minHeight, contentH);
    size = constraints.constrain(Size(constraints.maxWidth, height));
    final double extra = math.max(0.0, size.height - contentH);
    (top.parentData! as _TalkBodyParentData).offset = Offset.zero;
    (bottom.parentData! as _TalkBodyParentData).offset = Offset(
      0,
      top.size.height + extra / 2,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
