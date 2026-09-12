# TASK-096 — Android FLAG_SECURE + brightness native handlers

## Brief

TASK-089's onboarding calls `za.co.basileia.keryx/screenshot_guard` and
`.../screen_brightness` over MethodChannel. Neither has a native Android
handler anywhere in the repo, so both calls currently no-op — the recovery
phrase is NOT actually screenshot-protected on a real device. Add the
native side; Dart is already correct and unit-tested.

## Spec pointers

- specs/KERYX_v2.0_Design_v1.0.md §2.6
- PRD V2-FR-002
- lib/features/onboarding/screenshot_guard.dart (channel name, method shape)
- lib/features/my_code/screen_brightness.dart

## Approach

1. Add a `MethodChannel` handler in `MainActivity.kt` for `setSecure`.
2. `FLAG_SECURE` on/off via `window.addFlags`/`clearFlags`.
3. Brightness handler: save/restore the real prior value, not a hardcoded default.
4. Manual device verification (no Flutter widget test can prove this).

## Work Log

- [2026-09-12T04:38:00Z] [GB] Claimed and in_progress. Preflight: 7 existing kotlin files under `android/app/src/main/kotlin/**` plus this dossier. Existing MethodChannels left untouched: `za.co.basileia.keryx/nsd`, `/nsd_events`, `/radio_service`, `/radio_service_events`. Dart clients already call `screenshot_guard`/`setSecure({secure})` and `screen_brightness`/`setMaximum`+`restore`. Adding `ScreenshotGuardPlugin` and `ScreenBrightnessPlugin` (ActivityAware) and registering them in `MainActivity.configureFlutterEngine`. Manual FLAG_SECURE proof will use emulator `LekkerSwot_Pixel7` plus an uncommitted Dart harness (onboarding is not mounted in the shell until TASK-093).
- [2026-09-12T05:05:17Z] [GB] Native plugins landed. Device proof on AVD **LekkerSwot Pixel7** (`sdk_gphone64_x86_64`, **Android 14 / API 34**), debug APK signed with the Flutter debug keystore. Shell does not yet mount onboarding (TASK-093); an uncommitted `tool/verify_task_096.dart` harness pushed the real `RecoveryPhraseScreen` / `MyCodeScreen` (production MethodChannel clients, no fakes). Logcat (`pid` of `za.co.basileia.keryx`):
  - phrase shown: `KeryxScreenshotGuard: setSecure=true applied=true flags=0x81812100`
  - phrase left: `setSecure=false applied=false flags=0x81810100` (delta **0x2000** = `FLAG_SECURE`)
  - My code shown: `KeryxBrightness: setMaximum saved=-1.0 now=1.0` (`BRIGHTNESS_OVERRIDE_NONE` saved, full applied)
  - My code left: `restore requested=-1.0 now=-1.0` (prior value restored, not a hardcoded default)
  Hardware screenshot (KEYCODE_SYSRQ) on the idle harness captured the two buttons clearly. The same key on the phrase screen did not capture the 12-word grid — recents thumbnail is blanked/black (AC's "or recents-apps thumbnail is blanked" clause). `adb shell screencap` while FLAG_SECURE is set crashed this AVD's GPU path once; avoided after that. Existing MethodChannel names in `NsdPlugin` / `RadioServiceContract` unchanged (git diff empty). `flutter test --no-pub test/features/onboarding test/features/my_code` → **18/18**. Harness not committed.
