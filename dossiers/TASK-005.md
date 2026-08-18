# TASK-005 — Theme system: design tokens, typography, materials (KRX-010 token half)

## Brief
Implement DS §2–§4 as the single Dart theme source in `lib/core/theme/`. Every colour, type style, duration, curve, and layout ratio in the app comes from here; the design spec explicitly bans literal values elsewhere in the widget tree. All downstream face widgets (TASK-012…018) depend on this.

## Spec pointers
- DS §2 colour tokens (exact hexes): `--shell-900 #15181B`, `--shell-700 #22262A`, `--shell-500 #31363B`, `--glass #0F1512`, `--lcd #F2A93B` ("Unlit segments = --lcd at 7% opacity"), `--legend #CFCBC0`; signal: `--tx #E23D2E`, `--rx #7FD1A0`, `--emg #FF7A18`, `--olive #6B7052`. Rules: "amber appears only inside the glass. Red appears only while the floor is held by this device."
- DS §3: three type roles; scale "channel numerals 56/1.0; secondary glass line 15/1.2; telltales 11/1.0; legends 11/1.0 at 0.14em; panel body 15/1.5".
- DS §4: "Two curves only: `snap` (140 ms, cubic-bezier(.2,.9,.3,1)) … and `settle` (320 ms, ease-out)… Nothing eases in." 8 dp grid; face allocation "status strip 6% · glass 18% · grille 26% · control cluster 22% · PTT 22% · safe area 6%"; lip treatment (1 px white .06 top inner edge, 1 px black .5 bottom); "No gradients longer than 20% of an element's height."
- DS §9 KRX-010 amendment: "implement the token system of §2–§4 as a single theme source; no literal colour or duration values elsewhere in the widget tree."
- PT `:root` block mirrors all values — use as cross-check.

## Intended approach
1. `tokens.dart`: `KrxColors` (const Color values incl. `lcdGhost` = lcd @ 7%), `KrxMotion` (snap/settle `Duration` + `Curve` via `Cubic(.2,.9,.3,1)` and ease-out), `KrxLayout` (grid unit, face allocation fractions, key-travel 1 dp), `KrxMaterial` (lip shadow specs, noise-overlay opacity 2–3%).
2. `typography.dart`: `KrxType` text styles referencing the TASK-001 bundled families (`DSEG7Classic`, `ShareTechMono`, `BarlowCondensed`, `Inter`) with the exact sizes/spacing.
3. `theme.dart`: one exported facade (plus a faceplate-abstraction seam: tokens grouped so future faceplate packs can swap hue/material but never layout, per DS §8).
4. Tests assert every hex/size/duration against the spec numbers (the tests are the design reviewer).

## Work Log
