# TASK-057 — Accessibility and responsive polish

## Brief

A single-owner cross-screen gate, deliberately serialized after all seven Wave 4
screens: its territory is the union of theirs, so exactly one task ever holds the
whole successor feature surface at once. Sweep every screen against the
Verification §6 matrix and fix what fails rather than merely reporting it.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Verification_v1.0.md` §6 — 320 logical-pixel
  width, normal/large phone, landscape, text scale 1.0 and 2.0, large insets;
  48 dp targets, PTT size, contrast, focus order, TalkBack, keyboard/switch,
  reduced motion; "Design review must approve actual renderings, not just token
  names".
- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §5 (semantic labels; keyboard
  and screen-reader users must be able to tune, cancel, open Stations, navigate
  Settings and release a latched TX), §3.3, §3.4.
- PRD §6; ADR-001 §3 item 2 (old UI spec §8's accessibility substance carries
  forward).

## Approach

Narrow touch-ups only. Releasing a latched TX without a pointer is a safety
property, not a nicety — treat it as such. A defect needing a screen's
behavioural redesign is a finding for a successor task, not something absorbed
silently here. Note the known trap recorded in this plan: M3 pads
`IconButton`'s render box to 48×48 regardless, so assert `constraints` or use
`meetsGuideline`, never `tester.getSize`.

## Work Log
