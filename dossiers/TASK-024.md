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
