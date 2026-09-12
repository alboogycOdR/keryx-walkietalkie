import 'package:keryx/core/radio_host/radio_host.dart'
    show RadioHostSnapshot, SessionFailureKind;
import 'package:keryx/core/settings/settings_repository.dart' show KeryxSettings;
import 'package:keryx/core/state/radio_state.dart'
    show RadioPhase, RadioState, Transport;
import 'package:keryx/services/session/session.dart' show StationInfo;

import 'connection_condition.dart';
import 'presentation_cue.dart';
import 'radio_phase_presentation.dart';
import 'talk_target.dart';
import 'telemetry.dart';

/// Overlay cues for the 5 Design §4 catalogue rows that are **not** a
/// [RadioPhase], plus the FR-023 / DS §6 TOT-warning overlay (Design §4
/// has no dedicated "TX time-out warning" row; TX granted's treatment is
/// "Red + timer if authoritative") and the TASK-097 session-establishment
/// failure pair ([localSessionFailed]/[linkedSessionFailed] — also not a
/// Design §4 catalogue row; a field report, not the original spec, drove
/// this one). Each is an independent boolean/nullable field on
/// [RadioViewState], never folded into a single priority switch (Technical
/// §5.2; Design §4's closing paragraph). Kept as static constants here
/// (rather than duplicated inline) so their copy has exactly one source.
abstract final class OverlayCues {
  static const deniedFlash = PresentationCue(
    label: 'Someone is already transmitting',
    iconId: 'block',
  );
  static const latched = PresentationCue(
    label: 'Transmission locked',
    iconId: 'lock',
  );
  static const emergency = PresentationCue(
    label: 'Emergency active',
    iconId: 'warning',
  );
  static const permissionDenied = PresentationCue(
    label: 'Microphone required',
    iconId: 'mic_off',
  );
  static const serviceFault = PresentationCue(
    label: 'Background service unavailable',
    iconId: 'error',
  );

  /// TASK-097: LOCAL session establishment timed out or failed (typically
  /// no reachable LAN peer). Reuses `linkDegraded`'s own `wifi_off` icon —
  /// both name "no usable link right now", same disclosed icon-reuse
  /// convention this file already applies to colour (see
  /// `talk_screen.dart`'s `_overlayColorFor` dartdoc).
  static const localSessionFailed = PresentationCue(
    label: "Couldn't find anyone nearby",
    iconId: 'wifi_off',
  );

  /// TASK-097: LINKED session establishment timed out or failed (typically
  /// an unreachable relay or token service).
  static const linkedSessionFailed = PresentationCue(
    label: "Couldn't reach the relay",
    iconId: 'wifi_off',
  );

  /// FR-023 T-5 s TOT warning (DS §6 "TX time-out warning"). Not a Design
  /// §4 catalogue row — pinned copy, not colour-only (Design §5).
  static const totWarning = PresentationCue(
    label: 'Transmission ending soon',
    iconId: 'timer',
  );
}

/// Pure, immutable presentation projection sitting between
/// `RadioHost`/`RadioHostSnapshot` (TASK-045) and every Wave 4 screen —
/// Technical §9's `lib/core/presentation/`.
///
/// Every field here is independent — no field's value is inferred by
/// discarding another's (Technical §5.2: "Do not use a single priority
/// switch that hides actual TX because emergency is active"; Design §4:
/// "State precedence is not a single skin switch. Emergency is an overlay,
/// not a replacement for floor phase. A denied flash cannot override a
/// currently granted TX, and a global connection error cannot conceal an
/// active floor state."). A screen combines these fields itself (e.g.
/// rendering an emergency banner *and* the granted-TX indicator
/// simultaneously) rather than reading one collapsed "current state" enum
/// from this type.
///
/// This type never mutates `RadioState`/`RadioHostSnapshot`, never issues a
/// transport/floor/audio/platform call, and never dispatches
/// `TransmitGranted`/`EndTransmit`/a remote floor event to simulate a
/// result (Technical §5.1) — [RadioViewState.project] is a pure function
/// of its inputs.
class RadioViewState {
  const RadioViewState({
    required this.phase,
    required this.emergency,
    required this.latched,
    required this.deniedFlash,
    this.totWarning = false,
    required this.connection,
    required this.permissionDenied,
    required this.serviceFaultMessage,
    this.sessionFailureKind,
    required this.activeSpeakerPeerId,
    required this.activeSpeakerCallsign,
    required this.stations,
    required this.rosterCount,
    required this.signalQuality,
    required this.meterLevel,
    required this.isPro,
    this.target,
    this.audience = AudienceState.everyoneReachable,
  });

