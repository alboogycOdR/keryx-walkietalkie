import 'package:flutter/material.dart';

import '../../core/theme/ux_tokens.dart';
import 'contact_view_models.dart';
import 'contacts_copy.dart';

/// Design §3 presence cue: a coloured (or hollow) dot plus the state
/// word. Talking adds a ring around the dot; Nearby adds a Wi‑Fi glyph.
/// Colour is never the only cue.
class PresenceBadge extends StatelessWidget {
  const PresenceBadge({
    super.key,
    required this.visual,
    required this.label,
    this.isTalking = false,
    this.isNearby = false,
    this.semanticLabel,
  });

  final PresenceVisual visual;
  final String label;
  final bool isTalking;
  final bool isNearby;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = KeryxUxTokens.of(context);
    return Semantics(
      container: true,
      label: semanticLabel ?? label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PresenceDot(visual: visual, isTalking: isTalking, tokens: tokens),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: KeryxUxTypography.compact.copyWith(color: tokens.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isNearby) ...[
              const SizedBox(width: 6),
              Icon(Icons.wifi, size: 14, color: tokens.textSecondary),
              const SizedBox(width: 2),
              Text(
                ContactsCopy.nearbyLabel,
                style: KeryxUxTypography.compact.copyWith(color: tokens.textSecondary),
              ),
            ],
            if (isTalking) ...[
              const SizedBox(width: 6),
              Text(
                ContactsCopy.talkingLabel,
                style: KeryxUxTypography.compact.copyWith(color: tokens.stateRx),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PresenceDot extends StatelessWidget {
  const PresenceDot({super.key, required this.visual, required this.isTalking, required this.tokens});

  final PresenceVisual visual;
  final bool isTalking;
  final KeryxUxTokens tokens;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (visual) {
      PresenceVisual.available => tokens.stateRx,
      PresenceVisual.busy => tokens.stateWarning,
      PresenceVisual.dnd => tokens.textSecondary,
      PresenceVisual.offline => tokens.borderDefault,
    };
    final bool hollow = visual == PresenceVisual.offline;
    final Widget inner = visual == PresenceVisual.dnd
        ? Icon(Icons.nightlight_round, size: 10, color: color)
        : Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hollow ? Colors.transparent : color,
              border: Border.all(color: color, width: 1.5),
            ),
          );
    if (!isTalking) return inner;
    // Static ring rather than an infinite pulse — goldens and
    // pumpAndSettle must be able to complete (Design §3 "pulsing ring"
    // is the visual *idea*; the word "Talking" is the required cue).
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: tokens.stateRx, width: 1.5),
      ),
      child: inner,
    );
  }
}
