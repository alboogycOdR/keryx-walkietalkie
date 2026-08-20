import 'dart:async';

import 'package:flutter/material.dart';
import 'package:keryx/core/theme/theme.dart';

/// The orange EMG side key (TS §6.1 `[ EMG ]  (side key)`, FR-025).
///
/// FR-025: "long-press dedicated orange key → pre-emption tone on the
/// channel, overrides busy lockout, pins an `EMG` indicator until the sender
/// clears it." Pure presentation + intent: this widget fires
/// [onEmergencyToggled] once the long-press threshold is held, and never
/// decides on its own whether that arms or clears the indicator — the
/// caller (which owns `RadioState.isEmergency`, `lib/core/state/`, frozen)
/// interprets the toggle against current floor state.
///
/// [pinned] is purely visual (a lit/dimmed side-key treatment reflecting
/// externally-owned pin state) — this widget does not track its own pinned
/// flag.
class EmgKey extends StatefulWidget {
  const EmgKey({
    super.key,
    required this.onEmergencyToggled,
    this.pinned = false,
    this.enabled = true,
    this.armThreshold = const Duration(milliseconds: 600),
    this.width = 14,
    this.height = 76,
  });

  /// Fired once [armThreshold] elapses while the key is held.
  final VoidCallback onEmergencyToggled;

  /// Externally-owned pinned/lit visual state.
  final bool pinned;

  /// When `false`, the key is inert.
  final bool enabled;

  /// PT `.emgkey` long-press arm delay (L386-388:
  /// `setTimeout(()=>{...}, 600)`).
  final Duration armThreshold;

  /// PT `.emgkey` `width:14px` (L123).
  final double width;

  /// PT `.emgkey` `height:76px` (L123).
  final double height;

  @override
  State<EmgKey> createState() => EmgKeyState();
}

/// Public so widget tests can inspect the arming state directly.
class EmgKeyState extends State<EmgKey> {
  Timer? _armTimer;
  bool _pressed = false;
  bool _armed = false;

  /// Exposed for widget tests: whether the current press has crossed
  /// [EmgKey.armThreshold] and already fired [EmgKey.onEmergencyToggled].
  @visibleForTesting
  bool get isArmed => _armed;

  void _onDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    setState(() => _pressed = true);
    _armed = false;
    _armTimer?.cancel();
    _armTimer = Timer(widget.armThreshold, () {
      if (!mounted) return;
      _armed = true;
      widget.onEmergencyToggled();
    });
  }

  void _onUpOrCancel() {
    if (!widget.enabled) return;
    _armTimer?.cancel();
    setState(() => _pressed = false);
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lit = widget.pinned || _armed;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: 'Emergency',
      value: widget.pinned ? 'pinned' : 'idle',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        onPointerUp: (_) => _onUpOrCancel(),
        onPointerCancel: (_) => _onUpOrCancel(),
        child: AnimatedContainer(
          key: const Key('keryx-emg-key'),
          duration: KeryxTheme.snapDuration,
          curve: KeryxTheme.snapCurve,
          width: widget.width,
          height: widget.height,
          transform: _pressed
              ? (Matrix4.identity()
                  ..translateByDouble(KeryxTheme.keyTravel, 0.0, 0.0, 1.0))
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(6),
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: lit
                  ? <Color>[KeryxTheme.emergency, const Color(0xFF7A3A12)]
                  : const <Color>[Color(0xFF7A3A12), Color(0xFF4A2109)],
            ),
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
        ),
      ),
    );
  }
}
