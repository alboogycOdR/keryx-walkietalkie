# TASK-014 — CH steppers with auto-repeat + keypad direct-entry sheet (KRX-013)

## Brief
The precision/accessibility tuning paths in `lib/features/tuning/`: CH▲/CH▼ steppers with accelerating press-and-hold auto-repeat, the long-press keypad sheet for direct channel+code entry, and quick-recall of channel memory on long-press CH▼. All three emit intents into the same tuning state machine (TASK-004's reducer, wired by TASK-017).

## Spec pointers
- FR-004: "CH▲/CH▼ steppers with press-and-hold auto-repeat (accelerating)."
- FR-005: "Long-press channel display → keypad direct entry of channel + code."
- FR-009: "Channel memory: last 6 tuned channels accessible via quick-recall (long-press CH▼)."
- TS D1: "All three write to the same tuning state machine… steppers and keypad make it usable one-handed, gloved, or with TalkBack."
- FR-106: "stepper-first tuning path, haptic-only feedback profile, min 48 dp targets."
- DS §7 copy voice (keypad sheet copy stays in-world); DS G3 glove test (targets); PT stepper script: initial delay 420 ms, rate ×0.82 per repeat, floor 60 ms — treat as ratified feel.
- TS §6.3 / DS §6: no dialogs on the face — the keypad is an in-world sheet, not a Material dialog.

## Intended approach
1. `stepper_button.dart`: 54 dp-class key (≥ 48 dp target) with key-travel treatment from tokens; hold → repeat timer 420 ms → interval ×0.82 clamped at 60 ms; emits `tune(+1/−1)` intents; TalkBack semantics ("Channel up").
2. `keypad_sheet.dart`: in-world bottom sheet styled as housing, segment-font echo of entry, digits + code entry, validation (ch 1–99, code 00–38), confirm emits `tuneDirect(ch, code)`.
3. `channel_recall.dart`: long-press CH▼ surface listing up to 6 memory entries (list injected; persistence is TASK-008's).
4. Widget tests: repeat acceleration curve, long-press routing (recall vs step), keypad validation bounds, semantics labels present.

## Work Log
