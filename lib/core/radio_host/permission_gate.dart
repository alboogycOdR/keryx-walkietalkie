import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Outcome of a single runtime permission check, abstracted from
/// `permission_handler`'s own six-value `PermissionStatus` (denied/
/// restricted/limited/provisional/permanentlyDenied all collapse to
/// [denied]) down to the two-way distinction the host actually acts on:
/// "does the radio behave as if it has this permission or not".
enum FacePermissionOutcome { granted, denied }

/// Runtime permission surface the host requests on power-on (TS L368,
/// §11 E9 / KRX-080, KRX-092): microphone (blocking — the radio cannot
/// transmit without it), notifications and nearby-Wi-Fi-devices (both
/// non-blocking, API 33+ only).
///
/// Hoisted from `lib/features/face/permission_gate.dart` (deleted by
/// TASK-094). The real `permission_handler` plugin is a platform channel
/// that has no registered implementation under `flutter test`, so
/// [KeryxRadioHost] is constructor-injected with a [FacePermissionGate]
/// and a test supplies a fake.
abstract class FacePermissionGate {
  Future<FacePermissionOutcome> ensureMicrophone();
  Future<FacePermissionOutcome> ensureNotifications();
  Future<FacePermissionOutcome> ensureNearbyWifiDevices();
}

/// Real `permission_handler`-backed [FacePermissionGate].
///
/// **Status-check-before-request, on every method, is the whole design.**
/// Each call reads `.status` first and only escalates to `.request()` when
/// not already granted. This buys two things at once: (1) a user who
/// already granted a permission on a prior boot is never re-prompted;
/// (2) on API<33, no POST_NOTIFICATIONS/NEARBY_WIFI_DEVICES requests are
/// attempted — `permission_handler` reports those as already granted
/// pre-33, so `.request()` is never reached.
class DeviceFacePermissionGate implements FacePermissionGate {
  const DeviceFacePermissionGate();

  @override
  Future<FacePermissionOutcome> ensureMicrophone() =>
      _ensure(Permission.microphone);

  @override
  Future<FacePermissionOutcome> ensureNotifications() =>
      _ensure(Permission.notification);

  @override
  Future<FacePermissionOutcome> ensureNearbyWifiDevices() =>
      _ensure(Permission.nearbyWifiDevices);

  Future<FacePermissionOutcome> _ensure(Permission permission) =>
      ensurePermissionOutcome(
        status: () => permission.status,
        request: () => permission.request(),
      );
}

/// Status-check-before-request algorithm, factored out of
/// [DeviceFacePermissionGate] as a pure function over two injected
/// suspend-points so it is directly unit-testable without a real
/// `permission_handler` platform channel.
@visibleForTesting
Future<FacePermissionOutcome> ensurePermissionOutcome({
  required Future<PermissionStatus> Function() status,
  required Future<PermissionStatus> Function() request,
}) async {
  var current = await status();
  if (!current.isGranted) {
    current = await request();
  }
  return current.isGranted
      ? FacePermissionOutcome.granted
      : FacePermissionOutcome.denied;
}
