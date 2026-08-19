# TASK-016 — Speaker-grille RX visualiser (KRX-014)

## Brief
The grille widget in `lib/features/grille/`: horizontal slot bars that tremble with incoming RX amplitude — the one permitted ambient animation. Amplitude arrives as an injected stream; reduced-motion disables the tremble without touching audio/haptic behaviour.

## Spec pointers
- TS §6.1: "The **speaker grille visualisation** is the only 'animation for its own sake' allowed: grille bars tremble with incoming audio amplitude."
- DS §5.3: "Amplitude-driven tremble of the grille slots during RX — the only ambient animation permitted."
- DS §4: "`settle` (320 ms, ease-out) for the grille and meter, which have mass… `prefers-reduced-motion` removes the grille tremble and flywheel animation but **keeps every haptic and sound**."
- PT grille: 9 bars, scaleY tremble `1 + sin(t/90 + i) * 0.5 * amp * rand`, live tint `#12211a` during RX, monitor at 0.25 amplitude.

## Intended approach
1. `grille_widget.dart`: shell-900 recessed container (lip + inset shadows from tokens), N slot bars via CustomPaint or Rows.
2. `grille_controller.dart`: consumes `Stream<double>` amplitude (0–1), maps to per-bar scale with PT's phase-offset formula, `settle`-curve smoothing on level changes; `live` flag tints bars.
3. `MediaQuery.disableAnimations` / injected reduced-motion flag: freeze bars at rest scale while still subscribing (behaviour parity, visuals quiet).
4. Widget tests: amplitude > 0 changes transforms, reduced-motion keeps them static, live tint toggles, zero-amplitude rest state.

## Work Log

- [2026-08-19T20:55:03Z] [GB] Implemented KRX-014 under `lib/features/grille/` + `test/features/grille/`. `KeryxSpeakerGrille` takes an injected `Stream<double>` (no audio-engine import), settles level via `KeryxTheme.settleDuration`/`settleCurve` (not re-declared), trembles 9 slots with the PT `sin(t/90+i)*0.5*amp*rand` formula, live tint `#12211a` / idle `#0d0f10`. Reduced motion (`reduceMotion` or `MediaQuery.disableAnimations`) freezes scales at 1 while the stream still updates `lastAmplitude`. `flutter analyze` clean; `flutter test` 207/207. Handing off `needs_review`.
