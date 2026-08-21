import 'package:flutter/material.dart';
import 'package:keryx/core/theme/theme.dart';

/// A labelled, clamped integer control (squelch 0–10, the FR-023 TOT
/// 30–120 s duration) — `−`/`+` buttons ≥ 48 dp (FR-106), each tap already
/// clamped to `[min, max]` so this widget can never emit an out-of-range
/// value onto [SettingsRepository]'s own validation.
class PanelStepperRow extends StatelessWidget {
  const PanelStepperRow({
    super.key,
    required this.label,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.valueLabel,
    required this.onChanged,
  }) : assert(min <= max),
       assert(step > 0);

  final String label;
  final String description;
  final int value;
  final int min;
  final int max;
  final int step;
  final String Function(int value) valueLabel;
  final ValueChanged<int> onChanged;

  void _step(int direction) {
    final next = (value + direction * step).clamp(min, max);
    if (next != value) onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final display = valueLabel(value);
    return Semantics(
      label: '$label, $display',
      hint: description,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: KeryxTheme.panelBodyStrong.copyWith(
                      color: KeryxTheme.legend,
                    ),
                  ),
                  Text(
                    description,
                    style: KeryxTheme.panelBody.copyWith(
                      color: KeryxTheme.legend.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
            _StepButton(
              glyph: '−',
              semanticsLabel: 'Decrease $label',
              enabled: value > min,
              onPressed: () => _step(-1),
            ),
            SizedBox(
              width: 56,
              child: Text(
                display,
                textAlign: TextAlign.center,
                style: KeryxTheme.panelBodyStrong.copyWith(
                  color: KeryxTheme.lcd,
                ),
              ),
            ),
            _StepButton(
              glyph: '+',
              semanticsLabel: 'Increase $label',
              enabled: value < max,
              onPressed: () => _step(1),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.glyph,
    required this.semanticsLabel,
    required this.enabled,
    required this.onPressed,
  });

  final String glyph;
  final String semanticsLabel;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: KeryxTheme.shell500,
              borderRadius: BorderRadius.circular(8),
              boxShadow: KeryxTheme.raisedMaterialEdges,
            ),
            child: Text(
              glyph,
              style: KeryxTheme.panelBodyStrong.copyWith(
                color: enabled
                    ? KeryxTheme.legend
                    : KeryxTheme.legend.withValues(alpha: 0.35),
                fontSize: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
