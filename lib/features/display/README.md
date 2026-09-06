# Display — compact LCD strip

Self-contained header-strip widget for the Phase 2 hero-PTT face
(TASK-041). TASK-043 composes [KeryxLcdDisplay] into `FaceScreen`; this
package takes **plain data only** (ints, strings, a telltale set) and has
no import of face / session / controller types.

## What it renders

1. Telltale row: `LOCAL` / `LINKED` / `TX` / `RX` — lit = `KeryxTheme.lcd`,
   unlit = the same colour at `KeryxTheme.ghostSegmentOpacity` (7%).
2. `CH` prefix + two DSEG7 Classic digits with an `88` ghost underlay.
3. Nine-bar S-meter (FR-069 S1–S9). `signalQuality` 0 = all ghost; 1–9 =
   that many bars lit with `KeryxTheme.rx`.
4. Mono status line (`Share Tech Mono`): host supplies copy such as
   `CHANNEL CLEAR`, `TX 00:07`, `RX BRAVO-7`.

Chrome is unchanged: `KeryxTheme.glassBorder` / `glassInnerShadow` /
`glassHighlight` / backlight bloom to `glassBloomStop`.

## Constructor (for TASK-043)

```dart
KeryxLcdDisplay(
  model: KeryxDisplayModel(
    channel: 7,                 // 1–99
    mode: 'LOCAL',              // semantics only
    telltales: {KeryxStripTelltale.local},
    statusLine: 'CHANNEL CLEAR',
    signalQuality: 4,           // 0–9
    dimLevel: 1,                // 0–1, FR-108
    isBooting: false,           // FR-109 all-segments flash
  ),
)
```

Digit face is DSEG7 Classic at 32 dp (DS §3's 56 was the full-glass
scale; the approved canvas shrinks the surrounding layout).

## Not extracted from grille

`lib/features/grille/grille_motion.dart` was grille-slot tremble math
(`sin(t/90+i)*0.5*amp*jitter`, 9 bars). TASK-042's 64-tick radial ring
is a level→lit-tick mapping, not tremble. No shared meter-math was
moved here — TASK-042 should own its own copy.
