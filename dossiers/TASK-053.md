# TASK-053 — Stations screen

## Brief

A new full-screen roster over the *same* host station stream TASK-043's
`RosterScreen` used — data source unchanged, widget tree new. Live join/depart
while open, driven by its own subscription rather than a parent rebuild. The
honesty requirements are the substance of the task, not decoration.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §2.4 — live update without a
  parent rebuild, empty state, current-channel context, QR actions, quality
  omitted or marked unavailable, incomplete LINKED roster stated explicitly
  rather than shown as a verified zero.
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §1 (Roster row), §1.1
  (LOCAL-signaling-backed stream; `signalQuality` placeholder maximum).
- PRD UX-FR-008/026/040/045/046; Verification VT-024.
- ADR-001 §6 — "the live-data SOURCE is unchanged, the widget is".

## Approach

Re-prove the live join/depart guarantee here rather than assuming it carried
over. Neutral fallback for unknown identity, never a peer ID as a verified human
name. Local station count and any LINKED member count are distinct. QR entry
points only — the QR screens are TASK-056's.

## Work Log
