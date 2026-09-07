# `lib/core/theme`

Two token systems live here until TASK-061 retires the hardware face.

| System | Type | Consumers |
|---|---|---|
| `KeryxTheme` / `KeryxFacePlate` (`theme.dart`) | Static faceplate tokens | Legacy face, PTT, display, settings panel |
| `KeryxUxTokens` (`ux_tokens.dart`) | `ThemeExtension`, dark-default + complete light | Wave 4 screens (Channels, Talk, …) |

`theme.dart` re-exports the successor types so `package:keryx/core/theme/theme.dart` stays the single import surface.

## Successor tokens (TASK-047)

- Eleven Design §3.2 colours, both columns, **verbatim**. Contrast is tested, not assumed.
- Body text (WCAG AA 4.5:1) is sanctioned for `text/primary` and `text/secondary` on the three surfaces. Action/state colours are sanctioned as graphical objects (3:1) and always travel with a label + Material icon (`KeryxUxStateCue`) so colour is never the only cue.
- Four spec hexes miss 4.5:1 as 16 px text on `surface/raised`; they are **not** rewritten. Findings and minimal corrections are in `dossiers/TASK-047.md`.
- Type scale is Inter 24/30, 18/24, 16/24, 14/20, 12/16. No full-screen height allocation.
- Spacing: 8 dp grid, 16 dp page margin, 12–16 dp card spacing, 8–12 dp control gap, 48 dp min target.
- Motion: 160 ms state, 240 ms page/sheet. Reduced motion drops decorative/page motion and keeps critical state changes.

`keryxUxThemeData()` builds a `ThemeData` that carries the extension. Wiring it into `KeryxApp` is TASK-048.
