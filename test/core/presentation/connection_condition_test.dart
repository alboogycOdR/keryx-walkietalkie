import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/presentation/connection_condition.dart';
import 'package:keryx/core/state/radio_state.dart';

void main() {
  group('ConnectionCondition', () {
    test('uses an explicit unresolved state before a path is selected', () {
      const condition = ConnectionCondition(
        transport: Transport.none,
        degraded: false,
      );

      expect(condition.isResolved, isFalse);
      expect(condition.routeLabel, 'Connecting');
    });

    test('labels a resolved relay path', () {
      const condition = ConnectionCondition(
        transport: Transport.relay,
        degraded: false,
      );

      expect(condition.isResolved, isTrue);
      expect(condition.transport, Transport.relay);
      expect(condition.routeLabel, 'Relay');
    });

    test('never uses v1 LOCAL/LINKED/AUTO words', () {
      const unresolved = ConnectionCondition(
        transport: Transport.none,
        degraded: false,
      );
      const direct = ConnectionCondition(
        transport: Transport.direct,
        degraded: false,
      );
      const relay = ConnectionCondition(
        transport: Transport.relay,
        degraded: false,
      );
      const both = ConnectionCondition(
        transport: Transport.both,
        degraded: false,
      );

      for (final condition in [unresolved, direct, relay, both]) {
        expect(condition.routeLabel.toUpperCase(), isNot('LOCAL'));
        expect(condition.routeLabel.toUpperCase(), isNot('LINKED'));
        expect(condition.routeLabel.toUpperCase(), isNot('AUTO'));
      }
      expect(direct.routeLabel, 'Direct');
      expect(both.routeLabel, 'Direct and relay');
    });
  });
}
