/// Telemetry-honesty types (Technical §5.3, §1.1; PRD UX-FR-045/046/027;
/// Verification VT-015/024).
///
/// Every quantity the backend cannot yet actually measure must be
/// represented as *unavailable*, never as a synthetic real-looking value —
/// "the existing placeholder maximum must be projected as unavailable/
/// unknown rather than full bars" (Technical §5.3). A `measured` variant is
/// defined for each so a future real telemetry source (KRX-035 for signal
/// quality, TASK-065 for RX level) can plug in without a projection
/// redesign, but nothing in this file may synthesize one today.
library;

/// Per-station or aggregate signal-quality reading.
sealed class SignalQuality {
  const SignalQuality();

  /// Single shared instance — signal quality carries no per-call state.
  static const SignalQuality unavailable = UnavailableSignalQuality();
}

/// No real per-peer/aggregate signal metric exists yet (Technical §1.1:
/// `StationInfo.signalQuality` is a disclosed placeholder maximum; the
/// aggregate `RadioState.signalQuality` is never fed a real value either —
/// see `RadioStateBridge.updateSignalQuality`, which has no production
/// caller). UX-FR-045: "show unavailable/unknown, not synthetic
/// full-strength bars."
final class UnavailableSignalQuality extends SignalQuality {
  const UnavailableSignalQuality();

  @override
  bool operator ==(Object other) => other is UnavailableSignalQuality;

  @override
  int get hashCode => (UnavailableSignalQuality).hashCode;

  @override
  String toString() => 'SignalQuality.unavailable';
}

/// A real, verified S-meter reading (1–9, matching `RadioState`'s existing
/// domain) from an actual measurement source. Nothing in this task
/// constructs this variant — it exists so KRX-035 (or an equivalent
/// telemetry task) can plug a real value in later without redesigning the
/// projection (Technical §5.3).
final class MeasuredSignalQuality extends SignalQuality {
  const MeasuredSignalQuality(this.sMeter)
    : assert(sMeter >= 1 && sMeter <= 9, 'S-meter domain is 1–9.');

  final int sMeter;

  @override
  bool operator ==(Object other) =>
      other is MeasuredSignalQuality && other.sMeter == sMeter;

  @override
  int get hashCode => sMeter.hashCode;

  @override
  String toString() => 'SignalQuality.measured($sMeter)';
}

/// Count of stations visible on a LINKED roster, or an explicit
/// "incomplete" marker.
sealed class RosterCount {
  const RosterCount();
}

/// LINKED mode "does not provide a complete roster through this interface"
/// (Technical §1.1) — an incomplete/unknown roster must render as
/// unavailable, "never a verified zero count" (UX-FR-046, VT-024, Design
/// §2.4).
final class UnavailableRosterCount extends RosterCount {
  const UnavailableRosterCount();

  @override
  bool operator ==(Object other) => other is UnavailableRosterCount;

  @override
  int get hashCode => (UnavailableRosterCount).hashCode;

  @override
  String toString() => 'RosterCount.unavailable';
}

/// A verified station count (e.g. LOCAL discovery's own roster, which is
/// authoritative for the stations it reports).
final class KnownRosterCount extends RosterCount {
  const KnownRosterCount(this.count) : assert(count >= 0);

  final int count;

  @override
  bool operator ==(Object other) =>
      other is KnownRosterCount && other.count == count;

  @override
  int get hashCode => count.hashCode;

  @override
  String toString() => 'RosterCount.known($count)';
}

/// The PTT ring/level indicator's animation source (Technical §5.3: "An
/// animation driven by phase is decorative and must not be described as
/// measured RMS"; UX-FR-027; VT-015).
///
/// This retires TASK-043's `PttRingController` semantics, which accepted a
/// bare `double` percentage with no typed distinction between "this is a
/// real audio sample" and "this is a phase-driven decoration" — the exact
/// gap Technical §1.1 flags as "must not migrate". A screen consuming this
/// must render [DecorativeMeterLevel] as a non-telemetric animation (e.g.
/// an idle/TX pulse) and must not label it as a measured mic/network level
/// anywhere in its own UI surface (accessibility text included).
sealed class MeterLevel {
  const MeterLevel();

  static const MeterLevel decorative = DecorativeMeterLevel();
}

/// No real audio tap exists yet. The single shared instance carries no
/// value on purpose — a decorative animation's timing/shape is the
/// rendering widget's own concern, not state projected from the radio.
final class DecorativeMeterLevel extends MeterLevel {
  const DecorativeMeterLevel();

  @override
  bool operator ==(Object other) => other is DecorativeMeterLevel;

  @override
  int get hashCode => (DecorativeMeterLevel).hashCode;

  @override
  String toString() => 'MeterLevel.decorative';
}

/// A real, verified audio-derived level (0–100). Nothing in this task
/// constructs this variant — reserved for TASK-065's real RX metering.
final class MeasuredMeterLevel extends MeterLevel {
  const MeasuredMeterLevel(this.value)
    : assert(value >= 0 && value <= 100, 'Meter level domain is 0–100.');

  final double value;

  @override
  bool operator ==(Object other) =>
      other is MeasuredMeterLevel && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'MeterLevel.measured($value)';
}
