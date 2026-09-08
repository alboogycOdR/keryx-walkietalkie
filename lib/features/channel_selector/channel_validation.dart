import 'package:keryx/core/state/radio_state.dart' show RadioState;

/// Pure validation for the direct-entry fields (Design §2.3: "Users can
/// enter channel 1–99 and code 0–38"; UX-FR-003; VT-020). Rejects
/// non-numeric, empty, out-of-range and negative input without ever
/// dispatching a tune — parsing alone must never have a side effect.
abstract final class ChannelInputValidation {
  /// Parses a channel number, or `null` if [text] is not a valid channel
  /// (empty, non-numeric, or outside 1–99).
  static int? parseChannel(String text) => _parseInRange(
    text,
    RadioState.minimumChannel,
    RadioState.maximumChannel,
  );

  /// Parses a privacy code, or `null` if [text] is not a valid code (empty,
  /// non-numeric, or outside 0–38).
  static int? parseCode(String text) => _parseInRange(
    text,
    RadioState.minimumPrivacyCode,
    RadioState.maximumPrivacyCode,
  );

  static int? _parseInRange(String text, int min, int max) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    // int.tryParse alone would accept "+7"/"07" (fine) but also leading/
    // trailing garbage handled by trim; explicitly reject anything that
    // isn't plain digits so "1e2"/"1.0"/"--1" cannot slip through.
    if (!RegExp(r'^\d+$').hasMatch(trimmed)) return null;
    final value = int.tryParse(trimmed);
    if (value == null) return null;
    if (value < min || value > max) return null;
    return value;
  }

  /// Always-two-digit label (Design §2.3; UX-FR-003).
  static String twoDigit(int value) => value.toString().padLeft(2, '0');
}
