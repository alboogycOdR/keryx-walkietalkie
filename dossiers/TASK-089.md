# TASK-089 — v2 onboarding, My code and Restore screens

## Brief

Three screens, each a standalone widget with injected callbacks so the shell (TASK-093) can mount them. Onboarding: callsign entry (reuse `callsign.dart` validation) → recovery-phrase screen (12 words in a 3×4 numbered mono grid, no copy control, `FLAG_SECURE` on Android via the existing platform channel or a small new one under this territory, 'I've written it down' as the only exit) → `onDone`. My code: full-screen QR of `keryx://id?...`, callsign·code beneath, 'Share link' (`https://keryx.app/c/...`), brightness raised while shown. Restore: 12-word entry with per-word validation and suggestions, `onRestored(identity)`. Do not wire navigation; do not touch `lib/app_shell/**`.

## Spec pointers

- specs/KERYX_v2.0_Design_v1.0.md §2.4 (My code), §2.6 (first run), §2.7 Identity section wiring hooks; PRD V2-FR-001..004; Verification V2-VT-003, V2-VT-027, V2-VT-030 (My code, phrase goldens)
- Owned_Paths: lib/features/onboarding/**, lib/features/my_code/**, lib/features/restore/**, test/features/onboarding/**, test/features/my_code/**, test/features/restore/**, dossiers/TASK-089.md
- Depends_On: TASK-083, TASK-086

## Work Log
