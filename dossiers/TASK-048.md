# TASK-048 — Mobile app shell and navigation

## Brief

The convergence task: mount TASK-045's host above the navigator so it is built
once at app scope, then build the two-destination shell (Channels default,
Settings) with Talk as a route beneath Channels. Route registration, shared
providers and final wiring live here and nowhere else, which is why this is a
single-owner integration task and the gate for all seven screen tasks.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §1 — IA tree; two persistent
  destinations; "its presentation lifecycle must not own the radio session".
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §2 (`MobileAppShell`,
  single ProviderScope; no mandated routing/state package), §4 (navigation never
  starts/disposes/retunes), §9 (this task owns app.dart and route registration),
  §10 (dev-only compat route for the legacy face).
- PRD UX-D01, UX-D02, UX-FR-001/005/007/008; Verification VT-001, VT-004.
- ADR-001 §3 item 1 — supersedes PTS P1's no-bottom-nav clause.

## Approach

Thin stand-in destinations are acceptable so the shell is testable before Wave 4
fills them — but never fake data, presence or unread counts, and no destination
for an unimplemented product surface. Keep exactly one `ProviderScope`. Prefer
existing repo conventions for routing/state; adding a package means blocking with
`SPEC_AMBIGUITY`, since `pubspec.yaml` is frozen and out of territory. Legacy
face stays reachable only through the development-only compat route that
TASK-061 later deletes.

## Work Log
