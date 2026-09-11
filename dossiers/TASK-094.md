# TASK-094 — v2 deletions — channels, selector, stations, numbered Event QR, legacy face/ptt/display/settings_panel

## Brief

Delete what v2 replaced, after the shell no longer references it. Before deleting each module, list in the dossier every behavioural test it carried and where the surviving behaviour is now tested (Verification §0 rule); only presentation-only tests are dropped. `radio_controls` survives only if the shell still pushes it — if TASK-093 kept it, keep the module and drop it from this task's deletion list in the dossier; `tuning/` haptics that Talk still uses must be moved into `lib/features/talk/` by TASK-092 first (coordinate via the dossier, do not edit talk). Event QR: the keyed invite path now lives in TASK-091's groups feature; delete both `event_qr` directories. Then run V2-VT-028 repo-wide.

## Spec pointers

- specs/KERYX_v2.0_Technical_v1.0.md §6.2, §8 (legacy face folds in); PRD §1 (removed), §5.5; Verification V2-VT-028; ADR-001 §6 retirement list; ADR-003 consequences
- Owned_Paths: lib/features/channels/**, lib/features/channel_selector/**, lib/features/stations/**, lib/features/event_qr/**, lib/features/event_qr_ui/**, lib/features/face/**, lib/features/ptt/**, lib/features/display/**, lib/features/settings_panel/**, lib/features/tuning/**, lib/features/radio_controls/**, lib/features/features.dart, test/features/channels/**, test/features/channel_selector/**, test/features/stations/**, test/features/event_qr/**, test/features/event_qr_ui/**, test/features/face/**, test/features/ptt/**, test/features/display/**, test/features/settings_panel/**, test/features/tuning/**, test/features/radio_controls/**, test/regression/goldens/goldens/channels_*.png, test/regression/goldens/goldens/stations_*.png, test/regression/goldens/goldens/selector_*.png, test/regression/goldens/goldens/qr_*.png, test/regression/goldens/goldens/radio_controls_*.png, test/regression/goldens/channels_golden_test.dart, test/regression/goldens/stations_golden_test.dart, test/regression/goldens/selector_golden_test.dart, test/regression/goldens/event_qr_golden_test.dart, test/regression/goldens/radio_controls_golden_test.dart, dossiers/TASK-094.md
- Depends_On: TASK-093

## Work Log
