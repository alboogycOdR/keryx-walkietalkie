import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/directory_providers.dart';
import 'package:keryx/app_shell/talking_presence.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/services/directory/directory.dart';

import '../services/directory/fakes/fake_presence_transport.dart';

/// Test-only stand-in so a test can drive [radioStateProvider] straight to
/// any phase without wiring a real host — mirrors
/// `presence_bootstrap_test.dart`'s own `_TestRegistrationStatusController`.
class _TestRadioStateController extends RadioStateController {
  @override
  RadioState build() => const RadioState.off();

  void setState(RadioState next) => state = next;
}

void main() {
  late FakePresenceTransport transport;
  late ProviderContainer container;

  Future<ProviderContainer> build() async {
    transport = FakePresenceTransport();
    final keyPair = await IdentityKeyPair.generate();
    container = ProviderContainer(
      overrides: [
        radioStateProvider.overrideWith(_TestRadioStateController.new),
        presenceClientProvider.overrideWith(
          (ref) async => PresenceClient(
            baseUrl: Uri.parse('http://localhost'),
            keyPair: keyPair,
            transport: transport,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final presence = await container.read(presenceClientProvider.future);
    await presence!.start();
    return container;
  }

  test('reaching RadioPhase.tx sends talking:true; leaving it sends '
      'talking:false', () async {
    await build();
    container.read(talkingPresenceProvider); // arms the listener
    await Future<void>.delayed(Duration.zero);
    final radio = container.read(radioStateProvider.notifier) as _TestRadioStateController;

    radio.setState(const RadioState(phase: RadioPhase.tx));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(
      transport.lastSocket!.sent,
      contains(jsonEncode({'status': 'available', 'talking': true})),
    );

    radio.setState(const RadioState(phase: RadioPhase.idle));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(
      transport.lastSocket!.sent,
      contains(jsonEncode({'status': 'available', 'talking': false})),
    );
  });

  test('only sends on the tx boundary crossing, not on every phase change '
      'while already talking or already not talking', () async {
    await build();
    container.read(talkingPresenceProvider);
    await Future<void>.delayed(Duration.zero);
    final radio = container.read(radioStateProvider.notifier) as _TestRadioStateController;

    // `fireImmediately: true` sends one initial talking:false for the
    // off-phase build state — expected, and not part of what this test
    // asserts.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final afterArm = List<String>.from(transport.lastSocket!.sent);

    radio.setState(const RadioState(phase: RadioPhase.txRequest));
    radio.setState(const RadioState(phase: RadioPhase.tuning));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(
      transport.lastSocket!.sent,
      equals(afterArm),
      reason: 'txRequest/tuning are not tx — neither is a boundary crossing',
    );

    radio.setState(const RadioState(phase: RadioPhase.tx));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final afterFirstTx = List<String>.from(transport.lastSocket!.sent);

    radio.setState(const RadioState(phase: RadioPhase.tx, isTotWarning: true));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(
      transport.lastSocket!.sent,
      equals(afterFirstTx),
      reason: 'still in tx — a same-phase field change must not resend',
    );
  });
}
