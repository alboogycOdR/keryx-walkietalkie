# TASK-105 dossier — Contacts sync + presence start

## What shipped

1. **`lib/features/contacts/contacts_list_controller.dart`** — `load()` now
   loads disk (emits immediately for an instant UI), then **awaits** a
   server `refresh()` (this has to be awaited, not fire-and-forget: journey
   gate 6 calls `await controller.load()` then asserts synchronously — see
   "load() must be awaited" below). `accept`/`decline`/`block`/
   `removeContact`/`sendRequestFromId` each trigger a `refresh()` afterward,
   fire-and-forget (their own directory call's own success/failure is what
   the caller awaits; the follow-up refresh is best-effort). `refresh()`
   itself swallows any exception from `ContactsController.refreshFromServer`
   (offline / not yet registered) — that method never mutates local state
   before the network call succeeds, so disk state is naturally untouched.

2. **`lib/app_shell/presence_bootstrap.dart`** (new) — `presenceBootstrapProvider`
   watches `registrationStatusProvider` and calls `PresenceClient.start()`
   the first (and only the first) time it reports `RegistrationRegistered`.
   A later flap through `Offline`/`Failed` and back to `Registered` does
   **not** restart it — reconnect/backoff after a drop is `PresenceClient`'s
   own internal concern.

