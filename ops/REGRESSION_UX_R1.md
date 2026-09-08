# REGRESSION_UX_R1 — TASK-058 evidence report

G3/G4 evidence gate before hardware testing (Verification §9). Owned_Paths for
this task is `test/regression/**`, `ops/REGRESSION_UX_R1.md`,
`dossiers/TASK-058.md` only — deliberately no production directory, so any
defect this task finds is a **finding**, routed to the owning task, never a
same-task fix.

## 1. Baseline and test environment (Verification §2)

- Baseline commit (merge-base of `task/TASK-058-s5` and `master`):
  `3dc6129828b41f5972340118449909c9e7434ceb` — "chore(plan): TASK-058 reassign
  GB -> S5 (GB usage balance exhausted, no work lost) [ORCH]", 2026-09-08.
- Task branch head at time of this report: see `git log -1` on
  `task/TASK-058-s5`; all this task's commits are `test(regression):`/
  `docs(dossier):`/`chore(regression):`-scoped, zero production files touched.
- Toolchain: `flutter --version` → **Flutter 3.47.2** (channel stable),
  Framework revision `d3b14c8769` (2026-08-26), Engine hash `1cf1c4773fb9`,
  **Dart 3.13.2**, DevTools 2.60.0.
- Commands run (exact, from the worktree root):
  - `flutter pub get` (implicit via the commands below; no separate failure)
  - `flutter test` — full suite
  - `flutter analyze` — full repo
  - `flutter build apk --debug`
  - `flutter build apk --release`
