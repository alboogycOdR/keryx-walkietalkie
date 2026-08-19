# Speaker grille (KRX-014)

Amplitude-driven RX visualiser — the only ambient animation in the product
(TS §6.1, DS §5.3).

## Contract

`KeryxSpeakerGrille` is presentation only. It never imports the audio
engine. The host injects:

| Host condition | `amplitude` | `live` |
|---|---|---|
| Idle / squelched | `0` | `false` |
| MONITOR open, no RX | `GrilleMotion.monitorAmplitude` (`0.25`) | `false` |
| RX active | talking-station level in `[0, 1]` | `true` |

Non-finite stream values are logged and ignored. Finite values are clamped
to `[0, 1]`. Stream errors are logged; the last good amplitude is kept.

## Motion

- **Mass:** level changes run through `AnimationController.animateTo` with
  `KeryxTheme.settleDuration` (320 ms) and `KeryxTheme.settleCurve`
  (`cubic-bezier(.16,1,.3,1)`). The curve is not re-declared here (DS §10).
- **Tremble:** prototype formula, 9 slots:
  `scaleY = 1 + sin(t/90 + i) * 0.5 * amp * (0.6 + random * 0.6)`.
- **Reduced motion:** `reduceMotion: true` or `MediaQuery.disableAnimations`
  freezes every slot at rest scale `1`. The amplitude subscription stays
  alive so haptics/sound owned by other territories are unaffected.

## Visuals

Shell is `KeryxTheme.shell900` with the theme lip plus the prototype inset
recess. Slot fills `#0d0f10` (idle) / `#12211a` (live) match PT L79–82;
those colours are not theme tokens (TASK-028 does not add them).
