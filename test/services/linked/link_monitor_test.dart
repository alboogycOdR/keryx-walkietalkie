import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/services/linked/link_monitor.dart';
import 'package:keryx/services/linked/livekit_adapter.dart';

import 'fakes/fake_livekit_adapter.dart';

void main() {
  group('LinkMonitor', () {
    late FakeLiveKitRoom room;
    late List<RadioEvent> dispatched;

    setUp(() {
      room = FakeLiveKitRoom();
      dispatched = [];
    });

    test('dispatches LinkDegraded on reconnecting, LinkResolved on regain', () async {
      final monitor = LinkMonitor(room: room, dispatch: dispatched.add);

      room.emitConnectionState(LiveKitConnectionState.reconnecting);
      await Future<void>.delayed(Duration.zero);
      expect(dispatched, [const LinkDegraded()]);
      expect(monitor.isDegraded, isTrue);

      room.emitConnectionState(LiveKitConnectionState.connected);
      await Future<void>.delayed(Duration.zero);
      expect(dispatched, [const LinkDegraded(), const LinkResolved()]);
      expect(monitor.isDegraded, isFalse);

      monitor.dispose();
    });

    test('dispatches LinkDegraded only once for repeated loss events (no duplicate dispatch)', () async {
      final monitor = LinkMonitor(room: room, dispatch: dispatched.add);

      room.emitConnectionState(LiveKitConnectionState.disconnected);
      room.emitConnectionState(LiveKitConnectionState.reconnecting);
      await Future<void>.delayed(Duration.zero);

      expect(dispatched.whereType<LinkDegraded>().length, 1);
      monitor.dispose();
    });

    test('connecting (initial join) never dispatches LinkDegraded', () async {
      final monitor = LinkMonitor(room: room, dispatch: dispatched.add);

      room.emitConnectionState(LiveKitConnectionState.connecting);
      await Future<void>.delayed(Duration.zero);

      expect(dispatched, isEmpty);
      monitor.dispose();
    });

    test('gives up after maxAttempts and dispatches LinkResolved(useLocalFallback: true)', () async {
      final monitor = LinkMonitor(
        room: room,
        dispatch: dispatched.add,
        reconnect: () async => throw StateError('always fails'),
        initialBackoff: Duration.zero,
        maxBackoff: Duration.zero,
        maxAttempts: 2,
      );

      room.emitConnectionState(LiveKitConnectionState.disconnected);
      // Let the backoff timers (zero duration) and failed reconnect
      // attempts run to exhaustion.
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(dispatched.last, const LinkResolved(useLocalFallback: true));
      monitor.dispose();
    });

    test('a successful reconnect() re-attaches to the new room and resolves the link', () async {
      final replacementRoom = FakeLiveKitRoom();
      final monitor = LinkMonitor(
        room: room,
        dispatch: dispatched.add,
        reconnect: () async => replacementRoom,
        initialBackoff: Duration.zero,
        maxBackoff: Duration.zero,
        maxAttempts: 5,
      );

      room.emitConnectionState(LiveKitConnectionState.disconnected);
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Reconnect handed back replacementRoom; simulate it coming up.
      replacementRoom.emitConnectionState(LiveKitConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      expect(dispatched, contains(const LinkDegraded()));
      expect(dispatched.last, const LinkResolved());
      monitor.dispose();
    });

    test('dispose() stops further dispatches', () async {
      final monitor = LinkMonitor(room: room, dispatch: dispatched.add);
      monitor.dispose();

      room.emitConnectionState(LiveKitConnectionState.disconnected);
      await Future<void>.delayed(Duration.zero);

      expect(dispatched, isEmpty);
    });
  });
}
