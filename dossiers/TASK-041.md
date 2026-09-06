# TASK-041 — Retire the knob and grille, collapse the display into a top LCD strip

## Brief

The approved Phase 2 design (https://claude.ai/code/artifact/885a21ca-a4f2-4605-bc9a-7a36807be74e)
replaces the full knob+glass+grille main screen with a single hero PTT disc and a
compact top status strip. This task deletes the two features that no longer exist
in that design (knob, grille) and reshapes the display glass into a narrow,
self-contained header-strip widget that TASK-043 will drop into the new layout.
Palette/type/material tokens are unchanged — this is a layout and composition
change only, never a new hex or a new font.

## Spec pointers

- Approved canvas artboards `Main.dc.html` / `Emergency.dc.html` — the header
  block (telltale row + `CH ##` seven-segment + S-meter + status line) is what
  the reworked display widget must reproduce.
- `specs/KERYX_UI_Design_Specification_v1.0.md` §2 (Colour Tokens — unchanged),
  §3 (Typography — `DSEG7 Classic` numerals, `Share Tech Mono` secondary line),
  §5.1/§5.3 (knob/grille as signature elements — explicitly superseded for the
  main screen by the approved canvas; this spec text should eventually get a
  formal amendment, tracked as ORCH debt in `orchestrator_notes`, not this task).
- `lib/core/theme/theme.dart` — `KeryxTheme.glassBorder`, `glassInnerShadow`,
  `glassHighlight`, `glassBloomStop`, `ghostSegmentOpacity` (0.07) are the exact
  tokens the existing `keryx_lcd_display.dart` already uses; keep using them.

## Intended approach

1. Repo-wide grep for `features/knob` and `features/grille` imports before
   touching anything. Expect hits only inside their own directories and inside
   `lib/features/face/**` (which TASK-043 will clean up). Anything else is a
   surprise — note it in the Work Log rather than silently breaking it.
2. Delete `lib/features/knob/**`, `lib/features/grille/**`,
   `test/features/knob/**`, `test/features/grille/**` wholesale.
3. Rework `lib/features/display/keryx_lcd_display.dart` (or split into new
   files under `lib/features/display/` if that reads better — builder's call)
   into a standalone strip widget: constructor takes plain data (mode/channel/
   telltale booleans/status string), no `FaceScreen` or session coupling.
   Reuse the existing ghost-segment technique (dim `88` behind the lit value)
   rather than inventing a new one.
4. Check whether `lib/features/grille/grille_motion.dart` has amplitude-smoothing
   math TASK-042's ring meter could reuse. If yes, extract the pure function
   somewhere sensible under `lib/features/display/**` before the grille directory
   is deleted; if no, say so plainly so TASK-042 doesn't go looking for it.
5. Widget-test the new strip standalone across every telltale/status combination
   named in the acceptance criteria.

## Work Log

- [2026-09-06T05:16:58Z] [GB] Claimed on `task/TASK-041-gb`. Preflight pasted in PLAN.md (5 knob + 4 grille + 2 display + 3 knob tests + 2 grille tests + 1 display test + this dossier).
- [2026-09-06T05:20:00Z] [GB] Repo-wide grep for `features/knob` and `features/grille` **imports** before deletion:
  - **Real Dart imports (TASK-043 cleanup, expected):** `lib/features/face/face_view.dart` (`grille.dart`, `knob.dart`); `test/features/face/face_view_test.dart` (`knob.dart`). Face will not compile until TASK-043 rewires the layout — that is the scoped hand-off, not a hidden coupling.
  - **Comment-only hits, not imports, outside face/ and this task:** `lib/features/tuning/tuning_physics.dart`, `lib/features/tuning/tuning_haptics.dart`, `lib/features/ptt/ptt_haptics.dart`, `test/features/ptt/ptt_button_test.dart` — historical "mirrors KnobPhysics / KnobHapticFeedback" comments. Frozen/other-owned; not Dart imports; flagged, not silently edited.
  - **No other production import** of either package.
- [2026-09-06T05:21:00Z] [GB] **Meter-math decision: NOT extracted.** `GrilleMotion` is grille-slot tremble (`sin(elapsedMs/90 + barIndex) * 0.5 * amp * jitter`, 9 bars, MONITOR 0.25). TASK-042's ring is 64 radial ticks lighting from the top as a 0–100 level meter — a threshold mapping, not tremble. A shared utility would be a false abstraction. TASK-042 should own its own `level → lit-tick` mapping. `clampAmplitude` is three lines and not worth a cross-task dependency. Documented in `lib/features/display/README.md`.
- [2026-09-06T05:22:00Z] [GB] LCD strip reworked: telltales LOCAL/LINKED/TX/RX (amber or 7% ghost), `CH` + DSEG7 two-digit with `88` ghost, 9-bar S-meter, status line. Constructor is `KeryxDisplayModel({channel, mode, telltales, statusLine, signalQuality, dimLevel, isBooting})` — primitives + the strip enum only. Knob/grille source+tests deleted. Digit size 32 (DS §3's 56 was full-glass; canvas shrinks layout). Chrome wired to `KeryxTheme.glassBorder` / `glassInnerShadow` / `glassHighlight` / `glassBloomStop` (TASK-012 had hardcoded the same literals).
- [2026-09-06T05:23:20Z] [GB] Verify: `lib/features/knob`, `lib/features/grille`, `test/features/knob`, `test/features/grille` all absent (`Test-Path` False). `flutter analyze lib/features/display test/features/display` — No issues found. `flutter test test/features/display` — 13/13 pass. Revert-mutation: (1) TX telltale colour → `KeryxTheme.tx` fails `TX lit uses amber` (expected lcd amber, actual tx red); restored. (2) unlit opacity `0.09` (old glass) fails `all-ghost idle` (Expected 0.07, Actual 0.09); restored. Flutter's auto-upgrade of `analysis_options.yaml` was reverted — not in territory. Full suite will not compile until TASK-043 removes face's knob/grille imports; that is in-scope for 043, not a 041 defect. → needs_review.
