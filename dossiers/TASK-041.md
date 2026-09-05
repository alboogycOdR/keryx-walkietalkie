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

(empty — fill in as work proceeds)