  /// The authoritative floor phase — identical to `RadioState.phase`,
  /// never re-derived or renamed (Technical §5.2: `RadioPhase` "remains
  /// unchanged unless a separately approved defect requires a reducer
  /// change"). Carries Design §4's label/icon via [RadioPhasePresentation
  /// .cue] for the 8 catalogue rows that map onto a phase directly.
  final RadioPhase phase;

  /// Design §4 "Emergency" row — an overlay, independent of [phase]. Both
  /// may be true simultaneously (e.g. emergency pinned during an ordinary
  /// TX): Technical §5.2 forbids collapsing that into one state.
  final bool emergency;

  /// Design §4 "Latched" row. A deliberate latch is host-owned and
  /// survives navigation (Technical §4) — this field mirrors whatever the
  /// host currently reports, it does not itself track latch state.
  final bool latched;

  /// Design §4 "Denied/busy" row — a transient flash mirroring
  /// `RadioState.isTransmitDenied`. Never overrides a currently granted TX
  /// ([phase] == `RadioPhase.tx`); a screen renders both if both are true
  /// (which the reducer's own transient-clear semantics make rare but not
  /// impossible, e.g. a deny that lands the same tick a separate granted
  /// TX is reported for a different, unrelated station update).
  final bool deniedFlash;

  /// FR-023 / DS §6 "TX time-out warning" — a TX-phase overlay mirroring
  /// `RadioState.isTotWarning`. Independent of [phase]/[emergency]/
  /// [latched]: a TOT warning during granted TX projects both
  /// [phase] == `RadioPhase.tx` and this field simultaneously. Default
  /// `false` so out-of-territory direct constructors keep compiling;
  /// [RadioViewState.project] always sources the real reducer flag.
  final bool totWarning;

  /// Live transport vs. degraded connectivity (Technical §6.3).
  final ConnectionCondition connection;

  /// Design §4 "Permission denied" row. Gates `BootCompleted` upstream
  /// (`RadioHostSnapshot.micPermissionDenied`) — the radio never reaches
  /// `idle` while this is true, but the field is projected independently
  /// regardless of [phase]'s actual value.
  final bool permissionDenied;

  /// Design §4 "Service fault" row. Non-null exactly when
  /// `RadioHostSnapshot.serviceFaultMessage` is non-null. A sanitized,
  /// human-safe message only (Design §5) — never raw exception text
  /// (Technical §3).
  final String? serviceFaultMessage;

  /// TASK-097: non-null exactly when the most recent session-establishment
  /// attempt (LOCAL or LINKED) timed out or threw — mirrors
  /// `RadioHostSnapshot.sessionFailureKind` verbatim. Independent of
  /// [permissionDenied]/[serviceFaultMessage]/[phase]: a screen renders
  /// whichever apply, never collapsing them into one state (Technical
  /// §5.2). Defaults to `null` so out-of-territory direct constructors keep
  /// compiling (same convention as [totWarning]'s default).
  final SessionFailureKind? sessionFailureKind;

  /// Raw peer identifier of whoever holds the floor, or `null` — mirrors
  /// `RadioState.activeSpeaker` verbatim. Never itself rendered as a
  /// human-readable name (UX-FR-026).
  final String? activeSpeakerPeerId;

