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
