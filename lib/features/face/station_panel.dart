import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:keryx/core/theme/theme.dart';

import 'glass_flip_controller.dart';
import 'roster.dart';

/// FR-067 station-list content: "callsigns + S-meter per station."
///
/// Replaces the glass region when [GlassFlipController.showStations] is
/// true. Rendered inside the same glass-sized box as [KeryxLcdDisplay] so
/// the flip reads as one panel turning over, not a separate overlay.
class StationListPanel extends StatelessWidget {
  const StationListPanel({
    super.key,
    required this.stations,
    this.onScan,
    this.onExport,
    this.onInteraction,
  });

  final List<StationInfo> stations;

  /// FR-043/FR-044 Event QR entry points — see [FaceView]'s dartdoc on why
  /// this panel is where they live. `null` renders a disabled button
  /// rather than hiding it, so the layout stays stable regardless of
  /// whether a host has wired the callback yet.
  final VoidCallback? onScan;
  final VoidCallback? onExport;

  /// Review round-1 finding (b): `GlassFlipController.flipToStations`'s 5 s
  /// auto-flip (FR-067) does not otherwise know this panel is being looked
  /// at or reached for, so a slow-to-find tap on [onScan]/[onExport] could
  /// get flipped away mid-interaction. Fired on every pointer-down anywhere
  /// in this panel; the host wires it to restart the auto-flip window (see
  /// `FaceView._glassRegion`) rather than let it lapse under the user's
  /// thumb. `null` disables the behaviour (e.g. in tests that don't care).
  final VoidCallback? onInteraction;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onInteraction?.call(),
      child: Container(
        key: const Key('keryx-station-panel'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: KeryxTheme.glass,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: KeryxTheme.glassBorder),
          boxShadow: <BoxShadow>[
            KeryxTheme.glassInnerShadow,
            KeryxTheme.glassHighlight,
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _StationPanelHeader(onScan: onScan, onExport: onExport),
            const SizedBox(height: 6),
            Expanded(
              child: stations.isEmpty
                  ? Center(
                      child: Text(
                        'NO OTHER STATIONS',
                        style: KeryxTheme.glassSecondary.copyWith(
                          color: KeryxTheme.lcd.withValues(alpha: 0.6),
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: stations.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) => _StationRow(
                        station: stations[index],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationPanelHeader extends StatelessWidget {
  const _StationPanelHeader({required this.onScan, required this.onExport});

  final VoidCallback? onScan;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        // DS L134: "Touch targets >= 48 dp" is unconditional — the icon
        // itself stays visually small (`iconSize: 18`) but the tappable
        // `BoxConstraints` must not shrink below the accessibility floor.
        IconButton(
          key: const Key('keryx-station-panel-scan'),
          tooltip: 'Scan event QR',
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          color: KeryxTheme.lcd,
          onPressed: onScan,
          icon: const Icon(Icons.qr_code_scanner),
        ),
        IconButton(
          key: const Key('keryx-station-panel-export'),
          tooltip: 'Export event QR',
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          color: KeryxTheme.lcd,
          onPressed: onExport,
          icon: const Icon(Icons.qr_code),
        ),
      ],
    );
  }
}

class _StationRow extends StatelessWidget {
  const _StationRow({required this.station});

  final StationInfo station;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            station.callsign,
            style: KeryxTheme.glassSecondary.copyWith(color: KeryxTheme.lcd),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(9, (index) {
            final lit = index < station.signalQuality;
            return Container(
              width: 2.5,
              height: 5 + index.toDouble() * 0.7,
              margin: const EdgeInsets.only(left: 1),
              color: lit
                  ? KeryxTheme.lcd
                  : KeryxTheme.lcd.withValues(alpha: 0.12),
            );
          }),
        ),
      ],
    );
  }
}

/// Flips the glass region between [front] (the LCD display) and [back] (the
/// station list) using the ratified DS §10 settle token — per follow-up
/// (hh), this is the "assert it in TASK-017" consumer the mutation-proof
/// (TASK-016's) grille left unguarded; `glass_flip_controller_test.dart` and
/// `face_view_test.dart` both cover it.
class GlassFlipper extends StatefulWidget {
  const GlassFlipper({
    super.key,
    required this.controller,
    required this.front,
    required this.back,
  });

  final GlassFlipController controller;
  final Widget front;
  final Widget back;

  @override
  State<GlassFlipper> createState() => _GlassFlipperState();
}

class _GlassFlipperState extends State<GlassFlipper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: KeryxTheme.settleDuration,
  );
  late final Animation<double> _turn = CurvedAnimation(
    parent: _controller,
    curve: KeryxTheme.settleCurve,
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    if (widget.controller.showStations) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant GlassFlipper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  void _onControllerChanged() {
    if (widget.controller.showStations) {
      unawaited(_controller.animateTo(1));
    } else {
      unawaited(_controller.animateTo(0));
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _turn,
      builder: (context, child) {
        final showBack = _turn.value > 0.5;
        final scaleX = (1 - 2 * _turn.value).abs().clamp(0.0, 1.0);
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateY(_turn.value * math.pi);
        return Transform(
          alignment: Alignment.center,
          transform: matrix,
          child: showBack
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: Opacity(opacity: scaleX, child: widget.back),
                )
              : Opacity(opacity: scaleX, child: widget.front),
        );
      },
    );
  }
}
