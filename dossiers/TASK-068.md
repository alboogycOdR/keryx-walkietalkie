# TASK-068 — Replace Talk header overlay hack with real callback wiring

## Brief

ORCH-created 2026-09-08, closing a disclosed fragility from TASK-052's
review: `lib/app_shell/talk_screen.dart` intercepts Talk's picker/stations
header taps with invisible overlays positioned by hardcoded geometry,
because `TalkScreen` (TASK-051) never grew real callback parameters. The
reviewer proved this is a live risk (shifting the overlay 100dp left every
existing test green while a real-centre-tap probe failed) — a future Talk
layout change could silently break these buttons in production. Give
`TalkScreen` real callbacks, delete the overlays, and give Radio Controls a
proper header slot per Design §2.2 while in this territory.

## Spec pointers

- TASK-052's Review_Findings — the exact finding and its proof.
- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §2.2 — Talk header
  affordances, actual layout intent.

## Intended approach

1. Add `onOpenPicker`/`onOpenStations`/`onOpenRadioControls` constructor
   callbacks to `TalkScreen` (`lib/features/talk/**`).
2. In `lib/app_shell/talk_screen.dart`, wire the shell's real navigation
   through those callbacks; delete the geometry-matched overlay widgets.
3. Regression test: wrap Talk's header in extra padding (a test double) and
   confirm the callbacks still fire — this is the guard the overlay
   approach could never provide.
4. Move Radio Controls into a real header slot, not a bottom-left
   `IconButton` bolted onto the PTT area.
5. Full suite + analyze; revert-mutation the new regression test.

## Work Log
