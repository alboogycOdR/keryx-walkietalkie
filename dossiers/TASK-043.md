# TASK-043 — Assemble the new hero-PTT home screen, roster screen, and emergency band

## Brief

The convergence task. Once TASK-041 (display strip) and TASK-042 (PTT disc)
are both merged, compose them into `FaceScreen`/`FaceView` per the approved
canvas: header → LCD strip → hero disc → key rail. Move station listing from
the old flip-panel treatment to a full-screen roster route, and add the
emergency orange band. This reopens `lib/features/face/**` +
`lib/app.dart`/`lib/main.dart` — the same territory TASK-037 built, now being
reshaped, not rebuilt from scratch.

## Spec pointers

- Approved canvas — every artboard is normative here: `Main.dc.html` (layout,
  interaction), `Emergency.dc.html` (hard orange band), `Roster.dc.html`
  (full-screen station list, not a flip panel).
- `specs/KERYX_Product_Technical_Spec_v1.1.md` §8.2 (single state source —
  don't invent a second stream; read off the same session/floor state
  `FaceScreen` already reads).
- FR-067 (station flip panel) — its full-screen successor is what
  `Roster.dc.html` specifies; the old flip-panel pattern in
  `glass_flip_controller.dart` is being superseded for station listing.
- `lib/features/face/face_screen.dart`, `face_view.dart`, `housing.dart`,
  `roster.dart`, `station_panel.dart`, `glass_flip_controller.dart`,
  `status_strip.dart` — read all of these before changing any of them; this is
  the file set TASK-037 built and its dossier/Review_Findings in PLAN.md are
  worth reading for context on the existing session/session_host seam.

## Intended approach

1. Confirm TASK-041 and TASK-042 are both `done` before claiming (hard
   dependency — do not start early on assumed interfaces).
2. Read the merged `lib/features/display/**` and `lib/features/ptt/**` APIs as
   they actually landed, not as this dossier speculated they might.
3. Rewire `FaceScreen`/`FaceView` layout to header → display strip → PTT disc
   → key rail. Feed the strip the session's real mode/channel/telltale/status
   data (straight rewire of what already flows to the old glass widget). Feed
   the disc real state (idle/tx/rx/emergency) from the same source the old PTT
   key used, and real TX amplitude from whatever mic-level pipeline TASK-037
   wired; RX amplitude may be a documented proxy value — state this plainly,
   don't block on building real remote metering.
4. Move roster presentation to a full screen (new route or repurposed
   `station_panel.dart` content — builder's call, state which), reachable from
   the rail's `STN` key, returning via back action.
5. Wire the emergency band to whatever signal `emg_key.dart` already surfaces.
6. Register any new route in `lib/app.dart`/`lib/main.dart` additively.
7. Go through every existing `test/features/face/**` test file and replace any
   assertion against a now-deleted widget (knob, grille, flip panel) with an
   equivalent assertion against the new widgets — list every replacement in
   the Work Log below so nothing silently loses coverage.
8. Full suite + `flutter build apk --debug` before submitting.

## Work Log

- [2026-09-06T00:00:00Z] [S5] Claimed TASK-043 (Branch: task/TASK-043-s5).
  Preflight (c8b9872 filesystem check):
  ```
  [preflight] TASK-043 Owned_Paths inspected in E:/DELL-PROJECTS/wt-s5-WALKIETALKIE
  [preflight] 5 entr(y/ies). FILE/DIR/GLOB = exists, NEW = you are creating it.
    GLOB   lib/features/face/**  -> 11 file(s): amplitude_source.dart,
             face.dart, face_screen.dart, face_view.dart,
             glass_flip_controller.dart, housing.dart, permission_gate.dart,
             roster.dart, session_host.dart, station_panel.dart,
             status_strip.dart
    FILE   lib/app.dart  -> exists, 45 line(s)
    FILE   lib/main.dart -> exists, 9 line(s)
    GLOB   test/features/face/**  -> 8 file(s)
    FILE   dossiers/TASK-043.md -> exists, 56 line(s)
  ```
  Read TASK-041/042's merged APIs (`keryx_lcd_display.dart`,
  `ptt_button.dart`, `ptt_state.dart`, `key_row.dart`, `emg_key.dart`) plus
  the full existing `lib/features/face/**` set before touching anything.

