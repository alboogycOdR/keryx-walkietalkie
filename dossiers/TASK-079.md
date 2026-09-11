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
