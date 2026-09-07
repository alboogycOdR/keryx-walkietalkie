# TASK-046 — RadioViewState presentation projection + telemetry honesty

## Brief

A pure projection between TASK-045's host and every successor screen, so no
widget reads raw reducer state or invents its own state machine. Phase,
emergency, latch, denied flash, connection condition and service/permission
faults are modelled as *independent* fields with deliberate precedence — not a
single priority switch. Telemetry honesty ships with it: placeholder quality and
unknown LINKED roster counts project as unavailable, and any level animation is
typed as decorative.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §5.1 (command path; the UI
  never synthesizes floor events), §5.2 (composite state), §5.3 (telemetry
  honesty), §1.1 (`StationInfo.signalQuality` placeholder max; the mislabelled
  amplitude meter "must not migrate"; the `RadioState` equality gap), §9.
- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §4 — the 13-row state
  catalogue and the "emergency is an overlay, not a replacement" rule.
- PRD UX-FR-002/022/026/027/045/046; Verification VT-010, VT-015, VT-024.
- ADR-001 §5/§6 — reducer and floor semantics are not superseded.

## Approach

Immutable view-state + typed intents in `lib/core/presentation/**`, delegating
every intent to the host. Model both `measured` and `unavailable` telemetry
variants so TASK-065's real RX source can plug in later without a redesign —
but do not depend on TASK-065 landing. Assess Technical §1.1's `RadioState`
equality gap against each projected field and report rather than "fix" the
reducer; a genuine dependency on an excluded field is a `SPEC_AMBIGUITY` block,
not an opportunistic reducer change.

## Work Log
