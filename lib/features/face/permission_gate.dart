import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Outcome of a single runtime permission check, abstracted from
/// `permission_handler`'s own six-value `PermissionStatus` (denied/
/// restricted/limited/provisional/permanentlyDenied all collapse to
/// [denied]) down to the two-way distinction [FaceScreen] actually acts on:
/// "does the radio behave as if it has this permission or not".
enum FacePermissionOutcome { granted, denied }

/// Runtime permission surface `FaceScreen` requests on power-on (TS L368,
/// §11 E9 / KRX-080, KRX-092): microphone (blocking — the radio cannot
/// transmit without it), notifications and nearby-Wi-Fi-devices (both
/// non-blocking, API 33+ only).
///
/// Abstracted the same way `SessionHost`/`AudioSink`/identity are elsewhere
/// in this file's territory: the real `permission_handler` plugin is a
/// platform channel that has no registered implementation under
/// `flutter test` (calling it hangs/throws depending on the host), so
/// [FaceScreen] is constructor-injected with a [FacePermissionGate] and a
/// test supplies a fake.
abstract class FacePermissionGate {
  Future<FacePermissionOutcome> ensureMicrophone();
  Future<FacePermissionOutcome> ensureNotifications();
  Future<FacePermissionOutcome> ensureNearbyWifiDevices();
}

/// Real `permission_handler`-backed [FacePermissionGate].
///
/// **Status-check-before-request, on every method, is the whole design.**
/// Each call reads `.status` first and only escalates to `.request()` when
/// not already granted. This buys two things at once, for free, rather than
/// needing separate logic for each: (1) a user who already granted a
/// permission on a prior boot is never re-prompted; (2) the acceptance
/// criterion "on API<33, no POST_NOTIFICATIONS/NEARBY_WIFI_DEVICES requests
/// are attempted" holds without this file querying the Android SDK version
/// itself (which would need a new platform channel — out of this task's
/// `Owned_Paths`, `android/**` is not in it). Neither `POST_NOTIFICATIONS`
/// nor `NEARBY_WIFI_DEVICES` is a runtime-checked permission before API 33;
/// `permission_handler`'s own native side reports `.status` as already
/// granted on those OS versions, so `.request()` is never reached — the
/// gating happens inside the plugin, this class just has to ask first
/// rather than requesting unconditionally.
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

  Future<FacePermissionOutcome> _ensure(Permission permission) => ensurePermissionOutcome(
    status: () => permission.status,
    request: () => permission.request(),
  );
}

/// The actual status-check-before-request algorithm, factored out of
/// [DeviceFacePermissionGate] as a pure function over two injected
/// suspend-points so it is directly unit-testable without a real
/// `permission_handler` platform channel (there is no fake/mock backend for
/// the plugin in this project's dependency set — `flutter test` has no
/// registered implementation for it at all, real or fake).
///
/// This is where the TASK-038 "on API<33, no POST_NOTIFICATIONS/
/// NEARBY_WIFI_DEVICES request is attempted" acceptance criterion actually
/// lives: [request] is called if and only if [status]'s first read is not
/// already [PermissionStatus.granted] — see `permission_gate_test.dart`,
/// which drives this function directly with fake `status`/`request`
/// closures standing in for "the plugin already reports this permission
/// granted" (the real pre-33 behaviour for both of those two permissions)
/// versus "the plugin reports not-yet-granted and must be asked".
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
