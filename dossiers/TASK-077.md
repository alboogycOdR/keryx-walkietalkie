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
- [2026-09-11T14:20:00Z] [S5] **Rework round 1 fixes.** Both BLOCKING findings addressed on `f99ac19`:
  1. **System back on a screen pushed inside a tab.** The dartdoc claim that a branch's own Navigator would see the platform back button was false — Android back dispatch only reaches the *root* `Navigator`. Fixed by making the outer `PopScope`'s `canPop` (and its `onPopInvokedWithResult` fallback) query the active branch's live `NavigatorState.canPop()` first: `canPop: _index == 0 && !_activeBranchCanPop`; on a claimed pop, `_branchKeys[_index].currentState?.pop()` runs if the branch can pop, else the shell falls back to switching to Talk (or, on the Talk root with nothing pushed, lets the platform have it). Added a `_BranchPopObserver` (one per branch, wired into each `_BranchNavigator`'s `Navigator.observers`) that calls `setState` via `scheduleMicrotask` on every push/pop/remove/replace, so `canPop` is never stale between a branch mutation and the next real back press. Verified with **real** `tester.binding.handlePopRoute()` (never `Navigator.pop`/`popScreen` directly, which the round-1 review correctly flagged as unable to prove the platform path) for all four cases the review asked for: Talk→picker→back closes the picker and stays on Talk; Stations→Export→back returns to the Stations root (not Talk); Channels→selector→back returns to the Channels root; the pre-existing root cases (Channels root→Talk, Talk root→platform) still hold.
  2. **Connection indicator contrast.** `healthy` now resolves to `tokens.stateRx` (was `actionPrimary`, ~8° from `stateWarning` and indistinguishable), `degraded` to `tokens.stateWarning` (unchanged), and the previously-unhandled unresolved/connecting case (`!connection.isResolved`, i.e. `RadioMode.auto` not yet resolved to a concrete route) now renders `tokens.pttNeutralRing` with its own "connecting" semantic label, rather than silently reading as healthy. Three new widget tests seed `RadioState` via the existing `_SeededRadioStateController` override pattern and assert both the resolved `Container` decoration color and the `Semantics` label text for all three states, plus pairwise distinctness.
  - Full G4 evidence re-run in the foreground (no backgrounding, no early turn-end): `flutter analyze --no-pub lib/app_shell/` and repo-wide both **No issues found**; `flutter test --no-pub test/app_shell/mobile_app_shell_test.dart` **25/25 pass** (was 21, +4 handlePopRoute tests +3 connection-indicator-colour tests −3 old weaker assertions folded into a new group... net +4 tests, see Test_Evidence for exact delta); full `flutter test --no-pub` **1494 passed / 0 failed / 40 skipped** (same PARKED FR-025 soak-seed skips, untouched); `flutter build apk --debug` succeeded. Non-blocking findings (a)-(d) from the round-1 review were not separately addressed — none were blocking and none conflict with the fix above; (a) commit-tag and (b) checkbox-ticking are addressed in this same commit/PLAN.md update.
  - Setting Status: needs_review again with updated Test_Evidence, criteria boxes ticked, on PLAN.md (master).
