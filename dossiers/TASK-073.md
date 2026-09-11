# TASK-073 — UX R2 PTT ring widget

## Brief

Build `TalkPttRing` in a new file: dark face, thick state-coloured ring, mic glyph, no text, glow driven only by `MeasuredMeterLevel`, press scale plus haptic, and an accessible start/stop toggle via semantics action and keyboard. Nothing is wired; TASK-074 does that.

## Spec pointers

- docs/adr/ADR-002-zello-aligned-talk-first-ui.md §3 A3, A4
- Owner reference: Zello Android PTT (dark disc, one thick ring, faint mic glyph) — inspiration only, copy no assets (Design §0)
- lib/features/talk/talk_ptt_disc.dart — current `TalkPttDisc`: reuse its `Listener` + `_holding` idempotency exactly (VT-011)
- lib/core/presentation/telemetry.dart — `MeterLevel` sealed type
- Design §3.4: no fake waveform animation

## Approach

1. Colours come in as parameters; read no theme.
2. Build a CustomPainter for ring, sweep arc and lock badge, with the glow as a BoxShadow computed from the measured value.
3. Use AnimationControllers only for press, sweep and shake; none runs for DecorativeMeterLevel at rest.
4. Test gesture idempotency, the semantics custom actions, Enter/Space, sizeFor clamps and reduced motion.

## Work Log

- 2026-09-11T10:50:00Z [CX] Implemented standalone `TalkPttRing`: parameter-only colours, custom-painted face/ring/glyph/sweep/lock badge, measured-only glow, press feedback + haptic, reduced-motion static variants, idempotent pointer hold and semantics/keyboard toggles. Added focused widget tests for sizing, telemetry honesty, treatment rendering, hold cancellation, semantics and keyboard behavior. No Talk screen wiring or golden changes are part of this task.
- 2026-09-11T13:00:00Z [CX] Rework round 1: removed mount-time keyboard autofocus so Enter/Space only acts after deliberate PTT focus. Added direct painter-colour coverage for every treatment and disabled dimming; expanded motion coverage for requesting, denied flash and reduced motion; verified decorative idle schedules no animation; and verified pointer, semantics and keyboard input are all rejected while disabled.
