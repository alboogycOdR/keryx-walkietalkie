# TASK-078 — UX R2 regression + owner review build

## Brief

This is the evidence gate for UX R2: audit the goldens, add small-phone, large-text and landscape layout tests, and produce the split-per-ABI release APK the owner will install to review the new UI.

## Spec pointers

- docs/adr/ADR-002-zello-aligned-talk-first-ui.md §2 O4, §5
- specs/KERYX_Mobile_UX_Redesign_Verification_v1.0.md §6, §9 G4
- ops/REGRESSION_UX_R1.md (baseline counts)

## Approach

1. Add shell-frame and measured-glow goldens.
2. Add a layout matrix test.
3. Run the full suite, analyze, debug and release split builds.
4. Write ops/REGRESSION_UX_R2.md with the counts reconciliation and the arm64 APK size and sha256.

## Work Log

- [2026-09-11T14:12:00Z] [GB] Claimed TASK-078. Resume check: no GB in_progress/claimed. Depends_On TASK-077/079/080/081 all done. Branch `task/TASK-078-gb` from master `1707a42`. Preflight:

```
[preflight] TASK-078 Owned_Paths inspected in C:/CLAUDECODE_TOOLSETS/wt-grok-walkietalkie-keryx
[preflight] 3 entr(y/ies). FILE/DIR/GLOB = exists, NEW = you are creating it.
  GLOB   test/regression/**  -> 44 file(s):
           test/regression/goldens/channels_golden_test.dart
           test/regression/goldens/event_qr_golden_test.dart
           test/regression/goldens/goldens/channels_empty_dark.png
           test/regression/goldens/goldens/channels_empty_light.png
           test/regression/goldens/goldens/channels_populated_dark.png
           test/regression/goldens/goldens/channels_populated_light.png
           test/regression/goldens/goldens/qr_export_dark.png
           test/regression/goldens/goldens/qr_export_light.png
           test/regression/goldens/goldens/qr_scan_denied_dark.png
           test/regression/goldens/goldens/qr_scan_denied_light.png
           test/regression/goldens/goldens/qr_scan_granted_dark.png
           test/regression/goldens/goldens/qr_scan_granted_light.png
           ... and 32 more
  NEW    ops/REGRESSION_UX_R2.md  -> does not exist; parent ops/ exists
  FILE   dossiers/TASK-078.md  -> exists, 20 line(s), 739 bytes
```

  Implementing: shell-frame goldens (dark/light), measured-glow RX goldens, layout matrix (320×568 / 360×640 / 412×915 × scale 1.0/2.0 + landscape 640×360), overflow Settings/Radio-controls `handlePopRoute()` tests. No production files — territory is test/regression/** + ops/REGRESSION_UX_R2.md + this dossier.
