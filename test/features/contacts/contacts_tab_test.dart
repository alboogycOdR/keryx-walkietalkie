import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/contacts/contacts.dart';
import 'package:keryx/core/identity/keys.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/contacts/contacts_copy.dart';
import 'package:keryx/features/contacts/contacts_keys.dart';
import 'package:keryx/features/contacts/contacts_list_controller.dart';
import 'package:keryx/features/contacts/contacts_tab.dart';
import 'package:keryx/features/my_code/keryx_id_link.dart';
import 'package:keryx/services/directory/directory.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _key() => Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

Widget _fakeScanner({required ValueChanged<String> onRaw, required String payload}) {
  return TextButton(
    key: const Key('fake-scan-emit'),
    onPressed: () => onRaw(payload),
    child: const Text('emit'),
  );
}

/// Directory-backed [ContactsController] whose [sendRequest] always throws,
/// standing in for an unreachable / refusing directory (the scan-path bug).
class _ThrowingDirectoryContacts extends ContactsController {
  _ThrowingDirectoryContacts({
    required super.directoryClient,
    required super.repository,
  });

  @override
  Future<void> sendRequest(String toPk, {required String callsign}) async {
    throw DirectoryException.transport('directory unreachable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late IdentityKeyPair keyPair;
  late DirectoryClient directoryClient;
  late ContactsController contacts;
  late ContactsListController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    keyPair = await IdentityKeyPair.generate();
    directoryClient = DirectoryClient(
      baseUrl: Uri.parse('http://127.0.0.1:1'),
      keyPair: keyPair,
    );
    contacts = _ThrowingDirectoryContacts(
      directoryClient: directoryClient,
      repository: SharedPreferencesContactsRepository(await SharedPreferences.getInstance()),
    );
    controller = ContactsListController(
      contactsController: contacts,
      directoryClient: directoryClient,
    );
    await contacts.loadFromDisk();
  });

  tearDown(() async {
    await controller.dispose();
    await contacts.dispose();
    directoryClient.close();
  });

  testWidgets(
    'a throwing directory send via scan shows requestFailed and stays on the scan screen',
    (tester) async {
      final link = KeryxIdLink(callsign: 'BEN', publicKey: _key());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          ],
          child: MaterialApp(
            theme: keryxUxThemeData(),
            home: ContactsTab(
              controller: controller,
              autoPresentIncoming: false,
              scannerBuilder: ({required onRaw}) =>
                  _fakeScanner(onRaw: onRaw, payload: link.qrPayload),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(ContactsKeys.addFab));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ContactsKeys.addScan));
      await tester.pumpAndSettle();

      expect(find.byKey(ContactsKeys.scanScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('fake-scan-emit')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(ContactsKeys.scanScreen), findsOneWidget);
      expect(find.text(ContactsCopy.requestFailed), findsOneWidget);
      expect(controller.snapshot.contacts, isEmpty);
    },
  );

  testWidgets('forceLocalOnly override surfaces the contacts/presence warning', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        ],
        child: MaterialApp(
          theme: keryxUxThemeData(),
          home: ContactsTab(
            controller: controller,
            autoPresentIncoming: false,
            forceLocalOnly: true,
            scannerBuilder: ({required onRaw}) =>
                _fakeScanner(onRaw: onRaw, payload: 'unused'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(ContactsKeys.localOnlyNotice), findsOneWidget);
    expect(find.text(ContactsCopy.localOnlyWarning), findsOneWidget);
  });
}
