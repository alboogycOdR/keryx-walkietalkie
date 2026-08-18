# SFX pack v1 (placeholders)

Versioned sound root per TS §7: `assets/sfx/v1/`.

These files are **synthesized placeholders** (PT-style tones and band-passed
noise) so the §7.1 manifest and mixer can be exercised end-to-end. Commissioned
recordings (KRX-020) replace the WAVs in place; stems and the Dart registry
stay put.

| Rule | Value |
|---|---|
| Format | 48 kHz, 16-bit, mono PCM WAV |
| Loudness | −16 LUFS (ungated BS.1770-4 K-weight) |
| Emergency | `emg_alert.wav` at −12 LUFS |
| Loop beds | `static_bed_1/2/3.wav` — 2 s, 20 ms equal-power wrap |

Regenerate:

```
python assets/sfx/tools/generate_placeholders.py
```

The script is seeded (`0x4B455258`) so re-runs are bit-stable.

Device playback is **not** in this pack. `SfxEngine` talks only to an injected
`AudioSink` because `pubspec.yaml` is frozen without an SFX player package.
