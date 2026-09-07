# TASK-048 — Mobile app shell and navigation

## Brief

The convergence task: mount TASK-045's host above the navigator so it is built
once at app scope, then build the two-destination shell (Channels default,
Settings) with Talk as a route beneath Channels. Route registration, shared
providers and final wiring live here and nowhere else, which is why this is a
single-owner integration task and the gate for all seven screen tasks.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §1 — IA tree; two persistent
  destinations; "its presentation lifecycle must not own the radio session".
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §2 (`MobileAppShell`,
  single ProviderScope; no mandated routing/state package), §4 (navigation never
  starts/disposes/retunes), §9 (this task owns app.dart and route registration),
  §10 (dev-only compat route for the legacy face).
- PRD UX-D01, UX-D02, UX-FR-001/005/007/008; Verification VT-001, VT-004.
- ADR-001 §3 item 1 — supersedes PTS P1's no-bottom-nav clause.

## Approach

Thin stand-in destinations are acceptable so the shell is testable before Wave 4
fills them — but never fake data, presence or unread counts, and no destination
for an unimplemented product surface. Keep exactly one `ProviderScope`. Prefer
existing repo conventions for routing/state; adding a package means blocking with
`SPEC_AMBIGUITY`, since `pubspec.yaml` is frozen and out of territory. Legacy
face stays reachable only through the development-only compat route that
TASK-061 later deletes.

## Work Log

