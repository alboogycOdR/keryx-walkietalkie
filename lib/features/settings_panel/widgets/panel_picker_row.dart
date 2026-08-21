import 'package:flutter/material.dart';
import 'package:keryx/core/theme/theme.dart';

/// A labelled enum control (roger-beep variant, character-DSP intensity,
/// dim mode) — every option is its own ≥ 48 dp tap target (FR-106) rather
/// than a menu, so a TalkBack user can reach any value directly.
class PanelPickerRow<T> extends StatelessWidget {
  const PanelPickerRow({
    super.key,
    required this.label,
    required this.description,
    required this.value,
    required this.options,
    required this.optionLabel,
    required this.onChanged,
  });

  final String label;
  final String description;
  final T value;
  final List<T> options;
  final String Function(T value) optionLabel;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: KeryxTheme.panelBodyStrong.copyWith(color: KeryxTheme.legend),
          ),
          Text(
            description,
            style: KeryxTheme.panelBody.copyWith(
              color: KeryxTheme.legend.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: KeryxTheme.grid),
          Wrap(
            spacing: KeryxTheme.grid,
            runSpacing: KeryxTheme.grid,
            children: [
              for (final option in options)
                _OptionChip<T>(
                  label: optionLabel(option),
                  // Prefixed with the row's own label so two rows sharing
                  // an option word (e.g. ROGER BEEP's and CHARACTER DSP's
                  // both have an `OFF`) never collide on TalkBack focus or
                  // on a `find.bySemanticsLabel` widget-test lookup.
                  semanticsLabel: '$label ${optionLabel(option)}',
                  selected: option == value,
                  onSelected: () => onChanged(option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionChip<T> extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.semanticsLabel,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String semanticsLabel;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? KeryxTheme.olive : KeryxTheme.shell500,
                borderRadius: BorderRadius.circular(8),
                boxShadow: KeryxTheme.raisedMaterialEdges,
              ),
              child: Text(
                label,
                style: KeryxTheme.legendLabel.copyWith(
                  color: selected ? KeryxTheme.shell900 : KeryxTheme.legend,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
