# TASK-012 — Segment LCD glass component (KRX-012)

## Brief
The display glass as a self-contained, model-driven widget set in `lib/features/display/`: DSEG7 amber channel/code with ghost segments, mode label, dot-matrix status line, telltale row, backlight bloom, BOOT all-segments flash, and night dimming. It owns no state — TASK-017 feeds it a display model projected from the reducer.

## Spec pointers
- TS §6.1 glass region: "segment LCD: channel · code, mode, active speaker line, telltales (VOX, EMG, NO LINK, PRV, replay)".
- TS §6.3: "Segment/LCD typeface for channel + code; dot-matrix secondary line for callsigns/status. Telltale icons only — no toasts, no snackbars, no dialogs on the face."
- FR-001 (`CH 01`–`CH 99` segment-style), FR-002 (display `CH 07 · 21`), FR-007 (keyed → "`PRV` + user label").
- DS §1: "amber segments on a warm-black glass with visible pixel structure and a faint backlight bloom, including the classic 'all segments on' flash at power-up."
- DS §2: ghost segments = lcd @ 7%; "amber appears **only** inside the glass."
- DS §9: FR-108 night dimming (gate G4); FR-109 power-up sequence.
- PT `.glass` markup: ghost `88 · 88` underlay, row1 (chan + mode), row2 (status + telltales), bloom radial gradient, `.dim` brightness .55, blink animation for TUNING.

## Intended approach
1. `display_model.dart`: immutable input — channel/code or PRV+label, mode text, status line (speaker/`CHANNEL CLEAR`/`NO STATIONS`), set of lit telltales (TX MON PRV VOX EMG NOLINK REPLAY), boot-flash flag, blink flag, dim level.
2. `glass.dart`: container with substrate colour, inset shadows, bloom (bounded gradient per DS §4 rules), all from TASK-005 tokens.
3. `segment_display.dart`: DSEG7 text with ghost `88 · 88` underlay (Stack, ghost token colour).
4. `telltale_row.dart`: fixed-order row, unlit at ghost opacity, `snap`-curve transitions; TX red, EMG orange from signal tokens.
5. `boot_flash.dart`: brief all-segments state driven by the model (timing owned by caller so goldens can freeze it).
6. Widget tests: every telltale on/off, PRV rendering, dim, boot flash, blink.

## Work Log