- [2026-09-07T19:40:00Z] [S5] Claimed. Read TASK-045 (`lib/core/radio_host/**`),
  TASK-046 (`lib/core/presentation/**`) and TASK-047 (design tokens, not
  directly consumed by this task's thin stand-ins) fresh. Read `face_screen.dart`
  in full to lift its exact pre-hoist callback-bridge shape (settings/radio-state
  read/dispatch/listen, rememberChannel) and its default factory set
  (session/audioSink/identity/permissionGate/radioService) — these are
  duplicated verbatim into `lib/app_shell/radio_host_provider.dart` rather than
  imported, since they were `FaceScreen`-private `static` members and
  `lib/features/face/**` is outside this task's `Owned_Paths`. Not a rewrite:
  same classes, same construction, same wiring — only the caller moved.

- [2026-09-07T20:10:00Z] [S5] Implemented `lib/app_shell/**`:
  - `radio_host_provider.dart` — `radioHostProvider`, a plain (non-autoDispose)
    `Provider<RadioHost>` giving the whole app exactly one `KeryxRadioHost`,
    constructed lazily on first read and disposed via `ref.onDispose` only when
    the single `ProviderScope` itself tears down.
  - `mobile_app_shell.dart` — `MobileAppShell`: reads/starts the host once in
    `initState` (microtask-deferred, mirroring the pre-hoist `FaceScreen`
    exactly, since Riverpod forbids mutating a provider mid-build), then renders
    two persistent destinations (Channels, Settings) via `NavigationBar` +
    `IndexedStack`, each branch holding its **own** `Navigator` (a documented,
    package-free nested-navigator pattern — Technical §2 explicitly doesn't
    mandate a routing package) so pushing Talk beneath Channels never rebuilds
    or resets the Settings branch. Re-tapping the active destination pops that
    branch to root, matching ordinary bottom-nav UX, and never touches the host.
  - `channels_screen.dart` — default landing (UX-D01). Shows the real tuned
    channel/code from `radioStateProvider` and the real channel-recall memory
    already tracked by the host (`RadioHostSnapshot.channelMemory`) — never a
    fabricated channel/contact list (UX-FR-008/UX-D02). Tapping the current
    channel opens Talk without tuning; tapping a recall entry tunes (via
    `RadioViewIntents.tune`, TASK-046) then opens Talk.
  - `talk_screen.dart` — thin Talk stand-in. Projects `RadioViewState` (TASK-046)
    from the live `RadioState` + host snapshot + settings, forwards every
    gesture through `RadioViewIntents` (press/release/releaseLatch), and
    subscribes to `host.changes` so mic/service-fault overlay cues update live.
    Latch is UI-owned per Technical §4/TASK-046's disclosed finding — tracked
    here as local state, `releaseLatch()` called only on the deliberate unlatch.
  - `legacy_compat.dart` — `legacyFaceRouteName` constant, Technical §10's
    dev-only compat route.
  - `app_shell.dart` — barrel.
  Rewrote `lib/app.dart`: `KeryxApp` still wraps the single `ProviderScope`;
  `_KeryxMaterialShell`'s `home` is now `MobileAppShell` instead of the old
  single `FaceScreen`. `routes` keeps `backPanelRouteName` (the dev-only legacy
  `FaceScreen` still navigates to it by its own `⚙` key) and adds
  `legacyFaceRouteName` gated behind `kDebugMode`, pointing at the unmodified
  `FaceScreen()` with its own default factories. `lib/main.dart` needed no
  change (already just re-exports `KeryxApp` and calls `runApp`).

- [2026-09-07T20:40:00Z] [S5] Wrote `test/app_shell/**`:
  - `fake_radio_host.dart` — hand-written `RadioHost` double (same reasoning as
    `test/features/face/face_screen_test.dart`'s `FakeSessionHost`: no real
    transport/platform I/O can run under `flutter test`), records every call.
  - `mobile_app_shell_test.dart` (7 cases) — Channels is default landing;
    exactly 2 `NavigationDestination`s and no "Contacts" text anywhere
    (UX-D01/UX-D02); host started exactly once on mount; full
    Channels→Talk→Settings→Talk round trip causes **zero** additional
    start/dispose/tune calls (VT-001, the acceptance criterion's own scenario);
    re-tapping the active destination pops to root without touching the host;
    the legacy route name never appears as visible text/tooltip anywhere in the
    shell.
  - `channels_screen_test.dart` (3 cases) — shows the real current channel, no
    fabricated "Recently tuned" section when memory is empty; a real recall
    entry (pushed via `host.emit`) renders and tapping it both tunes (asserted
    against `host.tuneCalls`) and opens Talk; tapping the current-channel row
    opens Talk **without** tuning.
  - `talk_screen_test.dart` (3 cases) — press/release forward 1:1 to
    `pressPttCalls`/`releasePttCalls`; latch toggle only calls
    `releaseLatchCalls` on the unlatch tap, not on latching; a
    `micPermissionDenied` snapshot renders the "Microphone required" overlay
    cue (never a fabricated full-strength reading).
  - `legacy_compat_test.dart` (1 case) — a documented exception to "no I/O
    test can mount the default-wired `FaceScreen`" (see the file's own dartdoc
    for why): reads `lib/app.dart`'s source to confirm `legacyFaceRouteName` is
    registered exactly once and gated behind `kDebugMode`, and reads the three
    shell source files to confirm none of them reference the name — a
    legitimate provenance check for what is, at bottom, a purely structural
    criterion ("not present in a normal user navigation path").

- [2026-09-07T21:00:00Z] [S5] `flutter analyze` (repo-wide): 8 pre-existing
  TASK-035 warnings in `test/services/session/radio_session_controller_test.dart`
  only (unrelated, unowned by this task) — zero issues in any touched file.
  `flutter test` (full suite): **1109 passed, 0 failed, 40 skipped** (unchanged
  parked FR-025 seeds) — 1096 (TASK-046's own recorded baseline) + 13 new
  `test/app_shell/**` cases = 1109, delta fully explained.
  `flutter build apk --debug`: **succeeded** (`build/app/outputs/flutter-apk/
  app-debug.apk`); only pre-existing Gradle/AGP/Kotlin deprecation warnings,
  unrelated to this task.
  Revert-mutation-checked 2 of the most load-bearing new tests: (1) removed
  `host.start()`'s call in `MobileAppShell.initState` — flipped exactly
  "the host is constructed and started exactly once on mount" red, all others
  stayed green; (2) made the Channels current-channel row call `_tune()` before
  opening Talk (the exact "navigation must never retune" violation VT-001
  guards against) — flipped exactly "tapping the current-channel row opens Talk
  without tuning" red. Both mutations reverted immediately after, confirmed by
  an empty `git diff` on the mutated files afterward.
  Both `flutter analyze` (auto-appended an `analyzer: exclude:` block to
  `analysis_options.yaml`) and `flutter build apk --debug` (touched
  `android/gradle.properties`, "Upgrading gradle.properties") made
  environment-local edits to files outside this task's `Owned_Paths` — reverted
  with `git checkout --` both times before committing, consistent with
  TASK-046's own disclosed finding that this is a standing local-toolchain
  side effect, not something either task's diff should carry.
  → Status: needs_review.

## Non-blocking notes for ORCH / future tasks

- The seven Wave 4 screen tasks (TASK-049/050/051/053/054/055/056) replace
  `ChannelsScreen`/`TalkScreen`'s thin bodies with the real skeuomorphic UI —
  this task's versions are deliberately minimal (Design/PRD copy above the
  bottom nav, no theming from TASK-047's tokens) so as not to duplicate that
  work ahead of schedule.
- `BackPanelScreen` is reused unmodified as the Settings destination's body;
  no `lib/features/settings_panel/**` file was touched.
- The dev-only legacy route's own `FaceScreen()` instance constructs a
  *second*, independent `RadioHost`-equivalent stack (its own pre-hoist
  session/audio/service factories) — by design, since it's an unshipped,
  debug-only compatibility harness that TASK-061 deletes outright, not a
  concurrently-live second production session.
