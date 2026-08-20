# PTT button, secondary key row, EMG side key (KRX-015)

The transmit controls: the full-width thumb-native PTT (`PttButton`), a
standalone TX edge-glow overlay (`PttEdgeGlow`), the secondary key row
(`PttKeyRow`: MON/SCAN/SAY AGN/settings), and the orange EMG side key
(`EmgKey`).

## Contract

Every widget here is presentation + intent only. None talks to
`FloorEngine` (`lib/core/floor/**`, TASK-022, frozen) directly — a caller
(a future TASK-017-class assembly) derives `PttState` from
`RadioPhase`/`FloorEffect` and turns this package's intent callbacks into
`FloorEngine.requestTransmit()` / `.releaseTransmit()` / `.clearEmergency()`
calls, same relationship `KeryxTuningKnob` has to `RadioReducer`.

- `PttButton(state, onPressStart, onPressEnd, onLatchToggled, latchEnabled)`
  — hold-to-talk by default; when `latchEnabled`, a double-tap
  (`kDoubleTapTimeout` window — PT has no latch implementation to source a
  ratified figure from) engages `onLatchToggled(true)` instead, and any tap
  while `state == PttState.latched` fires `onLatchToggled(false)`.
- `PttEdgeGlow(active, {child})` — standalone housing-level overlay,
  exported separately so TASK-017 can mount it once regardless of which
  widget currently owns TX state.
- `PttKeyRow` — MON carries press-and-hold semantics
  (`onMonHoldStart`/`onMonHoldEnd`); SCAN/SAY AGN/settings are plain taps.
  `lockedKeys` renders the Pro-locked dimmed treatment but the key's intent
  still fires on a locked press (PT's own locked-key `onclick` still calls
  `SFX.deny()`) — the caller turns a locked intent into a deny sound.
- `EmgKey(onEmergencyToggled, pinned)` — fires once a 600 ms press-and-hold
  threshold (PT L386-388) is crossed; `pinned` is purely the externally-owned
  lit/dimmed visual, not internal state.

## Haptics

`PttHapticFeedback` mirrors `knob_feedback.dart`'s shape: `grant()` (TS
§6.4 `PRIMITIVE_QUICK_RISE`, single pulse), `denied()` (`PRIMITIVE_THUD ×2`,
pulse/pause/pulse matching PT's own `[18,40,18]` deny vibration), and
`totWarning()` (`PRIMITIVE_TICK ×3`) — the last is a composition primitive
only; `PttButton` never fires it itself, since TOT is a `FloorEffect.TotWarn()`
concern outside this widget's state machine. `grant()`/`denied()` fire
automatically from `PttButton`'s own state transitions (test/production seam:
`onGrantHaptic`/`onDeniedHaptic`, defaulting to the real implementation).

## Visuals

- PTT: PT's own `.ptt`/`.ptt.on`/`.ptt.deny` gradients (no theme token
  exists for these key-cap gradients — hardcoded with the same disclosure
  class as TASK-012's glass-recess chrome). Denied state shows PT's 260 ms
  deny flash (`PttButtonState.denyFlashDuration`) regardless of how long the
  caller holds `PttState.denied`.
- Press travel: `KeryxTheme.keyTravel` (1 dp) uniformly across every key in
  this package, including the PTT surface — DS §4's explicit "same three
  changes on every control" generalization, over PT's PTT-specific 2 px
  literal (disclosed in `ptt_button.dart`'s library dartdoc, same resolution
  direction TASK-016 took for the settle curve).
- Red (`KeryxTheme.tx`) appears only in `PttButton`'s granted/latched visuals
  and `PttEdgeGlow` when `active` — never elsewhere in this package (DS §2).
