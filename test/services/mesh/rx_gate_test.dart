import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/floor/clock.dart';
import 'package:keryx/core/floor/floor_engine.dart';
import 'package:keryx/core/floor/transport.dart';
import 'package:keryx/services/mesh/rx_gate.dart';

void main() {
  group('RxGate', () {
    late VirtualClock clock;
    late LoopbackHub hub;
    late FloorEngine local;
    late FloorEngine remote;

    setUp(() {
      clock = VirtualClock();
      hub = LoopbackHub();
      local = FloorEngine(
        localPeerId: 'alpha',
        transport: hub.attach('alpha'),
        clock: clock,
      );
      remote = FloorEngine(
        localPeerId: 'bravo',
        transport: hub.attach('bravo'),
        clock: clock,
      );
      local.updateRoster({'alpha', 'bravo'});
      remote.updateRoster({'alpha', 'bravo'});
    });

    tearDown(() {
      local.dispose();
      remote.dispose();
    });

    test('opens on RemoteFloorStarted with the live holder peerId', () async {
      final gate = RxGate(floorEngine: local);
      final holders = <String?>[];
      final sub = gate.holderChanges.listen(holders.add);

      // bravo is arbiter (lower peerId is 'alpha'... 'alpha' < 'bravo', so
      // alpha is arbiter; have bravo request so alpha (local) sees a remote
      // start).
      remote.requestTransmit();
      await Future<void>.delayed(Duration.zero);

      expect(holders, ['bravo']);
      expect(gate.currentHolder, 'bravo');

      await sub.cancel();
      await gate.dispose();
    });

    test('closes (emits null) on RemoteFloorEnded', () async {
      final gate = RxGate(floorEngine: local);
      final holders = <String?>[];
      final sub = gate.holderChanges.listen(holders.add);

      remote.requestTransmit();
      await Future<void>.delayed(Duration.zero);
      remote.releaseTransmit();
      await Future<void>.delayed(Duration.zero);

      expect(holders, ['bravo', null]);

      await sub.cancel();
      await gate.dispose();
    });

    test('polls the level source only while a peer holds the floor', () async {
      var calls = 0;
      final gate = RxGate(
        floorEngine: local,
        levelSource: (peerId) async {
          calls++;
          return 0.5;
        },
        pollInterval: const Duration(milliseconds: 5),
      );

      remote.requestTransmit();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      final duringHold = calls;
      expect(duringHold, greaterThan(0));

      remote.releaseTransmit();
      await Future<void>.delayed(Duration.zero);
      final atClose = calls;
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(calls, atClose, reason: 'polling must stop once floor is idle');

      await gate.dispose();
    });

    test('level samples are clamped to [0.0, 1.0]', () async {
      final levels = <double>[];
      final gate = RxGate(
        floorEngine: local,
        levelSource: (_) async => 3.7,
        pollInterval: const Duration(milliseconds: 5),
      );
      final sub = gate.levels.listen(levels.add);

      remote.requestTransmit();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(levels, isNotEmpty);
      expect(levels.every((l) => l <= 1.0 && l >= 0.0), isTrue);

      remote.releaseTransmit();
      await sub.cancel();
      await gate.dispose();
    });
  });
}
