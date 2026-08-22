import 'dart:async';

import 'package:flutter/foundation.dart';

/// Drives the STN-tap station-list flip per FR-067: "tap to flip the display
/// panel to the station list … Flip back automatically after 5 s."
///
/// Pure state + timer — no widget/animation concerns, so the 5 s auto-flip
/// is directly unit-testable without pumping a full widget tree.
class GlassFlipController extends ChangeNotifier {
  GlassFlipController({this.autoFlipBackAfter = const Duration(seconds: 5)});

  final Duration autoFlipBackAfter;

  bool _showStations = false;
  Timer? _autoFlipTimer;
  bool _disposed = false;

  bool get showStations => _showStations;

  /// STN tap. Re-tapping while already flipped restarts the 5 s window
  /// (matches the "flip back automatically after 5 s [of being shown]"
  /// reading, not a fixed wall-clock deadline from the first tap).
  void flipToStations() {
    _autoFlipTimer?.cancel();
    _autoFlipTimer = Timer(autoFlipBackAfter, flipToGlass);
    if (!_showStations) {
      _showStations = true;
      notifyListeners();
    }
  }

  /// Manual flip-back (also called by the auto-flip timer).
  void flipToGlass() {
    _autoFlipTimer?.cancel();
    _autoFlipTimer = null;
    if (_showStations) {
      _showStations = false;
      notifyListeners();
    }
  }

  /// Review round-1 finding (b): stops the 5 s auto-flip-back countdown
  /// without touching [showStations] — for a host that is about to cover
  /// the panel with another route (e.g. the FR-043 QR scan/export screens)
  /// and does not want the flip to fire invisibly underneath it. Pair with
  /// [resumeAutoFlipFresh] when control returns. A no-op if the panel isn't
  /// currently showing stations (nothing to pause).
  void pauseAutoFlip() {
    _autoFlipTimer?.cancel();
    _autoFlipTimer = null;
  }

  /// Restarts a full, fresh [autoFlipBackAfter] window — the counterpart to
  /// [pauseAutoFlip]. No-op if the panel isn't showing stations (nothing to
  /// resume).
  ///
  /// TASK-037 round-3 finding (j), fixed here: also a no-op once
  /// [dispose] has run. Without this guard, a caller whose route pops via
  /// `.whenComplete(resumeAutoFlipFresh)` (see `FaceScreen._onScanQr`/
  /// `_onExportQr`) after the controller itself was disposed (e.g. the
  /// whole face was torn down while the QR route was still open) would arm
  /// a fresh `Timer` on a dead controller — harmless today only because
  /// [notifyListeners] is itself disposed-safe, but still a pending timer
  /// past `dispose()` that a widened test's `FakeAsync` would rightly flag.
  void resumeAutoFlipFresh() {
    if (_disposed || !_showStations) return;
    _autoFlipTimer?.cancel();
    _autoFlipTimer = Timer(autoFlipBackAfter, flipToGlass);
  }

  @override
  void dispose() {
    _disposed = true;
    _autoFlipTimer?.cancel();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }
}
