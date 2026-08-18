# TASK-013 — Rotary knob widget: arc drag, detents, flywheel, haptic hooks (KRX-011)

## Brief
The hero interaction: a 96 dp knurled rotary knob widget in `lib/features/knob/` with detent physics, flywheel fling with friction decay, and per-detent same-frame callbacks (haptic + tick + LCD hook). Emits channel deltas only; the reducer owns tuning state. PT's knob script is the ratified physics reference.

## Spec pointers
- TS D1: "simulated rotary knob with flywheel physics, per-channel detents, and a haptic tick on every detent (VibrationEffect composition primitive CLICK)… the knob sells the fantasy."
- TS §6.2 (normative numbers): "1 detent = 1 channel; detent snap at ±12° with critically-damped settle. Fling → flywheel with exponential decay, detent ticks (audio + haptic) firing per channel crossed, capped at 12 ch/s… Every detent fires: haptic PRIMITIVE_CLICK, 8 ms mechanical tick sample, LCD update — all in the same frame."
- TS §6.4: knob detent haptic = "PRIMITIVE_CLICK (scale 0.6)".
- DS §5.1: "Knurled, 96 dp, with an olive indicator line."
- DS §4: "Nothing bounces except the knob flywheel, which follows real friction decay, not a spring preset." PT: 30°/detent, velocity clamp ≈12 detents/s, decay ×0.94/frame, snap-to-detent on rest.

## Intended approach
1. `knob_physics.dart`: pure physics model (angle, velocity, detent quantisation at 30°/channel, ±12° snap with critically-damped settle, friction decay, 12/s tick cap) — unit-testable without widgets, tick events emitted with channel delta.
2. `knob_widget.dart`: GestureDetector arc-drag (atan2 around centre, ±180° wrap), CustomPaint knurling (36 marks) + olive indicator from theme tokens, `Ticker`-driven flywheel.
3. `knob_feedback.dart`: per-detent callback surface `onDetent(int delta)` — caller wires haptics (vibration package composition CLICK w/ amplitude fallback), tick SFX, LCD update; widget guarantees single-frame co-firing.
4. Widget tests: drag N×30° → N deltas; fling produces decaying ticks never exceeding cap; rest position always a detent multiple.

## Work Log
