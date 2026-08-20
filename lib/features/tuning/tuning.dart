/// KERYX precision/accessibility tuning widgets (KRX-013): CH▲/CH▼ steppers
/// with accelerating auto-repeat, the keypad direct-entry sheet, and the
/// channel-memory quick-recall panel. All three emit tuning intents only —
/// channel state itself lives in `lib/core/state`'s reducer (TASK-004/027),
/// wired by TASK-017.
library;

export 'channel_recall.dart';
export 'keypad_sheet.dart';
export 'stepper_button.dart';
export 'tuning_haptics.dart';
export 'tuning_physics.dart';
