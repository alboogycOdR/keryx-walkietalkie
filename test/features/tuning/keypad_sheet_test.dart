import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/tuning/keypad_sheet.dart';

void main() {
  Future<KeypadSheetState> pumpSheet(
    WidgetTester tester, {
    required void Function(int channel, int code) onConfirm,
    VoidCallback? onCancel,
    int? initialChannel,
    int? initialPrivacyCode,
  }) async {
    final key = GlobalKey<KeypadSheetState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KeypadSheet(
            key: key,
            onConfirm: onConfirm,
            onCancel: onCancel,
            initialChannel: initialChannel,
            initialPrivacyCode: initialPrivacyCode,
          ),
        ),
      ),
    );
    return key.currentState!;
  }

  Future<void> tapKey(WidgetTester tester, String glyph) async {
    await tester.tap(find.byKey(Key('keryx-keypad-key-$glyph')));
    await tester.pump();
  }

  group('sequential digit entry', () {
    testWidgets('typing 2 channel digits then 2 code digits fills both fields', (
      tester,
    ) async {
      final state = await pumpSheet(tester, onConfirm: (_, _) {});

      await tapKey(tester, '0');
      await tapKey(tester, '7');
      expect(state.channelDigits, '07');
      expect(state.codeDigits, '');

      await tapKey(tester, '2');
      await tapKey(tester, '1');
      expect(state.channelDigits, '07');
      expect(state.codeDigits, '21');
    });

    testWidgets('a single channel digit plus "·" advances early (CH 07)', (
      tester,
    ) async {
      final state = await pumpSheet(tester, onConfirm: (_, _) {});

      await tapKey(tester, '7');
      expect(state.channelDigits, '7');
      await tapKey(tester, '·');
      await tapKey(tester, '5');
      expect(state.channelDigits, '7');
      expect(state.codeDigits, '5');
    });

    testWidgets('backspace steps back across fields', (tester) async {
      final state = await pumpSheet(tester, onConfirm: (_, _) {});

      await tapKey(tester, '0');
      await tapKey(tester, '7');
      await tapKey(tester, '2');
      expect(state.codeDigits, '2');

      await tapKey(tester, '⌫');
      expect(state.codeDigits, '');

      await tapKey(tester, '⌫'); // now backspaces the channel field
      expect(state.channelDigits, '0');
    });
  });

  group('range validation (1-99 / 00-38)', () {
    testWidgets('a valid entry confirms with exactly the typed values', (
      tester,
    ) async {
      int? confirmedChannel;
      int? confirmedCode;
      await pumpSheet(
        tester,
        onConfirm: (channel, code) {
          confirmedChannel = channel;
          confirmedCode = code;
        },
      );

      await tapKey(tester, '0');
      await tapKey(tester, '7');
      await tapKey(tester, '2');
      await tapKey(tester, '1');
      await tester.tap(find.byKey(const Key('keryx-keypad-confirm')));
      await tester.pump();

      expect(confirmedChannel, 7);
      expect(confirmedCode, 21);
    });

    testWidgets('channel 0 (below the 1-99 domain) is rejected inline', (
      tester,
    ) async {
      var confirmed = false;
      final state = await pumpSheet(
        tester,
        onConfirm: (_, _) => confirmed = true,
      );

      await tapKey(tester, '0');
      await tapKey(tester, '0');
      await tester.tap(find.byKey(const Key('keryx-keypad-confirm')));
      await tester.pump();

      expect(confirmed, isFalse);
      expect(state.error, isNotNull);
    });

    testWidgets('channel 100+ is unreachable (2-digit field caps at 99)', (
      tester,
    ) async {
      final state = await pumpSheet(tester, onConfirm: (_, _) {});

      await tapKey(tester, '9');
      await tapKey(tester, '9');
      await tapKey(tester, '9'); // third digit ignored — field already full
      expect(state.channelDigits, '99');
    });

    testWidgets('code 39 (above the 00-38 domain) is rejected inline', (
      tester,
    ) async {
      var confirmed = false;
      final state = await pumpSheet(
        tester,
        onConfirm: (_, _) => confirmed = true,
      );

      await tapKey(tester, '5');
      await tapKey(tester, '0');
      await tapKey(tester, '3');
      await tapKey(tester, '9');
      await tester.tap(find.byKey(const Key('keryx-keypad-confirm')));
      await tester.pump();

      expect(confirmed, isFalse);
      expect(state.error, isNotNull);
    });

    testWidgets('an omitted code defaults to 00 (open) and confirms', (
      tester,
    ) async {
      int? confirmedCode;
      await pumpSheet(
        tester,
        onConfirm: (_, code) => confirmedCode = code,
      );

      await tapKey(tester, '5');
      await tapKey(tester, '0');
      await tester.tap(find.byKey(const Key('keryx-keypad-confirm')));
      await tester.pump();

      expect(confirmedCode, 0);
    });

    testWidgets('no channel typed at all is rejected inline', (tester) async {
      var confirmed = false;
      final state = await pumpSheet(
        tester,
        onConfirm: (_, _) => confirmed = true,
      );

      await tester.tap(find.byKey(const Key('keryx-keypad-confirm')));
      await tester.pump();

      expect(confirmed, isFalse);
      expect(state.error, isNotNull);
    });
  });

  group('pre-fill', () {
    testWidgets('initialChannel/initialPrivacyCode pre-populate the fields', (
      tester,
    ) async {
      final state = await pumpSheet(
        tester,
        onConfirm: (_, _) {},
        initialChannel: 7,
        initialPrivacyCode: 21,
      );

      expect(state.channelDigits, '07');
      expect(state.codeDigits, '21');
    });
  });

  group('cancel', () {
    testWidgets('CANCEL fires onCancel and never onConfirm', (tester) async {
      var confirmed = false;
      var cancelled = false;
      await pumpSheet(
        tester,
        onConfirm: (_, _) => confirmed = true,
        onCancel: () => cancelled = true,
      );

      await tester.tap(find.byKey(const Key('keryx-keypad-cancel')));
      await tester.pump();

      expect(cancelled, isTrue);
      expect(confirmed, isFalse);
    });
  });
}
