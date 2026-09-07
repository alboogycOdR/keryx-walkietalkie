import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';

import 'fake_radio_host.dart';

void main() {
  late FakeRadioHost host;

  Widget build() {
    host = FakeRadioHost();
    return ProviderScope(
      overrides: <Override>[
        radioHostProvider.overrideWithValue(host),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
      child: const MaterialApp(home: ChannelsScreen()),
    );
  }

  testWidgets('shows the real current channel/code — never a fabricated '
      'list (UX-FR-008/PRD §2.2)', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.text('Current: CH 1 · Code 0'), findsOneWidget);
    // No recall memory yet: no fabricated "Recently tuned" section either.
    expect(find.text('Recently tuned'), findsNothing);
  });

  testWidgets('renders real channel-recall memory from the host snapshot, '
      'tapping an entry tunes and opens Talk', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    host.emit(
      const RadioHostSnapshot(
        channelMemory: <TunedChannel>[TunedChannel(channel: 7, privacyCode: 3)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recently tuned'), findsOneWidget);
    expect(find.text('CH 7 · Code 3'), findsOneWidget);

    await tester.tap(find.text('CH 7 · Code 3'));
    await tester.pumpAndSettle();

    expect(host.tuneCalls, <(int, int)>[(7, 3)]);
    expect(find.text('Talk'), findsWidgets);
  });

  testWidgets('tapping the current-channel row opens Talk without tuning', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Current: CH 1 · Code 0'));
    await tester.pumpAndSettle();

    expect(host.tuneCalls, isEmpty);
    expect(find.text('Talk'), findsWidgets);
  });
}
