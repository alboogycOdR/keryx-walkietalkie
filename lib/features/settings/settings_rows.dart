import 'package:flutter/material.dart';
import 'package:keryx/core/theme/ux_tokens.dart';

import 'settings_copy.dart';
import 'settings_keys.dart';

/// One Design §2.6 section: title, readable description, then rows.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final KeryxUxTokens tokens = KeryxUxTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: KeryxUxSpacing.cardSpacing),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tokens.borderDefault),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            KeryxUxSpacing.pageMargin,
            KeryxUxSpacing.controlGap,
            KeryxUxSpacing.pageMargin,
            KeryxUxSpacing.pageMargin,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: KeryxUxTypography.sectionTitle.copyWith(
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: KeryxUxTypography.secondary.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: KeryxUxSpacing.controlGap),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class ReconnectsRadioBadge extends StatelessWidget {
  const ReconnectsRadioBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final KeryxUxTokens tokens = KeryxUxTokens.of(context);
    return Semantics(
      label: SettingsCopy.reconnectsRadio,
      // TASK-057 round 2: at 320 lp width this badge sits inside a narrow
      // `Wrap` slot alongside the row's label text; a `mainAxisSize.min`
      // Row with an un-flexed Text reliably overflowed by a few pixels
      // (reproduced by the responsive-matrix test, not hypothetical).
      // `Flexible` + ellipsis lets it shrink rather than clip/throw.
      child: Row(
        key: SettingsKeys.reconnectBadge,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.sync, size: 16, color: tokens.stateWarning),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              SettingsCopy.reconnectsRadio,
              overflow: TextOverflow.ellipsis,
              style: KeryxUxTypography.compact.copyWith(
                color: tokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsRowHeader extends StatelessWidget {
  const SettingsRowHeader({
    super.key,
    required this.label,
    required this.description,
    this.sessionAffecting = false,
    this.error,
  });

  final String label;
  final String description;
  final bool sessionAffecting;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final KeryxUxTokens tokens = KeryxUxTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              label,
              style: KeryxUxTypography.body.copyWith(color: tokens.textPrimary),
            ),
            if (sessionAffecting) const ReconnectsRadioBadge(),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          description,
          style: KeryxUxTypography.secondary.copyWith(
            color: tokens.textSecondary,
          ),
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            error!,
            style: KeryxUxTypography.compact.copyWith(color: tokens.stateTx),
          ),
        ],
      ],
    );
  }
}

class SettingsStepperRow extends StatelessWidget {
  const SettingsStepperRow({
    super.key,
    required this.label,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.valueLabel,
    required this.onChanged,
    this.sessionAffecting = false,
  });

  final String label;
  final String description;
  final int value;
  final int min;
  final int max;
  final int step;
  final String Function(int value) valueLabel;
  final ValueChanged<int> onChanged;
  final bool sessionAffecting;

