import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/theme/ux_tokens.dart';

import 'fake_radio_host.dart';

/// A no-key-pair stand-in identity for `pumpShell` — [MobileAppShell]'s
/// `IndexedStack` keeps every branch mounted regardless of which tab is
/// active, so `ContactsTabScreen`/`GroupsTabScreen` (and so
/// `identityProvider`) build on every single `lib/app_shell/**` widget
/// test, not only the ones that visit those tabs. Without this override
/// `identityProvider`'s production default
/// (`IdentityRepository(SecureIdentityStore())`) hits the real
/// `flutter_secure_storage` platform channel, which has no mock handler
/// under `flutter test` and never replies — every `pumpAndSettle` in this
/// directory hung indefinitely until this override was added. `relayUrl`
/// is empty by default (see [pumpShell]'s own doc), so
/// `directoryClientProvider` short-circuits on the missing relay before it
/// would ever need a real key pair.
final _stubIdentity = DeviceIdentity(
  installUuid: '00000000-0000-4000-8000-000000000000',
  peerId: 'stub-peer',
  callsign: Callsign.parse('STUB-1'),
);

/// Maps a tab strip label to its `ShellKeys` — icon-only tabs carry no
/// on-screen text (only a `Semantics`/`Tooltip` label), so tests address
/// them by key rather than by visible copy.
///
/// v2 (TASK-093): Talk/Contacts/Groups replaces the R2 Talk/Channels/
/// Stations tab set.
const Map<String, Key> _tabKeysByLabel = <String, Key>{
  'Talk': ShellKeys.tabTalk,
  'Contacts': ShellKeys.tabContacts,
  'Groups': ShellKeys.tabGroups,
};

/// Shared pump for `lib/app_shell/**` widget tests — fake host + in-memory
/// settings, successor theme, phone-sized surface so ListView actions stay
/// on-screen. `settings.relayUrl` defaults to empty, so Contacts/Groups
/// render their real "needs a relay address" empty state rather than
/// requiring a fake directory backend for every test in this file.
Widget pumpShell({
  required FakeRadioHost host,
  required Widget home,
  ThemeData? theme,
}) {
  return ProviderScope(
    overrides: <Override>[
      radioHostProvider.overrideWithValue(host),
      settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      identityProvider.overrideWith((ref) async => _stubIdentity),
    ],
    child: MaterialApp(theme: theme ?? keryxUxThemeData(), home: home),
  );
}

void givePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Top tab strip destination, by label ("Talk"/"Contacts"/"Groups") —
/// resolved through `ShellKeys` since the icon-only tabs carry no visible
/// text (TASK-077, extended by TASK-093 for the v2 tab set).
Finder navDestination(String label) {
  final Key? key = _tabKeysByLabel[label];
  assert(key != null, 'no shell tab strip destination named "$label"');
  return find.byKey(key!);
}

/// Pop the route that owns [screen]. `WidgetTester.pageBack` looks up
/// tooltip "Back" globally and fails when Talk's header Back and a
/// pushed screen's AppBar Back are both on stage (or when two nested
/// navigators each imply a leading).
Future<void> popScreen(
  WidgetTester tester,
  Finder screen, {
  bool settle = true,
}) async {
  final BuildContext context = tester.element(screen);
  Navigator.of(context).pop();
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}