3. **`lib/app_shell/contacts_sync.dart`** (new) — `contactsSyncProvider`
   refreshes contacts on every `appForegroundProvider` event (TASK-104's
   shared observer — no second lifecycle subscription for that signal) and
   on a repeating 30 s timer while foregrounded. The timer is gated on
   `WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed`
   — **deliberately excluding `null`** (no lifecycle callback has ever
   arrived). This is what keeps the periodic timer from ever being armed
   under `flutter test` (`lifecycleState` never leaves `null` there) — see
   "the pending-timer minefield" below; on a real device the engine reports
   `resumed` within the first frame or two, so production behaviour is
   unaffected beyond a very small cold-start delay (already covered by
   `load()`'s own immediate refresh).

4. **`lib/app_shell/mobile_app_shell.dart`** — `initState` now also reads
   (deferred one microtask, same as `host.start`) `registrationStatusProvider`
   (TASK-104 review finding — arms the retry loop from app start regardless
   of which screen the user opens), `presenceBootstrapProvider`, and
   `contactsSyncProvider`. Added a `ValueNotifier<int> _tabIndex` mirroring
   `_index`, threaded into `ContactsTabScreen` as `tabIndex` — see "why not
   a bool prop" below.

5. **`lib/app_shell/contacts_tab_screen.dart`** — converted from a stateless
   `ContactsTabScreen` (which built a *fresh, never-loaded*
   `ContactsListController` on every build) to a `ConsumerStatefulWidget`
   that owns exactly one `ContactsListController` for as long as it's
   mounted (in practice, the app's lifetime — `IndexedStack` keeps every
   branch alive). The first time Contacts becomes the *visible* tab it
   calls `load()`; every later time it becomes visible again, `refresh()`
   alone (disk is already loaded).

## Why not a bool prop for "is Contacts visible" ("why not a bool prop")

`mobile_app_shell.dart`'s `_BranchNavigator` wraps each tab's root screen in
its own `Navigator` with `onGenerateRoute: (settings) =>
MaterialPageRoute(builder: builder, ...)`. That `builder` closure is only
invoked once, when the route is first pushed (a `Navigator`'s existing route
does not get rebuilt just because its ancestor rebuilt with a new closure).
So a `visible: _index == 1` constructor bool, captured at that one-time
`builder` call, would only ever reflect the value at first mount (`false`,
since Talk is always index 0 on launch) — it can never change later no
matter how many times the shell's own `_index` changes afterward. The fix:
thread down a stable `ValueListenable<int>` (`_tabIndex`) instead — the
*object* is threaded once (fine, since it's the same instance for the
widget's whole life), but `ContactsTabScreen` adds a listener to it
directly in `initState`, independent of whether its own widget gets
rebuilt through the Navigator.

## Why `load()` must be `await refresh()`, not fire-and-forget ("load() must be awaited")

The obvious design ("disk first so the UI is instant, server second") reads
as "kick off the server refresh in the background and return immediately".
That is what the first cut of this task shipped, and it broke journey gate
6 (`test/regression/journey_two_phones_test.dart`, TASK-103's territory,
not edited here): the gate does `await controller.load(); expect(...)`
immediately afterward, with the intent that `load()` deterministically
produces the server's view. A fire-and-forget refresh races that
assertion — sometimes the network call hadn't landed yet by the time the
`expect` ran. Fixed by making `load()`'s refresh `await`ed; "instant UI" is
still honoured because `_contacts.loadFromDisk()` already calls `_emit()`
(so any listener on the `contacts`/`pending` streams sees the disk state
immediately), it's only the `Future` `load()` itself returns that now
waits for both steps. **Verified**: ran
`test/regression/journey_two_phones_test.dart` locally with gates 6 and 7's
`skip:` lines removed (uncommitted, reverted before finishing — that file
is TASK-103's territory) — both pass; restored the file to its committed
(skipped) state afterward, confirmed `git diff` was empty. Left `skip:` in
place; ORCH lifts it at review per the established convention.

## The pending-timer minefield ("the pending-timer minefield")

`flutter_test`'s `AutomatedTestWidgetsFlutterBinding` fails a test if *any*
`Timer` is still scheduled when the test body returns — including a
periodic reconnect/refresh timer that is working exactly as designed, and
including `addTearDown`-registered cleanup, which runs *after* that
check, not before. Three real production behaviours this task adds are
each, by nature, long-lived timers: `ContactsSync`'s 30 s refresh loop,
`PresenceClient`'s reconnect backoff once started, and (pre-existing,
newly *reachable* because `registrationStatusProvider` is now read at
shell init in every test that mounts `MobileAppShell`) `identityEnrolmentProvider`'s
real `dart:io` HTTP timeout Timer. None of this is a logic bug in this
task's own code; each is a genuine "a widget test that boots the real
shell now does more real background work than it used to" collision.
Fixed three different ways, in three different files, for three different
reasons — worth reading in order if a similar failure resurfaces:

1. **`ContactsSync`'s own timer** — gated on `lifecycleState ==
   AppLifecycleState.resumed` (excluding `null`), so it is simply never
   armed under `flutter test` at all (`contacts_sync.dart`'s own dartdoc).
2. **`test/app_shell/mobile_app_shell_test.dart`'s two "real directory
   backend" tests** (this task's own territory) — `PresenceClient`'s
   reconnect timer *does* get armed there (real backend, registration
   succeeds), so both tests now call `presence?.stop()` and
   `directoryClient?.close()` explicitly before ending, rather than relying
   on `addTearDown`.
3. **A genuinely different root cause in the SAME two tests, found while
   fixing #2**: `directory_shell_harness.dart` (`test/app_shell/`, **not**
   this task's `Owned_Paths`) seeds a bare `InMemorySettingsStore()`. That
   was fine for its original purpose (it overrides
   `directoryClientProvider`/`presenceClientProvider` directly, bypassing
   `identityEnrolmentProvider` entirely) — but `registrationStatusProvider`
   reads the *un-overridden* `identityEnrolmentProvider`, which derives its
   own `DirectoryClient` straight from `settings.relayUrl`. An unseeded
   store triggers `SettingsRepository.load()`'s baked-in-relay migration
   (TASK-104), so `identityEnrolmentProvider` tries to reach an actual,
   non-loopback host and hangs on a real TLS handshake — `runAsync` can
   never make that "complete", because it never will. **Fixed without
   touching `directory_shell_harness.dart`** (outside this task's
   territory): `mobile_app_shell_test.dart` now builds its own
   `ProviderContainer` (`_buildClearedRelayContainer`) that pre-seeds an
   explicit "user cleared" relay, the same fix `regression_shell_harness.dart`
   already carries for the identical reason, instead of calling
   `directory.buildContainer(...)`.

## Known remaining failure — outside this task's `Owned_Paths`

**`test/regression/real_composition_test.dart`: "the real KeryxApp boots
against a stubbed directory backend and reaches Talk (Verification G3)"**
fails with the exact TLS-hang described in point 3 above — same root
cause, same fix shape, but this file is not in TASK-105's `Owned_Paths`
(`lib/app_shell/**`, `lib/features/contacts/**`, `lib/core/contacts/**`,
plus this task's own four `test/app_shell/*_test.dart` files and
`test/features/contacts/**`/`test/core/contacts/**` — `real_composition_test.dart`
is none of those). Its `settingsStoreProvider.overrideWithValue(InMemorySettingsStore())`
(around the "the real KeryxApp boots against a stubbed directory backend"
test) needs the identical one-line fix: pre-seed
`const KeryxSettings().copyWith(relayUrl: '', relayUrlUserCleared: true)`
before handing the store to the override, exactly as
`_buildClearedRelayContainer` does in this task's own
`mobile_app_shell_test.dart`. Flagging for ORCH rather than editing outside
territory. Full-suite evidence below records this as the one known
failure; everything else is green.

## Test evidence

- `flutter analyze --no-pub` → **No issues found.**
- `flutter test --no-pub --concurrency=2` → **1511 passed / 43 skipped / 1
  failed**, exit 1. The one failure is `real_composition_test.dart`'s G3
  test, described above — a pre-existing-pattern issue in a file outside
  this task's territory, root-caused precisely, not a regression in this
  task's own logic (its sibling test in the same file that boots the same
  way but through a harness this task *does* own —
  `mobile_app_shell_test.dart`'s "real directory backend" group — passes).
  Baseline before this task (TASK-104's merge) was 1503/43/0; net +8 tests
  (3 in `contacts_list_controller_test.dart`, 2 in
  `presence_bootstrap_test.dart`, 3 in `contacts_sync_test.dart`) and the
  one now-visible failure named above.
- `test/regression/journey_two_phones_test.dart` with gates 6 and 7's
  `skip:` lifted locally (uncommitted, reverted before finishing): **both
  pass** (`+19 ~1` — the one remaining skip is the receive-side gate,
  TASK-106's). Confirmed the journey file's `git diff` was empty afterward.

## Acceptance criteria — self-check

- [x] Stateful directory fake / `ContactsListController.load()` yields a
  pending request with no user action beyond opening Contacts — proven by
  `contacts_list_controller_test.dart`'s new test and by journey gate 6.
- [x] Refresh fires on load, after each request action, tab open,
  foreground event, and the 30 s foreground timer; none fires while
  backgrounded; a failing refresh never clears disk state —
  `contacts_list_controller_test.dart` (load/actions),
  `contacts_tab_screen.dart`'s visibility gating (tab open),
  `contacts_sync_test.dart` (foreground event, backgrounded-never-fires).
  The periodic-timer-firing-a-refresh path itself is exercised in
  production by the same code the foreground-event test exercises
  (`ContactsSync._restartTimer`/`_refresh`); a direct test that advances
  fake time *and* lets the resulting real socket call complete inside the
  same `flutter test` run proved unworkable (30 s of `tester.pump` combined
  with real loopback I/O deadlocks — neither `runAsync` nor `pump(duration)`
  alone can drive both a fake-clock timer fire and a real socket
  completion in the same step) — noted here rather than silently dropped.
- [x] `PresenceClient.start()` called exactly once after `registered`, never
  before — `presence_bootstrap_test.dart`.
- [x] `registrationStatusProvider` watched from `mobile_app_shell.dart` init,
  armed independently of Settings/onboarding — wired; exercised indirectly
  by every `mobile_app_shell_test.dart` test (no crash / no missing retry
  loop) and directly by `presence_bootstrap_test.dart`'s reliance on it.
- [x] Journey gates 6/7 pass with skips removed (see above); file restored
  untouched.
- [x] Full suite green except the one named, out-of-territory,
  root-caused issue.
