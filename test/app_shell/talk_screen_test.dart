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
      child: const MaterialApp(home: TalkScreen()),
    );
  }

  testWidgets('press/release forward straight to the host — never a '
      'synthesized grant (Technical §5.1)', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(find.text('PTT')));
    await tester.pump();
    expect(host.pressPttCalls, 1);
    expect(host.releasePttCalls, 0);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(host.releasePttCalls, 1);
  });

  testWidgets('latch toggle releases the latch through the host only on '
      'unlatch (Technical §4)', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Latch'));
    await tester.pumpAndSettle();
    expect(find.text('Unlatch'), findsOneWidget);
    expect(host.releaseLatchCalls, 0);

    await tester.tap(find.text('Unlatch'));
    await tester.pumpAndSettle();
    expect(host.releaseLatchCalls, 1);
  });

  testWidgets('a pending mic-permission fault projects as an overlay cue, '
      'not a fabricated full-strength signal', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    host.emit(const RadioHostSnapshot(micPermissionDenied: true));
    await tester.pumpAndSettle();

    expect(find.text('Microphone required'), findsOneWidget);
  });
}
