# TASK-077 — UX R2 shell — Talk-first launch, top tabs, overflow menu

## Brief

Swap the bottom navigation for a top app bar and an icon-only tab strip (Talk · Channels · Stations), with Talk as the default on every launch. Settings and Radio controls move to the overflow menu. The single app-scoped RadioHost lifecycle is untouched.

## Spec pointers

- docs/adr/ADR-002-zello-aligned-talk-first-ui.md §2 O1/O2, §3 A1
- specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md §1
- Verification VT-001–VT-005
- lib/app_shell/mobile_app_shell.dart (branch navigators + IndexedStack pattern to keep)

## Approach

1. Keep the branch-navigator IndexedStack.
2. Build the app bar and tab strip.
3. Wire the callbacks from TASK-074/075/076.
4. Handle back with PopScope.
5. Rewrite the shell tests, and add a drag-over-PTT test to prove tabs never swipe.

## Work Log

- [2026-09-11T13:45:00Z] [S5] Resumed after PreCompact checkpoint. Discarded a stale local-only diff to PLAN.md in this worktree (never edited there — master's PLAN.md at C:\CLAUDECODE_TOOLSETS\walkietalkie-keryx\PLAN.md is the coordination copy and already had the up-to-date Progress_Notes plus an ORCH note pointing at the exact next steps). Reviewed the uncommitted edits to `test/app_shell/channels_screen_test.dart` and `test/app_shell/talk_screen_test.dart` from the prior session (embedded ChannelsScreen with `onSwitchToTalk` replacing `onOpenTalk`/pushed-Talk assertions; TalkScreen wrapper's Stations header now asserts `onSwitchToStations` instead of a pushed `StationsScreen`, and asserts the Radio Controls button is absent since that moved to the overflow menu) — consistent with the shipped `f4dde8c` implementation, committed as `1c4bbba`. Ran all three G4 gates in the foreground per ORCH's instruction, waiting on each to completion (no run_in_background, no early turn-end):
  - `flutter analyze --no-pub`: **No issues found!** (74.9s)
  - `flutter test --no-pub`: **All tests passed!** — 1487 passed, 40 skipped (all skips are the pre-existing, explicitly PARKED FR-025 emergency-preemption soak seeds per the 2026-08-21T17:05Z owner decision — not new, not touched by this task), 0 failed.
  - `flutter build apk --debug`: **✓ Built build\app\outputs\flutter-apk\app-debug.apk**
  All acceptance criteria implemented per the 12:57:29Z note's detailed breakdown (top app bar with connection dot + overflow menu, icon-only 3-tab strip with no swipe gesture by construction, IndexedStack + 3 branch navigators, PopScope back behaviour, Talk/Channels/Stations wiring, auto-return selector). Setting Status: needs_review with full Test_Evidence on PLAN.md (master).
