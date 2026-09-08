# TASK-052 — Wire Wave 4 screens into the mobile app shell

## Brief

ORCH-created 2026-09-07 after TASK-049's review surfaced a real planning gap:
TASK-048 built the persistent shell with placeholder screen bodies and froze
`lib/app_shell/**` on merge, so none of the seven Wave 4 screen tasks
(TASK-049/050/051/053/054/055/056) — each correctly scoped to its own
`lib/features/<name>/**` — could ever mount its own real widget. This is the
single-owner convergence task that swaps every placeholder for the real
screen, mirroring the TASK-032/033→035→037 and TASK-041/042→043 pattern
already used twice in this plan. Do not touch `lib/features/**` — findings
there belong to that screen's own task record.

## Spec pointers

- `docs/adr/ADR-001-mobile-ux-redesign-reconciliation.md` §6 — the shell
  mounts real screens, owns no screen content itself.
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §2-§4 — persistent host
  survives navigation; navigation-shaped operations must not retune/dispose.
- `specs/KERYX_Mobile_UX_Redesign_PRD_v1.0.md` UX-D01/UX-D02 — Channels
  default landing, Channels+Settings required destinations.
- TASK-048's own dossier/Review_Findings — the branch-preservation test
  pattern (Talk pushed → Settings → back → Talk still on stack) to extend
  across all seven real screens, not just placeholders.

## Intended approach