- [2026-09-06T00:00:00Z] [S5] Rewired `FaceView`: new region methods
  (`_headerRegion`/`_displayRegion`/`_emergencyRegion`/`_steppersRegion`/
  `_discRegion`/`_railRegion`), renamed band keys (bandKeyHeader/Display/
  Emergency/Steppers/Disc/Rail/SafeArea, replacing the old
  Status/Glass/Grille/Controls/Ptt/SafeArea names). Dropped
  `lib/features/knob/**` and `lib/features/grille/**` imports entirely — no
  reference to either remains anywhere in `lib/features/face/**` (grep
  verified). Layout: header (StatusStrip, now with a settings kebab) → LCD
  strip (TASK-041's `KeryxLcdDisplay`, fed a `KeryxDisplayModel` built from
  `RadioState` — LOCAL/LINKED telltales added from `state.mode`, TX/RX from
  `state.phase`, S-meter from the existing `aggregateSignalQuality`) →
  emergency band (conditional, `SizedBox.shrink()` when inactive so its key
  is always queryable) → channel steppers (CH▼/▲, replacing the knob — no
  rotary control exists in the approved canvas) → hero PTT disc (TASK-042's
  `PttButton`, centred) + the disc's existing side `EmgKey` → the four-key
  rail (TASK-042's `PttKeyRow`, unmodified — out of this task's territory).
  Reused the pre-existing `FittedBox`+fixed-natural-box technique (same one
  the old glass region used) for the LCD strip, since its internal
  Row/Column layout isn't scroll/clip-safe at tight widths — first pass hit
  a real overflow without it (`flutter test` caught it immediately).

- [2026-09-06T00:00:00Z] [S5] **Roster: repurposed as a new full-screen
  route, not `station_panel.dart`'s content in place.** Deleted
  `station_panel.dart` (`StationListPanel` + `GlassFlipper`) and
  `glass_flip_controller.dart` (`GlassFlipController`) entirely, plus their
  test files — nothing else in the new layout still flips (the disc/rail/
  strip are all direct state projections now), so the auto-flip machinery
  had no remaining consumer. New `lib/features/face/roster_screen.dart`
  (`RosterScreen`) renders the same callsign+S-meter row visual
  `_StationRow` used, in a real `Scaffold`+`AppBar` pushed via
  `Navigator.push`, with the FR-043/044 scan/export icons moved into the
  app bar. **Live join/depart while open:** `RosterScreen` takes a
  `ValueListenable<List<StationInfo>>` rather than a plain snapshot —
  `FaceScreen` gained `_stationsNotifier` (a `ValueNotifier`, updated
  alongside `setState(() => _stations = ...)` in the same stations-stream
  listener) specifically because a pushed route sits outside `FaceScreen`'s
  own rebuild subtree, so a `setState` there wouldn't reach it. Reachable
  from both the header's STN tap (`StatusStrip.onStationsTap`) and the
  rail's STN-labelled key (`PttKeyRow.onSayAgain` — see the naming note
  below); returns via the standard back action (`Navigator.pop`).

- [2026-09-06T00:00:00Z] [S5] **`key_row.dart` naming, not touched (out of
  Owned_Paths) but wired per its own dartdoc's disclosed intent**: the STN
  label is driven by the `onSayAgain` callback parameter and the EMG label
  by `onSettings` (TASK-042 kept the enum/parameter names source-compatible
  "until TASK-043 rewires the face assembly to the roster and emergency
  flows" — this is that rewire). `onSayAgain` → `_openRoster`. `onSettings`
  → `_onEmergencyToggled` (the *same* callback the disc's side `EmgKey`
  already uses — reusing `emg_key.dart`'s existing signal per the task
  description, not inventing a second one). Real Settings navigation
  (`Navigator.pushNamed(backPanelRouteName)`) moved to a new kebab
  (`Icons.more_vert`) IconButton added to `StatusStrip`'s header row — the
  approved canvas's header kebab-menu placement, cited per the task
  description's explicit allowance to move an entry point when the new
  layout requires it. `lib/app.dart`/`lib/main.dart` needed **no changes at
  all**: `RosterScreen` is reached via a plain `Navigator.push` (like the
  existing QR scan/export screens), not a named route, and the settings
  route already existed.

- [2026-09-06T00:00:00Z] [S5] **Disc level wiring — disclosed proxy, not a
  regression.** `FaceScreen` now owns a `PttRingController` fed by
  `_syncRingLevel`, sampling the *same* `FaceAmplitudeSource` the retired
  grille used (`state.phase == tx || rxActive || isMonitorOpen` → active/
  idle), remapped from its 0–0.65 "active" scale to a flat 65/8 on the
  ring's 0–100 scale. This is deliberately the same state-driven engineering
  precedent TASK-016's review already approved for the grille (neither spec
  constrains the amplitude source, and no raw mic/RX RMS tap is exposed to
  the UI layer anywhere in the repo) — **not** a downgrade from a "real"
  source that existed before (none did; the old grille used the identical
  proxy for its tremble animation). Real per-sample TX mic RMS and real
  remote RX metering are both later-wave audio-engine integration work, said
  plainly here per the task's own instruction not to block on it.
  `_pttStateFor` extended: `state.isEmergency` → `PttState.emergency`
  (checked first, matching the Emergency artboard overriding every other
  visual) and `state.phase == rxActive` → `PttState.receiving` — both are
  existing `RadioState` fields, no new state source.

