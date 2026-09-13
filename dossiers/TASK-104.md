# TASK-104 — Relay baked in + registration as an explicit, retried, visible state

## Work Log

- [2026-09-13] [S5] Claimed. Preflight (`python scripts/preflight_paths.py TASK-104`):
  ```
  [preflight] TASK-104 Owned_Paths inspected in C:/CLAUDECODE_TOOLSETS/wt-s5-walkietalkie-keryx
  [preflight] 16 entr(y/ies). FILE/DIR/GLOB = exists, NEW = you are creating it.
    FILE   lib/core/settings/settings_model.dart  -> exists, 301 line(s), 11038 bytes
    FILE   lib/core/settings/settings_repository.dart  -> exists, 145 line(s), 4825 bytes
    FILE   lib/app_shell/directory_providers.dart  -> exists, 314 line(s), 14951 bytes
    NEW    lib/app_shell/app_lifecycle.dart  -> does not exist; parent lib/app_shell/ exists
    FILE   lib/app_shell/onboarding_gate.dart  -> exists, 216 line(s), 7607 bytes
    NEW    lib/app_shell/registration_step.dart  -> does not exist; parent lib/app_shell/ exists
    FILE   lib/features/settings/settings_screen.dart  -> exists, 747 line(s), 28159 bytes
    FILE   lib/features/settings/settings_copy.dart  -> exists, 204 line(s), 8996 bytes
    GLOB   test/core/settings/**  -> 2 file(s)
    FILE   test/app_shell/directory_enrolment_test.dart  -> exists, 349 line(s), 13375 bytes
    FILE   test/app_shell/directory_providers_test.dart  -> exists, 171 line(s), 7628 bytes
    NEW    test/app_shell/onboarding_gate_test.dart  -> does not exist
    NEW    test/app_shell/registration_step_test.dart  -> does not exist
    NEW    test/app_shell/app_lifecycle_test.dart  -> does not exist
    GLOB   test/features/settings/**  -> 6 file(s)
    NEW    dossiers/TASK-104.md  -> does not exist
  ```

