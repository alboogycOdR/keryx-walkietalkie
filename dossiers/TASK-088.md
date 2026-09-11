# TASK-088 — v2 session and host — target switching, roster-at-start, automatic direct/relay transport, v2 state and settings model

## Brief

The engine-facing half of v2. `RadioState`: remove `channel`, `privacyCode`, `mode`; add `roomId`, `transport (none|direct|relay|both)`; `SetMode` → `SetTransport`; update the reducer and its transition-matrix oracle in lockstep. `KeryxSettings`: remove `mode/region/channel/privacyCode`; add `preferDirectOnWifi` (default true), `messageRetention` (default 7 d), keep the relay URL. `RadioSessionController`: `retune` → `switchTarget(TalkTarget)` which tears down and rebuilds the chain for the target's room, calls `FloorEngine.updateRoster(members)` immediately from the directory member list (closes the solo join-guard, Technical §1.1), and runs LAN mesh and relay together, with the mesh only attaching listeners discovered on the LAN. `KeryxRadioHost.start`: load identity → directory `me` → presence socket → current target (last used, else first group, else none) → session. `RadioViewState`: add `target` and `audience {canHear, reason}`; `ConnectionCondition` becomes `{transport, degraded}`; audience ready rule per V2-FR-041. Fold in the carried debt: throttle meter snapshots (TASK-079 e) and seed the denied-flash timer on remount (TASK-082 a). `lib/core/floor/**` is not in this task and must not change.

## Spec pointers

- specs/KERYX_v2.0_Technical_v1.0.md §1.1, §6.3, §6.4, §7 (settings_model, radio_state, radio_session_controller); PRD V2-FR-040..045; Verification V2-VT-021, 022 (projection half), 023, 024; TASK-079 (e), TASK-082 (a) carried debt
- Owned_Paths: lib/services/session/**, lib/services/mesh/**, lib/core/radio_host/**, lib/core/state/**, lib/core/settings/**, lib/core/presentation/**, test/services/session/**, test/services/mesh/**, test/core/radio_host/**, test/core/state/**, test/core/settings/**, test/core/presentation/**, dossiers/TASK-088.md
- Depends_On: TASK-086, TASK-087

## Work Log
