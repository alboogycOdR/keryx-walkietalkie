# TASK-060 — Physical-device LINKED acceptance

## Brief

The relay-side hardware gate: LiveKit/Redis/Caddy/coturn plus the FastAPI token
service, same two phones. Validates relay join and bidirectional voice on the
existing backend, the full mode matrix including force-LOCAL override, and the QR
transition cases on real hardware. Territory-disjoint from TASK-059 so both
hardware gates can run concurrently.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Verification_v1.0.md` §7 (LINKED, network
  failure, audio routing, background, upgrade rows), §9 gate G5, VT-022, VT-023,
  VT-024.
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §7 (configured preference vs
  effective route; mode-policy changes need their own ADR), §8, §12.
- PRD UX-D07, UX-FR-046, UX-FR-062, §7; ADR-001 §5.

## Approach

Record explicitly whether the token-service default path was used (TASK-063
landed) or the `ops/TWO_PHONE_TEST.md` §6 bare-origin workaround was still
required — that is why TASK-063 is dispatched in Wave 1. Results to
`ops/FIELD_TEST_LINKED.md`; failures stay failures with a recommended successor
task.

## Work Log
