import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_bridge.dart';
import 'package:keryx/core/state/radio_state_controller.dart';

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
        PowerOff(),
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
        LinkResolved(),
        EmergencyPinned(),
        EmergencyCleared(),
        ActiveSpeakerChanged('BRAVO-7'),
        ArbiterIdentityChanged('AAA2222222'),
        RosterUpdated(3),
        SignalQualityUpdated(7),
        PrivateChannelChanged(true),
        ReplayChanged(true),
        MonitorChanged(true),
        ScanChanged(true),
        VoxChanged(true),
        TotWarningRaised(),
        TotWarningCleared(),
        TransmitDeniedIndicated(),
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

      expect(legalTransitions, 145);
      expect(illegalNoOps, 87);
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

        final denied = reducer.reduce(requesting, const TransmitDenied());
        expect(denied.phase, RadioPhase.idle);
        expect(denied.isTransmitDenied, isTrue);
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

    test('defaults to AUTO until a concrete effective route is resolved', () {
      final state = bootToIdle();

      expect(state.mode, RadioMode.auto);
      expect(
        reducer.reduce(state, const SetMode(RadioMode.local)).mode,
        RadioMode.local,
      );
      expect(
        reducer.reduce(state, const SetMode(RadioMode.linked)).mode,
        RadioMode.linked,
      );
      expect(
        reducer.reduce(state, const SetMode(RadioMode.auto)),
        state,
        reason: 'AUTO is a preference, never an effective route',
      );
    });

    test('accepts a concrete resolved route while booting', () {
      const booting = RadioState(phase: RadioPhase.boot);

      expect(
        reducer.reduce(booting, const SetMode(RadioMode.local)),
        const RadioState(phase: RadioPhase.boot, mode: RadioMode.local),
        reason: 'the session resolves its route before BootCompleted',
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
          if (phase == RadioPhase.off) {
            expect(degraded, RadioState(phase: phase, mode: RadioMode.linked));
            continue;
          }
          expect(degraded.phase, RadioPhase.linkDegraded);
          expect(degraded.isNoLink, isTrue);
          expect(
            reducer.reduce(degraded, const LinkResolved()).isNoLink,
            isFalse,
          );
          expect(
            reducer.reduce(degraded, const LinkResolved()).phase,
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
          reducer.reduce(state, const LinkResolved(useLocalFallback: true)),
          const RadioState(phase: RadioPhase.idle, mode: RadioMode.local),
        );
        expect(
          reducer.reduce(bootToIdle(), const LinkResolved()),
          bootToIdle(),
        );
      },
    );
  });

  test('Riverpod Notifier host projects the pure reducer state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(radioReducerProvider), isA<RadioReducer>());
    container.read(radioStateProvider.notifier).dispatch(const PowerOn());
    expect(container.read(radioStateProvider).phase, RadioPhase.boot);
    container.read(radioStateProvider.notifier).dispatch(const BootCompleted());
    container
        .read(radioStateProvider.notifier)
        .dispatch(const SetMode(RadioMode.linked));
    expect(
      container.read(radioStateProvider),
      const RadioState(phase: RadioPhase.idle, mode: RadioMode.linked),
    );
  });

  test('projection events own every display-only field', () {
    const start = RadioState(phase: RadioPhase.idle);
    final projected = [
      const EmergencyPinned(),
      const PrivateChannelChanged(true),
      const ReplayChanged(true),
      const MonitorChanged(true),
      const ScanChanged(true),
      const VoxChanged(true),
      const RosterUpdated(4),
      const ActiveSpeakerChanged('BRAVO-7'),
      const ArbiterIdentityChanged('ALFA-1'),
      const SignalQualityUpdated(9),
    ].fold(start, reducer.reduce);

    expect(projected.isEmergency, isTrue);
    expect(projected.isPrivate, isTrue);
    expect(projected.isReplay, isTrue);
    expect(projected.isMonitorOpen, isTrue);
    expect(projected.isScanning, isTrue);
    expect(projected.isVoxArmed, isTrue);
    expect(projected.stationCount, 4);
    expect(projected.activeSpeaker, 'BRAVO-7');
    expect(projected.arbiterId, 'ALFA-1');
    expect(projected.signalQuality, 9);
    expect(projected.isTotWarning, isFalse);
    expect(projected.isTransmitDenied, isFalse);
    expect(
      reducer.reduce(projected, const EmergencyCleared()).isEmergency,
      isFalse,
    );
  });

  test('TOT warning is raised only in TX and cleared without a timer', () {
    final requesting = reducer.reduce(bootToIdle(), const RequestTransmit());
    final tx = reducer.reduce(requesting, const TransmitGranted());

    expect(tx.isTotWarning, isFalse);
    final warning = reducer.reduce(tx, const TotWarningRaised());
    expect(warning.isTotWarning, isTrue);
    expect(warning.phase, RadioPhase.tx);

    expect(
      reducer.reduce(warning, const TotWarningCleared()).isTotWarning,
      isFalse,
    );
    expect(
      reducer.reduce(warning, const EndTransmit()),
      const RadioState(phase: RadioPhase.idle),
    );

    for (final phase in RadioPhase.values.where((p) => p != RadioPhase.tx)) {
      final state = RadioState(phase: phase);
      expect(
        reducer.reduce(state, const TotWarningRaised()),
        state,
        reason: '$phase must not accept TotWarningRaised',
      );
    }
  });

  test('transmit-denied flash is event-driven and not timer-cleared', () {
    final idle = bootToIdle();
    final denied = reducer.reduce(idle, const TransmitDeniedIndicated());
    expect(denied.isTransmitDenied, isTrue);
    expect(denied.phase, RadioPhase.idle);

    expect(
      reducer.reduce(denied, const PowerOn()),
      denied,
      reason: 'no-op events keep the deny flash',
    );

    final cleared = reducer.reduce(denied, const BeginTuning());
    expect(cleared.isTransmitDenied, isFalse);
    expect(cleared.phase, RadioPhase.tuning);

    final off = const RadioState.off();
    expect(reducer.reduce(off, const TransmitDeniedIndicated()), off);
  });

  test('rejects an out-of-domain roster update as a no-op', () {
    final state = RadioState(phase: RadioPhase.idle, stationCount: 2);

    expect(reducer.reduce(state, const RosterUpdated(-1)), state);
  });

  test('rejects out-of-domain signal-quality updates at both endpoints', () {
    final state = RadioState(phase: RadioPhase.idle, signalQuality: 5);

    expect(reducer.reduce(state, const SignalQualityUpdated(0)), state);
    expect(reducer.reduce(state, const SignalQualityUpdated(10)), state);
  });

  test('PowerOff and a changed channel clear replay', () {
    const replaying = RadioState(
      phase: RadioPhase.idle,
      channel: 7,
      privacyCode: 3,
      isReplay: true,
      activeSpeaker: 'BRAVO-7',
    );
    expect(
      reducer
          .reduce(replaying, const TuneTo(channel: 8, privacyCode: 3))
          .isReplay,
      isFalse,
    );
    final off = reducer.reduce(replaying, const PowerOff());
    expect(off.phase, RadioPhase.off);
    expect(off.isReplay, isFalse);
    expect(off.activeSpeaker, isNull);
  });

  test('the reducer source has no framework dependency', () {
    final source = File('lib/core/state/radio_state.dart').readAsStringSync();
    expect(source, isNot(contains('package:flutter')));
    expect(source, isNot(contains('package:riverpod')));
    expect(source, isNot(contains('dart:async')));
    expect(source, isNot(contains('isLan')));
    expect(source, isNot(contains('lanTrouble')));
  });

  test('the one-way bridge projects floor, presence, and telemetry', () async {
    final hub = LoopbackHub();
    const peerId = 'AAA2222222';
    final clock = VirtualClock();
    final engine = FloorEngine(
      localPeerId: peerId,
      transport: hub.attach(peerId),
      clock: clock,
      tot: FloorEngine.minTot,
    );
    var state = const RadioState(phase: RadioPhase.idle);
    final bridge = RadioStateBridge(
      engine: engine,
      dispatch: (event) => state = reducer.reduce(state, event),
    );
    addTearDown(() async {
      await bridge.dispose();
      engine.dispose();
      hub.detach(peerId);
    });

    engine.updateRoster({peerId});
    bridge.updateRoster(1);
    bridge.updateSignalQuality(6);
    bridge.updateVox(true);
    engine.requestTransmit(emergency: true);

    expect(state.phase, RadioPhase.tx);
    expect(state.activeSpeaker, peerId);
    expect(state.isEmergency, isTrue);
    expect(state.arbiterId, peerId);
    expect(state.stationCount, 1);
    expect(state.signalQuality, 6);
    expect(state.isVoxArmed, isTrue);
    expect(state.isTotWarning, isFalse);

    clock.elapse(FloorEngine.minTot - FloorEngine.totWarnLead);
    expect(state.isTotWarning, isTrue);
    expect(state.phase, RadioPhase.tx);

    clock.elapse(FloorEngine.totWarnLead);
    expect(state.isTotWarning, isFalse);
    expect(state.phase, RadioPhase.idle);

    engine.clearEmergency();
    expect(state.isEmergency, isFalse);
    expect(state.activeSpeaker, isNull);
  });

  test(
    'the bridge projects busy-lockout deny without a second state source',
    () {
      final hub = LoopbackHub();
      const aId = 'AAA2222222';
      const bId = 'BBB2222222';
      final clock = VirtualClock();
      final holder = FloorEngine(
        localPeerId: aId,
        transport: hub.attach(aId),
        clock: clock,
      );
      final locked = FloorEngine(
        localPeerId: bId,
        transport: hub.attach(bId),
        clock: clock,
      );
      var state = const RadioState(phase: RadioPhase.idle);
      final bridge = RadioStateBridge(
        engine: locked,
        dispatch: (event) => state = reducer.reduce(state, event),
      );
      addTearDown(() async {
        await bridge.dispose();
        holder.dispose();
        locked.dispose();
        hub.detach(aId);
        hub.detach(bId);
      });

      holder.updateRoster({aId, bId});
      locked.updateRoster({aId, bId});
      holder.requestTransmit();
      expect(state.phase, RadioPhase.rxActive);

      locked.requestTransmit();
      expect(state.isTransmitDenied, isTrue);
      expect(state.phase, RadioPhase.rxActive);
    },
  );
}

