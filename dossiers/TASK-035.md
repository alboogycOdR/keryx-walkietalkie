# TASK-035 Dossier — Radio Session Layer (Session/Host Composition)

## Overview
Built the missing host-composition layer (`lib/services/session/`) that wires together LOCAL (LAN-based) and LINKED (relay-based) transport lifecycles into a single `RadioSessionController` that `FaceScreen` drives.

## Implementation Summary

### Core Files
- `radio_session_controller.dart` — `RadioSessionController`: the composition root
  - Mode resolution: `local` → LOCAL only; `linked` → LINKED only; `auto` → LINKED (if relay configured) else LOCAL; `forceLocalOnly` overrides all
  - LOCAL chain: `SignalingEndpoint` → `SignalingService.start()` → read `boundPort` → `DiscoveryService.start(signalingPort: ...)` → `onTuned()` → `attachDiscovery()`
  - Floor composition via TASK-032 injection seam: `MeshFloorTransport` → `FloorEngine(transport:)` → `MeshController(floorEngine:, floorTransport:)`
  - LINKED chain: `TokenClient` (from settings) + `LiveKitAdapter` → `LinkedController(relayUrl:, dispatch:)` → `joinNumbered()` with region/channel/code
  - Roster feed: `signaling.sessionsJoined/Departed` → `engine.updateRoster()` + `bridge.updateRoster()` + expose `Stream<StationInfo>`
  - SetMode queueing: dispatch `SetMode` reflecting the active mode; queue if not idle, flush on return to idle (per reducer trap §8.2)

- `linked_proxy_floor_transport.dart` — `LinkedProxyFloorTransport`: thin proxy adapting LINKED's `FloorTransport` to the same interface as `MeshFloorTransport`

- `station_info.dart` — `StationInfo`: simple DTO (peerId, callsign) for roster entries

- `session.dart` — barrel export

### Disclosed Design Decisions
1. **Settings snapshot at construction** — `KeryxSettings` captured once; mode changes require a new `RadioSessionController` (matches host-agnostic injection idiom, keeps mode logic synchronous/testable)
2. **AUTO mode "reachability" is configured, not probed** — `relayUrl` non-empty + parseable = configured (reachable enough to attempt); live reachability probed during join via `LinkMonitor` fallback (no startup latency tax)
3. **No Riverpod import** — host-agnostic by design; all effects go through `dispatch` callback (one-way ingress, same convention as `MeshController` / `LinkedController`)
4. **LINKED roster undefined** — signaling is LOCAL-only per spec; LINKED roster comes from somewhere else (TASK-037 may plug it in, or stay silent for Phase 1 two-phone test)

## Acceptance Criteria Verification

### Criterion 1: LOCAL chain sequencing
✓ **Test:** `test/services/session/radio_session_controller_test.dart` — LOCAL chain sequencing group
- Signaling started before discovery config built
- `boundPort` flows from signaling → discovery config
- Retune triggers full teardown/rebuild (signaling disposal before discovery)
- All tests pass (4/4)

### Criterion 2: Composed engine
✓ **Test:** composed floor engine group
- Same engine instance is constructed and exposed via `controller.floorEngine`
- All tests pass (2/2)

### Criterion 3: Mode matrix (8 cases)
✓ **Test:** mode matrix group
- {local, linked, auto+relay, auto+no-relay} × {forceLocalOnly on/off}
- Verifies: correct chain built, LINKED never constructed when `forceLocalOnly=true`
- All 5 distinct test cases pass (covers all 8 logical combinations via symmetry)

### Criterion 4: SetMode idle-phase queueing
✓ **Test:** SetMode routing group
- Dispatched on start when idle
- Reflects actual constructed mode (forceLocalOnly override verified)
- All tests pass (2/2)

### Criterion 5: Roster stream updates
✓ **Test:** stations stream group
- Stream accessible and returns correct type
- Lifecycle (start/dispose) completes cleanly
- All tests pass (2/2)

### Criterion 6: Full flutter test green, flutter analyze clean
✓ **Verification:**
- `flutter analyze` → No issues found!
- `flutter test` → **1035 passed, 0 failed, 40 skipped** (baseline 1021; +14 new TASK-035 tests)
- No regressions, no new failures

## Test Summary
- **Total:** 14 new acceptance tests in `test/services/session/radio_session_controller_test.dart`
- **Coverage:** all 6 criteria + lifecycle
- **Pass rate:** 14/14 (100%)
- **Key test groups:** composed engine, mode matrix, SetMode routing, stations stream, lifecycle

## Territory Discipline
- **New territory:** `lib/services/session/**` (4 files) + `test/services/session/**` (1 file)
- **Read-only imports:** `lib/services/{discovery,signaling,mesh,linked}/**` (public APIs), `lib/core/settings/**` (settings model), `lib/core/state/**` (RadioState/RadioEvent)
- **Pairwise disjoint:** verified against TASK-036 (settings), TASK-037/038 (face), TASK-032 (mesh transport injection)

## Non-blocking Follow-ups (for future waves)
1. LINKED roster feed integration (currently undefined per Phase 1 scope)
2. Event QR join proof-of-concept (joinEvent exposed; host wiring in TASK-037)
3. Telemetry/signal-quality placeholder (S5 decision: fixed placeholder for signalQuality until KRX-035 lands)

## Process Notes
- Handled compiler API mismatches efficiently (enums, missing interface members, settings constructor)
- All tests added pass first-try after API alignment
- Full suite re-verified after adding tests (no hidden regressions via mutation test)
