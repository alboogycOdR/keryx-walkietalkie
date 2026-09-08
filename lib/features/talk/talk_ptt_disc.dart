import 'package:flutter/material.dart';

import 'talk_copy.dart';

/// The successor primary PTT surface (Design §2.2; ADR-001 §7 item 2 —
/// "rebuild fresh, do not wrap TASK-043's `PttButton`").
///
/// Sizing is **responsive**, not TASK-043's fixed 320 dp disc and not a
/// viewport-height percentage: [TalkPttDisc.sizeFor] derives a diameter from
/// the available width, clamped to a minimum 96 dp primary dimension (Design
/// §2.2). Every gesture callback fires **at most once per hold** — a
/// duplicate pointer-up/cancel is a no-op, satisfying VT-011's "duplicate
/// pointer-up/cancel and a late grant cannot cause duplicate or stuck
/// transmission" at the widget's own boundary (the caller, [TalkScreen],
/// re-asserts the same idempotency at its own layer as defense in depth).
///
/// This widget never talks to a floor engine, session or host directly —
/// [onHoldStart]/[onHoldEnd] are the only two things it does, and it accepts
/// its rendered color/label/icon/pressed/enabled state from the caller
/// (which derives them from `RadioViewState`) rather than inventing its own
/// classification of "what state am I in".
class TalkPttDisc extends StatefulWidget {
  const TalkPttDisc({
    super.key,
    required this.enabled,
    required this.showsTx,
    required this.label,
    required this.icon,
    required this.color,
    required this.onColor,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  /// Whether a gesture may currently start a hold (UX-FR-029: no live
  /// transmit action while booting, permission-denied, powered off or
  /// lacking a usable floor engine).
  final bool enabled;

  /// True only while the authoritative engine actually holds the floor for
  /// this device ([RadioPhase.tx] or a latch) — **never** true merely
  /// because a pointer is down or a request is outstanding (VT-010: "Assert
  /// that a pending request is not shown as granted TX").
  final bool showsTx;

  final String label;
  final IconData icon;
  final Color color;

  /// A contrasting foreground for [color] — the caller resolves this via
  /// `KeryxUxPalette.contrastingOn` (Design §3.2) so this widget never
  /// hardcodes a literal on-color itself.
  final Color onColor;

  /// Fired once per pointer-down that begins a new hold. Never fired again
  /// for the same hold (a second `PointerDownEvent` before the matching
  /// up/cancel cannot happen under normal `Listener` semantics, but the
  /// internal `_holding` guard makes that true even if it somehow did).
  final VoidCallback onHoldStart;

  /// Fired once per hold's terminating up/cancel. A duplicate up/cancel
  /// after the first is a no-op (VT-011).
  final VoidCallback onHoldEnd;

  /// Minimum primary dimension (Design §2.2).
  static const double minDiameter = 96;

  /// Design review's practical ceiling so the disc never dominates a large
  /// phone; still comfortably above the 96 dp floor.
  static const double maxDiameter = 240;

  /// Derives a responsive diameter from the available width — never a fixed
  /// 320 dp constant and never a viewport-height percentage (Design §2.2).
  static double sizeFor(double availableWidth) =>
      (availableWidth * 0.56).clamp(minDiameter, maxDiameter);

  @override
  State<TalkPttDisc> createState() => _TalkPttDiscState();
}

class _TalkPttDiscState extends State<TalkPttDisc> {
  bool _holding = false;

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled || _holding) return;
    setState(() => _holding = true);
    widget.onHoldStart();
  }

  void _onPointerUpOrCancel() {
    if (!_holding) return;
    setState(() => _holding = false);
    widget.onHoldEnd();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double diameter = TalkPttDisc.sizeFor(
          constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : TalkPttDisc.maxDiameter,
        );
        return Semantics(
          key: const Key('keryx-talk-ptt-disc-semantics'),
          button: true,
          enabled: widget.enabled,
          toggled: widget.showsTx,
          label: TalkCopy.holdToTalk,
          value: widget.label,
          child: SizedBox(
            key: const Key('keryx-talk-ptt-disc'),
            width: diameter,
            height: diameter,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointerDown,
              onPointerUp: (_) => _onPointerUpOrCancel(),
              onPointerCancel: (_) => _onPointerUpOrCancel(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.enabled
                      ? widget.color
                      : widget.color.withValues(alpha: .35),
                  border: Border.all(
                    color: widget.onColor.withValues(alpha: .18),
                    width: 2,
                  ),
                ),
                // FittedBox rather than a fixed font size: at a large
                // system text scale (Verification §6: up to 2.0) the label
                // must shrink to stay inside the disc's own fixed diameter
                // rather than overflow it — the label text still reflects
                // the full user text-scale preference everywhere else on
                // the screen; only this one fixed-size circular surface
                // needs to protect its own bounds.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(widget.icon, color: widget.onColor, size: 40),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          widget.label,
                          key: const Key('keryx-talk-ptt-label'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: widget.onColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Design §2.2's mandated "non-drag alternative" to the mechanical hold
/// gesture (Design §5: "Provide a switch-accessible alternative to
/// mechanical hold where the chosen behavior is safe and explicit"). A
/// single discrete tap starts a hold; the next discrete tap ends it — no
/// sustained pointer contact is required, so it is reachable by TalkBack,
/// switch access and keyboard (`Enter`/`Space` on a focused button).
///
/// Shares the same [onHoldStart]/[onHoldEnd] contract as [TalkPttDisc] so a
/// caller ([TalkScreen]) applies exactly one idempotency/safety policy
/// regardless of which control the user actually used.
class TalkPttToggleAlternative extends StatefulWidget {
  const TalkPttToggleAlternative({
    super.key,
    required this.enabled,
    required this.active,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final bool enabled;

  /// Whether the toggle should currently render as "engaged" — mirrors
  /// whatever the caller considers a hold-in-progress, so this control and
  /// [TalkPttDisc] never disagree about whether a hold is active.
  final bool active;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  State<TalkPttToggleAlternative> createState() =>
      _TalkPttToggleAlternativeState();
}

class _TalkPttToggleAlternativeState extends State<TalkPttToggleAlternative> {
  @override
  Widget build(BuildContext context) {
    final String label = widget.active
        ? TalkCopy.stopTransmitting
        : TalkCopy.startTransmitting;
    return SizedBox(
      key: const Key('keryx-talk-ptt-toggle-alt'),
      height: 48,
      child: OutlinedButton.icon(
        onPressed: widget.enabled
            ? () {
                if (widget.active) {
                  widget.onHoldEnd();
                } else {
                  widget.onHoldStart();
                }
              }
            : null,
        icon: Icon(widget.active ? Icons.stop_circle_outlined : Icons.mic_none),
        label: Text(label),
      ),
    );
  }
}
