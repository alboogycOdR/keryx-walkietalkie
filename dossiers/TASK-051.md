# TASK-051 — Talk screen and new PTT presentation

## Brief

The primary communication screen and the wave's most safety-critical task. The
intake merged "new PTT presentation" into it deliberately so two builders never
contend for `lib/features/talk/**` (this is why there is no TASK-052). Built
fresh per Design §2.2 — responsive sizing, explicitly not TASK-043's fixed
320 dp disc — and driven entirely by TASK-046's composite view-state.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §2.2 (content order,
  ≥96 dp / ≥48 dp sizing, active-speaker copy, "a disconnected screen must not
  show Ready", non-drag accessible alternative, PTT and Emergency separate),
  §4 (state catalogue), §5 (copy and accessibility).
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §5.1 (authoritative command
  path), §5.2 (preserve or explicitly replace `PttButton`'s pointer suppression
  and double-tap latch, with the full listed test set), §4 (latch owned by the
  host, survives navigation).
- PRD UX-FR-020..030, UX-D03; Verification VT-010..VT-015.
- ADR-001 §6 / §7 item 2 — gesture/latch/TOT semantics reused as logic, widget
  tree new.

## Approach

Requesting may show on pointer-down; red TX only after authoritative grant.
Cancellation, unmount, backgrounding, permission loss and engine replacement all
release ordinary hold with no accidental latch, asserted against engine state
rather than widget colour. Emergency is reflected here as an overlay only — the
control screen is TASK-054's, and FR-025 stays PARKED.

## Work Log
