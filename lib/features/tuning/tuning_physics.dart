/// Pure, widget-free stepper/keypad tuning constants (KRX-013).
///
/// Mirrors `KnobPhysics`'s shape (`lib/features/knob/knob_physics.dart`) —
/// each precision-tuning widget owns its own small constants file rather
/// than importing across frozen feature territories, same convention
/// `PttHapticFeedback`'s dartdoc documents for the haptics half.
///
/// **Channel/code domain bounds are duplicated from
/// `RadioState.minimumChannel`/`maximumChannel`/`minimumPrivacyCode`/
/// `maximumPrivacyCode` (`lib/core/state/radio_state.dart`, frozen) rather
/// than imported.** Same choice `KnobPhysics` made for the identical bounds:
/// this widget tree stays a pure presentation/intent layer with zero
/// dependency on the reducer's territory, and the two ORCH rulings that fix
/// these numbers (follow-up (k), 2026-08-19T18:30:00Z: CLAMP not wrap, at
/// exactly 1/99 and 00/38) are the single source of truth both files quote.
library;

/// CH▲/CH▼ stepper and keypad-entry constants.
abstract final class TuningPhysics {
  /// TS/`RadioState.minimumChannel`.
  static const int minimumChannel = 1;

  /// TS/`RadioState.maximumChannel`.
  static const int maximumChannel = 99;

  /// TS/`RadioState.minimumPrivacyCode`.
  static const int minimumPrivacyCode = 0;

  /// TS/`RadioState.maximumPrivacyCode`.
  static const int maximumPrivacyCode = 38;

  /// PT `stepper()`'s auto-repeat arm delay before the first repeat tick
  /// (`specs/keryx-face-prototype.html` L332: `setTimeout(function rep(){...},420)`).
  /// The very first tick fires synchronously on press, matching PT's `go()`
  /// call inside `start()` before this timer is even armed.
  static const Duration initialRepeatDelay = Duration(milliseconds: 420);

  /// PT `stepper()`'s repeat-rate starting point (`rate=260` in `start()`,
  /// consumed by the *first* `rep()` firing at [initialRepeatDelay]).
  static const double initialRepeatRateMs = 260;

  /// PT `rate=Math.max(60,rate*0.82)` — repeat interval shrinks by this
  /// factor on every subsequent tick.
  static const double repeatAcceleration = 0.82;

  /// PT `Math.max(60, ...)` — the repeat interval floor.
  static const double minRepeatRateMs = 60;

  /// Long-press threshold for CH▼'s quick-recall gesture (FR-009). PT never
  /// implements channel memory at all (grep-confirmed absent), so there is
  /// no ratified PT/TS number for this specific gesture; [ChStepperButton]'s
  /// own dartdoc discloses the resulting overlap with auto-repeat as a
  /// non-blocking engineering resolution. Reused verbatim from the
  /// established EmgKey long-press convention (`lib/features/ptt/emg_key.dart`,
  /// PT L386-388) for cross-widget consistency rather than inventing a new
  /// number.
  static const Duration recallLongPressThreshold = Duration(milliseconds: 600);

  /// Clamps a raw channel delta against [currentChannel] so the result never
  /// pushes the channel outside `[minimumChannel, maximumChannel]` — CLAMP
  /// semantics per the ORCH ruling (follow-up k), identical to
  /// `KnobPhysics.clampDelta`. Returns the delta actually applicable (may be
  /// `0` at a boundary).
  static int clampChannelDelta(int currentChannel, int rawDelta) {
    final target = (currentChannel + rawDelta).clamp(
      minimumChannel,
      maximumChannel,
    );
    return target - currentChannel;
  }

  /// `true` iff [channel] lies in `[minimumChannel, maximumChannel]`.
  static bool isValidChannel(int channel) =>
      channel >= minimumChannel && channel <= maximumChannel;

  /// `true` iff [code] lies in `[minimumPrivacyCode, maximumPrivacyCode]`.
  static bool isValidPrivacyCode(int code) =>
      code >= minimumPrivacyCode && code <= maximumPrivacyCode;
}
