# TASK-010 — SFX engine: dual-bus mixer, ducking, loop beds, roger variants (KRX-021 + KRX-024 playback)

## Brief
The SFX half of the audio stack in `lib/core/audio/` plus the `assets/sfx/v1/` placeholder pack: dual-bus architecture (Voice/SFX), the §7.1 manifest as a typed registry, seamless static-bed loops crossfaded by squelch level, ducking rules, and roger-beep variant playback. Commissioned real recordings (KRX-020) come later and just replace the files — the manifest contract is what matters now. TASK-011 (character DSP) extends this same territory afterwards; they are sequenced, never concurrent.

## Spec pointers
- TS §7 preamble: "48 kHz 16-bit WAV, loudness-normalised to −16 LUFS (SFX) with the emergency tone at −12 LUFS", versioned at `/assets/sfx/v1/`.
- TS §7.1 manifest: squelch_open/squelch_tail (40–80 ms), static_bed_1/2/3 ("Seamless loop points; squelch knob crossfades"), tune_burst ("Ducks under incoming audio"), scan_tick (≤ 30 ms), roger_k/roger_dual/roger_moto, deny_buzz, tot_warn/tot_cut, link_lost/link_up, emg_alert, rchk_ok, key_click/knob_tick/slider_thunk, power_on/power_off.
- TS §7.2: "Two buses: Voice bus (network audio) and SFX bus (local assets). SFX never traverses the network… SFX ducks voice by −3 dB during overlap ≤ 150 ms; voice never ducks for cosmetics."
- P4: "All SFX play from local assets on a dedicated bus — instant and identical regardless of network conditions."
- FR-006 tuning burst; FR-062 roger variants ("off / classic K-tone / dual-tone / custom pack"; the 60 ms in-band end marker rides the voice path later — playback-side hook here).
- PT audio engine section shows the intended synthesis flavour for placeholders.

## Intended approach
1. Generate placeholder WAVs with a small Dart/Python script committed under `assets/sfx/` tooling (script + output), synthesising PT-style tones/noise bursts at 48 kHz/16-bit; document LUFS targets (placeholder normalisation approximate; real pack lands via KRX-020 later).
2. `manifest.dart`: enum of all §7.1 assets → file paths + metadata (loop points for beds).
3. `sfx_engine.dart`: `SfxEngine` with `play(SfxId)`, bed control `setBedLevel(0..1)` (crossfades bed 1/2/3), duck coordination API; backed by an `AudioSink` abstraction (real impl over an audio package from TASK-001's pre-declared deps; if none fits, low-level via flutter_webrtc's audio is NOT appropriate — flag via blocked if a new dep is needed since pubspec is frozen).
4. `ducking.dart`: −3 dB duck of voice bus while SFX overlaps ≤ 150 ms, never the reverse.
5. Tests with a fake sink: routing (SFX never on voice bus), duck envelope timing, bed crossfade math, manifest completeness (every enum has an existing asset file).

## Work Log
