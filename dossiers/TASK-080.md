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

- [2026-09-11T12:15:00Z] [CX] Verified root cause with a pre-fix failing reducer regression: `KeryxRadioHost` dispatches `PowerOn`, starts `RadioSessionController`, then dispatches `BootCompleted`. The controller correctly resolves LOCAL/LINKED and sends `SetMode` during `boot`, but `RadioReducer` previously accepted it only during `idle`; the dispatch was silently discarded and the default `RadioMode.auto` remained visible. The root fix accepts a concrete `SetMode` in any powered phase and rejects AUTO as an effective-route event. Added an explicit `ConnectionCondition.isResolved` plus `routeLabel` (`Connecting` while unresolved), and regression coverage for boot resolution and AUTO labeling.
- [2026-09-11T12:15:00Z] [CX] Also incorporated TASK-079 review findings in the shared controller: meter polling now carries a generation token so an awaited superseded poll cannot start a second chain; audio-level read failures are caught as decorative and the RX poll continues. Targeted tests cover both cases.
- [2026-09-11T12:15:00Z] [CX] Ownership blocker: current presentation call sites that directly render `connection.effectiveRoute` are in `lib/features/channels/channel_format.dart`, `lib/features/channels/channels_landing.dart`, `lib/features/stations/stations_screen.dart`, `lib/features/talk/talk_screen.dart`, `lib/features/settings/about_diagnostics.dart`, and `lib/features/settings/settings_screen.dart`; none are in TASK-080 Owned_Paths. They must switch to `connection.routeLabel` to ensure no unresolved route displays literal `AUTO`. CX has not edited those paths per the ownership protocol.
