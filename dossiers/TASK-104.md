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

- [2026-09-13] [S5] **Second regression round, also fixed, both in-territory.**
  Discovered the auto-derivation described above (`relayUrl.isEmpty` →
  `relayUrlUserCleared: true` on every save) was itself too broad: it fired
  on *any* save carrying an untouched, already-empty `relayUrl` (not just an
  actual clear action), corrupting `settings_apply_test.dart`'s and
  `settings_screen_test.dart`'s session-affecting round-trip assertions.
  Fixed by making `relayUrlUserCleared` caller-declared instead of
  repository-derived — only `SettingsScreen`'s relay field `onSubmit` (the
  one real "user cleared it" action) sets the flag; `_saveUnlocked` trusts
  it verbatim. Also fixed two `test/features/settings/**` fixtures (in
  territory) whose fake-host `sessionAffectingFieldsChanged` baseline was
  seeded from a bare `KeryxSettings()`/an unresolved raw settings blob
  while the real `settingsProvider` now resolves an untouched relay to the
  baked-in default on every load — reseeded both from the
  repository-resolved value instead. Commits: `4c99e88`, `32dbd2f`.

## Current status

Every acceptance criterion for (A)–(D) is implemented and covered by new
tests, all green. `directory_enrolment_test.dart` (the frozen contract)
passes unchanged (one small, in-territory seed fix).
`flutter analyze` clean on every touched file. Full suite run 3 times
during this session as each regression was found and fixed; the 3rd run's
only remaining failures (14, all through one root cause) are detailed
below.

## Blocked_Reason — OWNERSHIP_CONFLICT

**File:** `test/regression/regression_shell_harness.dart` (NOT in this
task's `Owned_Paths`; owner unclear from PLAN.md — likely TASK-078/095's
original territory, both `done`).

