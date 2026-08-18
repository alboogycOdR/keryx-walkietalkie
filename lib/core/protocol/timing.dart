/// Locked timing constants from TS §8.6.
///
/// These values are asserted by unit tests here and by the KRX-044
/// simulation harness (TASK-023). Do not change without a spec revision.
abstract final class FloorTiming {
  /// Presence heartbeat interval. 3 missed beats = departed.
  static const Duration presenceHeartbeat = Duration(seconds: 5);

  /// Consecutive missed heartbeats before a peer is treated as departed.
  static const int presenceMissesToDepart = 3;

  /// Departure timeout = heartbeat × misses (5 s × 3 = 15 s).
  static const Duration presenceDeparture = Duration(seconds: 15);

  /// Padding added to TOT to form a grant lease.
  static const Duration grantLeasePadding = Duration(seconds: 2);

  /// Default TOT (FR-023: 60 s). Lease default is therefore 62 s.
  static const Duration defaultTot = Duration(seconds: 60);

  /// Default grant lease = default TOT + 2 s = 62 s.
  static const Duration defaultGrantLease = Duration(seconds: 62);

  /// Upper bound on arbiter re-election after churn detection.
  static const Duration arbiterReelectionSettle = Duration(milliseconds: 500);

  /// Delay between `TX_REQ` retries.
  static const Duration txReqRetry = Duration(milliseconds: 150);

  /// `TX_REQ` attempts before give-up (including the first send).
  static const int txReqAttempts = 3;

  /// Floor-idle debounce before an AUTO path switch.
  static const Duration floorIdleDebounce = Duration(milliseconds: 750);

  /// Grant lease for a configured TOT: `TOT + 2 s`.
  static Duration grantLease(Duration tot) => tot + grantLeasePadding;
}