  /// The active speaker's callsign, resolved against [stations] — `null`
  /// whenever [activeSpeakerPeerId] is `null` **or** the roster does not
  /// (yet) know that peer's callsign. UX-FR-026: "Never present a peer ID
  /// as a verified human name" — a screen falls back to a neutral
  /// "Someone is speaking" (Design §2.2) when this is `null` but
  /// [activeSpeakerPeerId] is not.
  final String? activeSpeakerCallsign;

  /// Station visibility — mirrors `RadioHostSnapshot.stations` verbatim
  /// (Technical §3's "station visibility"). Empty whenever no session is
  /// active, matching the host's own eager-reset behaviour.
  final List<StationInfo> stations;

  /// [stations]`.length` when that count is a **verified** total, or
  /// [UnavailableRosterCount] when the active transport cannot currently
  /// guarantee completeness (Technical §1.1; UX-FR-046; VT-024). Direct
  /// (LAN) discovery is the only path that earns a known count.
  final RosterCount rosterCount;

  /// Aggregate signal-quality telemetry — always [SignalQuality
  /// .unavailable] today; see `telemetry.dart`'s dartdoc for why (Technical
  /// §1.1/§5.3; UX-FR-045; VT-024).
  final SignalQuality signalQuality;

  /// The PTT ring/level indicator's animation source — always
  /// [MeterLevel.decorative] today (Technical §5.3; UX-FR-027; VT-015).
  final MeterLevel meterLevel;

  /// Entitlement — mirrors `KeryxSettings.isPro` verbatim (Technical §3's
  /// "entitlement").
  final bool isPro;

  /// v2 (Technical §6.3, TASK-088 re-scope note §6a): the currently selected
  /// talk destination, or `null` while no v2 target has been chosen (every
  /// v1 caller). Supplied by the caller (whichever host composes it from
  /// `lib/core/contacts/**`/`lib/core/groups/**`, a later task) — this
  /// projection never fabricates one.
  final TalkTarget? target;

  /// v2 (Technical §6.3): who can currently hear a transmission to [target].
  /// Defaults to [AudienceState.everyoneReachable] when [target] is `null`,
  /// so every existing v1 projection test keeps passing unmodified.
  final AudienceState audience;

  /// Design §4's cue for [phase] alone (the 8 phase-mapped rows). A
  /// screen composes this with [emergency]/[latched]/[deniedFlash]/
  /// [totWarning]/[permissionDenied]/[serviceFaultMessage]'s own cues —
  /// see [activeOverlayCues] — rather than reading one collapsed value.
  PresentationCue get phaseCue => phase.cue;

  /// Every overlay currently active. The five Design §4 non-phase rows
  /// stay in that table's order; FR-023's TOT warning is appended after
  /// Denied/busy (both are TX overlays) and before Latched. Deliberately
  /// a list, not a single value — more than one may be simultaneously
  /// true, and a screen must render all of them (Technical §5.2; Design
  /// §4's closing paragraph).
  List<PresentationCue> get activeOverlayCues => [
    if (permissionDenied) OverlayCues.permissionDenied,
    if (serviceFaultMessage != null) OverlayCues.serviceFault,
    if (sessionFailureKind == SessionFailureKind.local)
      OverlayCues.localSessionFailed,
    if (sessionFailureKind == SessionFailureKind.linked)
      OverlayCues.linkedSessionFailed,
    if (emergency) OverlayCues.emergency,
    if (deniedFlash) OverlayCues.deniedFlash,
    if (totWarning) OverlayCues.totWarning,
    if (latched) OverlayCues.latched,
  ];

  /// Design §2.2's dynamic "Receiving" row copy: the resolved callsign
  /// when known, a neutral "Someone is speaking" when a speaker is active
  /// but unresolved, or `null` when nobody currently holds the floor.
  /// UX-FR-026: never the raw peer ID.
  String? get receivingLabel {
    if (activeSpeakerPeerId == null) return null;
    return activeSpeakerCallsign != null
        ? '$activeSpeakerCallsign speaking'
        : 'Someone is speaking';
  }

