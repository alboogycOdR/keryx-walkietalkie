import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/contacts/contact_view_models.dart';
import 'package:keryx/features/contacts/contacts_copy.dart';
import 'package:keryx/features/contacts/contacts_keys.dart';
import 'package:keryx/features/contacts/contacts_screen.dart';

Widget _wrap(Widget child) => MaterialApp(theme: keryxUxThemeData(), home: child);

ContactsViewState _populated({List<RequestRowVm> requests = const []}) {
  return ContactsViewState(
    requests: requests,
    contacts: const [
      ContactRowVm(
        pk: 'ada',
        callsign: 'Ada',
        shortCode: '4R2M',
        visual: PresenceVisual.available,
        isNearby: true,
      ),
      ContactRowVm(
        pk: 'ben',
        callsign: 'Ben',
        shortCode: 'K9Q2',
        visual: PresenceVisual.busy,
        isTalking: true,
      ),
    ],
    alertDisabledPks: const {},
    nowUnixSeconds: 1_000,
  );
}

void main() {
  testWidgets('empty state has no app bar and shows the add FAB', (tester) async {
    await tester.pumpWidget(_wrap(const ContactsScreen(state: ContactsViewState.empty)));

    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(ContactsKeys.empty), findsOneWidget);
    expect(find.text(ContactsCopy.emptyStateTitle), findsOneWidget);
    expect(find.byKey(ContactsKeys.addFab), findsOneWidget);
  });

  testWidgets('requests section Accept/Decline/Block fire; accept is on the row', (tester) async {
    final accepted = <String>[];
    final declined = <String>[];
    final blocked = <String>[];
    String? armed;
    const request = RequestRowVm(pk: 'in1', callsign: 'Zed', shortCode: 'ABCD');

    await tester.pumpWidget(
      _wrap(
        ContactsScreen(
          state: _populated(requests: const [request]),
          confirmingBlockPk: armed,
          onArmBlockRequest: (pk) => armed = pk,
          onAcceptRequest: (r) => accepted.add(r.pk),
          onDeclineRequest: (r) => declined.add(r.pk),
          onBlockRequest: (r) => blocked.add(r.pk),
        ),
      ),
    );

    expect(find.byKey(ContactsKeys.requestsSection), findsOneWidget);
    await tester.tap(find.byKey(ContactsKeys.requestAccept('in1')));
    await tester.tap(find.byKey(ContactsKeys.requestDecline('in1')));
    await tester.tap(find.byKey(ContactsKeys.requestBlock('in1')));
    expect(accepted, ['in1']);
    expect(declined, ['in1']);
    expect(blocked, isEmpty);
    expect(armed, 'in1');
  });

  testWidgets('Block on a request row requires a second tap', (tester) async {
    final blocked = <String>[];
    String? armed;
    const request = RequestRowVm(pk: 'in1', callsign: 'Zed', shortCode: 'ABCD');

    Widget build() => _wrap(
      ContactsScreen(
        state: _populated(requests: const [request]),
        confirmingBlockPk: armed,
        onArmBlockRequest: (pk) => armed = pk,
        onBlockRequest: (r) => blocked.add(r.pk),
      ),
    );

    await tester.pumpWidget(build());
    await tester.tap(find.byKey(ContactsKeys.requestBlock('in1')));
    expect(blocked, isEmpty);
    expect(armed, 'in1');

    await tester.pumpWidget(build());
    await tester.tap(find.byKey(ContactsKeys.requestBlock('in1')));
    expect(blocked, ['in1']);
  });

  testWidgets('row tap selects a contact; outgoing pending does not', (tester) async {
    ContactRowVm? selected;
    final state = ContactsViewState(
      requests: const [],
      contacts: const [
        ContactRowVm(pk: 'ada', callsign: 'Ada', shortCode: '4R2M', visual: PresenceVisual.available),
        ContactRowVm(
          pk: 'out',
          callsign: 'Waiter',
          shortCode: 'ZZZZ',
          visual: PresenceVisual.offline,
          isOutgoingPending: true,
        ),
      ],
      alertDisabledPks: const {},
      nowUnixSeconds: 1,
    );

    await tester.pumpWidget(
      _wrap(ContactsScreen(state: state, onSelectTarget: (c) => selected = c)),
    );

    await tester.tap(find.byKey(ContactsKeys.contactRow('ada')));
    expect(selected?.pk, 'ada');
    selected = null;
    await tester.tap(find.byKey(ContactsKeys.contactRow('out')));
    expect(selected, isNull);
    expect(find.text(ContactsCopy.waitingToAccept('Waiter')), findsOneWidget);
  });

  testWidgets('presence words for all four statuses plus Nearby and Talking', (tester) async {
    const state = ContactsViewState(
      requests: [],
      contacts: [
        ContactRowVm(
          pk: 'a',
          callsign: 'Ada',
          shortCode: 'AAAA',
          visual: PresenceVisual.available,
          isNearby: true,
        ),
        ContactRowVm(
          pk: 'b',
          callsign: 'Ben',
          shortCode: 'BBBB',
          visual: PresenceVisual.busy,
          isTalking: true,
        ),
        ContactRowVm(pk: 'c', callsign: 'Cam', shortCode: 'CCCC', visual: PresenceVisual.dnd),
        ContactRowVm(
          pk: 'd',
          callsign: 'Dee',
          shortCode: 'DDDD',
          visual: PresenceVisual.offline,
          lastSeenAt: 1,
        ),
      ],
      alertDisabledPks: {},
      nowUnixSeconds: 7201,
    );

    await tester.pumpWidget(_wrap(const ContactsScreen(state: state)));

    expect(find.text(ContactsCopy.availableLabel), findsWidgets);
    expect(find.text(ContactsCopy.busyLabel), findsWidgets);
    expect(find.text(ContactsCopy.dndLabel), findsOneWidget);
    expect(find.text('Offline · 2 h ago'), findsOneWidget);
    expect(find.text(ContactsCopy.nearbyLabel), findsOneWidget);
    expect(find.text(ContactsCopy.talkingLabel), findsOneWidget);
  });

  testWidgets('long-press forwards the contact', (tester) async {
    ContactRowVm? held;
    await tester.pumpWidget(
      _wrap(
        ContactsScreen(
          state: _populated(),
          onLongPressContact: (c) => held = c,
        ),
      ),
    );
    await tester.longPress(find.byKey(ContactsKeys.contactRow('ada')));
    expect(held?.pk, 'ada');
  });

  testWidgets('forceLocalOnly shows a dismissable contacts/presence warning', (
    tester,
  ) async {
    var dismissed = false;
    await tester.pumpWidget(
      _wrap(
        ContactsScreen(
          state: ContactsViewState.empty,
          forceLocalOnly: true,
          onDismissLocalOnlyNotice: () => dismissed = true,
        ),
      ),
    );

    expect(find.byKey(ContactsKeys.localOnlyNotice), findsOneWidget);
    expect(find.text(ContactsCopy.localOnlyWarning), findsOneWidget);

    await tester.tap(find.byKey(ContactsKeys.localOnlyNoticeDismiss));
    await tester.pump();
    expect(dismissed, isTrue);
  });
}
