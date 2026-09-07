# TASK-050 — Channel selector and tune coordinator

## Brief

The selector UI plus the retune serialization work Technical §6 explicitly names
as a dedicated migration task: today the app dispatches `TuneTo` and fires an
async retune without awaiting it, so competing requests race. Deliver direct
entry and list selection (1–99 / 0–38, two-digit labels, recall as a separate
section, Apply disabled while invalid, Cancel a true no-op) over a coordinator
with a deterministic latest-wins policy.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §2.3 — full selector contract,
  pending-retune progress, "currently active channel remains authoritative".
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §6 — latest-wins, no
  optimistic claims, and "do not invent rollback support" where the previous
  chain is already torn down: document and test a recovery policy instead.
- PRD UX-FR-003/004/009/010/030; Verification VT-020, VT-021.
- ADR-001 §5 — session retune contracts preserved; the fix is at the coordinator.

## Approach

Build over TASK-045's single serialized tune entry point. Keep the requested
target visibly distinct from the authoritative current channel while tuning.
VT-021's deferred-future ordering test is the load-bearing evidence — write it
first, then make it pass.

## Work Log
