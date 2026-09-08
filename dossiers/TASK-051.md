# TASK-051 — Talk screen and new PTT presentation

## Brief

The primary communication screen and the wave's most safety-critical task. The
intake merged "new PTT presentation" into it deliberately so two builders never
contend for `lib/features/talk/**` (this is why there is no TASK-052). Built
fresh per Design §2.2 — responsive sizing, explicitly not TASK-043's fixed
320 dp disc — and driven entirely by TASK-046's composite view-state.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §2.2 (content order,
  ≥96 dp / ≥48 dp sizing, active-speaker copy, "a disconnected screen must not
  show Ready", non-drag accessible alternative, PTT and Emergency separate),
  §4 (state catalogue), §5 (copy and accessibility).
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §5.1 (authoritative command
  path), §5.2 (preserve or explicitly replace `PttButton`'s pointer suppression
  and double-tap latch, with the full listed test set), §4 (latch owned by the
  host, survives navigation).
- PRD UX-FR-020..030, UX-D03; Verification VT-010..VT-015.
- ADR-001 §6 / §7 item 2 — gesture/latch/TOT semantics reused as logic, widget
  tree new.

## Approach

Requesting may show on pointer-down; red TX only after authoritative grant.
Cancellation, unmount, backgrounding, permission loss and engine replacement all
release ordinary hold with no accidental latch, asserted against engine state
rather than widget colour. Emergency is reflected here as an overlay only — the
control screen is TASK-054's, and FR-025 stays PARKED.

## Work Log

