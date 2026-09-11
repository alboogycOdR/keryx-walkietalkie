# TASK-081 — Adopt the resolved route label in every UI call site

## Brief

ORCH re-carve of TASK-080's OWNERSHIP_CONFLICT block. TASK-080 fixed why the
effective route could stay `auto`, and added `ConnectionCondition.isResolved` /
`routeLabel`. Six UI call sites still format `effectiveRoute` themselves.
Route them all through the new label so AUTO never shows as an *effective* route.

## Spec pointers

- specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md §7; PRD UX-FR-002
- lib/core/presentation/connection_condition.dart (after TASK-080)
- dossiers/TASK-080.md (call-site list)

## Approach

1. Grep `lib/features/**` for `effectiveRoute` and `radioModeLabel(`.
2. Replace each effective-route rendering with `routeLabel`; leave the configured-mode labels alone.
3. Add unresolved/resolved widget tests per call site.
4. Regenerate only the goldens that actually change.

## Work Log
