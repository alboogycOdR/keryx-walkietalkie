# TASK-072 — UX R2 tokens — amber accent, PTT ring/face tokens, tab indicator, golden refresh

## Brief

The owner chose amber/radio-yellow as the accent (ADR-002 O3). This task retunes `actionPrimary`, adds the tokens the new PTT ring and tab strip need, and regenerates every golden so the repaint lands in one reviewed step before any screen work.

## Spec pointers

- docs/adr/ADR-002-zello-aligned-talk-first-ui.md §3 A5, A3, A1
- specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md §3.2 (tokens, contrast), §3.4
- lib/core/theme/ux_tokens.dart — existing palette + `contrastingOn`
- Current `stateWarning` is already amber (#F0B44C dark): after this change it must never be used on the PTT ring (A5)

## Approach

1. Pick amber values for dark and light, check contrast with the existing helpers, and make sure `contrastingOn(accent)` resolves to a dark foreground in dark mode.
2. Add the new tokens without renaming anything; dartdoc each with its ADR-002 clause.
3. Add hue-separation and contrast tests.
4. Run `flutter test --update-goldens test/regression/goldens`, spot-check the PNGs, and list them in the Work Log.

## Work Log
