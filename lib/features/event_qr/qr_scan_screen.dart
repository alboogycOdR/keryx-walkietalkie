import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'event_link.dart';

/// Pure decode step: pulls the first `keryx://` code out of a scan capture.
/// Separated from [EventQrScanHandler]/[EventQrScanScreen] so it is
/// testable without a platform camera channel — mirrors this project's
/// standing convention of keeping native/platform surfaces thin (see
/// TASK-026 Review_Findings on native-adapter test doctrine).
///
/// A [BarcodeCapture] can carry multiple codes in one frame; this returns
/// the first one that decodes as a structurally valid Event link and
/// ignores anything else in frame (a non-KERYX code sitting next to a real
/// one should not block the scan).
EventLinkDecodeResult handleBarcodeCapture(BarcodeCapture capture, {DateTime? now}) {
  EventLinkDecodeResult? lastFailure;
  for (final barcode in capture.barcodes) {
    final raw = barcode.rawValue;
    if (raw == null) continue;
    final result = decodeEventLink(raw, now: now);
    if (result is EventLinkDecoded) return result;
    lastFailure = result;
  }
  return lastFailure ?? const EventLinkDecodeFailure('no barcode in capture');
}

/// Stateful "handle exactly one successful scan" policy, kept independent
/// of [MobileScanner] so it is unit-testable without mounting the camera
/// widget (which requires a platform channel `mobile_scanner` does not
/// provide in `flutter test`).
class EventQrScanHandler {
  EventQrScanHandler({required this.onTuned, this.onInvalid, this.now});

  /// "Scanning tunes the radio instantly" (FR-044) — called with the
  /// decoded, non-expired payload the instant a valid code is captured.
  /// The host owns the actual tune/join (e.g. via
  /// `LinkedController.joinRoomId`, which is documented to expect exactly
  /// this — see that method's dartdoc); this handler owns no radio state.
  final void Function(EventLinkPayload payload) onTuned;

  /// Fired for an expired or malformed code. Expired scans surface an
  /// in-world flag/tone per this task's dossier, not a blocking dialog —
  /// the host decides how to render `reason`.
  final void Function(String reason)? onInvalid;

  /// Injection seam for deterministic expiry tests.
  final DateTime Function()? now;

  bool _handled = false;

  /// True once a terminal outcome (tuned or expired) has fired. Guards
  /// against a burst of duplicate detections across consecutive camera
  /// frames re-triggering the tune for the same physical code.
  bool get handled => _handled;

  void handle(BarcodeCapture capture) {
    if (_handled) return;
    final result = handleBarcodeCapture(capture, now: now?.call());
    switch (result) {
      case EventLinkDecoded(:final payload, :final isExpired):
        _handled = true;
        if (isExpired) {
          onInvalid?.call('expired');
        } else {
          onTuned(payload);
        }
      case EventLinkDecodeFailure(:final reason):
        // Not terminal: keep scanning until a valid or expired code shows.
        onInvalid?.call(reason);
    }
  }

  /// Re-arms the handler for another scan (e.g. host reused the screen).
  void reset() => _handled = false;
}

/// Camera scanner that tunes the radio the instant a valid Event QR /
/// `keryx://` code is captured.
class EventQrScanScreen extends StatefulWidget {
  const EventQrScanScreen({super.key, required this.onTuned, this.onInvalid, this.now});

  final void Function(EventLinkPayload payload) onTuned;
  final void Function(String reason)? onInvalid;
  final DateTime Function()? now;

  @override
  State<EventQrScanScreen> createState() => _EventQrScanScreenState();
}

class _EventQrScanScreenState extends State<EventQrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  late final EventQrScanHandler _handler = EventQrScanHandler(
    onTuned: widget.onTuned,
    onInvalid: widget.onInvalid,
    now: widget.now,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MobileScanner(controller: _controller, onDetect: _handler.handle);
  }
}
