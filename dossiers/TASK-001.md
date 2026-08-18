# TASK-001 — Repo scaffold: Flutter app + CI (KRX-001, app half)

## Brief
Create the Flutter application skeleton, the shared asset/font base, and CI. This task is the single owner of every cross-cutting app file (pubspec.yaml, analysis_options.yaml, .gitignore, .github/**) — after it merges those files are FROZEN and later changes need a dedicated ORCH-created integration task. Every other app-side task depends on this one.

## Spec pointers
- TS §8.1: "App: **Flutter (Dart 3)**, Android-first, min SDK 26, target latest" · "State mgmt: Riverpod" · "Voice engine: WebRTC via `flutter_webrtc` (LOCAL) and `livekit_client` (LINKED)" · "Persistence: Local only: settings + channel memory in encrypted prefs."
- TS §11 KRX-001: "Repo scaffold: Flutter app + `relay/` (Docker compose) + `token-svc/` + `sfx/` asset pipeline; CLAUDE.md conventions; CI (analyze, test, build APK)" — relay/token-svc halves are TASK-002/003, not yours.
- TS §7: "Sound is a first-class, versioned asset set (`/assets/sfx/v1/`)".
- DS §3 typography: DSEG7 Classic (channel numerals), Share Tech Mono (glass), Barlow Condensed 600 (legends), Inter 400/600 (panels).

## Intended approach
1. Read `C:\Users\Nuburo\Documents\BASILEIA\lekker swot\mobile\LESSONS.md` first (Flutter playbook — build pipeline and dep-upgrade gotchas apply directly).
2. `flutter create --platforms android --org za.co.basileia --project-name keryx` in a temp dir, then copy generated files in — do NOT let it overwrite the existing repo `.gitignore` (append Flutter section instead) and never touch DEVDEPARTMENT files (docs/, scripts/, tests/, hooks/, briefings/, board/, deploy/, specs/, PLAN.md, AGENTS.md, etc.). Note the repo already has a `tests/` (pack pytest) — Flutter tests live in `test/` (singular).
3. `android/app/build.gradle*`: minSdk 26.
4. pubspec: pre-declare flutter_riverpod, flutter_webrtc, livekit_client, flutter_secure_storage, shared_preferences, crypto, qr_flutter, mobile_scanner, vibration (pin versions that resolve today); font families + `assets/sfx/v1/` + `assets/fonts/` entries. Download OFL/Apache-licensed TTFs (DSEG7 Classic is SIL OFL; others are Google Fonts) into `assets/fonts/` with their licence files.
5. Skeleton dirs `lib/core/`, `lib/features/`, `lib/services/` (with .gitkeep or barrel stubs) and a trivial `lib/main.dart` + smoke `test/` so `flutter test` is green.
6. `.github/workflows/ci.yml`: flutter analyze → flutter test → build debug APK.
7. Root `README.md` (project intro; none exists yet).

## Work Log
