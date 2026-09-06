/// Visual/gesture state the PTT surface renders, per TS §6.1/§6.4/FR-020-022.
///
/// This is presentation state only — [PttButton] owns no floor logic and
/// never talks to `FloorEngine` directly (that stays a caller/assembly-task
/// concern, same relationship `KeryxTuningKnob` has to `RadioReducer`). A
/// caller derives this enum from `RadioPhase`/`FloorEffect` (both already
/// shipped by TASK-022, `lib/core/floor/**`, frozen) and feeds it in.
enum PttState {
  /// No TX request outstanding. Idle key-cap treatment.
  idle,

  /// TX requested, grant not yet arrived (FR-020: "Press → TX request →
  /// grant"). Same idle-ish visual as [idle] — there is no distinct PT
  /// treatment for this narrow window (TX attack is spec'd at ≤ 50 ms,
  /// FR-020) — kept as its own state so a caller can still gate on it
  /// (e.g. suppress a second press) without this widget inventing a
  /// dedicated skin for a state PT never rendered.
  requesting,

  /// Floor held by this device. Red TX skeuomorph + edge-glow (FR-026),
  /// "Red appears only while the floor is held by this device" (DS §2).
  granted,

  /// Busy-channel-lockout: "denied buzz + short haptic and the TX LED does
  /// not light" (FR-022). Transient — [PttButton] shows PT's 260 ms amber
  /// deny flash regardless of how long the caller holds this state, then
  /// visually settles back toward [idle].
  denied,

  /// Latch mode engaged (FR-021: "double-tap to lock TX, tap to release").
  /// Visually a held-open [granted]: floor stays held without a continuous
  /// press.
  latched,

  /// Another station owns the floor. The hero disc uses its RX treatment.
  receiving,

  /// A parent-owned emergency session is active. [EmgKey]'s hold behaviour
  /// remains unchanged; this only supplies the hero disc's orange visual.
  emergency,
}