- [2026-09-13] [S5] Implemented (A)–(D):
  - **(A) Relay baked in.** Added `KeryxSettings.relayUrlBakedIn` (the real
    field-test default, `wss://204-168-249-99.sslip.io` unless
    `--dart-define KERYX_RELAY_URL=...` overrides it). Deliberately did
    **not** change `KeryxSettings.relayUrlDefault` (the bare-constructor
    default, used pervasively by unowned tests expecting an empty/no-relay
    default) — first attempt did exactly that and broke
    `test/core/radio_host/keryx_radio_host_test.dart` and
    `radio_session_host_v2_test.dart` (both outside `Owned_Paths`), which
    build `KeryxSettings` directly and assert LOCAL-only behaviour. Fixed by
    applying the baked-in default only inside `SettingsRepository.load()`
    (fresh install / corrupt blob / a persisted-but-empty, never-cleared
    `relayUrl`) and `KeryxSettings.fromJson`'s not-cleared fallback — i.e.
    exactly the persistence boundary the task description names
    ("`SettingsRepository` load migrates an empty/absent `relayUrl`").
    Added `relayUrlUserCleared` (persisted) so an explicit user clear
    (saved empty) is honoured forever, while a legacy/never-configured
    empty value still migrates every load.
  - **(B) Registration state machine.** `lib/app_shell/app_lifecycle.dart`:
    `AppForegroundObserver` + `appForegroundProvider` (single app-wide
    `WidgetsBindingObserver`, exposed as a broadcast `Stream<void>`, only
    `AppLifecycleState.resumed`). `lib/app_shell/directory_providers.dart`:
    added `RegistrationStatus` (sealed: `Unregistered`/`InProgress`/
    `Registered`/`Offline`/`Failed`) and `registrationStatusProvider`
    (`NotifierProvider<RegistrationStatusController, RegistrationStatus>`),
    layered **on top of** the existing `identityEnrolmentProvider` rather
    than changing its shape — that provider's own
    `IdentityEnrolment`/`IdentityEnrolmentOutcome` contract is the seam
    `radioHostProvider` (frozen `lib/core/radio_host/**`) and
    `test/app_shell/directory_enrolment_test.dart` depend on, and the task
    explicitly requires the latter still pass unchanged. Backoff 1→60s cap,
    doubling on each failure, reset on success/`registerNow()`/foreground.
    `@visibleForTesting debugPendingRetryDelay`/`debugFirePendingRetry()`
    let tests assert/drive the ladder without a real or fake-clock wait —
    `Timer` itself needs a real wall clock either way since
    `identityEnrolmentProvider`'s own attempts are real `dart:io` HTTP
    against a loopback fake server (mirrors `directory_enrolment_test.dart`'s
    own approach; `FakeAsync` cannot complete real socket I/O, a constraint
    already documented elsewhere in this repo's test suite).
  - **(C) Onboarding confirmation.** `onboarding_gate.dart` gained
    `_GateStage.registering` between create/restore and `done`, rendered by
    new `registration_step.dart` (`RegistrationStep`): registered → "✓
    Registered as CALLSIGN·shortcode" (Continue); offline/other failure →
    "Not online yet…" (Continue anyway); `callsign_taken` → named failure,
    Back to the callsign step; an 8s internal timeout if still in-progress
    also falls through to "Continue anyway" — never blocks reaching Talk.
  - **(D) Settings → Identity.** Added a read-only registration-status row
    and a "Register now" action (hidden once registered) using
    `registrationStatusProvider`/`.notifier.registerNow()`; a callsign edit
    now calls `ref.invalidate(identityProvider)` so the app-wide identity
    (separate instance from this screen's own `IdentityRepository`) picks
    up the rename and `identityEnrolmentProvider`/`registrationStatusProvider`
    re-enrol without a restart (the `identity_exists` → `patchCallsign`
    route already existed).

- [2026-09-13] [S5] **Regression found and fixed (twice) before landing.**
  1st attempt baked the new default straight into `KeryxSettings.relayUrlDefault`
  — broke 2 unowned radio-host tests (see above), fixed by the
  `relayUrlDefault`/`relayUrlBakedIn` split.
  2nd, more serious: even after that split, `SettingsRepository.load()`'s
  fresh-install fallback still resolves a **non-empty** relay by default —
  correct per the task's own literal wording, but it silently flips every
  widget test that (a) uses a real (non-null) `keyPair` identity override
  and (b) does **not** override `directoryClientProvider`/`presenceClientProvider`
  wholesale, from "no relay → LOCAL only, no directory activity" to "a real
  (intercepted-to-400-under-`TestWidgetsFlutterBinding`) enrolment attempt".
  Root-caused via targeted temporary reversion + full-suite diff: the
  regression was 17 failures, ALL through exactly one shared, unowned test
  harness — `test/regression/regression_shell_harness.dart` (used by
  `layout_matrix_test.dart`, `overflow_system_back_test.dart`,
  `settings_golden_test.dart`, `shell_frame_golden_test.dart`) — which seeds
  a real `keyPair` + a bare `InMemorySettingsStore()` and never overrides
  `directoryClientProvider`. `test/app_shell/shell_harness.dart` and
  `test/app_shell/directory_shell_harness.dart` are NOT affected (the
  former's stub identity has `keyPair: null`, short-circuiting
  `identityEnrolmentProvider` to `notApplicable` regardless of `relayUrl`;
  the latter overrides `directoryClientProvider`/`presenceClientProvider`
  wholesale). `directory_enrolment_test.dart`'s own `buildContainer` (in
  `Owned_Paths`) needed one addition — an explicit `relayUrlUserCleared:
  relayUrl.isEmpty` when seeding its raw settings blob for the "no relay
  configured" test — since that test intentionally writes a raw
  `KeryxSettings(...).toJson()` blob bypassing `save()`'s own marker
  derivation. Fixed there (in territory). `regression_shell_harness.dart`
  is **not** in `Owned_Paths` and could not be fixed the same way.
  → See Blocked_Reason.

## Current status

Every acceptance criterion for (A)–(D) is implemented and covered by new
tests, all green (see Test_Evidence in PLAN.md). `directory_enrolment_test.dart`
(the frozen contract) passes unchanged (one small, in-territory seed fix).
`flutter analyze` clean on every touched file.

The one open item is the shared-harness ripple above — a single missing
`relayUrl: ''` seed in a file outside `Owned_Paths`. Routed to ORCH rather
than worked around by editing outside territory.
