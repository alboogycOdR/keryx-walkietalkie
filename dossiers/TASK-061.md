# TASK-061 — Legacy retirement

## Brief

The explicit cleanup task Technical §10 requires, gated behind both hardware
acceptance runs. Deletes the hardware-radio presentation outright per the owner's
UX-D04 decision — the face widget tree (including whatever remains of
`face_screen.dart` after TASK-045 hollowed it), `lib/features/ptt/**`,
`lib/features/display/**`, `lib/features/settings_panel/**`, the superseded
`lib/features/event_qr/**` screens, TASK-048's dev-only compat route, and the
hardware-face goldens. No dormant classic-theme flag is left behind.

## Spec pointers

- `docs/adr/ADR-001-mobile-ux-redesign-reconciliation.md` §3 item 4, §6
  (retirement list), §7 item 1 (delete outright, after real-device acceptance).
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §9, §10, §1 (Face row).
- `specs/KERYX_Mobile_UX_Redesign_Verification_v1.0.md` §0, §6 (goldens retained
  until explicit retirement).
- PRD UX-D04, §2.3.

## Approach

Sequencing note for a cold reader: TASK-045 owned `face_screen.dart` early in
the wave (hollowing it) and is long merged before this task starts — the
`Depends_On` chain 045 → 048 → screens → 057 → 058 → 059/060 → 061 makes
concurrency impossible. Any still-consumed behavioural logic must have been
migrated before its file is deleted; the dossier lists file-by-file what was
deleted, what was migrated and where. Historical tests asserting real behaviour
get equivalents; only tests asserting the retired look are deleted. Reconcile
before/after test counts explicitly.

## Work Log
