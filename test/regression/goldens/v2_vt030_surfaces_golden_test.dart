import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/contacts/contact_view_models.dart';
import 'package:keryx/features/contacts/contacts_screen.dart';
import 'package:keryx/features/groups/group_view_models.dart';
import 'package:keryx/features/groups/groups_list_screen.dart';
import 'package:keryx/features/my_code/my_code.dart';
import 'package:keryx/features/onboarding/onboarding.dart';

/// TASK-095 / V2-VT-030: Contacts, Groups, My code and phrase goldens in
/// dark and light, frozen under `test/regression/goldens/goldens/`.
void main() {
  Future<void> pumpSurface({
    required WidgetTester tester,
    required Brightness brightness,
    required Widget home,
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(brightness: brightness),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  const populatedContacts = ContactsViewState(
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
      ContactRowVm(
        pk: 'cam',
        callsign: 'Cam',
        shortCode: 'M00N',
        visual: PresenceVisual.dnd,
      ),
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

  late IdentityKeyPair keys;
  setUp(() async {
    keys = await IdentityKeyPair.fromSeed(List<int>.filled(32, 1));
  });

  final words = RecoveryPhrase.generate(random: Random(1)).words;

  for (final Brightness brightness in <Brightness>[
    Brightness.dark,
    Brightness.light,
  ]) {
    final String suffix = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('Contacts — empty ($suffix)', (tester) async {
      await pumpSurface(
        tester: tester,
        brightness: brightness,
        home: const ContactsScreen(state: ContactsViewState.empty),
      );
      await expectLater(
        find.byType(ContactsScreen),
        matchesGoldenFile('goldens/contacts_empty_$suffix.png'),
      );
    });

    testWidgets('Contacts — populated ($suffix)', (tester) async {
      await pumpSurface(
        tester: tester,
        brightness: brightness,
        home: const ContactsScreen(state: populatedContacts),
      );
      await expectLater(
        find.byType(ContactsScreen),
        matchesGoldenFile('goldens/contacts_populated_$suffix.png'),
      );
    });

    testWidgets('Contacts — with requests ($suffix)', (tester) async {
      await pumpSurface(
        tester: tester,
        brightness: brightness,
        home: const ContactsScreen(state: withRequests),
      );
      await expectLater(
        find.byType(ContactsScreen),
        matchesGoldenFile('goldens/contacts_requests_$suffix.png'),
      );
    });

    testWidgets('Groups — empty ($suffix)', (tester) async {
      await pumpSurface(
        tester: tester,
        brightness: brightness,
        home: const GroupsListScreen(rows: []),
      );
      await expectLater(
        find.byType(GroupsListScreen),
        matchesGoldenFile('goldens/groups_empty_$suffix.png'),
      );
    });

    testWidgets('Groups — populated ($suffix)', (tester) async {
      await pumpSurface(
        tester: tester,
        brightness: brightness,
        home: const GroupsListScreen(
          rows: [
            GroupListRow(
              id: 'g1',
              name: 'Site crew',
              onlineCount: 4,
              totalCount: 12,
              isAdmin: true,
            ),
            GroupListRow(
              id: 'g2',
              name: 'Weekend',
              onlineCount: 0,
              totalCount: 2,
              isAdmin: false,
            ),
          ],
        ),
      );
      await expectLater(
        find.byType(GroupsListScreen),
        matchesGoldenFile('goldens/groups_populated_$suffix.png'),
      );
    });

    testWidgets('My code ($suffix)', (tester) async {
      await pumpSurface(
        tester: tester,
        brightness: brightness,
        home: KeyedSubtree(
          key: const Key('my-code-golden-root'),
          child: MyCodeScreen(
            callsign: 'BEN',
            publicKey: keys.publicKey,
            brightness: const NoopScreenBrightness(),
          ),
        ),
      );
      await expectLater(
        find.byKey(const Key('my-code-golden-root')),
        matchesGoldenFile('goldens/my_code_$suffix.png'),
      );
    });

    testWidgets('phrase screen ($suffix)', (tester) async {
      await pumpSurface(
        tester: tester,
        brightness: brightness,
        home: KeyedSubtree(
          key: const Key('phrase-golden-root'),
          child: RecoveryPhraseScreen(
            words: words,
            screenshotGuard: const NoopScreenshotGuard(),
            onConfirmed: () {},
          ),
        ),
      );
      await expectLater(
        find.byKey(const Key('phrase-golden-root')),
        matchesGoldenFile('goldens/phrase_$suffix.png'),
      );
    });
  }
}
