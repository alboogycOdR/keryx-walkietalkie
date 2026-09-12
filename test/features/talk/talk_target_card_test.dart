import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/presentation/talk_target.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/talk/talk_target_card.dart';

const _contact = TalkTarget(
  kind: TalkTargetKind.contact,
  id: 'peer-1',
  name: 'Ben',
  roomId: 'room-1',
  memberPeerIds: ['peer-1'],
);

Widget _wrap(Widget child) =>
    MaterialApp(theme: keryxUxThemeData(), home: Scaffold(body: child));

void main() {
  group('TalkTargetCard', () {
    testWidgets('renders name and presence line, no channel copy', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const TalkTargetCard(target: _contact, presenceLine: 'Available'),
        ),
      );
      expect(find.text('Ben'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      expect(find.textContaining('CH '), findsNothing);
    });

    testWidgets('a null onOpenTargetDetail disables the chevron', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const TalkTargetCard(target: _contact, presenceLine: 'Available'),
        ),
      );
      final IconButton chevron = tester.widget<IconButton>(
        find.byKey(const Key('keryx-talk-target-detail')),
      );
      expect(chevron.onPressed, isNull);
    });

    testWidgets('tapping the chevron invokes onOpenTargetDetail', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(
          TalkTargetCard(
            target: _contact,
            presenceLine: 'Available',
            onOpenTargetDetail: () => taps++,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('keryx-talk-target-detail')));
      expect(taps, 1);
    });

    testWidgets(
      'a non-null ownStatus renders the status control; null hides it',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const TalkTargetCard(
              target: _contact,
              presenceLine: 'Available',
              ownStatus: PeerPresence.online,
            ),
          ),
        );
        expect(find.byKey(const Key('keryx-talk-own-status')), findsOneWidget);

        await tester.pumpWidget(
          _wrap(
            const TalkTargetCard(target: _contact, presenceLine: 'Available'),
          ),
        );
        expect(find.byKey(const Key('keryx-talk-own-status')), findsNothing);
      },
    );

    testWidgets('selecting a status option forwards it via onSetOwnStatus', (
      tester,
    ) async {
      PeerPresence? selected;
      await tester.pumpWidget(
        _wrap(
          TalkTargetCard(
            target: _contact,
            presenceLine: 'Available',
            ownStatus: PeerPresence.online,
            onSetOwnStatus: (status) => selected = status,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('keryx-talk-own-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Busy').last);
      await tester.pumpAndSettle();
      expect(selected, PeerPresence.busy);
    });
  });

  group('TalkNoTargetCard', () {
    testWidgets('renders both entry points and forwards taps', (
      tester,
    ) async {
      var addTaps = 0;
      var createTaps = 0;
      await tester.pumpWidget(
        _wrap(
          TalkNoTargetCard(
            onAddContact: () => addTaps++,
            onCreateGroup: () => createTaps++,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('keryx-talk-add-contact')));
      await tester.tap(find.byKey(const Key('keryx-talk-create-group')));
      expect(addTaps, 1);
      expect(createTaps, 1);
    });

    testWidgets('null callbacks render disabled buttons, never throw', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const TalkNoTargetCard()));
      final FilledButton addContact = tester.widget<FilledButton>(
        find.byKey(const Key('keryx-talk-add-contact')),
      );
      final OutlinedButton createGroup = tester.widget<OutlinedButton>(
        find.byKey(const Key('keryx-talk-create-group')),
      );
      expect(addContact.onPressed, isNull);
      expect(createGroup.onPressed, isNull);
    });
  });
}
