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
