import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/presentation/presentation.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/features/channels/channel_format.dart';

void main() {
  group('formatChannelCode', () {
    test('pads channel and code to two digits (Design §2.1 / §2.3)', () {
      expect(formatChannelCode(1, 0), 'CH 01 · 00');
      expect(formatChannelCode(7, 3), 'CH 07 · 03');
      expect(formatChannelCode(99, 38), 'CH 99 · 38');
    });
  });

  group('radioModeLabel', () {
    test('names each wire mode without conflating AUTO and LOCAL', () {
      expect(radioModeLabel(RadioMode.local), 'LOCAL');
      expect(radioModeLabel(RadioMode.linked), 'LINKED');
      expect(radioModeLabel(RadioMode.auto), 'AUTO');
    });
  });

  group('actualConnectionLabel', () {
    test('uses effective route, never the configured preference', () {
      expect(
        actualConnectionLabel(
          const ConnectionCondition(
            configuredMode: RadioMode.auto,
            effectiveRoute: RadioMode.local,
            degraded: false,
          ),
        ),
        'LOCAL',
      );
    });

    test('degraded reports Connection lost (Design §5), not the mode', () {
      expect(
        actualConnectionLabel(
          const ConnectionCondition(
            configuredMode: RadioMode.linked,
            effectiveRoute: RadioMode.linked,
            degraded: true,
          ),
        ),
        'Connection lost',
      );
    });
  });
}
