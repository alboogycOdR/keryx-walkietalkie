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

- [2026-09-08T15:55:00Z] [S5] Implemented: `_ChannelsLandingState` owns a
  `TuneCoordinator(intents: RadioViewIntents(host))` (TASK-050's class,
  imported directly, not reimplemented), subscribes to `outcomes`, and calls
  `onPhaseChanged` every build so TX-deferral behaves the same as the
  selector sheet. `_tuneRecent` now goes through `_coordinator.request(...)`
  instead of the flagged `unawaited(RadioViewIntents(host).tune(...))`. A
  pending retune shows a progress row and blocks a competing recall tap
  (both `_tuneRecent`'s busy guard and the `_RecentTile`'s disabled
  onTap/enabled — defense in depth, independently mutation-checked). A
  terminal outcome renders through a new `_RecallFeedback` widget reusing
  `ChannelSelectorCopy`'s exact wording; Retry calls
  `_coordinator.retry(outcome.target, ...)`, resubmitting the identical
  target per Technical §6's no-rollback policy. Extended
  `test/features/channels/fake_radio_host.dart` with
  `autoResult`/`holdTunes`/`pendingTunes`/`completeTune` (same convention as
  the channel_selector fake) and added two widget tests covering the
  failure+retry path and the pending/busy path. `flutter analyze` clean in
  territory (8 pre-existing TASK-035 warnings elsewhere, unrelated).
  `flutter test` full suite: 1250 passed / 0 failed / 40 skipped (unchanged
  parked FR-025 seeds). `flutter test test/features/channels/` in isolation:
  20 passed (18 pre-existing + 2 new). Revert-mutation-checked: (a) removing
  both busy guards together flips exactly the pending/busy test red; (b)
  disabling `_retryRecall` flips exactly the failure/retry test red; (c)
  removing the outcome-stream subscription flips both new tests red. All
  three reverted, `git diff` clean afterward. Did not touch
  `lib/features/channel_selector/**` — consumed its public API only.
  Committed to task/TASK-067-s5 @ a1b4146. -> Status: needs_review.
