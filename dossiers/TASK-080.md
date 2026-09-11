# TASK-080 — Effective route shows AUTO

## Brief

A real phone showed "Configured LOCAL · Route AUTO", which contradicts the invariant that the effective route is always a concrete route. Reproduce it with a failing test, find the root cause (leading hypothesis: a queued `SetMode` that is never flushed, and `RadioState.mode` defaulting to auto), fix it, and give the UI an explicit unresolved state.

## Spec pointers

- specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md §7; PRD UX-FR-002
- lib/core/presentation/connection_condition.dart dartdoc
- lib/services/session/radio_session_controller.dart start() -> _queueSetMode
- lib/core/state/radio_state.dart (mode defaults to RadioMode.auto)

## Approach

1. Write the failing tests first: start, retune, rebuild.
2. Find and record the cause.
3. Fix at the root.
4. Add an unresolved state to ConnectionCondition.

## Work Log
