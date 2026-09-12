import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/contacts/contact_view_models.dart';
import 'package:keryx/features/contacts/contacts_screen.dart';

/// TASK-090 goldens: empty / populated / with-requests, dark and light
/// (V2-VT-030). Kept under this task's `test/features/contacts/goldens/**`.
void main() {
  Future<void> pumpAndGolden(
    WidgetTester tester, {
    required String name,
    required Brightness brightness,
    required ContactsViewState state,
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(brightness: brightness),
        home: ContactsScreen(state: state),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ContactsScreen),
      matchesGoldenFile('goldens/contacts_$name.png'),
    );
  }

  const populated = ContactsViewState(
    requests: [],
    contacts: [
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
      ContactRowVm(pk: 'cam', callsign: 'Cam', shortCode: 'M00N', visual: PresenceVisual.dnd),
      ContactRowVm(
        pk: 'dee',
        callsign: 'Dee',
        shortCode: 'OFF1',
        visual: PresenceVisual.offline,
        lastSeenAt: 1,
      ),
    ],
    alertDisabledPks: {},
    nowUnixSeconds: 7201,
  );

  const withRequests = ContactsViewState(
    requests: [
      RequestRowVm(pk: 'zed', callsign: 'Zed', shortCode: 'ZZZ1'),
    ],
    contacts: [
      ContactRowVm(
        pk: 'ada',
        callsign: 'Ada',
        shortCode: '4R2M',
        visual: PresenceVisual.available,
      ),
    ],
    alertDisabledPks: {},
    nowUnixSeconds: 1,
  );

  for (final brightness in <Brightness>[Brightness.dark, Brightness.light]) {
    final suffix = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('Contacts — empty ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'empty_$suffix',
        brightness: brightness,
        state: ContactsViewState.empty,
      );
    });

    testWidgets('Contacts — populated ($suffix)', (tester) async {
      await pumpAndGolden(tester, name: 'populated_$suffix', brightness: brightness, state: populated);
    });

    testWidgets('Contacts — with requests ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'requests_$suffix',
        brightness: brightness,
        state: withRequests,
      );
    });
  }
}
