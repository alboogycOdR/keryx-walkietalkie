# TASK-094 — v2 deletions — channels, selector, stations, numbered Event QR, legacy face/ptt/display/settings_panel

## Brief

Delete what v2 replaced, after the shell no longer references it. Before deleting each module, list in the dossier every behavioural test it carried and where the surviving behaviour is now tested (Verification §0 rule); only presentation-only tests are dropped. `radio_controls` survives only if the shell still pushes it — if TASK-093 kept it, keep the module and drop it from this task's deletion list in the dossier; `tuning/` haptics that Talk still uses must be moved into `lib/features/talk/` by TASK-092 first (coordinate via the dossier, do not edit talk). Event QR: the keyed invite path now lives in TASK-091's groups feature; delete both `event_qr` directories. Then run V2-VT-028 repo-wide.

## Spec pointers

- specs/KERYX_v2.0_Technical_v1.0.md §6.2, §8 (legacy face folds in); PRD §1 (removed), §5.5; Verification V2-VT-028; ADR-001 §6 retirement list; ADR-003 consequences
- Owned_Paths: lib/features/channels/**, lib/features/channel_selector/**, lib/features/stations/**, lib/features/event_qr/**, lib/features/event_qr_ui/**, lib/features/face/**, lib/features/ptt/**, lib/features/display/**, lib/features/settings_panel/**, lib/features/tuning/**, lib/features/radio_controls/**, lib/features/features.dart, test/features/channels/**, test/features/channel_selector/**, test/features/stations/**, test/features/event_qr/**, test/features/event_qr_ui/**, test/features/face/**, test/features/ptt/**, test/features/display/**, test/features/settings_panel/**, test/features/tuning/**, test/features/radio_controls/**, test/regression/goldens/goldens/channels_*.png, test/regression/goldens/goldens/stations_*.png, test/regression/goldens/goldens/selector_*.png, test/regression/goldens/goldens/qr_*.png, test/regression/goldens/goldens/radio_controls_*.png, test/regression/goldens/channels_golden_test.dart, test/regression/goldens/stations_golden_test.dart, test/regression/goldens/selector_golden_test.dart, test/regression/goldens/event_qr_golden_test.dart, test/regression/goldens/radio_controls_golden_test.dart, dossiers/TASK-094.md
- Depends_On: TASK-093

## Work Log

- [2026-09-12T08:08:02Z] [GB] Claimed. Branch `task/TASK-094-gb` off master `d892ce7`.
- [2026-09-12T08:11:23Z] [GB] **OWNERSHIP_CONFLICT — stopped before any deletion.** Preflight confirmed every Owned_Paths glob exists. Grep of master `lib/` + `test/` after TASK-093 shows the modules this task is asked to delete are still imported from files outside Owned_Paths. Deleting them would not compile. Not improvising shims. Detail also in PLAN.md Progress_Notes. Full preflight:

```
[preflight] TASK-094 Owned_Paths inspected in C:/CLAUDECODE_TOOLSETS/wt-grok-walkietalkie-keryx
[preflight] 34 entr(y/ies). FILE/DIR/GLOB = exists, NEW = you are creating it.
  GLOB   lib/features/channels/**  -> 6 file(s):
           lib/features/channels/README.md
           lib/features/channels/channel_format.dart
           lib/features/channels/channel_memory.dart
           lib/features/channels/channels.dart
           lib/features/channels/channels_landing.dart
           lib/features/channels/presentation_icons.dart
  GLOB   lib/features/channel_selector/**  -> 4 file(s):
           lib/features/channel_selector/channel_selector_copy.dart
           lib/features/channel_selector/channel_selector_screen.dart
           lib/features/channel_selector/channel_validation.dart
           lib/features/channel_selector/tune_coordinator.dart
  GLOB   lib/features/stations/**  -> 5 file(s):
           lib/features/stations/README.md
           lib/features/stations/station_copy.dart
           lib/features/stations/station_identity.dart
           lib/features/stations/stations.dart
           lib/features/stations/stations_screen.dart
  GLOB   lib/features/event_qr/**  -> 5 file(s):
           lib/features/event_qr/README.md
           lib/features/event_qr/event_link.dart
           lib/features/event_qr/event_qr.dart
           lib/features/event_qr/qr_export_screen.dart
           lib/features/event_qr/qr_scan_screen.dart
  GLOB   lib/features/event_qr_ui/**  -> 5 file(s):
           lib/features/event_qr_ui/event_qr_join_coordinator.dart
           lib/features/event_qr_ui/event_qr_permission_gate.dart
           lib/features/event_qr_ui/event_qr_ui_copy.dart
           lib/features/event_qr_ui/event_qr_ui_export_screen.dart
           lib/features/event_qr_ui/event_qr_ui_scan_screen.dart
  GLOB   lib/features/face/**  -> 10 file(s):
           lib/features/face/amplitude_source.dart
           lib/features/face/face.dart
           lib/features/face/face_screen.dart
           lib/features/face/face_view.dart
           lib/features/face/housing.dart
           lib/features/face/permission_gate.dart
           lib/features/face/roster.dart
           lib/features/face/roster_screen.dart
           lib/features/face/session_host.dart
           lib/features/face/status_strip.dart
  GLOB   lib/features/ptt/**  -> 8 file(s):
           lib/features/ptt/README.md
           lib/features/ptt/edge_glow.dart
           lib/features/ptt/emg_key.dart
           lib/features/ptt/key_row.dart
           lib/features/ptt/ptt.dart
           lib/features/ptt/ptt_button.dart
           lib/features/ptt/ptt_haptics.dart
           lib/features/ptt/ptt_state.dart
  GLOB   lib/features/display/**  -> 3 file(s):
           lib/features/display/README.md
           lib/features/display/display.dart
           lib/features/display/keryx_lcd_display.dart
  GLOB   lib/features/settings_panel/**  -> 8 file(s):
           lib/features/settings_panel/back_panel_screen.dart
           lib/features/settings_panel/settings_copy.dart
           lib/features/settings_panel/settings_panel.dart
           lib/features/settings_panel/widgets/panel_picker_row.dart
           lib/features/settings_panel/widgets/panel_section.dart
           lib/features/settings_panel/widgets/panel_stepper_row.dart
           lib/features/settings_panel/widgets/panel_text_row.dart
           lib/features/settings_panel/widgets/panel_toggle_row.dart
  GLOB   lib/features/tuning/**  -> 7 file(s):
           lib/features/tuning/README.md
           lib/features/tuning/channel_recall.dart
           lib/features/tuning/keypad_sheet.dart
           lib/features/tuning/stepper_button.dart
           lib/features/tuning/tuning.dart
           lib/features/tuning/tuning_haptics.dart
           lib/features/tuning/tuning_physics.dart
  GLOB   lib/features/radio_controls/**  -> 2 file(s):
           lib/features/radio_controls/radio_controls_copy.dart
           lib/features/radio_controls/radio_controls_screen.dart
  FILE   lib/features/features.dart  -> exists, 1 line(s), 72 bytes
  GLOB   test/features/channels/**  -> 4 file(s):
           test/features/channels/channel_format_test.dart
           test/features/channels/channel_memory_test.dart
           test/features/channels/channels_landing_test.dart
           test/features/channels/fake_radio_host.dart
  GLOB   test/features/channel_selector/**  -> 4 file(s):
           test/features/channel_selector/channel_selector_screen_test.dart
           test/features/channel_selector/channel_validation_test.dart
           test/features/channel_selector/fake_radio_host.dart
           test/features/channel_selector/tune_coordinator_test.dart
  GLOB   test/features/stations/**  -> 3 file(s):
           test/features/stations/fake_radio_host.dart
           test/features/stations/station_identity_test.dart
           test/features/stations/stations_screen_test.dart
  GLOB   test/features/event_qr/**  -> 3 file(s):
           test/features/event_qr/event_link_test.dart
           test/features/event_qr/qr_export_screen_test.dart
           test/features/event_qr/qr_scan_screen_test.dart
  GLOB   test/features/event_qr_ui/**  -> 5 file(s):
           test/features/event_qr_ui/event_qr_join_coordinator_test.dart
           test/features/event_qr_ui/event_qr_ui_export_screen_test.dart
           test/features/event_qr_ui/event_qr_ui_scan_screen_test.dart
           test/features/event_qr_ui/fake_permission_gate.dart
           test/features/event_qr_ui/fake_radio_host.dart
  GLOB   test/features/face/**  -> 7 file(s):
           test/features/face/amplitude_source_test.dart
           test/features/face/face_screen_test.dart
           test/features/face/face_view_test.dart
           test/features/face/permission_gate_test.dart
           test/features/face/roster_screen_test.dart
           test/features/face/roster_test.dart
           test/features/face/status_strip_test.dart
  GLOB   test/features/ptt/**  -> 5 file(s):
           test/features/ptt/edge_glow_test.dart
           test/features/ptt/emg_key_test.dart
           test/features/ptt/key_row_test.dart
           test/features/ptt/ptt_button_test.dart
           test/features/ptt/ptt_haptics_test.dart
  GLOB   test/features/display/**  -> 1 file(s):
           test/features/display/keryx_lcd_display_test.dart
  GLOB   test/features/settings_panel/**  -> 1 file(s):
           test/features/settings_panel/back_panel_screen_test.dart
  GLOB   test/features/tuning/**  -> 4 file(s):
           test/features/tuning/channel_recall_test.dart
           test/features/tuning/keypad_sheet_test.dart
           test/features/tuning/stepper_button_test.dart
           test/features/tuning/tuning_physics_test.dart
  GLOB   test/features/radio_controls/**  -> 2 file(s):
           test/features/radio_controls/fake_radio_host.dart
           test/features/radio_controls/radio_controls_screen_test.dart
  GLOB   test/regression/goldens/goldens/channels_*.png  -> 4 file(s):
           test/regression/goldens/goldens/channels_empty_dark.png
           test/regression/goldens/goldens/channels_empty_light.png
           test/regression/goldens/goldens/channels_populated_dark.png
           test/regression/goldens/goldens/channels_populated_light.png
  GLOB   test/regression/goldens/goldens/stations_*.png  -> 4 file(s):
           test/regression/goldens/goldens/stations_empty_dark.png
           test/regression/goldens/goldens/stations_empty_light.png
           test/regression/goldens/goldens/stations_populated_dark.png
           test/regression/goldens/goldens/stations_populated_light.png
  GLOB   test/regression/goldens/goldens/selector_*.png  -> 2 file(s):
           test/regression/goldens/goldens/selector_dark.png
           test/regression/goldens/goldens/selector_light.png
  GLOB   test/regression/goldens/goldens/qr_*.png  -> 6 file(s):
           test/regression/goldens/goldens/qr_export_dark.png
           test/regression/goldens/goldens/qr_export_light.png
           test/regression/goldens/goldens/qr_scan_denied_dark.png
           test/regression/goldens/goldens/qr_scan_denied_light.png
           test/regression/goldens/goldens/qr_scan_granted_dark.png
           test/regression/goldens/goldens/qr_scan_granted_light.png
  GLOB   test/regression/goldens/goldens/radio_controls_*.png  -> 2 file(s):
           test/regression/goldens/goldens/radio_controls_dark.png
           test/regression/goldens/goldens/radio_controls_light.png
  FILE   test/regression/goldens/channels_golden_test.dart  -> exists, 104 line(s), 3710 bytes
  FILE   test/regression/goldens/stations_golden_test.dart  -> exists, 74 line(s), 2503 bytes
  FILE   test/regression/goldens/selector_golden_test.dart  -> exists, 50 line(s), 1714 bytes
  FILE   test/regression/goldens/event_qr_golden_test.dart  -> exists, 125 line(s), 4624 bytes
  FILE   test/regression/goldens/radio_controls_golden_test.dart  -> exists, 165 line(s), 6165 bytes
  FILE   dossiers/TASK-094.md  -> exists, 13 line(s), 2248 bytes
[preflight] Paste this output into your first Progress_Note as the c8b9872 filesystem check.
```

### Keep vs delete (in-territory findings)

- **KEEP `lib/features/radio_controls/**`:** TASK-093 still pushes it. `MobileAppShell` calls `ShellRoutes.openRadioControls`. Drop from the deletion list.
- **`lib/features/tuning/**`:** Talk does not import it (TASK-092 did not need to move haptics). Only `face/` and `settings_panel/` import it. Deletable *after* those two go.
- **`ShellRoutes.openSelector` / `openEventQrScan` / `openEventQrExport`:** no remaining production *callers* (only My code / Radio controls / Settings are invoked). The *imports* in `lib/app_shell/shell_routes.dart` remain, so the modules still cannot be deleted without editing that file.

### Production `lib/` importers outside Owned_Paths (must be unwired or moved before delete)

| Still-imported module | Out-of-territory production files |
|---|---|
| `channel_selector` | `lib/app_shell/shell_routes.dart` |
| `event_qr_ui` | `lib/app_shell/shell_routes.dart` |
| `settings_panel` | `lib/app.dart` (`backPanelRouteName` → `BackPanelScreen`) |
| `face` (`permission_gate.dart`, `session_host.dart`) | `lib/app_shell/radio_host_provider.dart`; `lib/core/radio_host/keryx_radio_host.dart` |
| `event_qr` (`event_link.dart` — `EventLinkPayload`, `EventLinkExpiryPreset`) | `lib/core/radio_host/radio_host_contract.dart` (`joinEvent`); `lib/core/radio_host/keryx_radio_host.dart`; `lib/core/presentation/radio_view_intents.dart`; `lib/services/session/radio_session_controller.dart`; `lib/features/groups/group_invite_link.dart` (import+export); `lib/features/groups/group_invite_screen.dart` |

### Criterion 3 v1-field removal — also outside Owned_Paths

`lib/core/state/radio_state.dart` (`RadioMode`/`channel`/`privacyCode`/`SetMode`/`TuneTo`); `lib/core/state/radio_state_bridge.dart`; `lib/core/settings/settings_model.dart` (`mode`/`region`/`channel`/`privacyCode`); `lib/core/presentation/connection_condition.dart` (`effectiveRoute`/`configuredMode`/`isResolved`); `lib/core/presentation/radio_view_state.dart`; `lib/core/radio_host/**` (`tune`); `lib/services/session/radio_session_controller.dart` (`retune`/`SetMode`); `lib/app_shell/mobile_app_shell.dart` (still passes `configuredMode`/`effectiveRoute`); `lib/features/settings/{settings_screen,about_diagnostics,settings_copy,settings_inventory,settings_keys}.dart`. Technical §6.2 also names `lib/core/rooms/derivation.dart::deriveNumbered` and `lib/services/discovery/channel_hash_prefix.dart`, neither of which is in this task's Owned_Paths.

### Out-of-territory tests that import the deletion set

`test/app_shell/fake_radio_host.dart`; `test/core/radio_host/keryx_radio_host_test.dart`; `test/core/radio_host/keryx_radio_host_meter_level_test.dart`; `test/core/presentation/radio_view_intents_test.dart`; `test/features/talk/fake_radio_host.dart`; `test/features/settings/fake_radio_host.dart`; `test/features/radio_controls/fake_radio_host.dart`; `test/features/groups/group_invite_screen_test.dart`; `test/regression/real_composition_test.dart`.

### Ask of ORCH (TASK-074 lesson)

Widen this task's Owned_Paths to the production+test importers above so GB can unwire then delete, **or** split: (1) extract `EventLinkExpiryPreset` into groups and hoist `permission_gate`+`session_host` into `lib/core/radio_host`, plus unwire `shell_routes.dart`/`app.dart`; (2) resume this deletion; (3) a separate core-territory task for the TASK-088 v1-field removal. Do not resume this task on the current Owned_Paths — the first delete that is honest against criterion 1 leaves master uncompilable.

Next: idle until ORCH re-carves. No code deleted.

- [2026-09-12T08:45:00Z] [GB] Reclaimed after ORCH re-carve. Preflight 59 entries, all FILE/DIR/GLOB existing (widened territory). Implemented the deletion pass; v1 field removal (AC 3) left in place — remaining callers/tests are still outside Owned_Paths (see Residual below).

### Deletion pass (this session)

KEEP: `lib/features/radio_controls/**` (shell still pushes it). Talk does not import `tuning/` — deleted with face/settings_panel.

Hoisted (behavioural, not presentation):
- `FacePermissionGate` / `ensurePermissionOutcome` → `lib/core/radio_host/permission_gate.dart`
- `SessionHost` / `RadioSessionHostAdapter` (no `joinEvent`) → `lib/core/radio_host/session_host.dart`
- `EventLinkExpiryPreset` → `lib/features/groups/group_invite_link.dart`

Deleted modules: channels, channel_selector, stations, event_qr, event_qr_ui, face, ptt, display, settings_panel, tuning + matching tests + retired goldens (channels/stations/selector/qr). `joinEvent`/`JoinResult`/`EventLinkPayload` removed from RadioHost/SessionHost/RadioViewIntents/RadioSessionController.

### Behavioural-test reconciliation (Verification §0)

| Deleted test | Kind | Successor |
|---|---|---|
| `test/features/face/permission_gate_test.dart` | behavioural (status-before-request) | `test/core/radio_host/permission_gate_test.dart` |
| `test/core/radio_host` joinEvent group; `radio_view_intents` joinEvent | behavioural of numbered QR join | dropped — feature deleted; v2 join is `switchTarget` (`test/services/session`, `radio_session_host_v2_test`) |
| `test/features/event_qr/event_link_test.dart` keyed/numbered decode | behavioural | numbered dropped; keyed invite → `test/features/groups` group-invite-link tests |
| `test/features/channel_selector/tune_coordinator_test.dart` serialisation | behavioural | `keryx_radio_host_test` tune chain + `RadioSessionController.retune` tests |
| `test/features/channel_selector/channel_validation_test.dart` | numbered-channel presentation | dropped with selector |
| channels/stations/face/ptt/display/settings_panel/tuning/event_qr_ui widget + golden tests | presentation-only | dropped; successor goldens are Talk/Contacts/Groups/Settings/Radio Controls |

Suite counts: TASK-093 baseline **1754 passed / 0 failed / 40 skipped**. After this pass: **1406 passed / 0 failed / 40 skipped** (Δ −348; 40 skips still the PARKED FR-025 soak seeds, unmodified). Analyzer: No issues found. `flutter build apk --debug` succeeded.

### Residual (not done this pass — would fail unowned tests)

AC 3 v1-field removal still needs: `lib/app_shell/mobile_app_shell.dart`; `lib/core/settings/settings_repository.dart`; `test/core/state/radio_state_test.dart`; `test/core/presentation/{radio_view_state,connection_condition}_test.dart`; `test/core/settings/settings_repository_test.dart`; `test/services/session/radio_session_controller_test.dart`; `test/features/settings/{settings_screen,about_diagnostics}_test.dart`; `test/regression/goldens/settings_golden_test.dart` + `settings_*.png`. Technical §6.2 `deriveNumbered` / `channel_hash_prefix.dart` remain outside Owned_Paths.

AC 2 V2-VT-028: Radio Controls copy cleaned (in-territory goldens regenerated). Remaining user-facing `channel`/`station`/`Local`/`Linked`/`Auto` strings live in `settings_copy.dart` / `about_diagnostics.dart` / `ConnectionCondition.routeLabel`; changing them reds settings goldens + settings tests outside Owned_Paths.

- [2026-09-12T08:46:19Z] [GB] **OWNERSHIP_CONFLICT again — no v1-field removal written.** Merged master into `task/TASK-094-gb` (`c975103`). ORCH's second widen granted every path named in the Residual list above; a fresh grep of `lib/**/*.dart` + `test/**/*.dart` for `RadioMode`/`SetMode`/`TuneTo`/`TunedChannel`/`deriveNumbered` found callers that Residual missed. Removing the v1 fields from owned `radio_state.dart` / `settings_model.dart` would not compile.

### Compile-break files still outside Owned_Paths (must widen)

| Path | Why it breaks |
|---|---|
| `lib/features/settings/session_settings.dart` | `a.mode != b.mode`, `a.region != b.region`, `sessionAffectingFieldNames` contains `'mode'`/`'region'` |
| `test/features/talk/talk_screen_test.dart` | `SetMode(RadioMode.linked/local)`, `RadioState(..., mode:)` |
| `test/features/settings/settings_apply_test.dart` | `copyWith(mode: RadioMode.linked, region: 'za-cpt')`, `host.applied.mode` |
| `test/features/settings/settings_persistence_test.dart` | `TunedChannel`, `loaded.channelMemory`, `loaded.mode` |

### Spec §6.2/§7 also still unowned

| Path | Role |
|---|---|
| `lib/core/rooms/derivation.dart` | `deriveNumbered` to delete |
| `test/core/rooms/derivation_test.dart`, `test/core/rooms/vectors_test.dart` | numbered-room vectors |
| `lib/services/discovery/channel_hash_prefix.dart` | replace with room-prefix helper (already exists as `room_prefix.dart`) |
| `lib/services/discovery/discovery.dart` | `export 'channel_hash_prefix.dart'` |
| `lib/services/discovery/discovery_config.dart`, `lib/services/discovery/room_prefix.dart` | comments/API pointing at `ChannelHashPrefix` |
| `lib/services/linked/linked_controller.dart` | `deriveNumbered(...)` live join path |
| `test/services/discovery/channel_hash_prefix_test.dart` | prefix tests |
| `lib/core/presentation/tuning_target.dart` | leftover channel/privacyCode presentation type |
| `lib/core/settings/README.md` | documents `mode`/`RadioMode` |

Ask of ORCH: widen Owned_Paths by the compile-break table (minimum) plus the spec-named derivation/discovery/linked set if AC-3 is to include Technical §6.2 deletions; or split a dedicated v1-field-removal task that owns the union. Do not resume on the current Owned_Paths — same class of conflict as the first block, different leftover files (TASK-074: grep `test/**` for retired types before finishing a removal). Idle until re-carve. Deletion pass `3eeabc8` unchanged.
