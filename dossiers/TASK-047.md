# TASK-047 — New design system, tokens and themes

## Brief

Replace the hardware-faceplate visual language with the successor token system
so every Wave 4 screen has one source of visual truth on day one: the eleven
Design §3.2 tokens in both dark and light, the §3.3 type scale and 8 dp spacing
grid, and §3.4's motion/reduced-motion tokens. Dark is default; light is
complete, not a stub. Additive — the legacy face still builds until TASK-061.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §3.1 (direction; no simulated
  screws/molded textures/seven-segment glass), §3.2 (token table, both columns;
  "do not scatter literal color values across widgets"), §3.3 (type scale, Inter,
  8 dp grid, 48×48 dp), §3.4 (icons and motion).
- PRD UX-D08, UX-FR-065 (KERYX branding; no Zello assets), §6 (WCAG AA).
- ADR-001 §3 item 2 — the old UI spec's §8 *substance* (≥4.5:1 contrast, 48 dp,
  TalkBack, sound/haptic-only operability) carries forward unchanged.

## Approach

A theme extension in `lib/core/theme/**` following this repo's existing
conventions, added alongside the faceplate tokens rather than replacing them
in place. Contrast is asserted by a real computation test over every sanctioned
foreground/background pair; a supplied hex that fails WCAG AA is reported with
its measured ratio and a minimal correction, never silently shipped or silently
substituted. Ships the system and its tests only — no `lib/features/**`.

## Work Log

- [2026-09-07T18:23:12Z] [GB] Claimed TASK-047 (`d4576ad`) on `task/TASK-047-gb`. Preflight (verbatim in PLAN.md): existing `theme.dart` + `theme_test.dart` + this dossier. Additive ThemeExtension; not replacing `KeryxFacePlate`.
- [2026-09-07T18:30:00Z] [GB] Contrast audit of Design §3.2 verbatim hexes (Flutter `computeLuminance` / WCAG 2). **Shipped unchanged.** Sanctioned body text (`text/primary` + `text/secondary` × three surfaces, both themes) all ≥4.5:1. Sanctioned graphical (action/state × surfaces) all ≥3:1. Four spec pairs miss 4.5:1 as 16 px body text on `surface/raised` and are **not** sanctioned as body text (colour remains a redundant cue via `KeryxUxStateCue` label+icon):
  - dark `action/primary` on `surface/raised` **4.40:1** — minimal correction `#5090FF` (~4.54), not applied
  - dark `state/tx` on `surface/raised` **3.94:1** — minimal correction `#F0665E` (~4.54), not applied
  - light `action/primary` on `surface/raised` **4.45:1** — minimal correction `#2366D8` (~4.51), not applied
  - light `state/rx` on `surface/raised` **4.35:1** — minimal correction `#137A55` (~4.53), not applied
  `border/default` vs surfaces is 1.18–1.69:1 and is not sanctioned as a 3:1 graphical object (hairline separator; grouping is by surface fill). On-fill labels use `contrastingOn` (palette token or black/white), never a rewritten fill hex. Icon family is Flutter Material Icons (`uses-material-design: true` already); no Zello/third-party asset added.
- [2026-09-07T18:36:00Z] [GB] Implementation: `KeryxUxTokens` ThemeExtension + `keryxUxThemeData()` (dark default, complete light). `theme.dart` re-exports; `KeryxTheme`/`KeryxFacePlate` untouched. Tests 17 new. Revert-mutation: (1) dark `text/primary` → `#000000` fails "dark column matches Design §3.2 verbatim"; restored. (2) skip reduced-motion zeroing (`if (false && reducedMotion)`) fails "reduced motion drops decorative/page" (Expected 0, Actual 160ms); restored. `flutter test test/core/theme/` 28/28. Full suite **1054 passed / 0 failed / 40 skipped**. `flutter analyze lib/core/theme test/core/theme` no issues; repo-wide 8 pre-existing TASK-035 warnings in `radio_session_controller_test.dart` only. Flutter CLI auto-upgrades `analysis_options.yaml`; reverted every time (not in territory). → needs_review.