RadioState _expectedMatrixResult(RadioState state, RadioEvent event) {
  final next = switch (event) {
    PowerOff() => state.copyWith(
      phase: RadioPhase.off,
      isNoLink: false,
      isReplay: false,
      clearActiveSpeaker: true,
      isTotWarning: false,
      isTransmitDenied: false,
    ),
    LinkDegraded() when state.phase != RadioPhase.off => state.copyWith(
      phase: RadioPhase.linkDegraded,
      isNoLink: true,
      isTotWarning: false,
    ),
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
    SetMode()
        when state.phase != RadioPhase.off && event.mode != RadioMode.auto =>
      state.copyWith(mode: event.mode),
    RequestTransmit() when state.phase == RadioPhase.idle => state.copyWith(
      phase: RadioPhase.txRequest,
    ),
    TransmitGranted() when state.phase == RadioPhase.txRequest =>
      state.copyWith(phase: RadioPhase.tx),
    TransmitDenied() when state.phase == RadioPhase.txRequest => state.copyWith(
      phase: RadioPhase.idle,
      isTransmitDenied: true,
    ),
    EndTransmit() when state.phase == RadioPhase.tx => state.copyWith(
      phase: RadioPhase.idle,
      isTotWarning: false,
    ),
    RemoteFloorStarted() when state.phase == RadioPhase.idle => state.copyWith(
      phase: RadioPhase.rxActive,
    ),
    RemoteFloorEnded() when state.phase == RadioPhase.rxActive =>
      state.copyWith(phase: RadioPhase.idle),
    LinkResolved() when state.phase == RadioPhase.linkDegraded =>
      state.copyWith(phase: RadioPhase.idle, isNoLink: false),
    EmergencyPinned() => state.copyWith(isEmergency: true),
    EmergencyCleared() => state.copyWith(isEmergency: false),
    ActiveSpeakerChanged() => state.copyWith(
      activeSpeaker: event.speaker,
      clearActiveSpeaker: event.speaker == null,
    ),
    ArbiterIdentityChanged() => state.copyWith(
      arbiterId: event.peerId,
      clearArbiterId: event.peerId == null,
    ),
    RosterUpdated() when event.stationCount >= 0 => state.copyWith(
      stationCount: event.stationCount,
    ),
    SignalQualityUpdated()
        when event.sMeter >= RadioState.minimumSignalQuality &&
            event.sMeter <= RadioState.maximumSignalQuality =>
      state.copyWith(signalQuality: event.sMeter),
    PrivateChannelChanged() => state.copyWith(isPrivate: event.isPrivate),
    ReplayChanged() => state.copyWith(isReplay: event.isActive),
    MonitorChanged() => state.copyWith(isMonitorOpen: event.isOpen),
    ScanChanged() => state.copyWith(isScanning: event.isActive),
    VoxChanged() => state.copyWith(isVoxArmed: event.isArmed),
    TotWarningRaised() when state.phase == RadioPhase.tx => state.copyWith(
      isTotWarning: true,
    ),
    TotWarningCleared() => state.copyWith(isTotWarning: false),
    TransmitDeniedIndicated() when state.phase != RadioPhase.off =>
      state.copyWith(isTransmitDenied: true),
    _ => state,
  };
  if (event is TransmitDeniedIndicated || event is TransmitDenied) {
    return next;
  }
  if (state.isTransmitDenied && next != state) {
    return next.copyWith(isTransmitDenied: false);
  }
  return next;
}
