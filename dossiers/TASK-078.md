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
