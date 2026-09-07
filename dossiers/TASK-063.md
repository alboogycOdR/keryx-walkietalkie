# TASK-063 — Token URL double-append fix

## Brief

Pure debt paydown, independent of the redesign, dispatched in Wave 1 so
TASK-060's LINKED hardware test can use real default settings instead of the
runbook's mandatory workaround. `resolvedTokenServiceUrl`
(`lib/core/settings/settings_model.dart:147-153`) already ends in `/token` and
`TokenClient._resolveTokenUri` (`lib/services/linked/token_client.dart:121-124`)
appends `token` again — `/token/token` → 404 → `NO LINK` on the default LINKED
path.

## Spec pointers

- `docs/adr/ADR-001-mobile-ux-redesign-reconciliation.md` §5 (carried as a
  narrowly scoped successor task, not absorbed into a rewrite).
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §0 ("Any confirmed transport
  defect is a separate, narrowly scoped corrective task"), §8 (token-service
  contracts retained).
- PLAN.md `orchestrator_notes` 2026-08-23T05:55Z — the original defect record
  with exact file/line references.
- `ops/TWO_PHONE_TEST.md` §6 — the bare-origin workaround this retires.

## Approach

Fix on exactly one side of the seam; state which and why. The regression test is
the deliverable's point: assert the **resolved URI string** for default settings
and for a path-prefixed custom URL, so neither side can silently reintroduce the
double-append. TASK-024's prefix-preservation behaviour must not regress.
`radio_session_controller.dart` wires the two but is out of territory — a need to
touch it is `OWNERSHIP_CONFLICT`, not a scope widening.

## Work Log
