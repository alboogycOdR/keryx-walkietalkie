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
