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
