import 'package:flutter/material.dart';
import 'package:keryx/core/theme/theme.dart';

/// A labelled free-text control (FR-008 region). Commits on submit
/// (keyboard "done" / losing focus) rather than per keystroke, so typing
/// "global" does not write five half-formed regions to storage.
class PanelTextRow extends StatefulWidget {
  const PanelTextRow({
    super.key,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    this.allowEmpty = false,
  });

  final String label;
  final String description;
  final String value;
  final ValueChanged<String> onChanged;
  final bool allowEmpty;

  @override
  State<PanelTextRow> createState() => _PanelTextRowState();
}

class _PanelTextRowState extends State<PanelTextRow> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  late final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(covariant PanelTextRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only overwrite the field when it isn't focused, so a remote update
    // (another device's `changes` emission) never clobbers an in-flight edit.
    if (widget.value != oldWidget.value &&
        !_focusNode.hasFocus &&
        _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  void _commit() {
    final next = _controller.text.trim();
    if (next != widget.value && (next.isNotEmpty || widget.allowEmpty)) {
      widget.onChanged(next);
    } else if (next.isEmpty) {
      // Refuse an empty region rather than writing one `SettingsRepository`
      // would reject (`_validate` throws on a blank region) — revert instead.
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: KeryxTheme.panelBodyStrong.copyWith(
                    color: KeryxTheme.legend,
                  ),
                ),
                Text(
                  widget.description,
                  style: KeryxTheme.panelBody.copyWith(
                    color: KeryxTheme.legend.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 120,
            height: 48,
            // `TextField` already exposes its own textField/value semantics
            // — no wrapping [Semantics] needed, unlike the tap-target rows
            // above. No `labelText` here either: the row's own bold label
            // above the field already reads it; a floating label would
            // duplicate that exact string in the render tree for no gain.
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textAlign: TextAlign.end,
              style: KeryxTheme.panelBody.copyWith(color: KeryxTheme.lcd),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _commit(),
              onTapOutside: (_) {
                _focusNode.unfocus();
                _commit();
              },
            ),
          ),
        ],
      ),
    );
  }
}
