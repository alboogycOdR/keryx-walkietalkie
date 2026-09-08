# TASK-054 — Radio controls and guarded emergency

## Brief

Secondary radio functions move off the main surface into a labelled controls
screen, replacing the legacy four-key rail's role without reusing its widgets.
Monitor keeps hold-to-open; scan shows authoritative state and eligibility;
locked or unimplemented capabilities explain themselves rather than appearing
enabled. Emergency gets a separate orange/priority treatment with a guarded
activation and an explicit clear, preserving the existing hold duration and
floor semantics exactly.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §2.5, §4 (Emergency row).
- PRD UX-FR-041/042/043/044, UX-D06; Verification VT-013, §8 (no location or
  emergency-service claims).
- `specs/KERYX_Product_Technical_Spec_v1.1.md` §8.2/§8.6 — arbitration and
  emergency semantics preserved.
- ADR-001 §5 — **FR-025 emergency-preemption double-grant stays PARKED.**

## Approach

Indicators are driven only by authoritative state — test both directions (state
lights it; local interaction alone does not). The intake risk register names this
task as the one most likely to drift into FR-025; if emergency behaviour looks
wrong at the engine level, record a finding and stop. Emergency renders as an
overlay that never conceals the actual floor phase.

## Work Log

- [2026-09-08T18:10:00Z] [S5] Implemented. Research (recorded in PLAN.md
  Progress_Notes) confirmed neither `RadioHost` nor `RadioViewIntents`
  expose Monitor/Scan/VOX/Replay entry points — a real architecture gap,
  not an oversight of this task. `lib/features/radio_controls/**`:
  - `radio_controls_copy.dart` — `RadioControlsCopy` (same
    `abstract final class` convention as `ChannelSelectorCopy`/
    `StationsCopy`).
  - `radio_controls_screen.dart` — `RadioControlsScreen`, host-injected
    (mirrors `TalkScreen`'s constructor-injection rule, not
    `StationsScreen`'s ambient-provider read). Renders **only** Monitor,
    Scan and Emergency — Latch is PTT-hold-scoped
    (`TalkScreen`'s `TalkLatchState`) and VOX/Replay have zero production
    trigger path anywhere in the repo (`RadioStateBridge.updateVox`/
    `updateReplay` are telemetry-*ingress* only), so per acceptance
    criterion 1 ("unimplemented entries are absent, not faked") they are
    omitted entirely rather than shown disabled.
  - Monitor/Scan dispatch `MonitorChanged`/`ScanChanged` via
    `ref.read(radioStateProvider.notifier).dispatch(...)` — the exact same
    mechanism the legacy (still-shipped, dev-route-only)
    `face_screen.dart` already uses today, and the only existing
    production precedent for driving these two events; not a second,
    competing pattern. Both are pure reducer `copyWith` transitions with no
    session/transport side effect. Eligibility (both the UI-attachment
    gate and an internal guard inside the handler — defense in depth,
    each independently mutation-checked below) is phase-derived:
    ineligible during off/boot/tuning/txRequest/tx, with a `state/warning`
    explanation row rendered whenever ineligible (UX-FR-044).
  - Emergency uses `RadioHostSnapshot.floorEngine` directly — the
    sanctioned direct-access seam its own dartdoc names for exactly this
    case — reusing `face_screen._onEmergencyToggled`'s existing
    grant/clear branches **verbatim**: `requestTransmit(emergency: true)`
    after a 600ms hold-arm (same constant `EmgKey.armThreshold` already
    uses — preserved, not re-chosen), `clearEmergency()` gated owner-only
    exactly as `FloorEngine.clearEmergency` already enforces. A
    `FloorEngine.effects` subscription (`EmgPinned`/`EmgCleared`) keeps the
    indicator authoritative for a *remotely*-raised emergency too, not
    just a locally-initiated arm (UX-FR-043: "never from local widget
    state"). No location or emergency-service claim anywhere in copy
    (Verification §8). FR-025 untouched — this screen only reads/writes
    through the same `requestTransmit`/`clearEmergency` calls the legacy
    UI already made; no floor-arbitration logic was touched, modified or
    re-tested.
  - `test/features/radio_controls/fake_radio_host.dart` — same shape as
    `test/features/talk/fake_radio_host.dart` (local per-feature copy,
    repo convention).
  - `test/features/radio_controls/radio_controls_screen_test.dart` — 11
    widget tests covering every acceptance criterion: only-implemented-rows
    (criterion 1), Monitor hold-open/close + authoritative-state-not-local
    + ineligible-explains-itself (2/3/4), Scan toggle + ineligible (2/3/4),
    Emergency 600ms arm-activates/under-duration-does-not/owner-clears/
    non-owner-blocked-with-reason/no-location-or-service-claim (5/6/7/8).
  Revert-mutation-checked 4 load-bearing pieces, each isolated:
  (a) removing the eligibility guard from *both* the UI-attachment layer
  (`eligible ? ... : null`) and the internal handler guard together —
  flipped exactly the two "ineligible... no-op" tests, nothing else;
  removing only one layer alone flipped nothing (the other layer alone is
  already sufficient — genuine two-layer defense-in-depth, each layer
  individually redundant with the other, both together the only way to
  observe a gap); (b) removing the `FloorEngine.effects` subscription
  entirely — flipped exactly the non-owner-remote-pin test (the one
  scenario with no local arm gesture to otherwise trigger a rebuild),
  nothing else; (c) changing `emergencyHoldDuration` from 600ms to
  1000ms — flipped exactly the two tests whose assertions depend on the
  600ms boundary (the 650ms-activates test and the owner-clear test that
  builds on it), nothing else. All three reverted immediately after,
  confirmed clean `git status`/`flutter analyze` afterward.
  `flutter analyze` (repo-wide) -> 8 pre-existing TASK-035 warnings in
  `test/services/session/radio_session_controller_test.dart` only, zero
  issues under `lib/features/radio_controls/**` or
  `test/features/radio_controls/**`. `flutter test` (full repo suite) ->
  1261 passed, 0 failed, 40 skipped (unchanged owner-parked FR-025 soak
  seeds; baseline before this task was 1250, delta +11 = exactly this
  task's new tests). `flutter test test/features/radio_controls/` in
  isolation -> 11 passed. Reverted the standing local-toolchain auto-edit
  to `analysis_options.yaml` before committing (no `android/gradle.properties`
  auto-edit this run). -> Status: needs_review.
