# TASK-089 — v2 onboarding, My code and Restore screens

## Brief

Three screens, each a standalone widget with injected callbacks so the shell (TASK-093) can mount them. Onboarding: callsign entry (reuse `callsign.dart` validation) → recovery-phrase screen (12 words in a 3×4 numbered mono grid, no copy control, `FLAG_SECURE` on Android via the existing platform channel or a small new one under this territory, 'I've written it down' as the only exit) → `onDone`. My code: full-screen QR of `keryx://id?...`, callsign·code beneath, 'Share link' (`https://keryx.app/c/...`), brightness raised while shown. Restore: 12-word entry with per-word validation and suggestions, `onRestored(identity)`. Do not wire navigation; do not touch `lib/app_shell/**`.

## Spec pointers

- specs/KERYX_v2.0_Design_v1.0.md §2.4 (My code), §2.6 (first run), §2.7 Identity section wiring hooks; PRD V2-FR-001..004; Verification V2-VT-003, V2-VT-027, V2-VT-030 (My code, phrase goldens)
- Owned_Paths: lib/features/onboarding/**, lib/features/my_code/**, lib/features/restore/**, test/features/onboarding/**, test/features/my_code/**, test/features/restore/**, dossiers/TASK-089.md
- Depends_On: TASK-083, TASK-086

## Work Log

- [2026-09-12T04:08:35Z] [GB] Claimed. Preflight: all six globs NEW; dossier exists. Specs read: Design §2.4/§2.6/§2.7/§5/§6, Technical §3.1/§3.2, PRD V2-FR-001..004, V2-VT-003/027/030.
- [2026-09-12T04:45:00Z] [GB] Implemented three standalone screens (no `lib/app_shell/**`):
  - `OnboardingScreen`: callsign (`Callsign.parse`) → 3×4 numbered Share Tech Mono phrase grid → `onDone` only from "I've written it down". `PopScope(canPop: confirmed)`; system back on phrase returns to callsign. `SelectionContainer.disabled`, no Copy. TalkBack label `Word N, word`. `ScreenshotGuard` MethodChannel `za.co.basileia.keryx/screenshot_guard` (`setSecure`); `android/**` is outside territory so MissingPluginException is swallowed. Tests inject `RecordingScreenshotGuard`.
  - `MyCodeScreen`: QR `keryx://id?v=1&c=&k=` via `KeryxIdLink`; share `https://keryx.app/c/<callsign>-<code>?k=`; display `<CALLSIGN>·<CODE>`. Copy affordance (Design §2.4) + injected `onShare`. Brightness via `za.co.basileia.keryx/screen_brightness`.
  - `RestoreScreen`: 12 BIP-39 fields, inline invalid-word error, prefix chips, checksum error, `onRestored(DeviceIdentity)` with the same peerId/shortCode/publicKey as the original phrase.
  Goldens live under `test/features/{onboarding,my_code}/goldens/` (regression goldens dir is out of territory). Native FLAG_SECURE/brightness window flags still need an Android plugin owner — Dart clients are ready.