  /// Pure projection from host-owned inputs. Never mutates any input,
  /// never issues a transport/floor/audio/platform call, never dispatches
  /// a `RadioEvent` (Technical §5.1) — this is the entire "projection"
  /// referred to throughout this file's dartdocs.
  ///
  /// [latched] is supplied by the caller because a deliberate latch is
  /// host-owned UI-adjacent state (Technical §4's dartdoc on
  /// `RadioHost.releaseLatch`: "a latch is owned by the UI layer") that
  /// does not live on `RadioState` or `RadioHostSnapshot` today; this
  /// projection does not invent a place to store it, only a place to
  /// render it.
  factory RadioViewState.project({
    required RadioState radioState,
    required RadioHostSnapshot hostSnapshot,
    required KeryxSettings settings,
    bool latched = false,
    TalkTarget? target,
    Map<String, PeerPresence> presenceByPeerId = const {},
  }) {
    final speakerId = radioState.activeSpeaker;
    String? speakerCallsign;
    if (speakerId != null) {
      for (final station in hostSnapshot.stations) {
        if (station.peerId == speakerId) {
          speakerCallsign = station.callsign;
          break;
        }
      }
    }

    return RadioViewState(
      phase: radioState.phase,
      emergency: radioState.isEmergency,
      latched: latched,
      deniedFlash: radioState.isTransmitDenied,
      totWarning: radioState.isTotWarning,
      connection: ConnectionCondition(
        transport: radioState.transport,
        degraded: radioState.isNoLink || radioState.phase == RadioPhase.linkDegraded,
      ),
      permissionDenied: hostSnapshot.micPermissionDenied,
      serviceFaultMessage: hostSnapshot.serviceFaultMessage,
      sessionFailureKind: hostSnapshot.sessionFailureKind,
      activeSpeakerPeerId: speakerId,
      activeSpeakerCallsign: speakerCallsign,
      stations: hostSnapshot.stations,
      // Technical §1.1: LINKED does not (yet) guarantee a complete roster
      // through this interface. Until a host surfaces "this route's roster
      // is verified complete", any non-LOCAL effective route must not
      // claim a verified count — UX-FR-046/VT-024 forbid presenting an
      // unknown roster as zero. LOCAL discovery's own station stream is
      // authoritative for what it reports, so it alone earns a known
      // count.
      rosterCount:
          radioState.transport == Transport.direct ||
              radioState.transport == Transport.both
          ? KnownRosterCount(hostSnapshot.stations.length)
          : const UnavailableRosterCount(),
      signalQuality: SignalQuality.unavailable,
      // TASK-079/ADR-002 A6: only a real, verified sample renders as
      // measured, and only while actually receiving — a `MeasuredMeterLevel`
      // left over from a just-ended RX (host emits decorative on
      // `RemoteFloorEnded`/`EndTransmit`, but this projection re-asserts it
      // independently so a caller can never observe a measured level
      // outside `rxActive` even from a stale/racing snapshot).
      meterLevel: radioState.phase == RadioPhase.rxActive
          ? hostSnapshot.meterLevel
          : MeterLevel.decorative,
      isPro: settings.isPro,
      target: target,
      audience: AudienceState.compute(
        target: target,
        presenceByPeerId: presenceByPeerId,
      ),
    );
  }

  @override
  String toString() =>
      'RadioViewState(phase: $phase, emergency: $emergency, '
      'latched: $latched, deniedFlash: $deniedFlash, totWarning: $totWarning, '
      'connection: $connection, '
      'permissionDenied: $permissionDenied, '
      'serviceFaultMessage: $serviceFaultMessage, '
      'sessionFailureKind: $sessionFailureKind, '
      'activeSpeakerPeerId: $activeSpeakerPeerId, '
      'activeSpeakerCallsign: $activeSpeakerCallsign, '
      'stations: ${stations.length}, rosterCount: $rosterCount, '
      'signalQuality: $signalQuality, meterLevel: $meterLevel, isPro: $isPro, '
      'target: $target, audience: $audience)';
}
