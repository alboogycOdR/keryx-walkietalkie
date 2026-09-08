# TASK-068 — Replace Talk header overlay hack with real callback wiring

## Brief

ORCH-created 2026-09-08, closing a disclosed fragility from TASK-052's
review: `lib/app_shell/talk_screen.dart` intercepts Talk's picker/stations
header taps with invisible overlays positioned by hardcoded geometry,
because `TalkScreen` (TASK-051) never grew real callback parameters. The
reviewer proved this is a live risk (shifting the overlay 100dp left every
existing test green while a real-centre-tap probe failed) — a future Talk
layout change could silently break these buttons in production. Give
`TalkScreen` real callbacks, delete the overlays, and give Radio Controls a
proper header slot per Design §2.2 while in this territory.

## Spec pointers

- TASK-052's Review_Findings — the exact finding and its proof.
- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §2.2 — Talk header
  affordances, actual layout intent.

## Intended approach

1. Add `onOpenPicker`/`onOpenStations`/`onOpenRadioControls` constructor
   callbacks to `TalkScreen` (`lib/features/talk/**`).
2. In `lib/app_shell/talk_screen.dart`, wire the shell's real navigation
   through those callbacks; delete the geometry-matched overlay widgets.
3. Regression test: wrap Talk's header in extra padding (a test double) and
   confirm the callbacks still fire — this is the guard the overlay
   approach could never provide.
4. Move Radio Controls into a real header slot, not a bottom-left
   `IconButton` bolted onto the PTT area.
5. Full suite + analyze; revert-mutation the new regression test.

## Work Log

- [2026-09-08T17:45:00Z] [S5] Implemented per the plan above. `TalkScreen`
  (lib/features/talk/talk_screen.dart) gained `onOpenPicker`/
  `onOpenStations`/`onOpenRadioControls` nullable `VoidCallback` constructor
  params, wired to `_Header`'s existing picker/stations `IconButton`s plus a
  new third `IconButton` (key `keryx-talk-radio-controls`, `TalkCopy
  .openRadioControls` = "Radio controls") for the Radio Controls affordance
  Design §2.2's header now carries. `lib/app_shell/talk_screen.dart` was
  rewritten from a `Stack` of geometry-matched overlays (`_HeaderHitTarget`,
  a bottom-left `IconButton`) down to a single `talkui.TalkScreen(...)`
  construction with the three callbacks wired straight to
  `ShellRoutes.openSelector/openStations/openRadioControls`. Removed the
  three now-dead shell-owned keys (`talkPickerHit`/`talkStationsHit`/
  `talkRadioControls`) from `lib/app_shell/shell_keys.dart` — tests address
  the real header buttons by their own keys, matching every other
  `TalkScreen` control's existing convention. Updated
  `test/app_shell/talk_screen_test.dart` and
  `test/app_shell/mobile_app_shell_test.dart` to tap the real header keys
  instead of the deleted overlay hit targets (mechanical rename, same
  assertions). Added a TASK-068 regression group to
  `test/features/talk/talk_screen_test.dart`: wraps `TalkScreen`'s header in
  137px of extra `Padding` (a test double reproducing a future layout
  change) and taps each of the three header buttons by key, asserting the
  supplied callback fires exactly once — the actual guard the overlay
  approach could never give (it worked by coordinate-matching the shell's
  own hardcoded geometry to Talk's layout, not by a real callback), plus one
  test that a `null` callback renders the button disabled rather than
  crashing on tap.

  `flutter analyze` (repo-wide) -> 8 pre-existing TASK-035 warnings in
  `test/services/session/radio_session_controller_test.dart` only, zero
  issues under `lib/features/talk/**`, `lib/app_shell/**`,
  `test/features/talk/**` or `test/app_shell/**`. `flutter test` (full repo
  suite) -> 1364 passed, 0 failed, 40 skipped (unchanged owner-parked FR-025
  soak seeds). `flutter test test/features/talk/ test/app_shell/` in
  isolation -> 68 passed.

  Revert-mutation-checked 3 load-bearing guards: (a) removing the
  `onOpenPicker:` wiring line from `lib/app_shell/talk_screen.dart` —
  flipped exactly `test/app_shell/talk_screen_test.dart`'s "picker's real
  onOpenPicker callback pushes TASK-050 ChannelSelectorScreen" test red,
  nothing else, reverted clean; (b) hardcoding `_Header`'s picker
  `IconButton.onPressed` to `null` (ignoring the `onOpenPicker` param) —
  flipped exactly the new TASK-068 "onOpenPicker fires... after the header
  is wrapped in extra padding" test red, nothing else, reverted clean;
  (c) defaulting the Radio Controls `IconButton.onPressed` to `onOpenRadioControls
  ?? () {}` instead of the raw nullable callback — flipped exactly the new
  "a null callback renders the button disabled rather than throwing on tap"
  test red, nothing else, reverted clean. All three reverted immediately
  after, confirmed clean `git diff`. Reverted the standing local-toolchain
  auto-edits (`analysis_options.yaml`, `pubspec.lock`) before committing,
  per every prior S5 task's convention. Code committed on
  `task/TASK-068-s5` @ `27bc53f` — `[TASK-068]` suffix present. ->
  Status: needs_review.
