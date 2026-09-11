import 'package:flutter/material.dart';

import '../../core/presentation/connection_condition.dart';
import '../../core/state/radio_state.dart' show RadioMode;
import '../../core/theme/ux_tokens.dart';
import 'talk_copy.dart';

/// ADR-002 §3 A2's channel card — replaces the old back/channel header row.
///
/// Purely presentational: it owns no radio/session state and issues no
/// navigation itself, only forwarding the caller-supplied callbacks. `48 dp`
/// tap targets throughout, `surface/card` fill, `16` radius (ADR-002 A2).
class TalkChannelCard extends StatelessWidget {
  const TalkChannelCard({
    super.key,
    required this.channel,
    required this.privacyCode,
    required this.connection,
    required this.stationCountLabel,
    this.onOpenPicker,
    this.onOpenStations,
    this.onOpenRadioControls,
  });

  /// Current, authoritative channel (1-99).
  final int channel;

  /// Current, authoritative privacy code (0-38).
  final int privacyCode;

  /// Configured mode vs. effective route (Technical §7) — the card shows
  /// the effective route always, and the configured preference only when
  /// it differs from the effective route.
  final ConnectionCondition connection;

  /// Honest station-count label (never a fabricated presence count —
  /// Design §2.1/§2.4), rendered on the trailing station-count chip.
  final String stationCountLabel;

  /// Opens the channel picker (TASK-050's selector). `null` renders the
  /// picker button disabled rather than throwing on tap.
  final VoidCallback? onOpenPicker;

  /// Opens the Stations tab/screen. `null` renders the station-count chip
  /// disabled rather than throwing on tap.
  final VoidCallback? onOpenStations;

  /// Opens Radio controls. Per ADR-002 A2/description, the tune icon
  /// renders **only when this callback is non-null** — it is not merely
  /// disabled when absent, it is omitted entirely.
  final VoidCallback? onOpenRadioControls;

  static String _modeLabel(RadioMode mode) => switch (mode) {
    RadioMode.local => 'LOCAL',
    RadioMode.linked => 'LINKED',
    RadioMode.auto => 'AUTO',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = KeryxUxTokens.of(context);
    final String channelLabel = channel.toString().padLeft(2, '0');
    final String codeLabel = privacyCode.toString().padLeft(2, '0');
    final String routeLabel = connection.routeLabel;
    final bool configuredDiffers =
        _modeLabel(connection.configuredMode) != routeLabel;
    final String routeLine = configuredDiffers
        ? 'Route $routeLabel · Configured ${_modeLabel(connection.configuredMode)}'
        : 'Route $routeLabel';

    return Container(
      key: const Key('keryx-talk-channel-card'),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: <Widget>[
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              channelLabel,
              key: const Key('keryx-talk-channel-tile'),
              style: KeryxUxTypography.sectionTitle.copyWith(
                color: tokens.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'CH $channelLabel · $codeLabel',
                  key: const Key('keryx-talk-channel-label'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KeryxUxTypography.body.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  routeLine,
                  key: const Key('keryx-talk-route-line'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KeryxUxTypography.compact.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // `Flexible`, not a bare `TextButton.icon` (which sizes to its
          // label's intrinsic width): at 320 lp width with system text
          // scale 2.0, an unbounded station-count label was the single
          // largest contributor to a `RenderFlex` overflow in this Row —
          // this lets it shrink and ellipsize instead of pushing the
          // picker/radio-controls buttons off the card.
          Flexible(
            child: SizedBox(
              height: 48,
              child: TextButton(
                key: const Key('keryx-talk-stations'),
                onPressed: onOpenStations,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.groups_outlined, color: tokens.textSecondary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        stationCountLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KeryxUxTypography.compact.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              key: const Key('keryx-talk-picker'),
              tooltip: TalkCopy.openChannelPicker,
              onPressed: onOpenPicker,
              icon: Icon(Icons.dialpad, color: tokens.textSecondary),
            ),
          ),
          if (onOpenRadioControls != null)
            SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                key: const Key('keryx-talk-radio-controls'),
                tooltip: TalkCopy.openRadioControls,
                onPressed: onOpenRadioControls,
                icon: Icon(Icons.tune, color: tokens.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}
