import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:permission_handler/permission_handler.dart';

/// Unit tests for [ensurePermissionOutcome] — the status-check-before-
/// request algorithm `DeviceFacePermissionGate` (the real
/// `permission_handler`-backed implementation) delegates every one of its
/// three methods to. See that class's dartdoc for why this pure function,
/// rather than `DeviceFacePermissionGate` itself, is the unit under test
/// here: `permission_handler` has no fake/mock platform backend in this
/// project's dependency set, so nothing under `lib/services/platform`'s
/// convention (a fake platform, like `FakeRadioServicePlatform`) is
/// available to drive the real class end-to-end under `flutter test`.
void main() {
  group('ensurePermissionOutcome', () {
    test(
      'already-granted status short-circuits: request is never called '
      '(TASK-038 acceptance criterion: this is exactly how API<33 produces '
      '"no POST_NOTIFICATIONS/NEARBY_WIFI_DEVICES request attempted" — '
      'permission_handler reports those two as already granted pre-33, '
      'with no explicit SDK-version check needed on this side)',
      () async {
        var requestCalls = 0;
        final outcome = await ensurePermissionOutcome(
          status: () async => PermissionStatus.granted,
          request: () async {
            requestCalls++;
            return PermissionStatus.granted;
          },
        );
        expect(outcome, FacePermissionOutcome.granted);
        expect(requestCalls, 0);
      },
    );

    test(
      'not-yet-granted status escalates to request; a granted result is '
      'reported granted',
      () async {
        var statusCalls = 0;
        var requestCalls = 0;
        final outcome = await ensurePermissionOutcome(
          status: () async {
            statusCalls++;
            return PermissionStatus.denied;
          },
          request: () async {
            requestCalls++;
            return PermissionStatus.granted;
          },
        );
        expect(outcome, FacePermissionOutcome.granted);
        expect(statusCalls, 1);
        expect(requestCalls, 1);
      },
    );

    test(
      'not-yet-granted status that is then denied by the user is reported '
      'denied',
      () async {
        final outcome = await ensurePermissionOutcome(
          status: () async => PermissionStatus.denied,
          request: () async => PermissionStatus.denied,
        );
        expect(outcome, FacePermissionOutcome.denied);
      },
    );

    test(
      'permanentlyDenied (a real PermissionStatus value distinct from '
      'denied) also reports FacePermissionOutcome.denied — the two-way '
      'outcome intentionally collapses every non-granted status',
      () async {
        final outcome = await ensurePermissionOutcome(
          status: () async => PermissionStatus.permanentlyDenied,
          request: () async => PermissionStatus.permanentlyDenied,
        );
        expect(outcome, FacePermissionOutcome.denied);
      },
    );
  });
}