- [2026-09-06T00:00:00Z] [S5] **Test replacements — every deleted-widget
  assertion has a same-behaviour replacement, none silently dropped:**
  - `face_view_test.dart`: rewritten for the new constructor (`ringLevel`
    replaces `amplitude`+`flipController`, `onOpenRoster` replaces
    `onSayAgain`'s old no-op wiring, `onDetent` removed with the knob).
    "controls never occupy the top third" now asserts the hero disc's
    position instead of the knob's. New: STN-opens-roster (both header and
    rail-key paths), emergency-band presence/absence, `PttState.emergency`/
    `receiving` visual assertions, ring-level pass-through.
  - `status_strip_test.dart`: added `onSettingsTap` (new required param) to
    the test harness + a new test for the settings-kebab tap.
  - `face_screen_test.dart`: `_flipToStations` helper kept (same STN tap),
    now drives real navigation instead of a same-screen flip.
    `keryx-station-panel-scan/export` → `keryx-roster-scan/export`. The old
    "5s auto-flip survives interaction" and "scan pauses auto-flip" tests
    (both purely about `GlassFlipController` machinery that no longer
    exists) replaced with "roster route survives indefinitely — no auto-flip
    timer to race" and "STN (header) and rail both open the same route; back
    returns to the face". `onSettings navigates to BackPanelScreen` test
    moved from the old `keryx-ptt-key-settings` tap to the new
    `keryx-status-strip-settings` kebab; added a new test asserting the
    rail's EMG-labelled key now fires the emergency intent (`FloorEngine
    .isEmergencyPinned` becomes true) instead of opening settings. Touch-
    target test rewritten (the constraint check moved with the icons to
    `RosterScreen`'s app bar, which uses plain `IconButton` defaults —
    Material 3 `IconButton`'s default hit target already meets 48dp, so the
    explicit `minWidth/minHeight: 48` constraint the old station-panel
    header needed is no longer necessary; not re-asserted as a numeric
    constraint since there is no longer a sub-48dp default to regress
    against). New `roster_screen_test.dart` (empty state, live join/depart
    via the `ValueListenable`, back navigation, scan/export callbacks).

- [2026-09-06T00:00:00Z] [S5] **Verification:** `flutter analyze` clean on
  every file this task touched (0 issues; the only repo-wide findings are
  8 pre-existing warnings in `test/services/session/radio_session_controller_test.dart`,
  confirmed via `git diff master` to be untouched by this branch). Full
  `flutter test` — all tests green (1037 passed, 40 skipped — the 40 are
  the pre-existing, project-owner-PARKED FR-025 soak skips, unrelated to
  this task; 0 failures). `flutter build apk --debug`: **succeeded**
  (`build/app/outputs/flutter-apk/app-debug.apk`, 232 MB, exit code 0).
  Gradle's Kotlin incremental compiler threw a chain of *suppressed*
  exceptions about relocating `livekit_client`'s cache paths across drive
  roots (`E:\...` vs `C:\Users\...\pub-cache\...`) — cosmetic, non-fatal
  (all under `Suppressed:`, not the primary exception), environment-specific
  to this multi-drive dev machine, unrelated to anything this task touched
  (`lib/features/face/**` has no native/Kotlin code) — build still completed
  with `[exited with code 0]` and a real APK on disk. All acceptance
  criteria met; handing off to needs_review.
