import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/state/radio_state.dart';

void main() {
  const reducer = RadioReducer();

  RadioState bootToIdle() => reducer.reduce(
    reducer.reduce(const RadioState.off(), const PowerOn()),
    const BootCompleted(),
  );

  group('RadioReducer lifecycle', () {
    test('has an exhaustive phase by event transition matrix', () {
      const events = <RadioEvent>[
        PowerOn(),
        BootCompleted(),
        BeginTuning(),
        FinishTuning(),
        TuneTo(channel: 42, privacyCode: 16),
        SetMode(RadioMode.local),
        RequestTransmit(),
        TransmitGranted(),
        TransmitDenied(),
        EndTransmit(),
        RemoteFloorStarted(),
        RemoteFloorEnded(),
        LinkDegraded(),
        LinkRecovered(),
      ];
      var legalTransitions = 0;
      var illegalNoOps = 0;

      for (final phase in RadioPhase.values) {
        for (final event in events) {
          final state = RadioState(
            phase: phase,
            mode: RadioMode.linked,
            channel: 7,
            privacyCode: 5,
          );
          final actual = reducer.reduce(state, event);
          final expected = _expectedMatrixResult(state, event);

          expect(actual, expected, reason: '$phase + $event');
          if (identical(expected, state)) {
            illegalNoOps++;
          } else {
            legalTransitions++;
          }
        }
      }

      expect(legalTransitions, 35);
      expect(illegalNoOps, 77);
    });

    test('moves OFF to BOOT to IDLE and ignores invalid lifecycle events', () {
      const off = RadioState.off();

      expect(reducer.reduce(off, const PowerOn()).phase, RadioPhase.boot);
      expect(reducer.reduce(off, const BootCompleted()), off);
      expect(reducer.reduce(bootToIdle(), const PowerOn()), bootToIdle());
      expect(bootToIdle().phase, RadioPhase.idle);
    });

    test('moves IDLE through TUNING and back', () {
      final idle = bootToIdle();
      final tuning = reducer.reduce(idle, const BeginTuning());

      expect(tuning.phase, RadioPhase.tuning);
      expect(
        reducer.reduce(tuning, const FinishTuning()).phase,
        RadioPhase.idle,
      );
      expect(reducer.reduce(idle, const FinishTuning()), idle);
    });

    test('moves IDLE through requested and granted TX back to IDLE', () {
      final requesting = reducer.reduce(bootToIdle(), const RequestTransmit());
      final transmitting = reducer.reduce(requesting, const TransmitGranted());

      expect(requesting.phase, RadioPhase.txRequest);
      expect(transmitting.phase, RadioPhase.tx);
      expect(
        reducer.reduce(transmitting, const EndTransmit()).phase,
        RadioPhase.idle,
      );
    });

    test(
      'returns a denied TX request to IDLE and rejects out-of-order TX events',
      () {
        final idle = bootToIdle();
        final requesting = reducer.reduce(idle, const RequestTransmit());

        expect(
          reducer.reduce(requesting, const TransmitDenied()).phase,
          RadioPhase.idle,
        );
        expect(reducer.reduce(idle, const TransmitGranted()), idle);
        expect(reducer.reduce(idle, const TransmitDenied()), idle);
        expect(reducer.reduce(idle, const EndTransmit()), idle);
      },
    );

    test('moves IDLE through RX_ACTIVE and back', () {
      final active = reducer.reduce(bootToIdle(), const RemoteFloorStarted());

      expect(active.phase, RadioPhase.rxActive);
      expect(
        reducer.reduce(active, const RemoteFloorEnded()).phase,
        RadioPhase.idle,
      );
      expect(
        reducer.reduce(bootToIdle(), const RemoteFloorEnded()),
        bootToIdle(),
      );
    });
  });

  group('RadioReducer settings and degradation', () {
    test('accepts the complete channel and privacy-code domains', () {
      final lower = reducer.reduce(
        const RadioState.off(),
        const TuneTo(
          channel: RadioState.minimumChannel,
          privacyCode: RadioState.minimumPrivacyCode,
        ),
      );
      final upper = reducer.reduce(
        lower,
        const TuneTo(
          channel: RadioState.maximumChannel,
          privacyCode: RadioState.maximumPrivacyCode,
        ),
      );

      expect(lower.channel, 1);
      expect(lower.privacyCode, 0);
      expect(upper.channel, 99);
      expect(upper.privacyCode, 38);
    });

    test(
      'rejects tuning values outside the channel and privacy-code domains',
      () {
        final state = bootToIdle();

        expect(
          reducer.reduce(state, const TuneTo(channel: 0, privacyCode: 0)),
          state,
        );
        expect(
          reducer.reduce(state, const TuneTo(channel: 100, privacyCode: 0)),
          state,
        );
        expect(
          reducer.reduce(state, const TuneTo(channel: 1, privacyCode: -1)),
          state,
        );
        expect(
          reducer.reduce(state, const TuneTo(channel: 1, privacyCode: 39)),
          state,
        );
      },
    );

    test('defaults to AUTO and permits all three route selections', () {
      const state = RadioState.off();

      expect(state.mode, RadioMode.auto);
      expect(
        reducer.reduce(state, const SetMode(RadioMode.local)).mode,
        RadioMode.local,
      );
      expect(
        reducer.reduce(state, const SetMode(RadioMode.auto)).mode,
        RadioMode.auto,
      );
      expect(
        reducer.reduce(state, const SetMode(RadioMode.linked)).mode,
        RadioMode.linked,
      );
    });

    test(
      'degradation is reachable from any state and resolves without a modal state',
      () {
        for (final phase in RadioPhase.values) {
          final degraded = reducer.reduce(
            RadioState(phase: phase, mode: RadioMode.linked),
            const LinkDegraded(),
          );
          expect(degraded.phase, RadioPhase.linkDegraded);
          expect(
            reducer.reduce(degraded, const LinkRecovered()).phase,
            RadioPhase.idle,
          );
        }
      },
    );

    test(
      'a resolved degradation can fall back to LOCAL and ignores a stray recovery',
      () {
        final state = RadioState(
          phase: RadioPhase.linkDegraded,
          mode: RadioMode.linked,
        );

        expect(
          reducer.reduce(state, const LinkRecovered(fallbackToLocal: true)),
          const RadioState(phase: RadioPhase.idle, mode: RadioMode.local),
        );
        expect(
          reducer.reduce(bootToIdle(), const LinkRecovered()),
          bootToIdle(),
        );
      },
    );
  });

  test('Riverpod controller projects the pure reducer state', () {
    final controller = RadioStateController(reducer);

    controller.dispatch(const PowerOn());
    controller.dispatch(const BootCompleted());
    controller.dispatch(const SetMode(RadioMode.linked));

    expect(
      controller.state,
      const RadioState(phase: RadioPhase.idle, mode: RadioMode.linked),
    );

    expect(controller.state.toString(), contains('RadioPhase.idle'));
    expect(controller.state.hashCode, isNot(0));
  });

  test('Riverpod providers expose the same authoritative reducer', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(radioReducerProvider), isA<RadioReducer>());
    container.read(radioStateProvider.notifier).dispatch(const PowerOn());
    expect(container.read(radioStateProvider).phase, RadioPhase.boot);
  });
}

