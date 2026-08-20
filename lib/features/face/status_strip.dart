import 'package:flutter/material.dart';
import 'package:keryx/core/theme/theme.dart';

/// Top status band per PT `.strip`: aggregate S-meter · `STN n` (tap to flip,
/// FR-067) · mode label · battery.
class StatusStrip extends StatelessWidget {
  const StatusStrip({
    super.key,
    required this.stationCount,
    required this.signalQuality,
    required this.modeLabel,
    required this.batteryLevel,
    required this.onStationsTap,
  });

  /// FR-067 `STN n` count, aggregate across the whole roster.
  final int stationCount;

  /// FR-069 aggregate S-meter (S1-S9), or `null` when there is no signal to
  /// aggregate (no stations in roster).
  final int? signalQuality;

  final String modeLabel;

  /// 0-1. No battery API is wired to this task's territory (no plugin
  /// dependency is in `Owned_Paths`); a caller may supply a live value once
  /// one exists. Defaults to a static placeholder in [FaceScreen].
  final double batteryLevel;

  final VoidCallback onStationsTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: KeryxTheme.shell900,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          _SMeter(quality: signalQuality),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              button: true,
              label: 'Station list, $stationCount station'
                  '${stationCount == 1 ? '' : 's'}. Double tap to view.',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onStationsTap,
                child: Text(
                  'STN $stationCount · $modeLabel',
                  key: const Key('keryx-status-strip-stn'),
                  style: KeryxTheme.panelBody.copyWith(
                    color: KeryxTheme.legend,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _Battery(level: batteryLevel),
        ],
      ),
    );
  }
}

class _SMeter extends StatelessWidget {
  const _SMeter({required this.quality});

  final int? quality;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: quality == null ? 'No signal' : 'Signal S$quality',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List<Widget>.generate(9, (index) {
          final bar = index + 1;
          final lit = quality != null && bar <= quality!;
          return Container(
            width: 3,
            height: 6 + index.toDouble(),
            margin: const EdgeInsets.only(right: 1.5),
            color: lit
                ? KeryxTheme.rx
                : KeryxTheme.legend.withValues(alpha: 0.18),
          );
        }),
      ),
    );
  }
}

class _Battery extends StatelessWidget {
  const _Battery({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final pct = (level.clamp(0, 1) * 100).round();
    return Semantics(
      label: 'Battery $pct percent',
      child: Text(
        'BAT $pct%',
        style: KeryxTheme.panelBody.copyWith(
          color: KeryxTheme.legend,
          fontSize: 12,
        ),
      ),
    );
  }
}
