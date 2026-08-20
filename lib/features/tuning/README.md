# `lib/features/tuning/` — CH steppers + keypad direct entry (TASK-014, KRX-013)

The precision/accessibility half of D1's "hybrid rotary + steppers + keypad"
channel selector. All three widgets in this package are pure
presentation-plus-intent: they emit tuning events and read a caller-injected
`channel` value, but own no channel state themselves. The reducer
(`lib/core/state/radio_state.dart`, TASK-004/027) is the single source of
truth; TASK-017 wires this package's callbacks to it.

## Contents

- **`stepper_button.dart` — `ChStepperButton`.** CH▲/CH▼ 54 dp key.
  Press-and-hold accelerating auto-repeat mirrors PT `stepper()` exactly
  (420 ms initial delay, ×0.82 acceleration, 60 ms floor). CH▼ additionally
  accepts an `onLongPress` (FR-009 quick-recall) — see the widget's own
  dartdoc for the disclosed, non-blocking overlap between the two gestures.
  Fires `TuningHapticFeedback.click()` (PRIMITIVE_CLICK) on every tick.
- **`keypad_sheet.dart` — `KeypadSheet` / `showKeryxKeypadSheet`.**
  Long-press-channel-display direct-entry sheet (FR-005): sequential
  2-digit channel then 2-digit code, in-world bottom sheet (not a Material
  dialog — see the widget dartdoc), validated against the same 1-99/00-38
  CLAMP-ruling domain the reducer enforces, with an inline (never a dialog)
  error line on out-of-domain entry.
- **`channel_recall.dart` — `ChannelRecallPanel` / `showChannelRecallPanel`.**
  Long-press-CH▼ quick-recall surface (FR-009). Renders whatever
  `List<TunedChannel>` (TASK-008's model, `lib/core/settings/`, imported
  read-only) its caller injects — this package never touches the settings
  repository directly.
- **`tuning_physics.dart` — `TuningPhysics`.** Channel/code domain bounds
  (duplicated from, not imported from, `RadioState` — same convention
  `KnobPhysics` established) and auto-repeat timing constants.
- **`tuning_haptics.dart` — `TuningHapticFeedback`.** PRIMITIVE_CLICK
  approximation, same shape as `KnobHapticFeedback`/`PttHapticFeedback`.

## Design decisions disclosed for ORCH review

1. **CH▼ long-press vs. auto-repeat overlap (FR-004 vs FR-009).** PT
   implements auto-repeat but never channel memory at all, so there is no
   ratified reference for how the two gestures should coexist on one key.
   Resolved as: auto-repeat continues normally until the 600 ms long-press
   threshold (reused from `EmgKey`'s established convention) is crossed, at
   which point auto-repeat is cancelled and recall opens instead — so a
   long-press emits one or two extra step-down ticks before the recall
   surface appears. Non-blocking; see `ChStepperButton`'s dartdoc.
2. **Keypad sheet is a `showModalBottomSheet`, chrome fully stripped**, not
   a custom `Overlay`/`Route` from scratch — the task Description's "not a
   Material dialog" is satisfied (this is a sheet, not a `Dialog`/
   `AlertDialog`), while reusing Flutter's own sheet lifecycle (back-button
   dismiss, barrier tap-outside) rather than reinventing it. Disclosed as an
   engineering choice, not a spec quote.
3. **Keypad direct-entry rejects out-of-domain values inline** rather than
   silently clamping them (unlike the steppers/knob, which clamp). A typed
   direct entry is exactly the place a user should be told "no", not have
   their number silently changed underneath them.

## Test evidence pointer

See `test/features/tuning/` for the full suite: auto-repeat acceleration
timing, long-press-vs-repeat interplay, domain clamp at both channel
boundaries, keypad range validation (both endpoints, both fields), and
semantics labels.
