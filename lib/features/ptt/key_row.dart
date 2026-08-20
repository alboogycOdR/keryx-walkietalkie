import 'package:flutter/material.dart';
import 'package:keryx/core/theme/theme.dart';

/// The four secondary keys in TS §6.1's face diagram:
/// `[MON] [SCAN] [SAY AGN] [⚙]`.
enum PttSecondaryKey { mon, scan, sayAgain, settings }

/// Secondary key row: MON, SCAN, SAY AGAIN, settings (TS §6.1, §11 KRX-015).
///
/// Pure presentation + intent, mirroring [PttButton]. [lockedKeys] renders
/// the Pro-locked dimmed treatment (TS §6.1 "Pro keys shown dimmed/locked
/// when unowned") but a locked key's intent **still fires** — PT's own
/// locked-key `onclick` handler still calls `SFX.deny()` (L380-382) even
/// though the key is visually locked, so the caller (not this widget) is
/// responsible for turning a locked-key intent into a deny sound/haptic
/// instead of the real action.
///
/// MON alone carries press-and-hold semantics ([onMonHoldStart] /
/// [onMonHoldEnd]) per the dossier's intended approach — SCAN, SAY AGAIN,
/// and settings are plain taps, firing their callback once on release.
class PttKeyRow extends StatelessWidget {
  const PttKeyRow({
    super.key,
    required this.onMonHoldStart,
    required this.onMonHoldEnd,
    required this.onScan,
    required this.onSayAgain,
    required this.onSettings,
    this.lockedKeys = const <PttSecondaryKey>{},
    this.enabled = true,
    this.height = 44,
  });

  /// PT `.keys` height (L105) — the row itself, not each key.
  final double height;

  /// Fired on MON pointer-down.
  final VoidCallback onMonHoldStart;

  /// Fired on MON pointer-up/cancel.
  final VoidCallback onMonHoldEnd;

  /// Fired on SCAN release (tap).
  final VoidCallback onScan;

  /// Fired on SAY AGAIN release (tap).
  final VoidCallback onSayAgain;

  /// Fired on settings release (tap).
  final VoidCallback onSettings;

  /// Pro-locked keys — dimmed + marker, but intents still fire. See the
  /// class dartdoc.
  final Set<PttSecondaryKey> lockedKeys;

  /// When `false`, all keys are inert (no visual feedback, no callbacks).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: <Widget>[
          Expanded(
            child: _SecondaryKeyCap(
              keyId: PttSecondaryKey.mon,
              label: 'MON',
              locked: lockedKeys.contains(PttSecondaryKey.mon),
              enabled: enabled,
              onPressStart: onMonHoldStart,
              onPressEnd: onMonHoldEnd,
            ),
          ),
          Expanded(
            child: _SecondaryKeyCap(
              keyId: PttSecondaryKey.scan,
              label: 'SCAN',
              locked: lockedKeys.contains(PttSecondaryKey.scan),
              enabled: enabled,
              onPressStart: _noop,
              onPressEnd: onScan,
            ),
          ),
          Expanded(
            child: _SecondaryKeyCap(
              keyId: PttSecondaryKey.sayAgain,
              label: 'SAY AGN',
              locked: lockedKeys.contains(PttSecondaryKey.sayAgain),
              enabled: enabled,
              onPressStart: _noop,
              onPressEnd: onSayAgain,
            ),
          ),
          Expanded(
            child: _SecondaryKeyCap(
              keyId: PttSecondaryKey.settings,
              label: '⚙', // ⚙ per TS §6.1 face diagram.
              locked: lockedKeys.contains(PttSecondaryKey.settings),
              enabled: enabled,
              onPressStart: _noop,
              onPressEnd: onSettings,
            ),
          ),
        ],
      ),
    );
  }

  static void _noop() {}
}

class _SecondaryKeyCap extends StatefulWidget {
  const _SecondaryKeyCap({
    required this.keyId,
    required this.label,
    required this.locked,
    required this.enabled,
    required this.onPressStart,
    required this.onPressEnd,
  });

  final PttSecondaryKey keyId;
  final String label;
  final bool locked;
  final bool enabled;
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;

  @override
  State<_SecondaryKeyCap> createState() => _SecondaryKeyCapState();
}

class _SecondaryKeyCapState extends State<_SecondaryKeyCap> {
  bool _pressed = false;

  void _onDown(TapDownDetails details) {
    if (!widget.enabled) return;
    setState(() => _pressed = true);
    widget.onPressStart();
  }

  void _onUp(TapUpDetails details) {
    if (!widget.enabled) return;
    setState(() => _pressed = false);
    // Locked keys still fire — see the class dartdoc.
    widget.onPressEnd();
  }

  void _onCancel() {
    if (!widget.enabled) return;
    setState(() => _pressed = false);
    widget.onPressEnd();
  }

  @override
  Widget build(BuildContext context) {
    final legendColor = widget.locked
        ? const Color(0xFF5A5F5D) // PT `.keys.locked` (L110).
        : (_pressed ? KeryxTheme.lcd : KeryxTheme.legend);
    final label = widget.locked ? '${widget.label} ✦' : widget.label;

    return Semantics(
      button: true,
      enabled: widget.enabled && !widget.locked,
      label: widget.locked ? '${widget.label}, Pro locked' : widget.label,
      child: GestureDetector(
        onTapDown: _onDown,
        onTapUp: _onUp,
        onTapCancel: _onCancel,
        child: Container(
          key: Key('keryx-ptt-key-${widget.keyId.name}'),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          alignment: Alignment.center,
          transform: _pressed
              ? (Matrix4.identity()
                  ..translateByDouble(0.0, KeryxTheme.keyTravel, 0.0, 1.0))
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: KeryxTheme.shell500,
            borderRadius: BorderRadius.circular(10),
            boxShadow: _pressed
                ? const <BoxShadow>[
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.5),
                      blurRadius: 4,
                      blurStyle: BlurStyle.inner,
                    ),
                  ]
                : KeryxTheme.raisedMaterialEdges,
          ),
          child: Text(
            label,
            style: KeryxTheme.legendLabel.copyWith(color: legendColor),
          ),
        ),
      ),
    );
  }
}
