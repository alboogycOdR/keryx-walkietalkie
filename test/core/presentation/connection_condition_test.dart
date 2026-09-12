import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/presentation/connection_condition.dart';
import 'package:keryx/core/state/radio_state.dart';

void main() {
  group('ConnectionCondition', () {
    test('uses an explicit unresolved state before a route is selected', () {
      const condition = ConnectionCondition(
        configuredMode: RadioMode.auto,
        effectiveRoute: RadioMode.auto,
        degraded: false,
      );

      expect(condition.isResolved, isFalse);
      expect(condition.routeLabel, 'Connecting');
    });

    test('keeps configured AUTO distinct from a resolved route', () {
      const condition = ConnectionCondition(
        configuredMode: RadioMode.auto,
        effectiveRoute: RadioMode.linked,
        degraded: false,
      );

      expect(condition.isResolved, isTrue);
      expect(condition.effectiveRoute, RadioMode.linked);
    });

    test('never labels an unresolved AUTO preference as an active route', () {
      const condition = ConnectionCondition(
        configuredMode: RadioMode.auto,
        effectiveRoute: RadioMode.auto,
        degraded: false,
      );

      expect(condition.routeLabel, isNot('AUTO'));
    });

    // v2 (Technical §6.3/§7, TASK-088 re-scope note §6a): additive
    // `transport` getter — every test above is unmodified.
    test('transport maps local/linked/unresolved to direct/relay/none', () {
      const local = ConnectionCondition(
        configuredMode: RadioMode.auto,
        effectiveRoute: RadioMode.local,
        degraded: false,
      );
      const linked = ConnectionCondition(
        configuredMode: RadioMode.auto,
        effectiveRoute: RadioMode.linked,
        degraded: false,
      );
      const unresolved = ConnectionCondition(
        configuredMode: RadioMode.auto,
        effectiveRoute: RadioMode.auto,
        degraded: false,
      );

      expect(local.transport, Transport.direct);
      expect(linked.transport, Transport.relay);
      expect(unresolved.transport, Transport.none);
    });
  });
}