  @override
  Widget build(BuildContext context) {
    final KeryxUxTokens tokens = KeryxUxTokens.of(context);
    final String display = valueLabel(value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KeryxUxSpacing.controlGap),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SettingsRowHeader(
              label: label,
              description: description,
              sessionAffecting: sessionAffecting,
            ),
          ),
          _StepButton(
            icon: Icons.remove,
            tooltip: 'Decrease $label',
            enabled: value > min,
            onPressed: () {
              final int next = (value - step).clamp(min, max);
              if (next != value) {
                onChanged(next);
              }
            },
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 36),
            // The bare value text between the two step buttons otherwise
            // announces with no context of which setting it belongs to —
            // give it an explicit label rather than relying on a screen
            // reader's proximity/reading-order guess (TASK-057; Design §5).
            child: Semantics(
              label: '$label, $display',
              excludeSemantics: true,
              child: Text(
                display,
                textAlign: TextAlign.center,
                style: KeryxUxTypography.body.copyWith(
                  color: tokens.textPrimary,
                ),
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add,
            tooltip: 'Increase $label',
            enabled: value < max,
            onPressed: () {
              final int next = (value + step).clamp(min, max);
              if (next != value) {
                onChanged(next);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final KeryxUxTokens tokens = KeryxUxTokens.of(context);
    return SizedBox(
      width: KeryxUxSpacing.minTarget,
      height: KeryxUxSpacing.minTarget,
      child: IconButton(
        tooltip: tooltip,
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, color: tokens.textPrimary),
      ),
    );
  }
}

class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    this.sessionAffecting = false,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool sessionAffecting;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KeryxUxSpacing.controlGap),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SettingsRowHeader(
              label: label,
              description: description,
              sessionAffecting: sessionAffecting,
            ),
          ),
          SizedBox(
            width: KeryxUxSpacing.minTarget,
            height: KeryxUxSpacing.minTarget,
            child: Switch(
              value: value,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPickerRow<T> extends StatelessWidget {
  const SettingsPickerRow({
    super.key,
    required this.label,
    required this.description,
    required this.value,
    required this.options,
    required this.optionLabel,
    required this.onChanged,
    this.sessionAffecting = false,
  });

  final String label;
  final String description;
  final T value;
  final List<T> options;
  final String Function(T value) optionLabel;
  final ValueChanged<T> onChanged;
  final bool sessionAffecting;

  @override
  Widget build(BuildContext context) {
    final KeryxUxTokens tokens = KeryxUxTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KeryxUxSpacing.controlGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SettingsRowHeader(
            label: label,
            description: description,
            sessionAffecting: sessionAffecting,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final T option in options)
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: KeryxUxSpacing.minTarget,
                  ),
                  child: ChoiceChip(
                    label: Text(optionLabel(option)),
                    selected: option == value,
                    onSelected: (bool selected) {
                      if (selected) {
                        onChanged(option);
                      }
                    },
                    selectedColor: tokens.surfaceRaised,
                    labelStyle: KeryxUxTypography.secondary.copyWith(
                      color: tokens.textPrimary,
                    ),
                    side: BorderSide(color: tokens.borderDefault),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class SettingsTextRow extends StatefulWidget {
  const SettingsTextRow({
    super.key,
    required this.label,
    required this.description,
    required this.value,
    required this.onSubmit,
    this.sessionAffecting = false,
    this.error,
    this.enabled = true,
  });

  final String label;
  final String description;
  final String value;
  final ValueChanged<String> onSubmit;
  final bool sessionAffecting;
  final String? error;
  final bool enabled;

  @override
  State<SettingsTextRow> createState() => _SettingsTextRowState();
}

class _SettingsTextRowState extends State<SettingsTextRow> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  late final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _commit();
      }
    });
  }

  @override
  void didUpdateWidget(covariant SettingsTextRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value &&
        !_focus.hasFocus &&
        _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  void _commit() {
    final String next = _controller.text.trim();
    if (next != widget.value) {
      widget.onSubmit(next);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final KeryxUxTokens tokens = KeryxUxTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KeryxUxSpacing.controlGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SettingsRowHeader(
            label: widget.label,
            description: widget.description,
            sessionAffecting: widget.sessionAffecting,
            error: widget.error,
          ),
          const SizedBox(height: 8),
          // The visible label lives in `SettingsRowHeader` above (not
          // `InputDecoration.labelText`, which would float a second,
          // visually duplicate label) — so a screen reader needs an
          // explicit association between that text and this field rather
          // than relying on proximity alone (TASK-057; Design §5).
          Semantics(
            label: widget.label,
            textField: true,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              enabled: widget.enabled,
              style: KeryxUxTypography.body.copyWith(
                color: tokens.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: tokens.surfaceRaised,
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: tokens.borderDefault),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: tokens.borderDefault),
                ),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _commit(),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsReadOnlyRow extends StatelessWidget {
  const SettingsReadOnlyRow({
    super.key,
    required this.label,
    required this.description,
    required this.value,
  });

  final String label;
  final String description;
  final String value;

  @override
  Widget build(BuildContext context) {
    final KeryxUxTokens tokens = KeryxUxTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KeryxUxSpacing.controlGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SettingsRowHeader(label: label, description: description),
          const SizedBox(height: 4),
          Text(
            value,
            style: KeryxUxTypography.body.copyWith(color: tokens.textPrimary),
          ),
        ],
      ),
    );
  }
}
