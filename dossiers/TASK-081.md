# TASK-081 — Adopt the resolved route label in every UI call site

## Brief

ORCH re-carve of TASK-080's OWNERSHIP_CONFLICT block. TASK-080 fixed why the
effective route could stay `auto`, and added `ConnectionCondition.isResolved` /
`routeLabel`. Six UI call sites still format `effectiveRoute` themselves.
Route them all through the new label so AUTO never shows as an *effective* route.

## Spec pointers

- specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md §7; PRD UX-FR-002
- lib/core/presentation/connection_condition.dart (after TASK-080)
- dossiers/TASK-080.md (call-site list)

## Approach

1. Grep `lib/features/**` for `effectiveRoute` and `radioModeLabel(`.
2. Replace each effective-route rendering with `routeLabel`; leave the configured-mode labels alone.
3. Add unresolved/resolved widget tests per call site.
4. Regenerate only the goldens that actually change.

## Work Log

- [2026-09-11T12:50:48Z] [GB] Claimed. Preflight confirmed all 18 Owned_Paths exist.
- [2026-09-11T13:01:46Z] [GB] Routed every listed UI call site through
  `ConnectionCondition.routeLabel`. Configured-preference labels still use
  `radioModeLabel` / `SettingsCopy.modeOptionLabel` so AUTO remains valid as
  a preference. Latch-after-lift: `canLatch` and `_engageLatch` require
  `_holding && !_latched && phase == tx`; `_lastBuiltPhase` removed; leftover
  latch flag is cleared when phase leaves TX so red/"Transmission locked"
  cannot outlive a grant.
- [2026-09-11T13:01:46Z] [GB] Leftover `effectiveRoute` grep hits in
  `lib/features/**` that this task did **not** touch (outside Owned_Paths or
  not a display of `ConnectionCondition.effectiveRoute`): widget Keys
  (`ChannelsLandingKeys.effectiveRoute`, `SettingsKeys.effectiveRoute`),
  Settings copy/inventory field names, `event_qr_ui` join-route *logic*
  (parameter, not a label), and `lib/features/stations/README.md`.
- [2026-09-11T13:01:46Z] [GB] Goldens regenerated (pixels actually changed):
  settings_dark/light; stations_empty/populated dark+light; all 16 talk_*.png
  (idle/requesting/granted/receiving/degraded/emergency/permission_denied/
  service_fault × dark+light). channels_*.png unchanged. talk_granted_* had
  the largest delta because Lock no longer renders on a grant without hold.
- [2026-09-11T13:15:00Z] [GB] Rework round 1: leftover-latch cleanup now
  calls `RadioViewIntents.releaseLatch()` exactly once, via `ref.listen`
  (live tx→other) plus a post-frame callback (remount already out of TX).
  No mutation inside `build()`. LinkDegraded test: `releaseLatchCalls==1`
  and no red latched treatment. EndTransmit: at most one call, no stuck
  "Transmission locked". Mutation-check: dropping the release call made
  the LinkDegraded test fail (`Expected: <1> Actual: <0>`); restored.
  Non-blocking: (a) `membersLabel` switches on `isResolved`+`effectiveRoute`;
  (b) settings/about effective route uses title-case `modeOptionLabel` when
  resolved so it matches the configured-mode row; (c) blank import in
  stations_screen.dart removed; (d) `configuredDiffers` compares modes, not
  label strings. Goldens for settings/talk/stations/channels still match
  (effective-route row is below the settings golden crop).

## Changed goldens

- test/regression/goldens/goldens/settings_dark.png
- test/regression/goldens/goldens/settings_light.png
- test/regression/goldens/goldens/stations_empty_dark.png
- test/regression/goldens/goldens/stations_empty_light.png
- test/regression/goldens/goldens/stations_populated_dark.png
- test/regression/goldens/goldens/stations_populated_light.png
- test/regression/goldens/goldens/talk_idle_dark.png
- test/regression/goldens/goldens/talk_idle_light.png
- test/regression/goldens/goldens/talk_requesting_dark.png
- test/regression/goldens/goldens/talk_requesting_light.png
- test/regression/goldens/goldens/talk_granted_dark.png
- test/regression/goldens/goldens/talk_granted_light.png
- test/regression/goldens/goldens/talk_receiving_dark.png
- test/regression/goldens/goldens/talk_receiving_light.png
- test/regression/goldens/goldens/talk_degraded_dark.png
- test/regression/goldens/goldens/talk_degraded_light.png
- test/regression/goldens/goldens/talk_emergency_dark.png
- test/regression/goldens/goldens/talk_emergency_light.png
- test/regression/goldens/goldens/talk_permission_denied_dark.png
- test/regression/goldens/goldens/talk_permission_denied_light.png
- test/regression/goldens/goldens/talk_service_fault_dark.png
- test/regression/goldens/goldens/talk_service_fault_light.png

