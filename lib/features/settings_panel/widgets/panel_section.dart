import 'package:flutter/material.dart';
import 'package:keryx/core/theme/theme.dart';

/// A back-panel / battery-hatch styled group of controls (FR-100) —
/// housing-coloured material framed with four corner "screws", echoing the
/// radio's physical hatch rather than reading as a generic settings list.
class PanelSection extends StatelessWidget {
  const PanelSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KeryxTheme.grid * 2),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: KeryxTheme.shell700,
              borderRadius: BorderRadius.circular(KeryxTheme.grid),
              boxShadow: KeryxTheme.raisedMaterialEdges,
            ),
            padding: const EdgeInsets.all(KeryxTheme.grid * 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: KeryxTheme.legendLabel.copyWith(color: KeryxTheme.olive),
                ),
                const SizedBox(height: KeryxTheme.grid),
                ...children,
              ],
            ),
          ),
          const _ScrewDot(alignment: Alignment.topLeft),
          const _ScrewDot(alignment: Alignment.topRight),
          const _ScrewDot(alignment: Alignment.bottomLeft),
          const _ScrewDot(alignment: Alignment.bottomRight),
        ],
      ),
    );
  }
}

/// Decorative only — [ExcludeSemantics] keeps the four dots per section out
/// of the TalkBack tree so they never dilute a screen reader's traversal.
class _ScrewDot extends StatelessWidget {
  const _ScrewDot({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KeryxTheme.shell500,
              boxShadow: KeryxTheme.raisedMaterialEdges,
            ),
          ),
        ),
      ),
    );
  }
}
