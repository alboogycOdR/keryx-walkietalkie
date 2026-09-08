import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/features/event_qr/event_qr.dart';
import 'package:keryx/features/event_qr_ui/event_qr_join_coordinator.dart';

import 'fake_radio_host.dart';

void main() {
  const payload = NumberedEventLink(region: 'global', channel: 5, code: 3);
  const coordinator = EventQrJoinCoordinator();

  Future<bool> approve() async => true;
  Future<bool> decline() async => false;

  group('EventQrJoinCoordinator.join', () {
    test('already linked: joins directly, never touches settings', () async {
      final host = FakeRadioHost();

      final result = await coordinator.join(
        host: host,
        payload: payload,
        effectiveRoute: RadioMode.linked,
        settings: const KeryxSettings(),
        requestRouteTransitionApproval: approve,
      );

      expect(result.isSuccess, isTrue);
      expect(host.joinEventCalls, [payload]);
      expect(host.applySettingsCalls, isEmpty);
    });

    test(
      'force-LOCAL enabled: blocked immediately, no approval prompt, no settings '
      'mutation, no join attempt (no WAN traffic — Technical §8; UX-FR-062)',
      () async {
        final host = FakeRadioHost();
        var approvalCalls = 0;

        final result = await coordinator.join(
          host: host,
          payload: payload,
          effectiveRoute: RadioMode.local,
          settings: const KeryxSettings(forceLocalOnly: true),
          requestRouteTransitionApproval: () async {
            approvalCalls++;
            return true;
          },
        );

        expect(result.outcome, EventQrJoinOutcome.forceLocalBlocked);
        expect(approvalCalls, 0, reason: 'force-LOCAL must never prompt for a transition');
        expect(host.applySettingsCalls, isEmpty);
        expect(host.joinEventCalls, isEmpty);
      },
    );

    test(
      'LOCAL, not force-LOCAL, user approves: switches to linked then joins',
      () async {
        final host = FakeRadioHost();

        final result = await coordinator.join(
          host: host,
          payload: payload,
          effectiveRoute: RadioMode.local,
          settings: const KeryxSettings(),
          requestRouteTransitionApproval: approve,
        );

        expect(result.isSuccess, isTrue);
        expect(host.applySettingsCalls, hasLength(1));
        expect(host.applySettingsCalls.single.mode, RadioMode.linked);
        expect(host.joinEventCalls, [payload]);
      },
    );

    test(
      'LOCAL, not force-LOCAL, user declines: cancelled, no settings mutation, no join',
      () async {
        final host = FakeRadioHost();

        final result = await coordinator.join(
          host: host,
          payload: payload,
          effectiveRoute: RadioMode.local,
          settings: const KeryxSettings(),
          requestRouteTransitionApproval: decline,
        );

        expect(result.outcome, EventQrJoinOutcome.cancelled);
        expect(host.applySettingsCalls, isEmpty);
        expect(host.joinEventCalls, isEmpty);
      },
    );

    test('route transition failure surfaces routeTransitionFailed, never joins', () async {
      final host = FakeRadioHost()..applySettingsError = StateError('rebuild failed');

      final result = await coordinator.join(
        host: host,
        payload: payload,
        effectiveRoute: RadioMode.local,
        settings: const KeryxSettings(),
        requestRouteTransitionApproval: approve,
      );

      expect(result.outcome, EventQrJoinOutcome.routeTransitionFailed);
      expect(host.joinEventCalls, isEmpty);
    });

    test('join failure after a successful route transition surfaces joinFailed', () async {
      final host = FakeRadioHost()
        ..joinEventResult = const JoinResult.transportFailure('peer unreachable');

      final result = await coordinator.join(
        host: host,
        payload: payload,
        effectiveRoute: RadioMode.linked,
        settings: const KeryxSettings(),
        requestRouteTransitionApproval: approve,
      );

      expect(result.outcome, EventQrJoinOutcome.joinFailed);
    });

    test('keyed payload: routes identically to a numbered payload (already linked)', () async {
      const keyedPayload = KeyedEventLink(roomId: 'r-abc123');
      final host = FakeRadioHost();

      final result = await coordinator.join(
        host: host,
        payload: keyedPayload,
        effectiveRoute: RadioMode.linked,
        settings: const KeryxSettings(),
        requestRouteTransitionApproval: approve,
      );

      expect(result.isSuccess, isTrue);
      expect(host.joinEventCalls, [keyedPayload]);
    });

    test('unavailableRoute from the host surfaces joinFailed, not success', () async {
      final host = FakeRadioHost()
        ..joinEventResult = const JoinResult.unavailableRoute('no active session');

      final result = await coordinator.join(
        host: host,
        payload: payload,
        effectiveRoute: RadioMode.linked,
        settings: const KeryxSettings(),
        requestRouteTransitionApproval: approve,
      );

      expect(result.outcome, EventQrJoinOutcome.joinFailed);
      expect(result.isSuccess, isFalse);
    });
  });
}
