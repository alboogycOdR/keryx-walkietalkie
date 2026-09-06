import 'package:flutter/material.dart';
import 'package:keryx/core/theme/theme.dart';

/// Mode/status telltales in the compact LCD strip.
///
/// Lit = [KeryxTheme.lcd] (amber). Unlit = the same colour at
/// [KeryxTheme.ghostSegmentOpacity] (7% ghost). The strip does not use
/// signal colours for these four labels — TX red / RX green live on the
/// PTT disc (TASK-042), not here.
enum KeryxStripTelltale { local, linked, tx, rx }

/// Immutable information rendered by [KeryxLcdDisplay].
///
/// Plain data only: no `FaceScreen`, session, or controller types. A host
/// (TASK-043) derives these fields from the reducer and replaces the model
/// as those sources change.
@immutable
class KeryxDisplayModel {
  const KeryxDisplayModel({
    required this.channel,
    this.mode = 'LOCAL',
    this.telltales = const <KeryxStripTelltale>{},
    this.statusLine = 'CHANNEL CLEAR',
    this.signalQuality = 0,
    this.dimLevel = 1,
    this.isBooting = false,
  }) : assert(channel >= 1 && channel <= 99),
       assert(signalQuality >= 0 && signalQuality <= 9),
       assert(dimLevel >= 0 && dimLevel <= 1),
       assert(mode != '');

  /// Numbered channel 1–99. Rendered as two DSEG7 digits.
  final int channel;

  /// Mode label for semantics / TalkBack (e.g. `LOCAL`, `LINKED`, `AUTO`).
  /// Lighting LOCAL vs LINKED is independent and lives in [telltales].
  final String mode;

  /// Which of LOCAL / LINKED / TX / RX are lit. Absent = ghost.
  final Set<KeryxStripTelltale> telltales;

  /// Mono status line. Host supplies copy such as `CHANNEL CLEAR`,
  /// `TX 00:07`, or `RX BRAVO-7`.
  final String statusLine;

  /// Aggregate S-meter 0–9 (0 = none lit, 1–9 = S1–S9 per FR-069).
  final int signalQuality;

  /// Glass luminance, from 0 (dark) to 1 (normal). Supplied by dim settings.
  final double dimLevel;

  /// When true the digit field shows the all-segments `88` flash (FR-109).
  final bool isBooting;

  /// Two-digit channel field, zero-padded. Boot flash is `88`.
  String get channelDigits =>
      isBooting ? '88' : channel.toString().padLeft(2, '0');

  /// Spoken / semantic primary readout, e.g. `CH 07`.
  String get primaryLine => 'CH $channelDigits';
}

/// Compact transflective LCD header strip.
///
/// Telltale row (LOCAL / LINKED / TX / RX) + `CH ##` seven-segment +
/// S-meter cluster + a mono status line, recessed in the same glass chrome
/// as the original full-size display. Height is intrinsic; the host sizes
/// the band around it.
class KeryxLcdDisplay extends StatelessWidget {
  const KeryxLcdDisplay({super.key, required this.model});

  final KeryxDisplayModel model;

  /// Compact strip scale. DS §3 lists channel numerals at 56 for the
  /// original full glass; the approved canvas shrinks the surrounding
  /// layout, so the face stays DSEG7 Classic at a strip-sized 32.
  static const double _digitSize = 32;

