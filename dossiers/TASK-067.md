# TASK-067 — Route Channels recall-tap through TASK-050's result-handling

## Brief

ORCH-created 2026-09-08, a decompose-time scoping miss surfaced by TASK-050's
review: `ChannelsLanding`'s recall-tap handler discards its `TuneResult`
(`unawaited(...)`), so a failed tap shows nothing. TASK-049's review required
TASK-050 to fix this, but TASK-050's territory never included
`lib/features/channels/**`, so it correctly declined and reported the gap.
This task closes it — reuse TASK-050's `TuneCoordinator`/outcome types, don't
reimplement UX-FR-009's four states a second way.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_PRD_v1.0.md` UX-FR-009 — pending/connected/
  failed/unavailable, real retry/cancel path.
- TASK-049's Review_Findings — flagged the original discard, cites the exact
  line (`channels_landing.dart:109`).
- TASK-050's Review_Findings — built the pattern this task must reuse
  (`TuneCoordinator`, monotonic generation guard, four-outcome mapping).

## Intended approach

1. Read TASK-050's `TuneCoordinator` public API (`lib/features/channel_selector/**`).
2. In `lib/features/channels/**` only, await/observe the recall-tap's
   `TuneResult` through that same coordinator (or a thin wrapper around it),
   surfacing failed/unavailable with a retry action matching the sheet's own
   treatment.
3. Do not touch `lib/features/channel_selector/**` — consume its public API.
4. Full suite + analyze; no build-apk needed unless the diff touches
   anything platform-adjacent (it shouldn't).

## Work Log
