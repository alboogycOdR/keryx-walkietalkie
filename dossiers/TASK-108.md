# TASK-108 — Wire target selection to RadioSessionController.switchTarget

## What was broken
`lib/app_shell/mobile_app_shell.dart`'s `_selectTarget` only wrote
`currentTargetProvider`'s presentation state. Nothing in `lib/app_shell/**`
ever called `RadioSessionController.switchTarget`. `RadioSessionHostV2`
(`lib/core/radio_host/radio_session_host_v2.dart`) was a fully-written,
already-correct seam for this, but was never constructed anywhere in `lib/`.

## Fix
Mirrors TASK-102's `RadioIdentityReloader` precedent exactly:

- `lib/core/radio_host/radio_host_contract.dart`: new additive optional
  interface `RadioTargetSwitcher` with `Future<void> switchTarget(TalkTarget
  target)`. Not a member of `RadioHost` itself, so out-of-territory
  `RadioHost` test doubles keep compiling unchanged.
- `lib/core/radio_host/keryx_radio_host.dart`: `KeryxRadioHost` now
  `implements RadioHost, RadioIdentityReloader, RadioTargetSwitcher`.
  `switchTarget` is a no-op (never throws) before `_session` exists or if
  `_session` is not a `RadioSessionHostAdapter`; otherwise it delegates to
  `session.debugController.switchTarget(target, memberPeerIds:
  target.memberPeerIds)`. `RadioSessionController.switchTarget` already
  drives engine re-adoption through `engineChanges` (TASK-107) — no new
  subscription/guard logic was added here.
- `lib/app_shell/mobile_app_shell.dart`: `_selectTarget` now also does
  `ref.read(radioHostProvider)` (plain read, not watched — stays a
  fire-and-forget side effect of selection, not a rebuild dependency), casts
  to `RadioTargetSwitcher` if supported, and calls `switchTarget` via
  `unawaited(...)` alongside the existing `currentTargetProvider` write.

## `radio_session_host_v2.dart`'s fate: **removed**
It duplicated exactly what the simpler `RadioTargetSwitcher` passthrough now
does, but needed a `KeryxRadioHost` accessor that was never wired and would
have left two competing paths to the same effect. Deleted
`lib/core/radio_host/radio_session_host_v2.dart` and its test
`test/core/radio_host/radio_session_host_v2_test.dart` (no other `lib/`
reference to either after removal — verified via
`grep -rn "RadioSessionHostV2\|radio_session_host_v2" lib/ test/`; the one
remaining `lib/` hit is a historical comment in
`lib/core/settings/settings_model.dart` naming a test file, outside this
task's `Owned_Paths`, left as-is since it's an accurate historical note, not
a claim that the gap is still open).

## Ownership note — `lib/app_shell/directory_providers.dart`
The task Description named this file's dartdoc (the TASK-093-filed
"OWNERSHIP_CONFLICT" disclosure) as needing a read-only correction once the
gap closed, but it is **not listed in this task's `Owned_Paths`**. The
territory-firewall hook mechanically blocked an edit attempt there
(`[territory-firewall] BLOCKED: lib/app_shell/directory_providers.dart is
outside your Owned_Paths for active task(s) TASK-108`). Per protocol
(`AGENTS.md` commandment 4 — "not one line, not 'just an import'"), I did
not force it. **Acceptance criterion "`currentTargetProvider`'s dartdoc no
longer claims this gap is open once closed" is therefore NOT met by this
task's diff.** ORCH either needs to add
`lib/app_shell/directory_providers.dart` to this task's `Owned_Paths` for a
follow-up commit, or make the one-comment-block fix directly. The exact
replacement text (correcting the "**Disclosed scope decision**" block at
`directory_providers.dart:268-283`) is proposed in this dossier's Work Log
below for whoever applies it.

