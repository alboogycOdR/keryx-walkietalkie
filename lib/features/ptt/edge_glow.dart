import 'package:flutter/material.dart';
import 'package:keryx/core/theme/theme.dart';

/// TX edge-glow overlay — "screen edge-glow while transmitting" (FR-026).
///
/// PT's own `.radio.txing` rule (`keryx-face-prototype.html`) adds
/// `inset 0 0 60px -20px var(--tx)` to the *housing's* box-shadow — an inset
/// glow bleeding in from the housing's own edge, not the display glass. This
/// widget is a standalone overlay, not embedded in [PttButton], so TASK-017
/// (face assembly) can mount it once at housing level regardless of which
/// widget currently owns TX state.
///
/// Pure presentation: [active] is the only input, driven by the caller from
/// `RadioPhase.tx` (or an equivalent floor-held check) — this widget itself
/// never inspects floor/radio state.
///
/// "Red appears only while the floor is held by this device. If a
/// screenshot shows red and nobody is transmitting, it is a bug." (DS §2) —
/// enforced here by construction: the glow's opacity is `0` unless [active]
/// is `true`, so there is no code path that renders it without the caller
/// explicitly asserting the floor is held.
class PttEdgeGlow extends StatelessWidget {
  const PttEdgeGlow({super.key, required this.active, this.child});

  /// `true` while this device holds the floor (DS §2).
  final bool active;

  /// Optional content stacked beneath the glow (e.g. the rest of the face).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        ?child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              key: const Key('keryx-ptt-edge-glow'),
              duration: KeryxTheme.snapDuration,
              curve: KeryxTheme.snapCurve,
              opacity: active ? 1 : 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: KeryxTheme.tx,
                      blurRadius: 60,
                      spreadRadius: -20,
                      blurStyle: BlurStyle.inner,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
