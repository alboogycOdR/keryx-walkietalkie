# TASK-079 — RX level telemetry

## Brief

Wire the inbound-rtp audioLevel reader from TASK-065 into `RadioViewState.meterLevel` as `MeasuredMeterLevel` during receive, so the new PTT ring can show a real receive glow. Everything else stays decorative. No TX metering.

## Spec pointers

- docs/adr/ADR-002-zello-aligned-talk-first-ui.md §3 A6
- specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md §5.3; VT-015
- lib/services/mesh/rtc_adapter.dart readAudioLevel / audioLevelFromInboundRtpStats
- lib/core/presentation/telemetry.dart

## Approach

1. Trace where the active speaker connection is known in mesh_controller.
2. Poll at ~10 Hz only while rxActive, with an injectable clock.
3. Surface the level via the session controller into RadioHostSnapshot, then RadioViewState.project.
4. Check livekit participant audioLevel for LINKED.
5. Throttle emissions.

## Work Log

- [2026-09-11T12:15:00Z] [S5] Implemented and tested. Design settled after tracing the actual wiring:
  - **MeshController** (`lib/services/mesh/mesh_controller.dart`): kept a parallel `_peerConnections` map (alongside `_connections`) populated in `_openConnection`, purely so `readAudioLevel(peerId)` can reach `rtcRemoteTracks(pc).tracks.first.readAudioLevel()` without widening `MeshConnection`'s own API — `mesh_connection.dart` is NOT in this task's `Owned_Paths` and the firewall hook confirmed that live. Cleared on peer departure and dispose.
  - **RadioSessionController**: new `_onEffectForMeterLevel` listens the same `engine.effects` stream `_onEffectForIdleTracking` already does. `RemoteFloorStarted` → `_startMeterPolling(engine.holder)`; `RemoteFloorEnded`/`EndTransmit`/`TransmitGranted` → stop. Polling is a self-rescheduling `_clock.schedule(100ms, …)` chain (10 Hz), reading via `_mesh?.readAudioLevel(speakerId)`, mapped to `MeasuredMeterLevel(value*100)` or decorative on unavailable. Re-checks `_polledSpeakerId`/`_disposed` after every `await` so a retune/dispose/speaker-change mid-poll can't resurrect a stale timer or write a level for the wrong speaker. Exposes `meterLevel` (current) + `meterLevelChanges` (broadcast stream), closed in `dispose()`. **LINKED is NOT implemented** — `LiveKitRoom`/`LiveKitAdapter` (`lib/services/linked/livekit_adapter.dart`) expose no per-participant `audioLevel` at all, and that file is outside this task's `Owned_Paths` (only `linked_controller.dart` is), so LINKED stays `MeterLevel.decorative` unconditionally, exactly as the task text's own fallback allows ("Otherwise LINKED stays decorative, with the reason in the dossier").
  - **RadioHostSnapshot**: new `meterLevel` field, default `MeterLevel.decorative`.
  - **KeryxRadioHost**: `SessionHost` (`lib/features/face/session_host.dart`) was deliberately NOT widened — outside `Owned_Paths`, and doing so would force every hand-written `SessionHost` test double across the codebase to implement a new member. Instead reused the already-public `RadioSessionHostAdapter.debugController` seam (that class's own dartdoc: "lets a production-path integration test reach into the composed chain without widening `SessionHost` itself" — literally anticipates this exact need). `_startSession` does `if (session is RadioSessionHostAdapter) { … subscribe controller.meterLevelChanges … }`; a hand-written fake `SessionHost` simply isn't that type, so it falls through to the decorative default with zero special-casing needed in test harnesses. Subscription cancelled on session rebuild and on `dispose()`.
  - **RadioViewState.project**: `meterLevel` now reads `hostSnapshot.meterLevel`, but ONLY while `radioState.phase == RadioPhase.rxActive` — re-asserted independently so a stale/racing measured snapshot can never leak through outside an actual RX window (defensive; the host already goes decorative on `RemoteFloorEnded`, but the projection doesn't trust that alone).
  - Throttling: the 10 Hz self-reschedule IS the throttle — no additional debounce needed since `_setMeterLevel` already no-ops on an unchanged value (equality check on the sealed `MeterLevel` variants).
  - Test evidence: `flutter analyze` (full repo) → **No issues found**. `flutter test` (full repo) → **1448 passed, 0 failed, 40 skipped** (the same 40 named PARKED FR-025 soak seeds, untouched), run twice for determinism, both clean. New/changed test files, all inside `Owned_Paths`: `test/services/mesh/mesh_controller_test.dart` (+4 `readAudioLevel` tests), `test/services/session/radio_session_controller_test.dart` (+5 tests in a new "RX level telemetry" group, using direct `TxStart`/`TxEnd` `FloorCodec` injection on a fake data channel rather than relying on two independently-faked RTC adapters to actually relay to each other), `test/core/radio_host/keryx_radio_host_meter_level_test.dart` (new file — the only place the `RadioSessionHostAdapter` cast branch is exercised end-to-end with a real `RadioSessionController`), `test/core/presentation/radio_view_state_test.dart` (+2 tests; existing decorative-regardless-of-phase test kept, since it's still true for a decorative host snapshot).
  - Acceptance criteria: all 5 met. `git diff master...HEAD --stat` confirms every changed file sits inside `Owned_Paths`. → Status: needs_review.