Proposed replacement for the dartdoc block on `currentTargetProvider`:
```dart
/// **Resolved (TASK-108):** this provider only drives the Talk screen's
/// header card, audience computation and ready-ring rule (all
/// presentation, Technical §6.3) — it does not itself call
/// `RadioSessionController.switchTarget`. That call is now made
/// separately, from the same selection write-site
/// (`lib/app_shell/mobile_app_shell.dart:_selectTarget`), via the additive
/// `RadioTargetSwitcher` capability on `KeryxRadioHost`
/// (`lib/core/radio_host/radio_host_contract.dart`), mirroring
/// `RadioIdentityReloader`'s (TASK-102) precedent. The previously-named
/// `RadioSessionHostV2` seam was removed as redundant once this simpler
/// passthrough landed.
```

## Tests added
- `test/core/radio_host/keryx_radio_host_switch_target_test.dart`: new
  group `KeryxRadioHost.switchTarget (RadioTargetSwitcher, TASK-108)` — real
  `RadioSessionController`/`RadioSessionHostAdapter` chain, proves
  `switchTarget` reaches the live controller (engine re-adopts, PTT works
  on the new target), and that calling it before `start()` is a no-op that
  never throws.
- `test/app_shell/mobile_app_shell_test.dart`: new test using a test-local
  `_TargetSwitchingFakeRadioHost` (adds `RadioTargetSwitcher` to
  `FakeRadioHost` without touching that shared file) proving selecting a
  contact calls `switchTarget` with the right target.
- `test/regression/real_composition_test.dart` (AC1, real composition): new
  test builds the real `KeryxApp` with the real `RadioSessionController` +
  `RadioSessionHostAdapter` + `KeryxRadioHost` chain (not
  `_RealCompositionHarness`'s fake `SessionHost` — `switchTarget` only
  delegates for a `RadioSessionHostAdapter`), a real `FakeDirectoryServer`
  contact, selects it through the real Contacts tab, and asserts
  `radioStateProvider.roomId` becomes the real `deriveDirectRoom` result —
  proving the real session joined the target's room, not just that
  `currentTargetProvider`'s presentation state changed.

### Gotchas hit while writing the real-composition test
- Must pre-seed `settingsStoreProvider` with an explicit "user cleared"
  relay (same fix `mobile_app_shell_test.dart`/`regression_shell_harness.dart`
  already apply) — an unseeded store triggers `SettingsRepository.load()`'s
  TASK-104 baked-in-relay migration mid-test, which fires a second,
  unrelated `listenSettings` emission that raced the `switchTarget`-driven
  room state.
- `flutter_test`'s fake-async `pump` clock doesn't advance real
  `Future.delayed`/`Timer` chains the discovery/signaling stack uses —
  poll with `tester.runAsync(() => Future.delayed(...))` + `tester.pump()`,
  same fix already used elsewhere in this file for real socket I/O.
- Must explicitly close `directoryClient`/`presenceClient` and give
  `host.dispose()`'s `unawaited` async chain real event-loop turns via
  `runAsync` before the test ends, or `flutter_test`'s pending-timer
  invariant check fails on the real `FloorEngine`'s presence-heartbeat
  `Timer` / the directory `HttpClient`'s keep-alive idle timer.

## Test_Evidence
- `flutter analyze lib test` → No issues found!
- `flutter test` (full suite) → `+1528 ~41` (41 skips are the
  pre-existing, explicitly PARKED FR-025 soak seeds per
  `PLAN.md`/`CLAUDE.md` — not touched by this task). 0 failures.

## Work Log
- [2026-09-13T19:20:00Z] [S5] Claimed TASK-108.
- [2026-09-13T21:10:00Z] [S5] Resumed after a context checkpoint; found
  substantial prior-session work already on disk and uncommitted
  (`RadioTargetSwitcher` contract, `KeryxRadioHost`/`mobile_app_shell.dart`
  wiring, `radio_session_host_v2.dart` deleted, unit + widget tests
  written). Verified it against the task's acceptance criteria: AC1's
  required `test/regression/real_composition_test.dart` proof was missing
  — added it (see "Tests added" above), fixing a real-composition timing
  bug that only surfaced under the real `RadioSessionController` chain
  (settings-migration race). Attempted the AC's dartdoc fix on
  `lib/app_shell/directory_providers.dart`; blocked by the territory
  firewall since that file isn't in `Owned_Paths` — documented above with
  the proposed replacement text for ORCH/a follow-up task. Full suite green,
  `flutter analyze` clean. Handing to `needs_review`.