**Exact root cause:** `pumpRegressionShell` (line ~36) seeds a **real**
`IdentityKeyPair` and a bare `InMemorySettingsStore()` (line 40, never
pre-written), and does **not** override `directoryClientProvider`/
`presenceClientProvider` the way `test/app_shell/directory_shell_harness.dart`
does. TASK-104's own acceptance criterion #1 requires
`SettingsRepository.load()` to migrate a never-configured `relayUrl` to
the baked-in default (`KeryxSettings.relayUrlBakedIn`) — correct and
spec-mandated (Owner requirements 2026-09-13; this task's own Description
(A)). The combination (real key pair + now-non-empty relay + no
`directoryClientProvider` override) means every widget test through this
harness now drives a **real** `identityEnrolmentProvider` attempt, which
under `TestWidgetsFlutterBinding` gets an instant HTTP 400 — and something
downstream of that (not yet isolated further: candidates are
`ContactsController`/`GroupsController`'s own reconnect/refresh scheduling,
pre-existing code outside this task's `Owned_Paths` too) keeps producing
new frames forever, so every `pumpAndSettle` in this harness times out.
Confirmed via targeted temporary reversion (reverting just the baked-in
default made all 14 pass; restoring it reproduced all 14) — this is not
speculative.

**Affected tests (14, all and only through this one harness):**
`test/regression/goldens/settings_golden_test.dart` (2),
`test/regression/goldens/shell_frame_golden_test.dart` (2),
`test/regression/layout_matrix_test.dart` (7, all cases),
`test/regression/overflow_system_back_test.dart` (3).

**Not affected (confirmed, so not a blanket regression):**
`test/app_shell/shell_harness.dart` (its stub identity's `keyPair` is
`null`, so `identityEnrolmentProvider` short-circuits to `notApplicable`
regardless of `relayUrl`) and `test/app_shell/directory_shell_harness.dart`
(overrides `directoryClientProvider`/`presenceClientProvider` wholesale,
bypassing `identityEnrolmentProvider` entirely) — both patterns already in
use elsewhere in this same test tree, either of which fixes this harness
too.

**Suggested one-line fix (for whoever owns this file):** either (a) seed
the store with an explicit clear —
`await store.write(SettingsRepository.storageKey, jsonEncode(const KeryxSettings().copyWith(relayUrl: '', relayUrlUserCleared: true).toJson()))`
before building the container — or (b) override
`directoryClientProvider`/`presenceClientProvider` to `null`-returning
stubs the way `shell_harness.dart`'s `keyPair: null` achieves implicitly.
Either restores "no relay configured" for these layout/golden/back-nav
tests, which never cared about directory/registration behaviour in the
first place.

**Why blocked rather than worked around:** the fix is outside `Owned_Paths`.
Editing it would violate territorial isolation (AGENTS.md commandment 4)
even though the change itself is small and mechanical.

Every other in-territory acceptance criterion, test, and evidence item is
complete and green — this is the sole blocker.

## Update 2026-09-13 — ORCH re-carved `test/regression/regression_shell_harness.dart`
into this task's `Owned_Paths`; fixed there (commit `2a0ccb9`): pre-seed
`InMemorySettingsStore` with an explicit `KeryxSettings(relayUrl: '',
relayUrlUserCleared: true)` blob before building the container, so the
baked-in migration does not resolve a non-empty relay and drive a real
`identityEnrolmentProvider` attempt in this harness. Confirmed: all 12
tests through `regression_shell_harness.dart`
(`layout_matrix_test.dart` ×7, `overflow_system_back_test.dart` ×3,
`shell_frame_golden_test.dart` ×2) now pass; `flutter analyze` clean.

## New Blocked_Reason — OWNERSHIP_CONFLICT (round 2, same root cause, different file)

Full-suite re-run after the fix above: **1483 passed / 2 failed / 40
skipped** (skips unchanged, pre-existing FR-025 soak park). The 2
remaining failures are `test/regression/goldens/settings_golden_test.dart`
("Settings (dark)" and "Settings (light)") — a real pixel diff (4.69% /
97271px), not a hang: `matchesGoldenFile` runs and returns a genuine
diff.

**Root cause:** identical pattern to `regression_shell_harness.dart`, in a
file this task does **not** own. `settings_golden_test.dart`'s own
`pumpAndGolden` (not `pumpRegressionShell`) builds its own
`InMemorySettingsStore()` and never writes to it before pumping
`SettingsScreen`. TASK-104's spec-mandated migration means
`SettingsRepository.load()` now resolves that untouched store's `relayUrl`
to the baked-in default, and this task's own in-territory addition to
`settings_screen.dart` (the Identity section's live registration-status
row + "Register now") now renders on that screen — which is exactly the
new content the golden fixture was never generated against. The pixel
diff is the correct, expected consequence of an in-territory UI change;
the golden image and/or its seeding just needs updating, but the file that
needs the update is not in `Owned_Paths`.

**Suggested fix for whoever owns/re-carves this file:** mirror the
`regression_shell_harness.dart` fix — seed `settingsStore` with an
explicit `KeryxSettings(relayUrl: '', relayUrlUserCleared: true)` blob (or
override `directoryClientProvider`/`presenceClientProvider` to inert
stubs) before pumping, so the golden fixture's Settings screen shows the
same "no relay configured" state it always has and the existing PNGs stay
valid — OR, if the Identity section's new row is meant to appear in this
golden's baseline, regenerate `test/regression/goldens/settings_dark.png`
and `settings_light.png` (`--update-goldens`) after seeding a deterministic
`registered`/`offline` state, whichever the reviewer prefers.

**Not fixable in territory:** `settings_golden_test.dart` is not listed in
this task's `Owned_Paths`, so per AGENTS.md commandment 4 this cannot be
edited here. Requesting the same one-file re-carve ORCH already granted
for `regression_shell_harness.dart`.

Every other acceptance criterion is met; only this one file (and, if the
reviewer prefers the "update golden" resolution, its two PNG assets)
blocks a fully green suite.

## Update 2026-09-13 — settings_golden_test.dart regenerated (ORCH's chosen resolution)

Per ORCH's 2026-09-13T10:35Z decision, regenerated (not reseeded) the two
Settings goldens: `flutter test test/regression/goldens/settings_golden_test.dart
--update-goldens` → 2/2, then re-ran clean without the flag → 2/2 pass again
(determinism confirmed). Visually confirmed both `settings_dark.png` and
`settings_light.png` now render the new Identity registration-status row with
its amber "Register now" affordance (screenshots inspected directly — same
discipline as TASK-058's light-golden fix). `flutter analyze` clean. Full-suite
evidence appended below once the run completes.
