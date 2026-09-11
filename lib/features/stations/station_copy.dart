import 'package:keryx/core/presentation/connection_condition.dart';
import 'package:keryx/core/presentation/telemetry.dart';
import 'package:keryx/core/state/radio_state.dart' show RadioMode;

/// User-facing copy for the Stations screen (Design §2.4 / §5).
abstract final class StationsCopy {
  static const String title = 'Stations';

  /// Design §5 empty-state copy. Used only when [RosterCount] is a
  /// verified [KnownRosterCount] of zero — never on an unknown roster
  /// (UX-FR-046; VT-024).
  static const String empty = 'No other stations are currently visible';

  /// Design §2.4 / UX-FR-046 — roster is incomplete through this
  /// interface (Technical §1.1). Never paired with a numeric member count.
  static const String linkedUnavailable = 'Complete member list unavailable';

  /// Host station-stream fault — stated unavailable, not a stale snapshot
  /// and not Design §5's verified-empty copy.
  static const String streamUnavailable = 'Station list unavailable';

  /// UX-FR-045 / VT-024 — no real quality metric on the projection.
  static const String qualityUnavailable = 'Quality unavailable';

  /// Presence label for a station currently on the live stream.
  static const String presenceVisible = 'Visible';

  /// UX-FR-026 — unknown identity; never a raw peer ID.
  static const String unknownStation = 'Unknown station';

  static const String scanEventQr = 'Scan event QR';
  static const String exportEventQr = 'Export event QR';

  /// Semantic label for a verified local (signaling-backed) count.
  static const String localCountLabel = 'Local stations';

  /// Semantic label for the LINKED member-count field.
  static const String linkedCountLabel = 'LINKED members';

  /// Semantic label while the effective route is still unresolved.
  /// AUTO is a configured preference, never an effective-route members
  /// heading (Technical §7).
  static const String connectingCountLabel = 'Connecting';

  static String localCount(int count) => '$localCountLabel: $count';

  /// Incomplete-roster field label follows the resolved effective route,
  /// never a hardcoded LINKED string and never AUTO.
  static String membersLabel(ConnectionCondition connection) {
    if (!connection.isResolved) return connectingCountLabel;
    return switch (connection.effectiveRoute) {
      RadioMode.local => localCountLabel,
      RadioMode.linked => linkedCountLabel,
      RadioMode.auto => connectingCountLabel,
    };
  }

  static String incompleteRoster(ConnectionCondition connection) =>
      '${membersLabel(connection)}: $linkedUnavailable';

  /// Real S-meter text (1–9). Never a bar widget (UX-FR-045).
  static String qualityMeasured(int sMeter) => 'Quality: S$sMeter';

  static String qualityLabel(SignalQuality quality) => switch (quality) {
    UnavailableSignalQuality() => qualityUnavailable,
    MeasuredSignalQuality(:final int sMeter) => qualityMeasured(sMeter),
  };

  static String channelContext(int channel, int privacyCode) {
    final String ch = channel.toString().padLeft(2, '0');
    final String code = privacyCode.toString().padLeft(2, '0');
    return 'CH $ch · $code';
  }
}
