# TASK-033 — Real device `AudioSink` + controlled pubspec unfreeze

## Brief
The audio engine is complete but `AudioSink` had only `RecordingAudioSink`. This
task is the sanctioned pubspec unfreeze: one playback package + a production
sink that implements the six-method contract, and `permission_handler` allocated
(not used) for TASK-038.

## Spec pointers
- TS §7 preamble: 48 kHz 16-bit WAV, −16 LUFS (SFX) / −12 LUFS (emergency).
- TS §7.1: 22-asset manifest including three loopable static beds.
- TS §7.2: two buses; SFX ducks voice −3 dB ≤ 150 ms; cosmetics never duck.
- TASK-010 review finding (8): nothing in the repo can actually make a sound.

## Intended approach
1. Evaluate `flutter_soloud` / `soundpool` / `just_audio` against latency, triple
   loop + per-loop gain, and per-bus dB. Pick from requirements, not familiarity.
2. `DeviceAudioSink` implements the existing sync `AudioSink` contract; async
   `initialize()` preloads all 22 WAVs.
3. Tests inject a fake `PlaybackBackend` (no native device in `flutter test`).
4. `flutter build apk --debug` proves the plugin+asset chain compiles.
5. Do not import or call `permission_handler`. Do not map `GrantTone`.

## Work Log

- [2026-08-21T19:22:00Z] [GB] Claimed on `task/TASK-033-gb`. Preflight: existing
  `lib/core/audio/**` (17 files) + `test/core/audio/**` (6 files) + `pubspec.yaml`;
  this dossier NEW. Package evaluation in progress; `pubspec.lock` is not in
  Owned_Paths and will be flagged if ORCH has not widened it before the dep commit.
- [2026-08-21T19:40:00Z] [GB] Chose `flutter_soloud` ^4.1.7 (low-latency one-shots,
  three gapless loops + per-voice gain, SFX mix bus). Rejected `soundpool` (no
  loop-point control, no mix bus, last published 2023) and `just_audio` (media
  pipeline latency, N `AudioPlayer` instances). `permission_handler` allocated
  in pubspec only — not imported (pinned ^12.0.3; see next log). `DeviceAudioSink` implements the six
  sync contract methods; `initialize()` preloads all 22 WAVs. Tests inject
  `PlaybackBackend` (SoLoud has no reliable headless/null-device mode). Criterion
  3 delivery: fake-backend load of all 22 + `flutter build apk --debug` +
  on-device smoke checklist below. ORCH widened Owned_Paths to include
  `pubspec.lock`. `flutter analyze` clean; `flutter test test/core/audio` 55/55
  (44 prior untouched + 11 new); full `flutter test` 1006 passed / 0 failed / 40
  skipped (named FR-025 parked seeds).
- [2026-08-21T19:42:00Z] [GB] `permission_handler` 13.0.1 failed `flutter build
  apk --debug`: `permission_handler_android` 14.0.0 `build.gradle.kts` has an
  unbound `kotlin { compilerOptions }` block (plugin not applied) on AGP 8.11.1.
  Pinned `^12.0.3` (newest that configures). Disclosed in README. Retrying APK.
- [2026-08-21T19:51:00Z] [GB] `flutter build apk --debug --target-platform
  android-arm64` succeeded: `build/app/outputs/flutter-apk/app-debug.apk`
  (211504782 bytes). Fat-APK (all ABIs) died when the Gradle daemon disappeared
  during SoLoud `armeabi-v7a` cmake; arm64 is the HONOR 90 Lite / two-phone
  path. Criterion 3 delivered as: unit test loads all 22 via the real sink
  class + debug APK proving the plugin+asset chain + smoke checklist above
  (not executed on-device this session). Ready for `needs_review`.

## On-device smoke checklist (not executed this session unless a device is attached)

Plugin chain is proven by `flutter build apk --debug`. Native playback is not
exercised by `flutter test` (SoLoud has no headless/null-device mode we can rely
on). On a phone, after TASK-037 wires the sink:

1. Power on → hear `power_on.wav`.
2. Knob / PTT → `knob_tick` / `key_click` feel mechanical (≤ 50 ms).
3. Squelch 0→10 → three hiss beds crossfade; a mid-detent point has two beds
   audible at independent levels.
4. Tune / deny while RX is up → voice dips ~3 dB for ≤ 150 ms (needs TASK-037
   to apply `onVoiceBusGain` to WebRTC).
5. Power off → `power_off.wav`, then silence (loops stopped).
