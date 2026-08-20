# TASK-024 — LINKED integration: livekit_client join/publish/subscribe mirroring PTT (KRX-052 + KRX-055)

## Brief
The LINKED path in `lib/services/linked/`: derive roomId, fetch a JWT from the token service, join the LiveKit room with a pre-published muted track, mirror PTT state, carry floor messages over LiveKit data messages, and implement link-loss/regain (chirp events, `NO LINK`, auto-fallback to LOCAL — never a modal).

## Spec pointers
- TS §8.4: "Channel → deterministic `roomId` (§8.7) → token service issues a short-lived LiveKit JWT (identity = callsign + random suffix) → join room. One LiveKit room per channel; audio publish/subscribe mirrors PTT state; floor control messages ride LiveKit data messages (same schema as LOCAL)."
- TS §8.5 muted pre-publish (same ≤ 50 ms attack as LOCAL).
- FR-045: "relay unreachable → radio drops to LOCAL with an audible 'link lost' double-chirp and `NO LINK` display flag; never a modal error dialog." §7.1 `link_lost`/`link_up` chirps.
- FR-043 join methods (numbered + code, keyed passphrase, Event QR — QR UI is TASK-025; this task exposes the join-by-derivation API they all use).
- FR-046: force-LOCAL-only must hard-disable this service (respect the TASK-008 setting).
- TS §8.9: LiveKit `connectionQuality` + stats API → S-meter input.

## Intended approach
1. `token_client.dart`: HTTP client for TASK-003's `POST /token` contract (read its README); no callsign logging.
2. `linked_controller.dart`: over an abstract `LiveKitAdapter` — connect(room, jwt), pre-publish muted local track, `setEnabled(true)` on grant, data-message send/stream bridged to the same `FloorTransport` interface TASK-022 consumes (TASK-006 codec).
3. `link_monitor.dart`: connection-state stream → linkLost/linkUp events (chirp + `NO LINK` flag consumers), reconnection with backoff, fallback signal to the mode layer (AUTO policy itself is a later task — expose the events).
4. Telemetry tap: connectionQuality/stats surfaced as peer-quality stream for the S-meter mapping.
5. Tests against `FakeLiveKitAdapter`: join sequence (derive→token→connect→muted publish), grant mirroring, data round-trip through the codec, loss → events + fallback signal, force-LOCAL guard refuses to connect.

## Work Log
- [2026-08-20T20:34:17Z] [S5] Implemented lib/services/linked/** (livekit_adapter.dart, livekit_client_adapter.dart, token_client.dart, linked_floor_transport.dart, linked_controller.dart, link_monitor.dart, linked.dart) and test/services/linked/** per the Intended approach above, with two deliberate deviations recorded in PLAN.md TASK-024s Progress_Notes and flagged for ORCH: (1) token_client.dart uses dart:io HttpClient directly rather than adding an http/dio dependency, since pubspec.yaml sits outside this task Owned_Paths; (2) link_lost/link_up chirp playback is not wired here since no SFX player subscribes to RadioState anywhere yet (same gap noted in the 2026-08-20 handover for the mesh path) - LinkMonitor only dispatches LinkDegraded/LinkResolved into RadioStateBridge dispatch. flutter analyze clean repo-wide; flutter test test/services/linked 29/29 green. Committed to task/TASK-024-s5 (5ff4880). PLAN.md set to needs_review.