- [2026-09-07T22:30:00Z] [S5] Claimed. Preflight (`python scripts/preflight_paths.py TASK-051`):
  ```
  [preflight] TASK-051 Owned_Paths inspected in E:/DELL-PROJECTS/wt-s5-WALKIETALKIE
  [preflight] 3 entr(y/ies). FILE/DIR/GLOB = exists, NEW = you are creating it.
    GLOB   lib/features/talk/**  -> matches nothing yet (new territory)
    GLOB   test/features/talk/**  -> matches nothing yet (new territory)
    FILE   dossiers/TASK-051.md  -> exists, 33 line(s), 1614 bytes
  ```
  Read TASK-046's `RadioViewState`/`RadioViewIntents`/telemetry types, TASK-045's
  `RadioHost` contract, TASK-047's `KeryxUxTokens`, the legacy `PttButton`/`PttState`,
  and Design/Technical/PRD/Verification §2.2/§4/§5/§5.1/§5.2/VT-010..015 in full before
  writing code.

  **Architecture decision — host injection, not an app_shell provider.** TASK-048's
  `lib/app_shell/**` (including its `radioHostProvider` and the stand-in `TalkScreen`
  it built) is frozen again post-merge and not in this task's `Owned_Paths`. Rather than
  import an app_shell-owned provider into `lib/features/talk/**` (wrong dependency
  direction — features should not depend on the shell composition root), `TalkScreen`
  takes `RadioHost host` as a constructor parameter; `radioStateProvider`/
  `settingsProvider` (both `lib/core/**`) are read via the normal Riverpod providers,
  same as TASK-046/048's own screens.

  **Known planning gap, flagged for ORCH, not a blocker for this task:** no task in
  the current plan owns swapping `lib/app_shell/talk_screen.dart`'s stand-in for this
  real widget — Owned_Paths for 049/050/051/053/054/055/056 (Wave 4) and 057/058
  (Wave 5 gates) all exclude `lib/app_shell/**`, and TASK-058's own Description states
  explicitly "this task modifies no production code (its territory contains none)".
  TASK-048's Review_Findings (round 1, finding 3) anticipated this exact screen
  "replaces wholesale" but Owned_Paths never reopened `lib/app_shell/talk_screen.dart`
  for 051. Recommend a short single-owner wiring task (same shape as TASK-048 itself)
  once all seven Wave 4 screens are done, analogous to how TASK-048 converged 045+046+047.

  **Explicit replacement of `PttButton`'s double-tap latch (Technical §5.2, documented
  rationale):** rather than reproduce the legacy quick-tap-then-second-down-within-window
  gesture (which requires a real, if brief, TX blip before converting to a latch, and is
  materially harder for switch/keyboard/TalkBack users to discover or trigger reliably
  within a timing window), latch engagement is a separate, clearly-labeled "Lock
  transmission" action in the secondary row, enabled only once a hold is genuinely
  granted (`RadioPhase.tx`). Releasing a latch is likewise an explicit "Release
  transmission" action calling `RadioHost.releaseLatch()`. This satisfies Design §5's
  "Optional latch is clearly labeled" and the keyboard/switch-access requirement more
  directly than a hidden gesture would, and is within round-1's own discretion window
  ("preserve or explicitly replace... with documented rationale and the full test set").

  Built `lib/features/talk/talk_copy.dart` (Design §5 copy constants), `talk_ptt_disc.dart`
  (`TalkPttDisc` — responsive gesture disc, `TalkPttToggleAlternative` — non-drag
  accessible alternative), `talk_screen.dart` (composition: header, connection line,
  overlay-cue chips, status line, disc, toggle alternative, secondary latch/roster row,
  all in `SafeArea`). VT-011/VT-012 safety net: `_holding`/`_latched` bookkeeping at the
  screen layer (idempotent hold-start/hold-end, latch suppresses the ordinary release),
  plus `WidgetsBindingObserver` for app-background release and snapshot-diffing for
  permission-loss/floor-engine-replacement release — all disclosed in dartdoc.

  Added `test/features/talk/fake_radio_host.dart` (same shape as
  `test/app_shell/fake_radio_host.dart`, this task's own copy since `test/app_shell/**`
  is out of territory) and `test/features/talk/talk_screen_test.dart` (23 cases):
  VT-011 request/grant/release incl. a genuine two-pointer overlap (not a same-pointer
  replay, which `GestureBinding` itself refuses to route twice) and a late-grant-after-
  release case; VT-012 cancellation/unmount/backgrounding-is-structural(not directly
  testable without a real platform lifecycle channel, covered via the same
  `_releaseOrdinaryHoldIfOwed` code path as the other four triggers, so its own dedicated
  test would exercise identical code, not additional risk)/permission-loss/engine-
  replacement, plus a latch-survives-unmount case; latch engage/release; the latch
  control disabled before a real grant; the non-drag toggle alternative; VT-010 state
  matrix (pending-not-granted, receiving with resolved/unresolved callsign, disconnected-
  never-Ready, emergency overlay, denied-flash-composed-with-granted-TX, off/no-engine/
  permission-denied all disabling the PTT surface); VT-015 roster-unavailable honesty;
  sizing (96 dp floor, 320 lpx width no-overflow).

  While writing the emergency/denied-flash coverage, found and fixed a real bug: the
  granted-TX branch of `_statusLineFor` rendered "Hold to talk" instead of Design §4's
  "Transmitting" — added `TalkCopy.transmitting` and fixed the switch arm; the new
  VT-010 cases are what caught it.

  Revert-mutation-checked 3 load-bearing guards from within this task's own
  `Owned_Paths`: (a) `TalkPttDiscState._onPointerUpOrCancel`'s `if (!_holding) return;`
  guard — removed, flipped exactly the two-pointer-overlap VT-011 case red (release
  count 2 instead of 1), nothing else; (b) `_TalkScreenState._handleHoldEnd`'s
  `if (_latched) return;` suppression — removed, flipped exactly the latch-engage/
  release case red (`releasePttCalls` went from 0 to 1 while latched), nothing else;
  (c) the `engineReplaced` disjunct in `_onSnapshot`'s safety-net trigger — removed,
  flipped exactly the engine-replacement VT-012 case red, nothing else. All three
  reverted immediately after with a clean `git diff` confirmed.

  Reverted the same two standing local-toolchain auto-edits every prior S5 task on
  this repo has disclosed (`analysis_options.yaml`'s analyzer-exclude block from
  `flutter analyze`; `android/gradle.properties` from `flutter build`) before every
  commit — not part of this diff.

  **Disclosed, honest gaps (not blockers, but real):**
  - Content order (Design §2.2's exact sequence) is a structural claim verified by
    reading the composed widget tree, not independently asserted by a dedicated
    ordering test (`find...` position comparisons) — same testing-depth caveat
    TASK-048 disclosed for its own structural claims.
  - No decorative meter/ring animation was built on the PTT disc (Design mentions the
    ring only insofar as it must not be mislabeled as measured — `RadioViewState
    .meterLevel` exists and is `MeterLevel.decorative` today; this screen simply
    doesn't render anything from it yet, which is a stricter, not weaker, reading of
    VT-015 UX-FR-027, but is a visual-polish gap relative to the legacy `PttButton`'s
    64-tick ring). Flagging for TASK-057 (a11y/responsive polish) or a design-review
    follow-up rather than adding unreviewed visual design in this task.
  - `RadioState.isTotWarning` is not projected onto `RadioViewState` at all (TASK-046's
    own scope, `lib/core/presentation/**` is out of this task's territory) — this
    screen therefore cannot and does not render a distinct TOT-warning indicator. TOT
    hard-cut itself still operates through the existing engine unaffected (VT-013's
    engine-level claim), this is purely a UI-surfacing gap.
  - `RadioPhase.boot`/`RadioPhase.tuning` disabled/label states share the exact same
    `ptteEnabled`/`_statusLineFor` code path already covered by the `off` and
    `permission-denied` cases (all three gate on the same boolean expression), so a
    dedicated test for each would exercise identical code — not added to keep the
    suite additive rather than repetitive, but noted here rather than silently assumed.

  Status -> needs_review.

- [2026-09-08T12:00:00Z] [S5] Round-2 rework. Resumed on the existing branch
  `task/TASK-051-s5` (already checked out; `git status` clean except a stray
  `analysis_options.yaml` diff from the local toolchain, reverted with
  `git checkout -- analysis_options.yaml` before starting). Read ORCH's
  Review_Findings in full from `PLAN.md` fresh before touching code.

  **BLOCKING 1/2 — stuck-latch defect.** ORCH's diagnosis was exactly right:
  `_TalkScreenState._latched` was a plain `bool` field, disposed with the
  widget on every route unmount. A latched transmission survived correctly at
  the engine (`dispose()` never releases a latch, per Technical §4) but lost
  its *only* UI release affordance on remount, because the fresh `State`
  started with `_latched == false`. Considered going `blocked` with
  `OWNERSHIP_CONFLICT` per the finding's own suggested escape hatch (no
  `RadioHost` acquire-latch operation exists), but concluded a host-side
  change isn't actually required: `RadioViewState.latched`'s own dartdoc
  already says a deliberate latch is "UI-owned" state that must "survive
  navigation" — the contract was always that *some* durable UI-side store
  holds it, not necessarily `RadioHost` itself. Added
  `lib/features/talk/talk_latch_state.dart`: `TalkLatchState`, an
  `Expando<bool>` at module scope keyed on `RadioHost` identity. Module scope
  (not a `State` field) means it survives exactly as long as the `RadioHost`
  instance does — which in the real app is the persistent, app-scoped host
  (TASK-045), i.e. exactly as long as Design/Technical require. Keying by
  identity (not a shared static bool) means a fresh `FakeRadioHost()` per
  test — or a genuinely replaced host — never inherits a stale flag.
  `_latched` is now a getter reading this store; `_engageLatch`/
  `_releaseLatch` write through it. Added the test ORCH specified verbatim:
  latch → unmount (assert nothing released, matches the existing pre-fix
  test) → remount against the *same* host **and** the same `ProviderContainer`
  (deliberately not `build()`, which constructs a fresh container/settings
  store and would reset `RadioState` too — that is not what a real
  navigation does; the real app's container and host both outlive the
  route) → assert the overlay cue and `keryx-talk-unlatch` are both still
  present → tap it → assert exactly one `releaseLatch` call and the screen
  returns to the un-latched affordance. Mutation-checked: reverted the getter
  to `=> false`, which flipped exactly this one new test red (`Found 0
  widgets with key 'keryx-talk-unlatch'`), nothing else; reverted clean.

  **BLOCKING 3(a) — per-row icon/colour.** Rebuilt the disc's icon/colour
  resolution to route through `RadioPhase.cue` (`radio_phase_presentation
  .dart`, the same catalogue source `RadioViewState.phaseCue` already
  exposes) instead of the old 4-bucket (`idle`/`requesting`/`tx`/`rx`)
  mapping that gave every non-tx/rx/requesting phase (off/boot/idle/tuning/
  linkDegraded) the same icon and colour. This surfaced two real defects
  beyond the missing test coverage itself: (1) Requesting rendered
  `actionPrimary` (blue) — Design §4's table says Requesting is
  "Pending/amber"; (2) Off/Boot/Tuning all rendered `actionPrimary` too —
  the table gives them their own "Neutral disabled"/"Neutral progress"/
  "Progress" treatments, and only the Ready row itself earns blue. Added
  `_idleColorFor`/`_iconForCueId` to resolve these correctly, and did the
  same for `_OverlayCueChip`, which previously hardcoded `Icons.circle` +
  `tokens.stateWarning` for all five overlay rows — collapsing Latched
  ("Red + explicit release") and Emergency ("Orange priority banner") into
  the same amber as Denied/busy and Service fault, losing exactly the colour
  half of Design §4's redundant label+icon+colour requirement for the two
  rows the spec calls out by name. Added a `Key('keryx-talk-overlay-
  ${cue.iconId}')` to `_OverlayCueChip` so tests can address each row
  directly. Added 13 new tests, one per Design §4 catalogue row, each
  asserting the `TalkPttDisc` widget's own `.icon`/`.color` (the semantic
  values this screen computed and handed down — not the rendered
  `AnimatedContainer` decoration, which additionally applies the disc's own
  disabled-state alpha dimming, a presentation concern belonging to
  `TalkPttDisc` itself, already covered by its existing enabled/disabled
  tests) or the matching overlay chip's `Icon`. Mutation-checked both splits:
  reverting `_idleColorFor` to always return `actionPrimary` flipped exactly
  the Off/Boot/Tuning tests red (3 failures, nothing else); reverting
  `_overlayColorFor`'s emergency branch flipped exactly the Emergency test
  red (1 failure, nothing else). Both reverted clean.

  **BLOCKING 3(b) — TOT.** Confirmed (did not just re-assert) that
  `RadioState.isTotWarning` has no projection anywhere in `RadioViewState`
  by grepping `lib/core/presentation/**` for `isTotWarning`/`TOT` — zero
  hits outside `radio_state.dart` itself. This is TASK-046's own scope, not
  reachable from `lib/features/talk/**`. Per the finding's own instruction,
  left the acceptance box unchecked but replaced the vague prose with an
  explicit carve-out request recorded inline on the criterion in `PLAN.md`,
  asking ORCH to task the projection against `lib/core/presentation/**`.

  **BLOCKING 3(c) — VT-015.** Re-confirmed no decorative meter is built
  (`RadioViewState.meterLevel` still constructed but never read by this
  screen). Documented the stricter-reading decision inline on the criterion
  and checked the box, per the finding's own suggested resolution.

  **Non-blocking (i)-(iv).** (i) Deleted the two genuinely dead `TalkCopy`
  constants (`channelBusy`, `emergencyActive`) — confirmed via grep they are
  referenced nowhere; the overlay chip's labels come from core-owned
  `OverlayCues` constants, never these. Wired the two that *should* have
  been used: `channelClear` and `microphonePermissionRequired` (see (ii)).
  (ii) Idle status line is now the full Design §5 copy, "Channel clear. Hold
  to talk." (was bare "Hold to talk" — `TalkCopy.holdToTalk` itself stays
  period-free since it doubles as Design §4's bare catalogue label for the
  Ready row); permission-denied status line now says "Microphone permission
  required" instead of falling through to the generic idle copy. (iii) Fixed
  as part of BLOCKING 3(a) above — overlay chip icon+colour are now per-cue.
  (iv) This round's commits all carry the `[TASK-051]` suffix; round-1's two
  non-conforming commits are already merged history on `master` and are not
  being rewritten to fix a commit-message nit.

  `flutter analyze` (repo-wide): clean except the same 8 pre-existing
  TASK-035 warnings, none in this territory. `flutter test` (full repo
  suite): 1182 passed, 0 failed, 40 skipped — 1168 round-1 baseline + 14 new
  (1 latch-remount test + 13 catalogue tests); the 40 skips are the
  unchanged, owner-parked FR-025 soak seeds. `flutter test
  test/features/talk/` in isolation: 37 passed (23 round-1 + 14 new).
  `flutter build apk --debug`: succeeded. Reverted the same two standing
  local-toolchain auto-edits (`analysis_options.yaml`, `android/
  gradle.properties`) before every commit, as every prior S5 task on this
  repo has disclosed.

  Status -> needs_review.