RadioState _expectedMatrixResult(RadioState state, RadioEvent event) {
  return switch (event) {
    LinkDegraded() => state.copyWith(phase: RadioPhase.linkDegraded),
    PowerOn() when state.phase == RadioPhase.off => state.copyWith(
      phase: RadioPhase.boot,
    ),
    BootCompleted() when state.phase == RadioPhase.boot => state.copyWith(
      phase: RadioPhase.idle,
    ),
    BeginTuning() when state.phase == RadioPhase.idle => state.copyWith(
      phase: RadioPhase.tuning,
    ),
    FinishTuning() when state.phase == RadioPhase.tuning => state.copyWith(
      phase: RadioPhase.idle,
    ),
    TuneTo() => state.copyWith(
      channel: event.channel,
      privacyCode: event.privacyCode,
    ),
    SetMode() => state.copyWith(mode: event.mode),
    RequestTransmit() when state.phase == RadioPhase.idle => state.copyWith(
      phase: RadioPhase.txRequest,
    ),
    TransmitGranted() when state.phase == RadioPhase.txRequest =>
      state.copyWith(phase: RadioPhase.tx),
    TransmitDenied() when state.phase == RadioPhase.txRequest => state.copyWith(
      phase: RadioPhase.idle,
    ),
    EndTransmit() when state.phase == RadioPhase.tx => state.copyWith(
      phase: RadioPhase.idle,
    ),
    RemoteFloorStarted() when state.phase == RadioPhase.idle => state.copyWith(
      phase: RadioPhase.rxActive,
    ),
    RemoteFloorEnded() when state.phase == RadioPhase.rxActive =>
      state.copyWith(phase: RadioPhase.idle),
    LinkRecovered() when state.phase == RadioPhase.linkDegraded =>
      state.copyWith(phase: RadioPhase.idle),
    _ => state,
  };
}
