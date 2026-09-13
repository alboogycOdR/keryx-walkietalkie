import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/contacts_sync.dart';
import 'package:keryx/app_shell/directory_providers.dart';
import 'package:keryx/core/contacts/contacts.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/services/directory/directory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/directory/fakes/fake_directory_server.dart';

/// TASK-105 §1: "a refresh fires on: load, after each request action, tab
/// open, foreground event, and the 30 s foreground timer... none fires
/// while backgrounded". `ContactsListController.load()`/actions are
/// covered by `test/features/contacts/contacts_list_controller_test.dart`;
/// this file is [ContactsSync]'s own remaining triggers.
void main() {
  Future<
      ({
        ProviderContainer container,
        DirectoryClient directoryClient,
        FakeDirectoryServer server,
      })> setUpHarness({
    required void Function() onMeRequest,
  }) async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final server = await FakeDirectoryServer.start();
    server.responder = (RecordedDirectoryRequest req) {
      if (req.path == '/v2/identity/me') onMeRequest();
      return const DirectoryFakeResponse(
        statusCode: 200,
        body: <String, Object?>{
          'pk': 'me',
          'callsign': 'ME',
          'status': 'available',
          'contacts': <Object?>[],
          'pending_in': <Object?>[],
          'pending_out': <Object?>[],
          'groups': <Object?>[],
        },
      );
    };
    final keyPair = await IdentityKeyPair.generate();
    final directoryClient = DirectoryClient(baseUrl: server.baseUrl, keyPair: keyPair);
    final contacts = ContactsController(
      directoryClient: directoryClient,
      repository: SharedPreferencesContactsRepository(await SharedPreferences.getInstance()),
    );
    final container = ProviderContainer(
      overrides: [contactsControllerProvider.overrideWith((ref) async => contacts)],
    );
    return (container: container, directoryClient: directoryClient, server: server);
  }

  testWidgets('no refresh fires before the first foreground event (no '
      'lifecycle callback ever arrives under `flutter test`)', (tester) async {
    var meCalls = 0;
    final h = await setUpHarness(onMeRequest: () => meCalls++);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: h.container, child: const SizedBox()),
    );
    h.container.read(contactsSyncProvider);
    await tester.pump();
    await tester.pump(contactsSyncInterval * 2);

    expect(meCalls, 0);
    h.container.dispose();
    await tester.runAsync(() async {
      h.directoryClient.close();
      await h.server.close();
    });
  });

  testWidgets('a foreground event triggers an immediate refresh', (tester) async {
    var meCalls = 0;
    final h = await setUpHarness(onMeRequest: () => meCalls++);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: h.container, child: const SizedBox()),
    );
    h.container.read(contactsSyncProvider);
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i = 0; i < 10 && meCalls == 0; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    expect(meCalls, greaterThanOrEqualTo(1));

    // Dispose (cancels the periodic timer just armed) and force-close the
    // real socket/server before the test's own pending-timer invariant
    // check runs.
    h.container.dispose();
    await tester.runAsync(() async {
      h.directoryClient.close();
      await h.server.close();
    });
  });

  testWidgets(
      'the 30 s foreground timer itself fires a second refresh once the '
      'interval elapses (not just the foreground-event refresh)', (tester) async {
    var meCalls = 0;
    final h = await setUpHarness(onMeRequest: () => meCalls++);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: h.container, child: const SizedBox()),
    );
    h.container.read(contactsSyncProvider);
    await tester.pump();

    // Arm the timer via the foreground event (as in the sibling test above)
    // and wait out its own immediate refresh first, so the assertion below
    // isolates the *periodic* fire rather than double-counting this one.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i = 0; i < 10 && meCalls == 0; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    expect(meCalls, greaterThanOrEqualTo(1));
    final afterForegroundEvent = meCalls;

    // `ContactsSync`'s `Timer.periodic` is created inside `flutter_test`'s
    // own fake-async zone, so only `tester.pump(duration)` advances it far
    // enough to fire the callback — a real `runAsync` wait alone never
    // ticks it. But the callback's own body (`_refresh()`) then does a
    // genuine `dart:io` socket round trip, which only `runAsync` can drive
    // to completion. Neither tool alone can do both, so: fire the fake
    // clock past the interval first, then poll with real `runAsync` delays
    // for the resulting real request to land (mirrors the sibling
    // foreground-event test's own real-request poll above).
    await tester.pump(contactsSyncInterval + const Duration(seconds: 1));
    for (var i = 0; i < 20 && meCalls == afterForegroundEvent; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    expect(
      meCalls,
      greaterThan(afterForegroundEvent),
      reason: 'the periodic timer must fire its own refresh once '
          'contactsSyncInterval elapses while foregrounded');

    h.container.dispose();
    await tester.runAsync(() async {
      h.directoryClient.close();
      await h.server.close();
    });
  });

  testWidgets('no refresh fires once backgrounded again', (tester) async {
    var meCalls = 0;
    final h = await setUpHarness(onMeRequest: () => meCalls++);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: h.container, child: const SizedBox()),
    );
    h.container.read(contactsSyncProvider);
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i = 0; i < 10 && meCalls == 0; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    expect(meCalls, greaterThanOrEqualTo(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final afterPause = meCalls;
    await tester.pump(contactsSyncInterval * 2);
    expect(meCalls, afterPause, reason: 'no refresh while backgrounded');

    h.container.dispose();
    await tester.runAsync(() async {
      h.directoryClient.close();
      await h.server.close();
    });
  });
}