1. Read each of TASK-049/050/051/053/054/055/056's final merged widget entry
   points (their dossiers' Artifacts sections name the top-level widget).
2. In `lib/app_shell/**` only, replace each placeholder screen reference with
   the real widget, wiring through whatever constructor parameters the real
   screen needs from `RadioViewState`/`RadioViewIntents`/`RadioHost`.
3. Extend TASK-048's branch-preservation `IndexedStack` test to push/pop
   through the real screens.
4. Re-verify (don't re-litigate) that no screen mounted here reaches past
   `RadioViewIntents`/`RadioHost` into transport/floor/audio/platform APIs —
   each screen's own review already checked this in isolation.
5. Full suite + analyze + debug APK build before `needs_review`.

## Work Log

- [2026-09-08T12:19:36Z] [GB] Session start. Claimed TASK-052, branch
  `task/TASK-052-gb` off master `7aaffd7`. Preflight pasted in PLAN.md.
  `test/app_shell/**` is not in Owned_Paths — flagged; proceeding with
  in-territory wiring.

- [2026-09-08T12:26:49Z] [GB] In-territory wiring landed on the branch
  (not yet `needs_review` — existing `test/app_shell` suite is red and
  this task cannot edit it).

  **Mounted widgets (all real Wave-4 entry points, none of TASK-048's
  stand-ins):**
  - TASK-049 `ChannelsLanding` — Channels destination, callbacks
    `onOpenTalk` / `onSelectChannel`.
  - TASK-051 `talkui.TalkScreen` — pushed from Open Talk; host injected.
  - TASK-050 `ChannelSelectorScreen` — from Channels `onSelectChannel`
    AND from Talk's picker overlay; `onCancel` pops.
  - TASK-055 `SettingsScreen` — Settings destination (replaces
    `BackPanelScreen`).
  - TASK-053 `StationsScreen` — from Talk stations overlay; `onScan` /
    `onExport` push TASK-056.
  - TASK-054 `RadioControlsScreen` — from a visible shell-owned Talk
    affordance (`ShellKeys.talkRadioControls`). Talk has no Radio
    Controls button at all.
  - TASK-056 `EventQrUiScanScreen` / `EventQrUiExportScreen` — from
    Stations' existing callbacks.

  **TASK-051 finding (not fixed here, per Description):**
  `lib/features/talk/talk_screen.dart` `_Header` picker/stations
  `onPressed` are empty no-ops with comments claiming the shell will
  wire them, but there are no callback parameters. Workaround in
  `lib/app_shell/talk_screen.dart`: invisible 48×48 overlays aligned to
  Talk's header geometry (`SafeArea` + 16/12 padding + 48 dp buttons)
  plus a visible Radio Controls `IconButton` at bottom-left. Prefer
  Talk growing `onSelectChannel` / `onOpenStations` /
  `onOpenRadioControls` callbacks in a successor; the overlay is a
  composition-root compensation, not a Talk edit.

  **Imports (criterion 5):** new files import only `RadioHost` + the
  seven screen widgets + theme tokens for the Radio Controls icon
  colour. No new `core/audio`, `core/floor`, `services/mesh`,
  `services/linked`, `services/platform` imports. (TASK-048's
  `radio_host_provider.dart` still has the production audio/platform
  factories — untouched.)

  **`flutter test test/app_shell` after the swap: 8 failed / 8 passed.**
  Failures are all placeholder-copy finders this task cannot edit:
  - `channels_screen_test`: `Current: CH 1 · Code 0`, `Recently tuned`
  - `talk_screen_test`: `PTT`, `Latch` (mic-permission cue case still
    passed — that copy survived)
  - `mobile_app_shell_test`: three cases tap `Current: CH 1 · Code 0`
    to open Talk (VT-001, re-tap pop, branch-preservation)

  **BLOCKING OWNERSHIP_CONFLICT:** need `test/app_shell/**` added to
  this task's Owned_Paths. Cannot put `flutter_test` files under
  `lib/app_shell/**` (`flutter analyze` / `flutter test` both refuse
  that). Full suite cannot go green, and criteria 1/3/6 cannot be
  evidenced, without retargeting those files.

  **Exact next step once `test/app_shell/**` is granted (same branch,
  do not re-claim):**
  1. `channels_screen_test.dart` — assert `find.byKey(ShellKeys.channelsLanding)`
     / `ChannelsLandingKeys.openTalk` / `selectChannel`; recents via
     `ChannelsLandingKeys.recentSection` ("Recent channels"); tap Open
     Talk → `find.byKey(ShellKeys.talk)`; tap Select channel →
     `find.byKey(ShellKeys.channelSelector)`.
  2. `talk_screen_test.dart` — drop placeholder `PTT`/`Latch` finders
     (real Talk is already covered in `test/features/talk/**`); keep a
     thin composition test: `TalkPttDisc` present, picker overlay
     (`ShellKeys.talkPickerHit`) pushes `ChannelSelectorScreen`,
     stations overlay pushes `StationsScreen`, Radio Controls button
     pushes `RadioControlsScreen`.
  3. `mobile_app_shell_test.dart` — replace every
     `find.text('Current: CH 1 · Code 0')` with
     `find.byKey(ChannelsLandingKeys.openTalk)` (or `find.text('Open Talk')`);
     replace `find.text('Talk')` with `find.byKey(ShellKeys.talk)`;
     extend the branch-preservation case to also push selector /
     Stations / Radio Controls / Event QR and switch Channels↔Settings
     with `startCalls == 1` / `disposeCalls == 0` / `tuneCalls` empty.
  4. Add a widget-tree case that each of the seven real types is
     `findsOneWidget` after the matching navigation.
  5. Revert-mutation: IndexedStack → bare `[...][_index]` (existing
     pattern); overlay `onTap` no-op; SettingsScreen → BackPanelScreen.
  6. `flutter analyze`, full suite, `flutter build apk --debug`.

  Wiring files: `lib/app_shell/shell_keys.dart`,
  `lib/app_shell/shell_routes.dart`, rewritten `channels_screen.dart` /
  `talk_screen.dart`, `mobile_app_shell.dart` Settings swap,
  `app_shell.dart` export.

- [2026-09-08T13:20:00Z] [GB] Resume after ORCH grant of `test/app_shell/**`.
  Same branch `task/TASK-052-gb` @ `b3d5d91` — no re-claim. Preflight
  against master PLAN.md (`--repo E:/DELL-PROJECTS/WALKIETALKIE`):

  ```
  [preflight] TASK-052 Owned_Paths inspected in E:/DELL-PROJECTS/WALKIETALKIE
  [preflight] 3 entr(y/ies). FILE/DIR/GLOB = exists, NEW = you are creating it.
    GLOB   lib/app_shell/**  -> 6 file(s):
             lib/app_shell/app_shell.dart
             lib/app_shell/channels_screen.dart
             lib/app_shell/legacy_compat.dart
             lib/app_shell/mobile_app_shell.dart
             lib/app_shell/radio_host_provider.dart
             lib/app_shell/talk_screen.dart
    GLOB   test/app_shell/**  -> 6 file(s):
             test/app_shell/app_theme_test.dart
             test/app_shell/channels_screen_test.dart
             test/app_shell/fake_radio_host.dart
             test/app_shell/legacy_compat_test.dart
             test/app_shell/mobile_app_shell_test.dart
             test/app_shell/talk_screen_test.dart
    FILE   dossiers/TASK-052.md  -> exists, 41 line(s), 2167 bytes
  [preflight] Paste this output into your first Progress_Note as the c8b9872 filesystem check.
  ```

  Master preflight lists 6 `lib/app_shell` files because `shell_keys.dart`
  / `shell_routes.dart` live only on this branch. Worktree `lib/app_shell`
  has those 8 files; `test/app_shell` is now in-territory. Retargeting
  placeholder finders and adding the criterion-1 widget-tree /
  criterion-3 branch-preservation cases.

- [2026-09-08T12:48:08Z] [GB] Tests retargeted; ready for review.

  **Widget-tree (criterion 1):** `ChannelsLanding`, `ChannelSelectorScreen`,
  `talkui.TalkScreen` + `TalkPttDisc`, `StationsScreen`,
  `RadioControlsScreen`, `SettingsScreen`, `EventQrUiScanScreen`,
  `EventQrUiExportScreen` each `findsOneWidget` after the matching
  navigation (`mobile_app_shell_test` "each Wave-4 screen type").

  **UX-D01/D02 (criterion 2):** Channels default landing; two
  NavigationDestinations; Settings is the other persistent destination.

  **Host survival (criterion 3):** `startCalls == 1`, `disposeCalls == 0`,
  `tuneCalls` empty across destination switches and selector / Stations /
  Radio Controls / Event QR pushes. IndexedStack branch-preservation
  extended to those real screens.

  **Selector (criterion 4):** reachable from Channels `selectChannel` AND
  Talk picker overlay.

  **Imports (criterion 5):** wiring files (not `radio_host_provider.dart`)
  contain none of `core/audio`, `core/floor`, `services/mesh`,
  `services/linked`, `services/platform`.

  **Talk header compensation (unchanged finding):** overlay hit-targets
  now carry `TalkCopy` semantics; Radio Controls remains a visible
  shell `IconButton`.

  **Revert-mutation (restored after each, `git diff` of
  `mobile_app_shell.dart` empty of residue):**
  1. IndexedStack → `[children][_index]` — branch-preservation fails
     (`shell.talk` Expected 1, Actual 0).
  2. picker overlay `onTap: () {}` — picker test fails
     (`shell.channel-selector` Found 0).
  3. `SettingsScreen` → `BackPanelScreen` — Wave-4 type test fails
     (`SettingsScreen` Found 0).
