/// Pure, widget-free tuning-knob physics (KRX-011).
///
/// Mirrors `specs/keryx-face-prototype.html`'s arc-drag + flywheel script
/// (L286-323) — the "ratified physics reference" per the task dossier —
/// with two deliberate, disclosed resolutions of PT-vs-TS numeric tension:
///
/// 1. **Channel clamp, not wrap.** PT wraps at the 99/1 boundary
///    (`((S.ch-1+n)%99+99)%99+1`); ORCH ruled 2026-08-19T18:30:00Z
///    (follow-up k) that this widget must CLAMP instead, matching most
///    physical radio channel selectors and avoiding an accidental
///    fling/auto-repeat overshoot discontinuity. See [KnobPhysics.clampDelta].
/// 2. **Explicit 12 ch/s tick governor.** PT's literal velocity cap (`22`
///    deg/frame, comment "cap ≈ 12 detents/sec") does not, by itself,
///    guarantee that ceiling — at 60 fps a capped-velocity fling can still
///    cross one detent on consecutive frames, which is nearer 44-60 ch/s
///    than 12. TS §6.2 states "capped at 12 ch/s" as an explicit normative
///    number, so [KnobFlywheel] enforces it as a hard governor on top of
///    PT's decay feel. Same class of PT/TS numeric resolution as DS §10's
///    settle-curve precedent (TASK-016) and TASK-028's housing-noise-opacity
///    disclosure — flagged for ORCH, non-blocking.
library;

/// Tuning-knob physical constants and pure helper functions.
abstract final class KnobPhysics {
  /// PT `DETENT` — degrees of knob rotation per channel (TS §6.2: "1 detent
  /// = 1 channel").
  static const double detentDegrees = 30;

  /// PT `up()`'s velocity clamp: `Math.max(-22,Math.min(22,vel))`, in
  /// degrees per animation frame (~16 ms at 60 fps).
  static const double velocityCap = 22;

  /// PT `vel*=0.94` per animation frame — exponential friction decay, "not
  /// a spring preset" (DS §4).
  static const double frictionPerFrame = 0.94;

  /// PT `Math.abs(vel)<.4` — velocity magnitude below which the flywheel is
  /// considered at rest and snaps to the nearest detent.
  static const double restThreshold = 0.4;

  /// TS §6.2 "capped at 12 ch/s" — the normative fling detent-tick rate
  /// ceiling. See the library dartdoc for why this is enforced explicitly
  /// rather than relying on [velocityCap] alone.
  static const double maxTicksPerSecond = 12;

  /// Minimum device channel (TS/[`RadioState.minimumChannel`]).
  static const int minimumChannel = 1;

  /// Maximum device channel (TS/[`RadioState.maximumChannel`]).
  static const int maximumChannel = 99;

  /// Clamps a raw velocity (deg/frame) into `[-velocityCap, velocityCap]`.
  static double clampVelocity(double raw) =>
      raw.clamp(-velocityCap, velocityCap);

  /// Nearest detent index for a continuous knob angle in degrees. Detent 0
  /// sits at angle 0; each whole detent is [detentDegrees] further around.
  static int detentIndexFor(double angleDegrees) =>
      (angleDegrees / detentDegrees).round();

  /// Resolves a raw (unclamped) channel delta against [currentChannel] so
  /// the result never pushes the channel outside
  /// `[minimumChannel, maximumChannel]` — CLAMP semantics per the ORCH
  /// ruling in the library dartdoc. Returns the delta actually applicable
  /// (may be smaller than [rawDelta], or `0` at a boundary).
  static int clampDelta(int currentChannel, int rawDelta) {
    final target = (currentChannel + rawDelta).clamp(
      minimumChannel,
      maximumChannel,
    );
    return target - currentChannel;
  }
}

/// One post-release fling simulation instance.
///
/// Framerate-agnostic in its tick-rate governor: [step] is meant to be
/// called once per rendered frame (mirroring PT's
/// `requestAnimationFrame`-driven `spin()`), but regardless of how often it
/// is called, emitted detent ticks never exceed
/// [KnobPhysics.maxTicksPerSecond] — ticks that would exceed the governor
/// are batched (not dropped) and flushed on the next allowed slot, or on
/// rest, so the cumulative channel delta over a fling's lifetime is always
/// exact even though instantaneous rotation follows PT's uncapped decay.
class KnobFlywheel {
  KnobFlywheel({required double initialVelocity, double startAngle = 0})
    : _angle = startAngle,
      _velocity = KnobPhysics.clampVelocity(initialVelocity);

  double _angle;
  double _velocity;
  int _pending = 0;
  double _msSinceEmit = double.infinity;

  /// Current continuous knob angle, degrees. Widgets read this every tick
  /// to drive the visual rotation.
  double get angle => _angle;

  /// Current flywheel velocity, degrees/frame.
  double get velocity => _velocity;

  /// `true` once velocity has decayed under [KnobPhysics.restThreshold] and
  /// the angle has snapped to the nearest detent — the caller should stop
  /// ticking after this.
  bool get isFinished => _velocity.abs() < KnobPhysics.restThreshold;

  /// Advances the simulation by one rendered frame. [elapsedMs] is the real
  /// wall-clock time since the previous [step] call (or since construction,
  /// for the first call) — used only to gate the [KnobPhysics.maxTicksPerSecond]
  /// governor; the angle/velocity integration itself is PT's per-frame
  /// model exactly (frame-counted, not time-scaled), matching the ratified
  /// physics reference.
  ///
  /// Returns the signed channel delta to emit this frame — usually `0`, an
  /// arbitrary batched integer when the governor releases pending ticks, or
  /// the final remainder when the flywheel comes to rest.
  int step(double elapsedMs) {
    if (isFinished) return _flush();
    final beforeIndex = KnobPhysics.detentIndexFor(_angle);
    _angle += _velocity;
    _velocity *= KnobPhysics.frictionPerFrame;
    final afterIndex = KnobPhysics.detentIndexFor(_angle);
    _pending += afterIndex - beforeIndex;
    _msSinceEmit += elapsedMs;
    if (isFinished) {
      // PT: `knobAngle=Math.round(knobAngle/DETENT)*DETENT` — snap to rest.
      _angle = afterIndex * KnobPhysics.detentDegrees;
      return _flush();
    }
    final minGapMs = 1000 / KnobPhysics.maxTicksPerSecond;
    if (_pending == 0 || _msSinceEmit < minGapMs) return 0;
    return _flush();
  }

  int _flush() {
    if (_pending == 0) return 0;
    final out = _pending;
    _pending = 0;
    _msSinceEmit = 0;
    return out;
  }
}
