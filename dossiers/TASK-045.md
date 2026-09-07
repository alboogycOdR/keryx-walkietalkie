# TASK-045 — Persistent RadioHost extraction

## Brief

Everything in this wave depends on this task. `_FaceScreenState` currently
constructs and disposes the entire radio stack — `SessionHost`/
`RadioSessionController`, the floor engine, `AudioSink`, `SfxEngine`,
`SfxProjection`, `RadioServiceController` and the station notifier — inside
`initState`→`_boot()`/`dispose()`. Any disposable route above that widget kills
the session on navigation, so an app-scoped host must exist before a navigation
shell can. This is a hoist, not a rewrite: no new engine, session, transport or
audio pipeline is created.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §1.1 (the exact ownership
  inventory and why FaceScreen-under-a-route is wrong), §2 (target architecture),
  §3 (illustrative `RadioHost` contract + typed results), §4 (ten lifecycle
  invariants), §9 (`lib/core/radio_host/`, and "a separate integration task owns
  app.dart / route registration" — that is TASK-048, not this one).
- `specs/KERYX_Mobile_UX_Redesign_Verification_v1.0.md` VT-001 (single instance),
  VT-002 (boot race), VT-003, VT-004 (disposal/background).
- `docs/adr/ADR-001-mobile-ux-redesign-reconciliation.md` §6 — the migration
  diagram; the host box is explicitly "hoisted out, unchanged in substance".
- `specs/KERYX_Product_Technical_Spec_v1.1.md` §8.2–§8.5 — preserved verbatim.

## Approach

Create `lib/core/radio_host/**` owning the block lifted from `_FaceScreenState`,
exposing a narrow interface shaped like Technical §3 with typed results (success
/ validation failure / cancellation / unavailable route / transport failure).
Reuse `lib/features/face/session_host.dart`'s injection seam and its existing
fakes — do not invent a second seam. Then hollow `face_screen.dart` so it
*consumes* a host rather than constructing services; the host is still created at
the same point in the tree for now, keeping `lib/app.dart`/`lib/main.dart`
untouched and out of territory. TASK-048 hoists it above the navigator;
TASK-061 deletes what remains of `face_screen.dart` much later, behind this task
in the dependency chain. Preserve today's tune semantics but expose one
serialized entry point for TASK-050 to build its coordinator on.

## Work Log

- [2026-09-07T18:15:00Z] [S5] Claimed. Preflight (c8b9872):
  ```
  [preflight] TASK-045 Owned_Paths inspected in E:/DELL-PROJECTS/wt-s5-WALKIETALKIE
  [preflight] 4 entr(y/ies). FILE/DIR/GLOB = exists, NEW = you are creating it.
    GLOB   lib/core/radio_host/**  -> matches nothing yet (new territory)
    FILE   lib/features/face/face_screen.dart  -> exists, 981 line(s), 42942 bytes
    GLOB   test/core/radio_host/**  -> matches nothing yet (new territory)
    FILE   dossiers/TASK-045.md  -> exists, 41 line(s), 2322 bytes
  ```
  Read `face_screen.dart`, `session_host.dart`, `radio_state.dart`,
  `floor_engine.dart`, `sfx_projection.dart`, `radio_service_controller.dart`,
  `settings_repository.dart`, `permission_gate.dart`, and the existing
  989-line `test/features/face/face_screen_test.dart` (out of territory,
  read-only) to understand every seam a hoist has to preserve byte-for-byte.

- [2026-09-07T19:40:00Z] [S5] Implemented the hoist:
  - `lib/core/radio_host/radio_host.dart` — barrel + module dartdoc.
  - `lib/core/radio_host/radio_host_contract.dart` — `RadioHost` abstract
    interface (Technical §3's illustrative contract, names kept as given),
    `TuneResult`/`JoinResult`/`RadioHostOutcome` typed results.
  - `lib/core/radio_host/radio_host_snapshot.dart` — `RadioHostSnapshot`,
    the host-owned side state a UI needs alongside `radioStateProvider`
    (mic/service condition, stations, channel memory, live `FloorEngine`
    reference) — deliberately does NOT duplicate any `RadioState` field.
  - `lib/core/radio_host/keryx_radio_host.dart` — `KeryxRadioHost`, the
    actual hoisted block. **Riverpod-agnostic by design**: every ambient
    read/dispatch/listen is a plain callback the caller supplies (today:
    `FaceScreen`'s `ref`), so this whole module never imports
    `flutter_riverpod` and is unit-testable with zero widget-test
    machinery — see `test/core/radio_host/keryx_radio_host_test.dart`.
  - `lib/features/face/face_screen.dart` — hollowed to *consume* the host:
    constructs `KeryxRadioHost` in `initState` with the exact same
    factories the widget always took (constructor API is byte-identical —
    every existing test double built against it keeps working unmodified),
    subscribes to `host.changes`, and forwards every gesture to a host
    method (`pressPtt`/`releasePtt`/`releaseLatch`/`tune`/`joinEvent`/
    `dispose`) or, for emergency pin/clear (not in the narrow contract),
    directly to `host.current.floorEngine` — Technical §3 explicitly
    sanctions this: "The actual floor engine remains the source of truth
    for TX ownership."
  - Regression fix folded in, disclosed here rather than silently: found
    that `_onRadioServiceEvent`'s `RadioServiceKilled`/
    `RadioServicePowerOffAction` handlers never called
    `floorEngine.releaseTransmit()` before the pre-hoist code either — a
    latent hot-mic gap this task's own acceptance criterion ("service kill
    ... leaves no locally transmitting track") requires closing. Added the
    release call to both handlers and to `dispose()`/`powerOff()`. This is
    squarely in-scope (the criterion names it explicitly), not "opportunistic
    rewrite" territory.
  - `region` for QR export: `_appliedSettings?.region` no longer exists on
    the widget (that snapshot moved into the host, scoped to only the
    session-affecting fields it needs); replaced with a fresh
    `ref.read(settingsProvider).valueOrNull?.region` read at export time —
    same value, no behavior change, no new field to keep in sync.

- [2026-09-07T20:05:00Z] [S5] **Found and fixed a real bug the hoist itself
  introduced**, before this ever reached review: `KeryxRadioHost.dispose()`
  was originally written as an `async` function that `await`ed
  `_stationsSub?.cancel()` etc. before reaching `_session?.dispose()`.
  Since `FaceScreen.dispose()` calls `unawaited(_host.dispose())`
  (fire-and-forget, matching the pre-hoist widget's own fully-synchronous
  `dispose()` override), that `await` meant only `dispose()`'s synchronous
  prefix ran inside the widget's own synchronous `State.dispose()` call —
  the actual session/`FloorEngine` teardown (and the timer it cancels) was
  deferred to a later microtask a test's final pump might never flush.
  Caught by running `flutter test test/features/face/face_screen_test.dart`
  (existing suite, not my Owned_Paths, but the empirical baseline this
  task must not regress): **all 27 of its tests failed** with "A Timer is
  still pending even after the widget tree was disposed" the moment I
  wired the widget to the new host. Root-caused via a temporary debug
  print confirming `dispose()` *was* being called with a non-null
  `_session`, which narrowed it to the `await`-before-critical-teardown
  shape rather than a lifecycle-wiring bug. Fix: `dispose()` now mirrors
  the pre-hoist shape exactly — every teardown step fire-and-forget
  (`unawaited`), never `await`, so the entire synchronous prefix (which is
  the whole body) runs inside the caller's synchronous call frame. All 27
  tests pass afterward, unmodified. This is exactly the kind of bug a pure
  hoist can introduce without changing "substance" on paper — recorded in
  full since it's the single most load-bearing fix in this task.

- [2026-09-07T20:20:00Z] [S5] Wrote `test/core/radio_host/keryx_radio_host_test.dart`
  — 16 Riverpod-free unit tests directly against `KeryxRadioHost` (no
  `WidgetTester`/`ProviderScope` needed, since the module takes plain
  callbacks): boot (single session/engine/sfx/service, mic-denied gating,
  VT-001 idempotent `start()`), VT-002 boot-race session reconstruction
  (two overlapping session-affecting `applySettings` calls fired without
  awaiting between them → exactly one undisposed session, matching
  `current.floorEngine`), VT-004 disposal (idempotent, resource release,
  no-hot-mic on dispose/`RadioServiceKilled`/`powerOff`), `tune` (range
  validation, success path, and a genuine serialization proof — a
  controllable `rememberChannel` gate proves a second `tune()` call cannot
  reach the session ahead of a still-suspended first call), `joinEvent`
  (no-session → `unavailableRoute`, success, thrown failure →
  `transportFailure`, never an unhandled exception), and direct PTT
  forwarding. Every test **revert-mutation-checked by hand** (production
  guard reverted, target test confirmed red, restored) before counting it
  as passing — including one negative result caught in the process: the
  first draft of the `tune` serialization test still passed green after I
  removed `_tuneChain` entirely, because the fake session's own operations
  never actually raced without an explicit delay. Rewrote it with a
  controllable `rememberChannelGate` + a `retuneOrder` trace so it now
  fails correctly on that exact mutation (confirmed) — left this
  discovered-and-fixed non-discriminating-test moment in the log
  deliberately, per REVIEW.md's standing note that this exact failure mode
  has recurred before and should be caught by the author, not by review.

- [2026-09-07T20:35:00Z] [S5] Full-suite verification (see Test_Evidence).
  `analysis_options.yaml`/`pubspec.lock` were touched transiently by
  `flutter analyze`'s own auto-upgrade step and by the first
  `flutter pub get` — reverted via `git checkout` immediately each time;
  neither is in `Owned_Paths` and neither is part of any commit.

- [2026-09-07T21:00:00Z] [S5] `flutter build apk --debug` — succeeded:
  `Running Gradle task 'assembleDebug'... 196.3s`, `√ Built
  build\app\outputs\flutter-apk\app-debug.apk`, exit code 0 (some
  Kotlin-incremental-cache warnings from `livekit_client`'s own Gradle
  plugin logged mid-build, cross-drive relative-path noise, non-fatal —
  the build completed and produced a real APK). The build incidentally
  touched `android/gradle.properties` (Flutter's own Kotlin-migrator
  auto-appending two flags) and created `android/.kotlin/` — both outside
  `Owned_Paths`, both reverted/removed via `git checkout`/`rm -rf`
  immediately after capturing the result; neither is part of any commit.

- [2026-09-07T21:05:00Z] [S5] All acceptance criteria verified; handing off
  to `needs_review`. Territory: `lib/core/radio_host/**` (new, 3 files),
  `lib/features/face/face_screen.dart` (rewritten to consume the host,
  778-line diff: 114 insertions / 664 deletions — net far smaller, since
  every constructed-service block moved out), `test/core/radio_host/**`
  (new, 1 file, 16 tests), `dossiers/TASK-045.md`. `lib/app.dart`/
  `lib/main.dart` untouched, confirmed by `git diff --stat`. No other
  task's territory touched.
