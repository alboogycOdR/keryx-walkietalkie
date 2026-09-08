import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/features/settings/settings.dart';

import 'fake_radio_host.dart';

void main() {
  late InMemorySettingsStore store;
  late SettingsRepository repo;
  late ReconstructingFakeHost host;
  late SettingsApplyCoordinator coordinator;
  const KeryxSettings initial = KeryxSettings();

  setUp(() {
    store = InMemorySettingsStore();
    repo = SettingsRepository(store);
    host = ReconstructingFakeHost(initial);
    coordinator = SettingsApplyCoordinator(host: host, save: repo.save);
  });

  tearDown(() {
    repo.dispose();
  });

  RadioHostSnapshot snap({FloorEngine? engine}) =>
      RadioHostSnapshot(floorEngine: engine);

  const RadioState idle = RadioState(phase: RadioPhase.idle);
  const RadioState tx = RadioState(phase: RadioPhase.tx);

  test('presentation-only fields cause zero reconstructions', () async {
    for (final KeryxSettings next in <KeryxSettings>[
      initial.copyWith(squelchLevel: 8),
      initial.copyWith(rogerBeep: RogerBeepVariant.off),
      initial.copyWith(latchMode: true),
      initial.copyWith(characterDspIntensity: CharacterDspIntensity.full),
      initial.copyWith(dimMode: DimMode.manual),
    ]) {
      host.reconstructions = 0;
      host.applied = initial;
      final SettingsApplyResult result = await coordinator.propose(
        current: initial,
        next: next,
        snapshot: snap(),
        radio: idle,
        confirmSession: () async => fail('presentation-only must not confirm'),
      );
      expect(result.status, SettingsApplyStatus.appliedPresentation);
      expect(host.reconstructions, 0);
    }
    expect(host.disposedSessions, isEmpty);
  });

  test(
    'each session-affecting field causes exactly one reconstruction',
    () async {
      final List<KeryxSettings> cases = <KeryxSettings>[
        initial.copyWith(mode: RadioMode.linked),
        initial.copyWith(forceLocalOnly: true),
        initial.copyWith(relayUrl: 'wss://relay.example'),
        initial.copyWith(tokenServiceUrl: 'https://token.example/token'),
        initial.copyWith(totSeconds: 90),
        initial.copyWith(busyLockout: false),
        initial.copyWith(region: 'za-cpt'),
      ];
      for (final KeryxSettings next in cases) {
        host = ReconstructingFakeHost(initial);
        coordinator = SettingsApplyCoordinator(host: host, save: repo.save);
        final SettingsApplyResult result = await coordinator.propose(
          current: initial,
          next: next,
          snapshot: snap(),
          radio: idle,
          confirmSession: () async => true,
        );
        expect(result.status, SettingsApplyStatus.appliedSession);
        expect(host.reconstructions, 1, reason: next.toJson().toString());
        expect(host.applied.toJson(), next.toJson());
        expect(host.disposedSessions, hasLength(1));
        expect(host.disposedSessions.single.disposed, isTrue);
        expect(host.disposedSessions.single.changes.isClosed, isTrue);
        expect(host.session, isNot(same(host.disposedSessions.single)));
      }
    },
  );

  test('overlapping session applies serialize; last settings win', () async {
    host.gate = Completer<void>();
    final Future<SettingsApplyResult> first = coordinator.propose(
      current: initial,
      next: initial.copyWith(mode: RadioMode.linked),
      snapshot: snap(),
      radio: idle,
      confirmSession: () async => true,
    );
    await Future<void>.delayed(Duration.zero);
    final Future<SettingsApplyResult> second = coordinator.propose(
      current: initial.copyWith(mode: RadioMode.linked),
      next: initial.copyWith(mode: RadioMode.linked, region: 'za-cpt'),
      snapshot: snap(),
      radio: idle,
      confirmSession: () async => true,
    );
    expect(host.reconstructions, 0);
    host.gate!.complete();
    await first;
    await second;
    expect(host.reconstructions, 2);
    expect(host.applied.mode, RadioMode.linked);
    expect(host.applied.region, 'za-cpt');
    expect(host.disposedSessions, hasLength(2));
    expect(
      host.disposedSessions.every((FakeSession s) => s.changes.isClosed),
      isTrue,
    );
  });

  test('RadioPhase.tx defers applySettings — no hot-mic window', () async {
    final SettingsApplyResult result = await coordinator.propose(
      current: initial,
      next: initial.copyWith(mode: RadioMode.linked),
      snapshot: snap(),
      radio: tx,
      confirmSession: () async => true,
    );
    expect(result.status, SettingsApplyStatus.deferred);
    expect(host.applySettingsCalls, isEmpty);
    expect(host.reconstructions, 0);

    final SettingsApplyResult flushed = await coordinator.flushDeferred(
      snapshot: snap(),
      radio: idle,
    );
    expect(flushed.status, SettingsApplyStatus.appliedSession);
    expect(host.reconstructions, 1);
    expect(host.applied.mode, RadioMode.linked);
  });

  test(
    'FloorEngine.isTransmitting is the authoritative deferral signal',
    () async {
      final LoopbackHub hub = LoopbackHub();
      final VirtualClock clock = VirtualClock();
      final FloorEngine engine = FloorEngine(
        localPeerId: 'AAA2222222',
        transport: hub.attach('AAA2222222'),
        clock: clock,
      );
      engine.updateRoster(<String>{'AAA2222222'});
      engine.requestTransmit();
      addTearDown(engine.dispose);

      expect(engine.isTransmitting, isTrue);
      expect(
        isLocallyTransmitting(
          snapshot: snap(engine: engine),
          radio: idle, // reducer idle must not override the engine
        ),
        isTrue,
      );

      final SettingsApplyResult result = await coordinator.propose(
        current: initial,
        next: initial.copyWith(mode: RadioMode.linked),
        snapshot: snap(engine: engine),
        radio: idle,
        confirmSession: () async => true,
      );
      expect(result.status, SettingsApplyStatus.deferred);
      expect(host.applySettingsCalls, isEmpty);

      engine.releaseTransmit();
      expect(engine.isTransmitting, isFalse);
      final SettingsApplyResult flushed = await coordinator.flushDeferred(
        snapshot: snap(engine: engine),
        radio: idle,
      );
      expect(flushed.status, SettingsApplyStatus.appliedSession);
      expect(host.reconstructions, 1);
    },
  );

  test('cancelled confirmation does not persist or reconstruct', () async {
    final SettingsApplyResult result = await coordinator.propose(
      current: initial,
      next: initial.copyWith(mode: RadioMode.linked),
      snapshot: snap(),
      radio: idle,
      confirmSession: () async => false,
    );
    expect(result.status, SettingsApplyStatus.cancelled);
    expect(host.applySettingsCalls, isEmpty);
    expect((await repo.load()).mode, RadioMode.auto);
    expect((await repo.load()).forceLocalOnly, isFalse);
  });

  test('force-LOCAL apply never calls joinEvent', () async {
    await coordinator.propose(
      current: initial.copyWith(forceLocalOnly: true),
      next: initial.copyWith(forceLocalOnly: true, mode: RadioMode.linked),
      snapshot: snap(),
      radio: idle,
      confirmSession: () async => true,
    );
    expect(host.joinEventCalls, isEmpty);
    expect(host.methodLog, isNot(contains('joinEvent')));
    expect(host.applied.forceLocalOnly, isTrue);
    expect(host.applied.mode, RadioMode.linked);
  });
}
