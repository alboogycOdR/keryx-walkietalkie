# TASK-074 — UX R2 Talk screen recomposition

## Brief

Recompose `TalkScreen` to ADR-002 §3 A2's content order (channel card →
overlay banners → flexible space → PTT ring → status text below the ring →
contextual latch row), wire in TASK-073's standalone `TalkPttRing`, delete
the old `TalkPttDisc` and the visible "Start transmitting" toggle button.
All hold/latch/lifecycle safety logic in `_TalkScreenState` is presentation-
only churn — the state machine itself (VT-010–VT-015) is untouched.

## Spec pointers

- docs/adr/ADR-002-zello-aligned-talk-first-ui.md §3 A2/A3/A4
- specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md §2.2, §4, §5
- specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md §7 (configured vs
  effective route)
- specs/KERYX_Mobile_UX_Redesign_Verification_v1.0.md VT-010–VT-015

## Approach

1. New `TalkChannelCard` (own file) — channel tile, `CH NN · CC`, route
   line (effective route, configured mode only when it differs), station
   chip, picker button, optional radio-controls icon (only when its
   callback is non-null).
2. `TalkScreen.build` recomposed top-to-bottom per ADR-002 A2, with
   `TalkPttRing` replacing `TalkPttDisc`/the toggle row; treatment mapped
   from `RadioViewState` (`_treatmentFor`); status text split into a
   primary/secondary pair below the ring; contextual lock/"Release" row
   below that.
3. Preserve every `_TalkScreenState` field/method that owns hold/latch/
   lifecycle bookkeeping unchanged — only the widget tree changed.
4. Regenerate `talk_*` goldens dark+light at 360×640 (in practice a fixed
   1080×1920 physical surface, matching the pre-existing golden harness).

## Work Log

- 2026-09-11T11:50:34Z [S5] Claimed. First session was killed by the
  headless 600s background-task ceiling after delegating to background
  sub-agents; nothing committed (see ORCH's redispatch Progress_Note).
- 2026-09-11T12:10:00Z [S5] Resumed on the existing branch with the
  surviving uncommitted worktree state (TalkChannelCard + recomposed
  TalkScreen + partially-updated tests already present from the killed
  session). Worked directly in this session, no background agents/jobs.
  Found and fixed two real defects surfaced only by running tests, not
  present in the description:
  - **Latch-visibility bug:** `canLatch` originally gated on this screen's
    own transient `_holding` flag as well as `phase == tx`. That hid the
    lock control the instant the physical hold ended — before the user
    had any chance to tap it — because a deliberate latch is meant to
    *outlive* the hold that requested it. Fixed to `!latched && phase ==
    tx` (ADR-002 A4: "while TX is granted", not "while this screen thinks
    a finger is still down"). Caught by two pre-existing owned tests
    (`VT-012 ... remains releasable on remount`, `engaging latch then
    releasing calls releaseLatch exactly once`).
  - **320 lp / text-scale-2.0 overflow:** `TalkChannelCard`'s trailing
    station-count `TextButton.icon` had no width constraint, so at 320 lp
    width with system text scale 2.0 its label alone overflowed the Row
    by 176–428 px. Fixed by wrapping it in `Flexible` with an internal
    `Flexible(Text(..., overflow: ellipsis))`, and added `maxLines: 1` +
    ellipsis to the channel-label/route-line text too, so the card
    degrades gracefully instead of overflowing.
  Also fixed a `pumpAndSettle` timeout in both `talk_screen_test.dart` and
  `talk_states_golden_test.dart`: the ring's `requesting` sweep animates
  continuously by design (ADR-002 A3), so any test that settles in that
  treatment now pumps a bounded duration instead of calling
  `pumpAndSettle`. Updated one status-copy assertion
  (`'Channel clear. Hold to talk.'`) to the new two-line split
  (`TalkCopy.channelClear` / `TalkCopy.holdToTalk`), matching ADR-002 A2's
  primary/secondary line design (the old assertion predated the split).
  Regenerated all 16 `talk_*` goldens (dark+light) on this machine.
  Full suite for every file in this task's `Owned_Paths` is green (see
  Test_Evidence). **One residual issue found, out of territory:**
  `test/app_shell/channels_screen_test.dart` (owned by TASK-048, not this
  task) references `TalkPttDisc` by type
  (`expect(find.byType(TalkPttDisc), findsOneWidget)`), which no longer
  exists once this task deletes `talk_ptt_disc.dart` — confirmed this file
  is unmodified since `master` and was already broken by the plan's own
  instruction to delete `TalkPttDisc` (ADR-002 A4), not by anything else
  in this task. Reported to PLAN.md as `blocked`/`OWNERSHIP_CONFLICT`
  rather than edited directly.

## Work Log — 2026-09-11T13:30Z [S5] Rework round 1 fixes

Resumed on existing branch `task/TASK-074-s5` after ORCH round-1 review
(REWORK, 2 blocking findings). Fixed both directly in this session,
foreground only, no background jobs:

1. **BLOCKING 1** — ORCH added `test/app_shell/channels_screen_test.dart`
   to this task's `Owned_Paths` (it referenced the deleted `TalkPttDisc`,
   a direct consequence of this task's own ADR-002 A4 deletion). Switched
   its import and `find.byType` assertion to `TalkPttRing`, mirroring the
   equivalent fix already made in `talk_screen_test.dart` /
   `mobile_app_shell_test.dart`.
2. **BLOCKING 2** — added a widget test at `Size(360, 640)`, text scale
   1.0, asserting `keryx-talk-channel-card`, `keryx-talk-ptt-disc` and
   `keryx-talk-status-line` all have their full rect contained within the
   360x640 viewport with zero scroll offset. Passed on first run — no
   layout change was needed for this criterion.
3. **Non-blocking (a)** — `_engageLatch`'s precondition previously
   required `_holding`, so the visible Lock control could go inert in a
   window where TX was granted but the finger had already lifted. Added a
   `_lastBuiltPhase` field set at the end of `build()` and changed the
   guard to `_latched || _lastBuiltPhase != RadioPhase.tx`, matching the
   `canLatch` visibility condition exactly. (b)/(c)/(d) left as recorded —
   correctly scoped to TASK-078/081 or accepted as-is per the review.

Worktree's local `PLAN.md` copy was stale from claim time (missing the
Owned_Paths expansion) — the territory-firewall hook initially blocked the
channels_screen_test.dart edit on that stale copy; refreshed it from
master's PLAN.md (content only, no commit from this worktree) before
retrying, which then succeeded.

Verification (foreground, waited for completion each time):
- `flutter analyze --no-pub` — No issues found.
- `flutter test --no-pub test/features/talk/talk_screen_test.dart` — 54/54
  passed, including the new 360x640 test.
- `flutter test --no-pub test/features/talk/ test/app_shell/` — 92/92
  passed.
- `flutter test --no-pub` (full suite) — **1472 passed / 0 failed / 40
  skipped** (the 40 are the pre-existing parked FR-025 soak skips).

Committed as `8024f74` on `task/TASK-074-s5`. Moving to `needs_review`.
