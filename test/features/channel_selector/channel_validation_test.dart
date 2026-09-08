import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/channel_selector/channel_validation.dart';

void main() {
  group('VT-020 explicit boundaries', () {
    for (final (text, expected) in <(String, int?)>[
      ('1', 1),
      ('99', 99),
      ('0', null),
      ('100', null),
    ]) {
      test('channel "$text" returns $expected', () {
        expect(ChannelInputValidation.parseChannel(text), expected);
      });
    }

    for (final (text, expected) in <(String, int?)>[
      ('0', 0),
      ('38', 38),
      ('-1', null),
      ('39', null),
    ]) {
      test('privacy code "$text" returns $expected', () {
        expect(ChannelInputValidation.parseCode(text), expected);
      });
    }

    test('privacy code rejects signed text even within the numeric range', () {
      // -1 alone cannot distinguish the digit gate from the lower-bound
      // guard. int.tryParse accepts -0 and +1, both numerically in range;
      // rejecting them proves the plain-digit input contract as well.
      expect(ChannelInputValidation.parseCode('-0'), isNull);
      expect(ChannelInputValidation.parseCode('+1'), isNull);
    });
  });

  group('ChannelInputValidation.parseChannel', () {
    test('accepts the full valid range', () {
      expect(ChannelInputValidation.parseChannel('1'), 1);
      expect(ChannelInputValidation.parseChannel('99'), 99);
      expect(ChannelInputValidation.parseChannel('42'), 42);
    });

    test('rejects 0, 100, negative, non-numeric and empty', () {
      expect(ChannelInputValidation.parseChannel('0'), isNull);
      expect(ChannelInputValidation.parseChannel('100'), isNull);
      expect(ChannelInputValidation.parseChannel('-1'), isNull);
      expect(ChannelInputValidation.parseChannel('abc'), isNull);
      expect(ChannelInputValidation.parseChannel(''), isNull);
      expect(ChannelInputValidation.parseChannel('   '), isNull);
      expect(ChannelInputValidation.parseChannel('1.5'), isNull);
      expect(ChannelInputValidation.parseChannel('1e2'), isNull);
    });
  });

  group('ChannelInputValidation.parseCode', () {
    test('accepts the full valid range', () {
      expect(ChannelInputValidation.parseCode('0'), 0);
      expect(ChannelInputValidation.parseCode('38'), 38);
      expect(ChannelInputValidation.parseCode('19'), 19);
    });

    test('rejects 39, -1, non-numeric and empty', () {
      expect(ChannelInputValidation.parseCode('39'), isNull);
      expect(ChannelInputValidation.parseCode('-1'), isNull);
      expect(ChannelInputValidation.parseCode('abc'), isNull);
      expect(ChannelInputValidation.parseCode(''), isNull);
    });
  });

  group('ChannelInputValidation.twoDigit', () {
    test('always renders two digits', () {
      expect(ChannelInputValidation.twoDigit(1), '01');
      expect(ChannelInputValidation.twoDigit(38), '38');
      expect(ChannelInputValidation.twoDigit(0), '00');
    });
  });
}
