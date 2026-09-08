/// User-facing copy for the Stations screen (Design §2.4 / §5).
abstract final class StationsCopy {
  static const String title = 'Stations';

  /// Design §5 empty-state copy. Used when the local station stream is
  /// empty; never as a verified LINKED member total (UX-FR-046).
  static const String empty = 'No other stations are currently visible';

  /// Design §2.4 / UX-FR-046 — LINKED roster is incomplete through this
  /// interface (Technical §1.1). Never paired with a numeric member count.
  static const String linkedUnavailable = 'Complete member list unavailable';

  /// UX-FR-045 / VT-024 — placeholder `signalQuality` is not measured.
  static const String qualityUnavailable = 'Quality unavailable';

  /// Presence label for a station currently on the live stream.
  static const String presenceVisible = 'Visible';

  /// UX-FR-026 — unknown identity; never a raw peer ID.
  static const String unknownStation = 'Unknown station';

  static const String scanEventQr = 'Scan event QR';
  static const String exportEventQr = 'Export event QR';

  /// Semantic label for the local (signaling-backed) count, distinct
  /// from any LINKED member count (UX-FR-046).
  static const String localCountLabel = 'Local stations';

  /// Semantic label for the LINKED member-count field.
  static const String linkedCountLabel = 'LINKED members';

  static String localCount(int count) => '$localCountLabel: $count';

  static String channelContext(int channel, int privacyCode) {
    final String ch = channel.toString().padLeft(2, '0');
    final String code = privacyCode.toString().padLeft(2, '0');
    return 'CH $ch · $code';
  }
}
