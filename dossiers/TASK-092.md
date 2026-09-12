# TASK-092 — v2 Talk — target card, audience-aware ready ring, honest lone-press refusal, status control, Alert banner

## Brief

Rework the Talk screen for v2 targets. `TalkChannelCard` → `TalkTargetCard`: avatar/glyph, name, presence line (`Ben · Available · Nearby` / `Site crew · 4 of 12 online`), own-status control (Available/Busy/DND/appear offline) on the right, chevron → `onOpenTarget`. No-target state replaces the ring with the 'Add your first contact / Create a group' card. Ring ready rule from `RadioViewState.audience` (V2-FR-041); a press with `canHear == 0` is refused locally, never calls `press()`, and reuses the TASK-082 flash with the audience reason as copy (V2-FR-044). Alert-received banner (10 s, Reply). Remove every channel/route string. All VT-010..015 safety logic stays untouched.

## Spec pointers

- specs/KERYX_v2.0_Design_v1.0.md §2.1, §4; PRD V2-FR-040..045, V2-FR-033; Verification V2-VT-022 (UI half), V2-VT-024, V2-VT-030 (talk goldens); ADR-002 A3/A7 (ring and flash carried)
- Owned_Paths: lib/features/talk/**, test/features/talk/**, test/regression/goldens/goldens/talk_*.png, test/regression/goldens/talk_states_golden_test.dart, dossiers/TASK-092.md
- Depends_On: TASK-088

## Work Log

- [2026-09-12T09:00:00Z–~10:40:00Z] [S5] Implemented additively/replacively within Owned_Paths:
  - `lib/features/talk/talk_target_card.dart` (new): `TalkTargetCard` (avatar/glyph, name, presence line, own-status `PopupMenuButton`, chevron `onOpenTargetDetail`) and `TalkNoTargetCard` (Add contact / Create group).
  - `lib/features/talk/talk_screen.dart`: added `target`/`presenceByPeerId`/`ownStatus`/`onSetOwnStatus`/`onOpenTargetDetail`/`onAddContact`/`onCreateGroup`/`onAlertTarget`/`pendingAlert`/`onReplyToAlert`/`onDismissAlert` params; `RadioViewState.project` now receives `target`/`presenceByPeerId`; ring treatment/readiness driven by `viewState.audience.canHear` (V2-FR-041); `_handleHoldStart` refuses a press locally when `canHear == 0` (never calls `intents.press()`), reusing the 1.5s flash pattern via a new `_audienceRefusalTimer` alongside the existing host-driven `_deniedFlashTimer`; `_targetOnDndLabel()` computes Design's exact "X is on Do Not Disturb" copy directly from presence (not through `AudienceState.reason`, since that type lives in TASK-088's territory and its own wording differs slightly); new `TalkAlert` class + `_AlertBanner` widget + `_syncAlertTimer` (10s auto-dismiss via `onDismissAlert`).
  - `lib/features/talk/talk_copy.dart`: removed every v1 channel/route string (`channelBusy`→`someoneAlreadyTransmitting`, `channelClear`→`readyToTalk`, `requestingChannel` text de-channeled, `noOtherStations*`/`rosterUnavailable`/`openChannelPicker`/`openRadioControls`/`openStations` deleted); added `nobodyIsListening`, `noTargetHeadline`, `addFirstContact`, `createAGroup`, `ownStatus`, `openTargetDetail`, `alert`, `reply`.
  - Deleted `lib/features/talk/talk_channel_card.dart` (replaced by `talk_target_card.dart`) and its test.
  - `test/features/talk/talk_screen_test.dart`: rewritten in place — default test harness now injects a solo-reachable `TalkTarget` (so every existing VT-010..015/ADR-002 A3/A7 test keeps its intent unmodified: a reachable target's `AudienceState` is `canHear: 1`, matching the v1 `everyoneReachable` default exactly); obsolete route/roster/picker-only assertions replaced with v2-equivalents; new groups for audience refusal, DND row, Alert banner.
  - `test/features/talk/talk_target_card_test.dart` (new): unit coverage for both cards in isolation.
  - `test/regression/goldens/talk_states_golden_test.dart` + `test/regression/goldens/goldens/talk_*.png`: regenerated (every existing state's header card is now taller/different; three new states added — no-target, nobody-listening, alert-banner — dark+light).

- **Disclosed compat decision (read before touching this file again):** `lib/app_shell/**` (TASK-093's Owned_Paths) still mounts `TalkScreen` without a `target` and still wires `onOpenPicker`/`onOpenStations` to a real channel-selector/Stations-tab switch — none of that is in this task's territory to change. A first pass that literally followed Design §2.1 ("no-target state replaces the ring") and dropped the picker/stations buttons broke 17 tests outside `test/features/talk/**` (`test/app_shell/**`, `test/regression/goldens/shell_frame_golden_test.dart`, `test/regression/layout_matrix_test.dart`, plus assorted others via cascading pends). Resolved, in order of preference:
  1. `pttGroup` (the ring/status/latch cluster) always mounts now, regardless of `target` — a `null` target still projects to `AudienceState.everyoneReachable` (TASK-088's own v1-safe-default pattern), so the ring behaves exactly as it did pre-this-task when no target is wired. Only the header card swaps between `TalkTargetCard`/`TalkNoTargetCard`.
  2. `onOpenPicker`/`onOpenStations` are still accepted and, when non-null, still render real `keryx-talk-picker`/`keryx-talk-stations` icon buttons on whichever header card is showing (tooltip text removed — no "channel"/"station" copy).
  3. `TalkTargetCard`/`TalkNoTargetCard` share the legacy `keryx-talk-channel-card` key on their outer container (they're mutually exclusive, never mounted together) so `test/regression/layout_matrix_test.dart`'s geometry check still locates "the header card".
  - After (1)-(3): repo-wide `flutter test` dropped from 17 failures to 2, both `test/regression/goldens/shell_frame_golden_test.dart` (Talk tab, dark+light) — a genuine, unavoidable pixel diff from Talk's header actually looking different per Design §2.1, on a golden file this task does not own (`test/regression/goldens/goldens/shell_frame_*.png` is TASK-093's `Owned_Paths`). Only TASK-093 can regenerate it, and it depends on this task, so it will do so as part of its own rewiring. Not force-closed by touching an out-of-territory file.

- **Full-repo verification (all four gates re-run in the foreground after the above fix, not just the targeted package):**
  - `flutter analyze --no-pub` (full repo): No issues found.
  - `flutter test --no-pub` (full repo): 1722 passed, 2 failed (both `shell_frame_golden_test.dart`, disclosed above, TASK-093 territory), 40 skipped (same PARKED FR-025 soak seeds, unmodified) — baseline was 1697 passed / 0 failed / 40 skipped.
  - `flutter test --no-pub test/features/talk test/regression/goldens/talk_states_golden_test.dart`: 116/116 passed.
  - `git diff --stat -- . ':!PLAN.md'`: every changed/added/deleted file is inside Owned_Paths (`lib/features/talk/**`, `test/features/talk/**`, `test/regression/goldens/goldens/talk_*.png`, `test/regression/goldens/talk_states_golden_test.dart`).