  static const int _sMeterBars = 9;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: _semanticLabel(),
      child: Opacity(
        opacity: model.dimLevel,
        child: Container(
          key: const Key('keryx-lcd-glass'),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: KeryxTheme.glass,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: KeryxTheme.glassBorder),
            boxShadow: <BoxShadow>[
              KeryxTheme.glassInnerShadow,
              KeryxTheme.glassHighlight,
            ],
          ),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.bottomCenter,
                        radius: 1.15,
                        colors: <Color>[
                          KeryxTheme.lcd.withValues(alpha: 0.06),
                          KeryxTheme.glassBloomStop,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _telltaleRow(),
                  const SizedBox(height: 6),
                  _channelRow(),
                  const SizedBox(height: 6),
                  _statusLine(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _telltaleRow() => Row(
    children: KeryxStripTelltale.values
        .map(
          (indicator) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _TelltaleIndicator(
              telltale: indicator,
              isActive: model.telltales.contains(indicator),
            ),
          ),
        )
        .toList(growable: false),
  );

  Widget _channelRow() => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 2, right: 6),
        child: Text(
          'CH',
          key: const Key('keryx-lcd-channel-prefix'),
          style: KeryxTheme.glassSecondary.copyWith(
            color: KeryxTheme.lcd.withValues(alpha: 0.85),
          ),
        ),
      ),
      Stack(
        alignment: Alignment.centerLeft,
        children: <Widget>[
          Text(
            '88',
            key: const Key('keryx-lcd-ghost-segments'),
            style: KeryxTheme.channelNumerals.copyWith(
              fontSize: _digitSize,
              color: KeryxTheme.lcd.withValues(
                alpha: KeryxTheme.ghostSegmentOpacity,
              ),
            ),
          ),
          Text(
            model.channelDigits,
            key: const Key('keryx-lcd-primary'),
            style: KeryxTheme.channelNumerals.copyWith(
              fontSize: _digitSize,
              color: KeryxTheme.lcd,
              shadows: <Shadow>[
                Shadow(
                  color: KeryxTheme.lcd.withValues(alpha: 0.35),
                  blurRadius: 14,
                ),
              ],
            ),
          ),
        ],
      ),
      const Spacer(),
      _SMeter(quality: model.signalQuality),
    ],
  );

  Widget _statusLine() => Text(
    model.statusLine,
    key: const Key('keryx-lcd-secondary'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: KeryxTheme.glassSecondary.copyWith(color: KeryxTheme.lcd),
  );

  String _semanticLabel() {
    final lit = model.telltales.map((t) => t.name.toUpperCase()).join(', ');
    final meter = model.signalQuality == 0
        ? 'no signal'
        : 'signal S${model.signalQuality}';
    return '${model.primaryLine}, ${model.mode}, ${model.statusLine}, '
        '$meter${lit.isEmpty ? '' : ', $lit'}';
  }
}

class _TelltaleIndicator extends StatelessWidget {
  const _TelltaleIndicator({required this.telltale, required this.isActive});

  final KeryxStripTelltale telltale;
  final bool isActive;

  static const Map<KeryxStripTelltale, String> _labels =
      <KeryxStripTelltale, String>{
        KeryxStripTelltale.local: 'LOCAL',
        KeryxStripTelltale.linked: 'LINKED',
        KeryxStripTelltale.tx: 'TX',
        KeryxStripTelltale.rx: 'RX',
      };

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isActive ? 1 : KeryxTheme.ghostSegmentOpacity,
      child: Text(
        _labels[telltale]!,
        key: Key('keryx-lcd-telltale-${telltale.name}'),
        style: KeryxTheme.telltale.copyWith(
          color: KeryxTheme.lcd,
          letterSpacing: 11 * 0.12,
        ),
      ),
    );
  }
}

/// Nine-bar S-meter cluster (FR-069 S1–S9). Lit bars use the RX signal
/// token; unlit bars are LCD-ghost so they stay inside the glass amber
/// rule for unlit segments.
class _SMeter extends StatelessWidget {
  const _SMeter({required this.quality});

  final int quality;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: quality == 0 ? 'No signal' : 'Signal S$quality',
      child: Row(
        key: const Key('keryx-lcd-smeter'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List<Widget>.generate(KeryxLcdDisplay._sMeterBars, (index) {
          final bar = index + 1;
          final lit = bar <= quality;
          return Container(
            key: Key('keryx-lcd-smeter-bar-$bar'),
            width: 3,
            height: 4 + index * 1.1,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: lit
                  ? KeryxTheme.rx
                  : KeryxTheme.lcd.withValues(
                      alpha: KeryxTheme.ghostSegmentOpacity,
                    ),
              borderRadius: BorderRadius.circular(1),
            ),
          );
        }),
      ),
    );
  }
}
