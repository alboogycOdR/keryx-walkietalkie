import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/protocol/protocol.dart';

void main() {
  test('presence heartbeat is 5 s / 3 missed = 15 s', () {
    expect(FloorTiming.presenceHeartbeat, const Duration(seconds: 5));
    expect(FloorTiming.presenceMissesToDepart, 3);
    expect(FloorTiming.presenceDeparture, const Duration(seconds: 15));
    expect(
      FloorTiming.presenceHeartbeat * FloorTiming.presenceMissesToDepart,
      FloorTiming.presenceDeparture,
    );
  });

  test('grant lease is TOT + 2 s and defaults to 62 s', () {
    expect(FloorTiming.grantLeasePadding, const Duration(seconds: 2));
    expect(FloorTiming.defaultTot, const Duration(seconds: 60));
    expect(FloorTiming.defaultGrantLease, const Duration(seconds: 62));
    expect(
      FloorTiming.grantLease(FloorTiming.defaultTot),
      FloorTiming.defaultGrantLease,
    );
    expect(
      FloorTiming.grantLease(const Duration(seconds: 30)),
      const Duration(seconds: 32),
    );
    expect(
      FloorTiming.grantLease(const Duration(seconds: 120)),
      const Duration(seconds: 122),
    );
    expect(FloorTiming.defaultGrantLease.inMilliseconds, 62000);
  });

  test('arbiter re-election settle is 500 ms', () {
    expect(
      FloorTiming.arbiterReelectionSettle,
      const Duration(milliseconds: 500),
    );
  });

  test('TX_REQ retry is 150 ms / 3 attempts', () {
    expect(FloorTiming.txReqRetry, const Duration(milliseconds: 150));
    expect(FloorTiming.txReqAttempts, 3);
  });

  test('floor-idle debounce is 750 ms', () {
    expect(FloorTiming.floorIdleDebounce, const Duration(milliseconds: 750));
  });
}
