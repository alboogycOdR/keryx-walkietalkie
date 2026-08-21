import 'package:flutter/material.dart';
import 'package:keryx/core/theme/theme.dart';

/// A single labelled on/off control (latch, busy lockout, force-LOCAL-only)
/// — ≥ 48 dp target (FR-106) and TalkBack labelled through one merged
/// [Semantics] node rather than the decorative [Switch]'s own, same
/// merge-avoidance convention `ChStepperButton` established
/// (`lib/features/tuning/stepper_button.dart`).
class PanelToggleRow extends StatelessWidget {
  const PanelToggleRow({
    super.key,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      hint: description,
      toggled: value,
      button: true,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
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
                  Switch(
                    value: value,
                    onChanged: onChanged,
                    activeThumbColor: KeryxTheme.olive,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
