# `lib/core/audio`

SFX mixer (KRX-021 / KRX-024) and voice-bus radio character DSP (KRX-022)
plus squelch wiring (KRX-023).

## Voice RX pipeline

`VoiceRxProcessor.process(Float32List)` is buffer-in / buffer-out:

1. `RxGate` — energy gate. Threshold comes from the TASK-008 squelch detent
   (0 = closed / high threshold, 10 = open / low threshold).
2. `RadioCharacterChain` — Off is a sample-exact bypass. Light (default) and
   Full run 300–3400 Hz HP+LP, 3:1 soft-knee compression, +0…+6 dB makeup,
   and an optional hiss floor mixed at the squelch-mapped level.

Resting hiss is **not** on the voice bus. `SfxEngine.applySquelch(detent)`
maps 0–10 onto `Squelch.maxRestingBed` (0.12, a faint bed) and drives the
three static-bed loops.

## Duck release

`SfxEngine.tick()` still works for a polling host. Prefer injecting
`scheduleDuckRelease` so the −3 dB voice duck restores when the window
expires without the host remembering to poll.

## Beds

`BedMixer` and the placeholder generator use equal-power (`sqrt`)
crossfades so the squelch sweep does not sag 3 dB mid-fade.

## Production sink (TASK-033)

`DeviceAudioSink` is the real [AudioSink](audio_sink.dart). Call
`await sink.initialize()` once at power-on (loads all 22 `assets/sfx/v1/*.wav`
into RAM) before constructing `SfxEngine`. Dispose with `await sink.dispose()`.

### Package choice

Requirements that drove the pick: (1) trigger-to-audible ≤ 50 ms for 8–30 ms
mechanical clicks, (2) three simultaneous 2 s loop beds with per-loop gain,
(3) per-bus gain in dB, (4) all 22 WAVs.

| Package | Verdict |
|---|---|
| **`flutter_soloud` ^4.1.7** | **Chosen.** Game-engine mixer: low-latency one-shots (`play` starts at the next buffer; 1024 frames @ 48 kHz ≈ 21 ms), gapless `[start, end)` loops, per-voice volume (`setLoopGain`), mixing buses (`setBusGainDb` on the SFX bus is one volume write), RAM `LoadMode.memory` for the 22 short WAVs. Official Flutter cookbook audio plugin. |
| `soundpool` | Rejected. Android `SoundPool` is built for short one-shots; looping is a repeat count without loop-point control, 2 s beds fight the per-sound 1 MB decoded cap / truncation behaviour, and there is no mix-bus primitive for the −3 dB duck. Package last published 2023. |
| `just_audio` | Rejected. Media player (ExoPlayer). Simultaneous beds would be N `AudioPlayer` instances with media-pipeline latency (typically > 50 ms), no mix bus, and a well-known parallel-instance resource ceiling. Wrong tool for 8 ms knob ticks. |

`permission_handler` is allocated in `pubspec.yaml` in the same unfreeze so
TASK-038 can request runtime grants. This package does not import or call it.

Pinned at **^12.0.3**, not 13.0.1: `permission_handler` 13.0.1 pulls
`permission_handler_android` 14.0.0 whose `android/build.gradle.kts` applies
only `com.android.library` then calls `kotlin { compilerOptions { jvmTarget } }`,
which fails to configure on this repo's AGP 8.11.1 / Gradle 8.14 / Kotlin 2.2.20
(`Unresolved reference: compilerOptions`). 12.0.3 is the newest stable that
compiles here. Bumping to 13.x belongs with an AGP 9 upgrade (out of this
territory).

### Voice-bus duck (disclosed)

`setBusGainDb(AudioBus.voice, −3)` is stored and emitted on the optional
`onVoiceBusGain` callback. SoLoud never sees the voice bus — WebRTC / LiveKit
owns that path. TASK-037 must apply `DeviceAudioSink.voiceBusGainLinear` (or
the callback's dB) to the remote audio track. SFX-bus gain *is* applied inside
SoLoud.

### On-device smoke (after `flutter build apk --debug`)

Unit tests cover the six contract methods against a fake backend (no native
device in `flutter test`). Plugin + asset compile is proven by the debug APK.
On a phone:

1. Power on → `power_on.wav` (≈ 280 ms sweep).
2. Knob / PTT press → `knob_tick` / `key_click` feel mechanical, not lagged.
3. Squelch detent 0 → 10 → three hiss beds crossfade; two can be audible at
   a fade point with independent levels.
4. Programme SFX (tune / deny) while RX audio is up → voice dips ~3 dB for
   ≤ 150 ms (once TASK-037 wires `onVoiceBusGain`).
5. Power off → `power_off.wav`, then silence (no looping hiss).