- Working directory for every command: `E:/DELL-PROJECTS/wt-s5-WALKIETALKIE`
  (this task's own worktree, `task/TASK-058-s5` branch).

## 2. Full regression suite (`flutter test`)

**Result: 1412 passed, 0 failed, 40 skipped.**

The 40 skips are exactly the ADR-001 §5 owner-parked FR-025
emergency-preemption soak seeds (`test/simulation/soak_test.dart`), each
carrying its own `Skip: PARKED (project-owner decision 2026-08-21T17:05Z): ...`
reason string, unchanged and unweakened (Verification §0; ADR-001 §5). No
other test anywhere in the repo is skipped.

This total already includes every new test this task added
(`test/regression/**`, 41 tests: 5 real-composition + 36 goldens across 7
golden-test files) — see §4/§6 below for their own breakdown.

Historical-preservation check (Verification §0 / Technical §1): the legacy
`test/features/face/**` suite (7 files, the pre-redesign hardware-face screen
and its supporting tests) is untouched and still green at this commit — it
is not deleted or weakened here; TASK-061 owns its eventual removal.

## 3. Analyzer (`flutter analyze`)

**Result: 8 issues, zero new.**

All 8 are the already-documented, pre-existing TASK-035 warnings, entirely
confined to `test/services/session/radio_session_controller_test.dart`
(unused imports/locals/elements) — a file wholly outside this task's
`Owned_Paths`. No file this task touched (`test/regression/**`) produces any
analyzer issue.

## 4. VT-001 – VT-005: host and navigation integration (Verification §3)

| VT | Covering test(s) | Status |
|---|---|---|
| VT-001 (single instance) | `test/app_shell/mobile_app_shell_test.dart` ("start/dispose/tune calls (VT-001)", IndexedStack branch-preservation group) — scoped `FakeRadioHost`. **Also** `test/regression/real_composition_test.dart` ("navigating Channels -> Talk -> Settings -> Talk through the real composition...") — the **real** `KeryxApp`/`radioHostProvider`/`KeryxRadioHost`, added by this task to satisfy §9's "actual composition" requirement (see below). | Covered |
| VT-002 (boot race) | `test/core/radio_host/keryx_radio_host_test.dart`, group "boot race / session reconstruction (Verification VT-002)" — real `KeryxRadioHost`, factory-level fakes, no widget tree. | Covered |
| VT-003 (settings reconstruction) | `test/features/settings/settings_apply_test.dart` (presentation-only → 0 reconstructions; each session-affecting field → exactly 1; cancelled confirm → 0). | Covered |
| VT-004 (disposal/background) | `test/core/radio_host/keryx_radio_host_test.dart`, group "disposal (Verification VT-004)" (repeated-dispose idempotency). **Also** `test/regression/real_composition_test.dart` ("disposing the real composition tears down the real session, floor engine and audio sink exactly once") — real host, real dispose chain, added by this task. | Covered |
| VT-005 (configuration persistence) | `test/features/settings/settings_persistence_test.dart` ("VT-005: legacy fixture loads; appearance save does not drop fields"), with a documented pre-redesign fixture blob. | Covered |

**AC 4 / Verification §9 — "include a test that exercises the actual
composition when the defect concerns wiring":** before this task, no test
anywhere pumped the real `KeryxApp` → real `radioHostProvider` → real
`KeryxRadioHost` → real `FloorEngine` chain; every widget-level test
substituted a scoped `FakeRadioHost` (an interface-level double), and the one
place the real `KeryxRadioHost` class ran (`keryx_radio_host_test.dart`) did
so with no `WidgetTester`/`ProviderScope`/`KeryxApp` at all. This task adds
`test/regression/real_composition_test.dart`: 5 tests pumping the literal
`KeryxApp` widget with the real `radioHostProvider` construction (copied
verbatim in shape from `lib/app_shell/radio_host_provider.dart`) and only the
five native/platform-boundary factories (`sessionFactory`,
`audioSinkFactory`/`Disposer`, `identityFactory`, `permissionGateFactory`,
`radioServiceFactory`) substituted with deterministic fakes, exactly as
Verification §2 itself instructs ("Use fake SessionHost, audio sink, identity
and permission/service adapters ... Never require real UDP sockets or native
plugin availability"). Result: **5/5 pass.**

## 5. VT-010 – VT-015: PTT and floor-state (Verification §4)

| VT | Covering test(s) | Status |
|---|---|---|
| VT-010 (state matrix) | `test/features/talk/talk_screen_test.dart`, groups "VT-010 — state matrix" and "Design §4 state catalogue — icon and colour". Verified line-by-line for this report: every one of the 13 phase/overlay rows named in Verification §4 has its own icon+colour(+label where applicable) assertion — off, boot, idle/ready, tuning, requesting, TX granted, receiving, no-link/degraded, denied/busy overlay, latched overlay, emergency overlay, permission-denied overlay, service-fault overlay. "A pending request is not shown as granted TX" is asserted explicitly. | Covered (confirmed exhaustive, not partial — corrects this task's own earlier coverage-map note) |
| VT-011 (request/grant/release) | `talk_screen_test.dart`, group "VT-011 — request/grant/release": pointer-down = one request, no red TX before grant, release = one release intent, duplicate pointer-up/late-grant cause no duplicate/stuck TX. | Covered |
| VT-012 (cancellation/disposal) | `talk_screen_test.dart`: pointer-cancel, route-unmount-mid-hold, permission-loss-mid-hold, engine-replacement-mid-hold — each asserts authoritative engine calls (`releasePttCalls`/`releaseLatchCalls`), not widget colour. | Covered |
| VT-013 (busy/TOT/emergency) | `test/core/floor/floor_engine_test.dart`: busy lockout, TOT warn-at-T-5s/hard-cut-at-0, emergency pre-emption/priority/override-busy. Tested at the engine level per VT-013's own scope note ("tested separately"). FR-025 emergency-preemption is explicitly named and PARKED (ADR-001 §5) — not reopened, not silently removed; its 40 named soak skips are intact (§2 above). | Covered |
| VT-014 (multiple entry points) | Previously **partial**: no test proved on-screen PTT + notification PTT + hardware controls converge on the same floor engine inside the new shell, or that leaving Talk preserves the notification action. **Closed by this task**: `test/regression/real_composition_test.dart` adds "on-screen PTT and a simulated notification PTT action both act on the same real FloorEngine instance" (holds the real on-screen disc, then fires a simulated `RadioServicePttAction` through the real `RadioServiceController` event stream, asserting both land on the identical `FloorEngine` instance) and "navigating away from Talk does not stop the native radio service" (the foreground service stays `isRunning` after `pageBack()` off Talk). | Covered (closed by this task) |
| VT-015 (audio truthfulness) | `talk_screen_test.dart`, group "VT-015 — audio truthfulness". | Covered |

## 6. VT-020 – VT-024: tuning and connectivity (Verification §5)

| VT | Covering test(s) | Status |
|---|---|---|
| VT-020 (input validation) | `test/features/channel_selector/channel_selector_screen_test.dart` (Apply disabled on invalid/empty input, Cancel no-op, recall dedup/order/tap-dispatches-tune); `test/features/channels/channel_memory_test.dart` ("preserves newest-first order and drops duplicates (VT-020)"); `test/core/radio_host/keryx_radio_host_test.dart` ("rejects an out-of-range channel/code"). | Covered |
| VT-021 (retune serialization) | `test/features/channel_selector/tune_coordinator_test.dart`, group "VT-021 — serialization / latest-wins" (rapid A→B→C out-of-order completion → one deterministic outcome, no stale adoption) and its "recovery policy" group (validation-failure/cancelled/retryable classification); `keryx_radio_host_test.dart` "serializes concurrent tune calls". Retune-after-teardown specifically is covered by the general repeated-dispose safety guarantee (VT-004) rather than a dedicated named scenario — recorded here as a minor documentation gap, not a behavioural one (the serialization chain and the dispose guard are both unconditional, so the combination is provably safe by composition, just not exercised by one single named test). | Covered (one sub-clause documented rather than independently tested — see note) |
| VT-022 (mode matrix) | `test/features/settings/settings_screen_test.dart`, "VT-022: configured, effective and Local only are distinct; force-LOCAL blocks WAN" (Auto configured / Local effective / force-LOCAL blocks a tap to Linked). This is the one test confirmed by name; the full LOCAL/LINKED/AUTO × with/without-relay × relay-failure-fallback matrix is not each individually named in one place — the force-LOCAL-overrides-WAN clause (the safety-relevant half of VT-022) is solidly covered; the remaining combinations are a documentation gap for a future task to close with named tests, not a code defect found here. | Partial (documented, not a defect — routed as a finding, see §9) |
| VT-023 (QR transition) | `test/features/event_qr_ui/event_qr_join_coordinator_test.dart` (already-linked/route-transition-failure/join-failure-after-transition/keyed-payload/unavailable-route) and `event_qr_ui_scan_screen_test.dart` (denied/permanently-denied/unavailable/granted permission, LOCAL approve/cancel, join-failure-no-false-select, expired, malformed). | Covered |
| VT-024 (roster/quality) | `test/features/stations/stations_screen_test.dart` (live join/depart while open, unknown-identity fallback, AUTO-incomplete-roster labelling, LOCAL-no-member-count, `KnownRosterCount` vs `.length`, `UnavailableRosterCount`-with-empty-stations-is-unknown-not-zero, placeholder-max-ignored); `test/core/presentation/radio_view_state_test.dart` ("Telemetry honesty ... VT-024"). | Covered |

## 7. §6 Visual and accessibility verification

**Golden fixtures — TOTAL GAP before this task, closed here.** No golden-image
infrastructure (`matchesGoldenFile`, a golden-testing package, or any
`goldens/*.png` fixture) existed anywhere in the repository. Every prior
dark/light or visual-state claim was a logic/semantic assertion, never a
rendered pixel diff. This task adds the first golden infrastructure under
`test/regression/goldens/**`:

| File | Coverage | Themes | Count |
|---|---|---|---|
| `talk_states_golden_test.dart` | Talk: idle, requesting, granted/TX, receiving, degraded-link, emergency, permission-denied, service-fault (8 states, driven through the real `radioStateProvider` reducer, never a hand-built `RadioState`) | dark + light | 16 |
| `channels_golden_test.dart` | Channels: empty recall, populated recall | dark + light | 4 |
| `selector_golden_test.dart` | Channel selector | dark + light | 2 |
| `stations_golden_test.dart` | Stations: empty, populated | dark + light | 4 |
| `settings_golden_test.dart` | Settings | dark + light | 2 |
| `radio_controls_golden_test.dart` | Radio Controls | dark + light | 2 |
| `event_qr_golden_test.dart` | Event QR export (numbered channel); Event QR scan (permission granted; permission denied — the latter doubling as one of §6's named "error states") | dark + light | 6 |
| **Total** | every screen category named in Verification §6 ("Talk state, Channels empty/populated, selector, Stations empty/populated, Settings, controls, QR and error states") | dark + light | **36** |

All 36 goldens were generated with `--update-goldens` and then confirmed
deterministic across two independent clean re-runs (`flutter test
test/regression/goldens/` — 36/36 pass both times, no `--update-goldens`).
Two non-determinism sources were found and fixed during that verification
(recorded here rather than silently absorbed, per this report's own §2
standard): (a) the Event QR export golden used the wall-clock `DateTime.now()`
default for its expiry countdown — fixed by injecting a constant `now`; (b)
the Settings golden seeded an **empty** identity store, so
`IdentityRepository` minted a random UUID/NATO callsign on every run
(`Random.secure()`) — fixed by seeding a fixed UUID/callsign. Both fixes are
in the test files themselves (`test/regression/**`), not production code.

**Not attempted in this task** (documented, not silently skipped): a
full state × width × text-scale × inset matrix (320 lp / normal phone /
larger phone / landscape / scale 1.0 & 2.0 / large insets) per every golden
category — that responsive matrix already has its own dedicated
non-golden test coverage per screen (the "TASK-057 round 2 — responsive
matrix + rendered guidelines" groups in `channel_selector_screen_test.dart`,
`stations_screen_test.dart`, `event_qr_ui_*_screen_test.dart`), which this
task did not duplicate as goldens given the territory's scope and time
budget. Recorded as a known limitation, not a gate failure.

**48 dp touch targets / WCAG AA contrast** — covered by the existing
"TASK-057 round 2" test groups named above.

**TalkBack labels** — pervasive `Semantics`/`semanticsLabel` coverage across
every screen's own test file (`talk_screen_test.dart`,
`channels_landing_test.dart`, `channel_selector_screen_test.dart`,
`radio_controls_screen_test.dart`, `settings_screen_test.dart`,
`stations_screen_test.dart`, `event_qr_ui_*_screen_test.dart`).

**Keyboard/switch access** — `test/features/radio_controls/
radio_controls_screen_test.dart`, group "TASK-069 — keyboard/switch access"
(Monitor latch via Activate, Emergency confirm-then-arm two-step, Escape
cancels confirm without arming). This task's own coverage-map review flagged
one open, non-blocking finding from TASK-069's own review that belongs to a
future task, not this one: `androidTapTargetGuideline` still cannot see the
Monitor/Emergency hold targets' 48 dp size because their `Semantics.onTap`
wrapper is non-container and its tap action merges into a larger ancestor
node — routed as a finding (§9).

**Reduced motion** — `test/core/theme/ux_tokens_test.dart` ("reduced motion
drops decorative/page and keeps critical state", "MediaQuery
disableAnimations drops decorative motion").

**Non-drag PTT alternative / reliable latch release** —
`talk_screen_test.dart`, groups "non-drag accessible alternative" and
"latch — explicit affordance" (engaging then releasing calls `releaseLatch`
exactly once; the latch control is unavailable before a real grant).

**Focus order** — no explicit `FocusTraversal`/ordering assertion was found
anywhere in the suite. Recorded as an open gap (§9), not fabricated as
covered.

## 8. Legacy/historical preservation (Verification §0, Technical §1)

`test/features/face/**` (7 files: `amplitude_source_test.dart`,
`face_screen_test.dart`, `face_view_test.dart`, `permission_gate_test.dart`,
`roster_screen_test.dart`, `roster_test.dart`, `status_strip_test.dart`) is
present, unmodified, and passing at this commit (all counted in the 1412
total in §2). `lib/app.dart` still registers the debug-only
`legacyFaceRouteName` route per Technical §10. TASK-061 owns the eventual
deletion; not touched here.

## 9. Findings routed to owning tasks (this task modifies no production code)

1. **VT-022 mode-matrix documentation gap** (not a code defect): only one
   named test (`settings_screen_test.dart`'s VT-022 test) explicitly
   exercises the mode matrix; the full LOCAL/LINKED/AUTO × relay-configured/
   not × relay-failure-fallback combination set is not each individually
   named. The safety-relevant force-LOCAL-blocks-WAN clause is solidly
   covered. Suggest: a future settings-screen task adds the remaining named
   cases.
2. **VT-021 retune-after-teardown** is covered only by composition (the tune
   chain's serialization + the host's unconditional-safe-dispose), not by one
   dedicated named test exercising "retune requested, then host torn down
   mid-flight". Suggest: `keryx_radio_host_test.dart`'s owning task adds one.
3. **`androidTapTargetGuideline` cannot see the Monitor/Emergency
   keyboard/switch hold targets' 48 dp size** (TASK-069's own Review_Findings
   already named this as non-blocking and inherited from master, not a
   TASK-069 regression). Repeated here because this task's own golden/
   regression pass is exactly where Verification §6's guideline check lives;
   still open, still routed to whichever task next touches
   `lib/features/radio_controls/**`.
4. **No `FocusTraversal`/explicit keyboard focus-order assertion** exists
   anywhere in the suite (§6's "focus order" clause). Suggest: a future
   accessibility-focused task adds an explicit traversal-order test across
   the shell's primary screens.
5. **Golden responsive-matrix (width/text-scale/inset) breadth**: this task's
   36 goldens are one canonical surface size per screen/state; the existing
   non-golden responsive-matrix tests (TASK-057 round 2 groups) already cover
   the width/scale/inset dimension logically. A future task could extend the
   golden set itself across that matrix if pixel-level regression on those
   axes specifically becomes a priority.

None of the above are regressions introduced by this task or by any
already-merged task; all are either pre-existing scope gaps this task's own
mapping pass surfaced, or (item 3) an already-disclosed, already-triaged
non-blocking finding repeated here for visibility at the gate where it is
checked.

## 10. G4 evidence — build status

- `flutter test` (full suite): **1412 passed / 0 failed / 40 skipped (parked)**.
- `flutter analyze` (full repo): **8 issues, all pre-existing TASK-035, 0 new**.
- `flutter build apk --debug`: **SUCCESS** — `build/app/outputs/flutter-apk/
  app-debug.apk`, 232,368,319 bytes. A suppressed Kotlin incremental-cache
  `IllegalArgumentException` from `livekit_client`'s Gradle module was logged
  mid-build (a cross-drive relative-path issue in Kotlin's own incremental
  compiler cache, pre-existing toolchain noise unrelated to this task) —
  non-fatal, exit code 0, APK produced.
- `flutter build apk --release`: **SUCCESS** — `build/app/outputs/flutter-apk/
  app-release.apk`, 121,935,768 bytes (116.3MB). Same benign suppressed
  Kotlin-cache warning, this time from `shared_preferences_android`'s Gradle
  module; same non-fatal outcome.

G4 is met: complete regression suite, analyzer and both Android build
variants pass, with every pre-existing exception (8 TASK-035 analyzer
warnings, 40 named PARKED FR-025 soak skips) documented rather than silently
absorbed.
