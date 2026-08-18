import 'package:flutter/material.dart';
import 'package:keryx/core/theme/theme.dart';

/// Immutable information rendered by [KeryxLcdDisplay].
///
/// This model deliberately owns no radio state. A host derives it from the
/// reducer, floor engine, and settings, then replaces it as those sources
/// change.
@immutable
class KeryxDisplayModel {
  const KeryxDisplayModel.numbered({
    required this.channel,
    required this.code,
    this.modeLabel = 'LOCAL',
    this.statusLine = 'CHANNEL CLEAR',
    this.telltales = const <KeryxTelltale>{},
    this.isBooting = false,
    this.dimLevel = 1,
  }) : privateLabel = null,
       assert(channel >= 1 && channel <= 99),
       assert(code >= 0 && code <= 38),
       assert(dimLevel >= 0 && dimLevel <= 1);

  const KeryxDisplayModel.private({
    required String label,
    this.modeLabel = 'LOCAL',
    this.statusLine = 'KEYED CHANNEL',
    this.telltales = const <KeryxTelltale>{},
    this.isBooting = false,
    this.dimLevel = 1,
  }) : channel = -1,
       code = -1,
       privateLabel = label,
       assert(label != ''),
       assert(dimLevel >= 0 && dimLevel <= 1);

  final int channel;
  final int code;
  final String? privateLabel;
  final String modeLabel;
  final String statusLine;
  final Set<KeryxTelltale> telltales;
  final bool isBooting;

  /// Glass luminance, from 0 (dark) to 1 (normal). Supplied by dim settings.
  final double dimLevel;

  bool get isPrivate => privateLabel != null;

  String get primaryLine {
    if (isBooting) return '88 · 88';
    if (isPrivate) return 'PRV';
    return 'CH ${channel.toString().padLeft(2, '0')} · '
        '${code.toString().padLeft(2, '0')}';
  }

  String get secondaryLine => isPrivate ? privateLabel! : statusLine;
}

/// Indicators which can be lit inside the display glass.
enum KeryxTelltale { tx, mon, prv, vox, emg, noLink, replay }

/// The radio's self-contained transflective LCD glass.
class KeryxLcdDisplay extends StatelessWidget {
  const KeryxLcdDisplay({super.key, required this.model});

  final KeryxDisplayModel model;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: _semanticLabel(),
      child: Opacity(
        opacity: model.dimLevel,
        child: Container(
          key: const Key('keryx-lcd-glass'),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: KeryxTheme.glass,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF0A0F0C)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.85),
                offset: Offset(0, 3),
                blurRadius: 10,
                blurStyle: BlurStyle.inner,
              ),
              BoxShadow(color: Color.fromRGBO(255, 255, 255, 0.05)),
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
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _primaryRow(),
                  const SizedBox(height: 8),
                  _secondaryRow(),
                  const SizedBox(height: 7),
                  _telltaleRow(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _primaryRow() => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: <Widget>[
      Expanded(
        child: Stack(
          alignment: Alignment.centerLeft,
          children: <Widget>[
            Text(
              '88 · 88',
              key: const Key('keryx-lcd-ghost-segments'),
              style: KeryxTheme.channelNumerals.copyWith(
                color: KeryxTheme.lcd.withValues(
                  alpha: KeryxTheme.ghostSegmentOpacity,
                ),
              ),
            ),
            Text(
              model.primaryLine,
              key: const Key('keryx-lcd-primary'),
              style: KeryxTheme.channelNumerals.copyWith(
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
      ),
      Text(
        model.modeLabel,
        key: const Key('keryx-lcd-mode'),
        style: KeryxTheme.telltale.copyWith(
          color: KeryxTheme.lcd.withValues(alpha: 0.85),
          letterSpacing: 11 * 0.16,
        ),
      ),
    ],
  );

  Widget _secondaryRow() => Row(
    children: <Widget>[
      Expanded(
        child: Text(
          model.secondaryLine,
          key: const Key('keryx-lcd-secondary'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: KeryxTheme.glassSecondary.copyWith(color: KeryxTheme.lcd),
        ),
      ),
    ],
  );

  Widget _telltaleRow() => Wrap(
    spacing: 7,
    children: KeryxTelltale.values
        .map(
          (indicator) => _TelltaleIndicator(
            telltale: indicator,
            isActive:
                model.telltales.contains(indicator) ||
                (model.isPrivate && indicator == KeryxTelltale.prv),
          ),
        )
        .toList(growable: false),
  );

  String _semanticLabel() =>
      '${model.primaryLine}, ${model.secondaryLine}, '
      '${model.modeLabel}${model.telltales.isEmpty ? '' : ', indicators active'}';
}

class _TelltaleIndicator extends StatelessWidget {
  const _TelltaleIndicator({required this.telltale, required this.isActive});

  final KeryxTelltale telltale;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = switch (telltale) {
      KeryxTelltale.tx => KeryxTheme.tx,
      KeryxTelltale.emg => KeryxTheme.emergency,
      _ => KeryxTheme.lcd,
    };
    return Opacity(
      opacity: isActive ? 1 : 0.09,
      child: Text(
        telltale.name == 'noLink' ? 'NO LINK' : telltale.name.toUpperCase(),
        key: Key('keryx-lcd-telltale-${telltale.name}'),
        style: KeryxTheme.telltale.copyWith(
          color: color,
          letterSpacing: 11 * 0.12,
        ),
      ),
    );
  }
}
