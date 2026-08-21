import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/event_qr/event_link.dart';
import 'package:keryx/features/event_qr/qr_scan_screen.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

BarcodeCapture _captureOf(List<String?> rawValues) {
  return BarcodeCapture(
    barcodes: [for (final v in rawValues) Barcode(rawValue: v)],
  );
}

void main() {
  group('handleBarcodeCapture', () {
    test('decodes the first valid keryx:// code in the capture', () {
      final link = encodeEventLink(const NumberedEventLink(region: 'za-cpt', channel: 7, code: 21));
      final result = handleBarcodeCapture(_captureOf([link.toString()]));
      expect(result, isA<EventLinkDecoded>());
    });

    test('skips a non-KERYX code and finds the real one later in frame', () {
      final link = encodeEventLink(const NumberedEventLink(region: 'za-cpt', channel: 7, code: 21));
      final result = handleBarcodeCapture(
        _captureOf(['https://example.com', link.toString()]),
      );
      expect(result, isA<EventLinkDecoded>());
    });

    test('empty capture -> failure, never throws', () {
      expect(() => handleBarcodeCapture(_captureOf([])), returnsNormally);
      expect(handleBarcodeCapture(_captureOf([])), isA<EventLinkDecodeFailure>());
    });

    test('null rawValue barcodes are skipped without throwing', () {
      expect(() => handleBarcodeCapture(_captureOf([null, null])), returnsNormally);
      expect(handleBarcodeCapture(_captureOf([null])), isA<EventLinkDecodeFailure>());
    });

    test('all-malformed capture -> failure', () {
      final result = handleBarcodeCapture(_captureOf(['not a link', 'also not one']));
      expect(result, isA<EventLinkDecodeFailure>());
    });
  });

  group('EventQrScanHandler', () {
    test('valid non-expired scan calls onTuned exactly once', () {
      final link = encodeEventLink(const NumberedEventLink(region: 'za-cpt', channel: 7, code: 21));
      EventLinkPayload? tuned;
      var invalidCalls = 0;
      final handler = EventQrScanHandler(
        onTuned: (p) => tuned = p,
        onInvalid: (_) => invalidCalls++,
      );

      handler.handle(_captureOf([link.toString()]));

      expect(tuned, isNotNull);
      expect((tuned! as NumberedEventLink).channel, 7);
      expect(invalidCalls, 0);
      expect(handler.handled, isTrue);
    });

    test('expired scan calls onInvalid("expired"), never onTuned', () {
      final expiresAt = DateTime.utc(2026, 1, 1);
      final link = encodeEventLink(
        NumberedEventLink(region: 'za-cpt', channel: 7, code: 21, expiresAt: expiresAt),
      );
      var tunedCalls = 0;
      String? reason;
      final handler = EventQrScanHandler(
        onTuned: (_) => tunedCalls++,
        onInvalid: (r) => reason = r,
        now: () => expiresAt.add(const Duration(seconds: 1)),
      );

      handler.handle(_captureOf([link.toString()]));

      expect(tunedCalls, 0);
      expect(reason, 'expired');
      expect(handler.handled, isTrue);
    });

    test('malformed scan calls onInvalid but stays armed (not handled)', () {
      var tunedCalls = 0;
      final reasons = <String>[];
      final handler = EventQrScanHandler(
        onTuned: (_) => tunedCalls++,
        onInvalid: reasons.add,
      );

      handler.handle(_captureOf(['garbage']));
      expect(tunedCalls, 0);
      expect(reasons, hasLength(1));
      expect(handler.handled, isFalse);

      // Still armed: a real code right after a bad frame still tunes.
      final link = encodeEventLink(const NumberedEventLink(region: 'za-cpt', channel: 1, code: 0));
      handler.handle(_captureOf([link.toString()]));
      expect(tunedCalls, 1);
      expect(handler.handled, isTrue);
    });

    test('duplicate detections after a successful tune do not fire onTuned again', () {
      final link = encodeEventLink(const NumberedEventLink(region: 'za-cpt', channel: 7, code: 21));
      var tunedCalls = 0;
      final handler = EventQrScanHandler(onTuned: (_) => tunedCalls++);

      handler.handle(_captureOf([link.toString()]));
      handler.handle(_captureOf([link.toString()]));
      handler.handle(_captureOf([link.toString()]));

      expect(tunedCalls, 1);
    });

    test('reset() re-arms the handler for another scan', () {
      final link = encodeEventLink(const NumberedEventLink(region: 'za-cpt', channel: 7, code: 21));
      var tunedCalls = 0;
      final handler = EventQrScanHandler(onTuned: (_) => tunedCalls++);

      handler.handle(_captureOf([link.toString()]));
      expect(tunedCalls, 1);

      handler.reset();
      expect(handler.handled, isFalse);

      handler.handle(_captureOf([link.toString()]));
      expect(tunedCalls, 2);
    });
  });
}
