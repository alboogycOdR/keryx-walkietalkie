# TASK-011 — Radio character DSP + squelch gate wiring (KRX-022, KRX-023)

## Brief
Extend `lib/core/audio/` (same territory as TASK-010 — sequenced via Depends_On, never concurrent) with the voice-bus RX character chain and the squelch wiring: band-pass, soft-knee compression, makeup gain, optional hiss floor, Off/Light/Full intensity; squelch level drives both the RX gate threshold and the resting bed level. Pure buffer-in/buffer-out so it tests without any network.

## Spec pointers
- TS §7.2 RX chain: "jitter buffer → Opus decode → **radio character DSP** (300–3400 Hz band-pass, 3:1 soft-knee compression, +0…+6 dB makeup, optional hiss floor mixed at squelch-knob level) → output. Character DSP intensity: Off / Light / Full (default Light)."
- FR-061: "**Squelch knob** (settings face): actually functions — sets RX gate threshold *and* the resting hiss level (from silent to faint bed)."
- KRX-022 "Radio character DSP (band-pass, compression, hiss floor) with Off/Light/Full"; KRX-023 "Squelch knob ↔ gate threshold + bed level wiring".

## Intended approach
1. `dsp/biquad.dart`: HP @300 Hz + LP @3400 Hz biquads (or one band-pass pair), Float32 sample processing.
2. `dsp/compressor.dart`: 3:1 soft-knee with makeup 0…+6 dB, envelope follower.
3. `dsp/character_chain.dart`: composable chain with intensity presets — Off (bypass), Light (gentler knee/mix), Full — default Light; hiss-floor mix level injected from squelch setting.
4. `squelch.dart`: maps the persisted squelch value (TASK-008 key, consumed via interface) to (a) RX gate threshold and (b) `SfxEngine.setBedLevel`.
5. Tests: process synthesized buffers — assert band edges (energy at 100 Hz/8 kHz attenuated vs 1 kHz), compression ratio on step signals, bypass equality for Off, squelch mapping monotonicity.

## Work Log
