import 'package:permission_handler/permission_handler.dart' as ph;

/// Camera permission state, narrowed to what the Event QR scan screen
/// needs to render an actionable state (Design §2.7: "appropriate
/// camera/permission states") rather than a blank screen or raw error.
enum EventQrPermissionState {
  /// Camera may be used right away.
  granted,

  /// Not yet granted, but the OS prompt can still be shown again.
  denied,

  /// The OS will no longer show its own prompt — only Settings can grant
  /// it now.
  permanentlyDenied,

  /// No usable camera / platform support at all (e.g. restricted profile,
  /// no camera hardware). Nothing further can be requested.
  unavailable,
}

/// Injectable seam for camera-permission checks. `permission_handler`'s
/// real plugin has no fake/mock platform-channel backend (same problem
/// `lib/features/face/permission_gate.dart`'s `FacePermissionGate`
/// documents for microphone/notification permissions), so `event_qr_ui`
/// widgets depend on this interface — never the plugin directly — to stay
/// unit-testable.
abstract class EventQrPermissionGate {
  /// Current status, without prompting.
  Future<EventQrPermissionState> checkCamera();

  /// Prompts if [checkCamera] returned [EventQrPermissionState.denied];
  /// a no-op status read otherwise (the OS will not re-prompt for
  /// [EventQrPermissionState.permanentlyDenied] or
  /// [EventQrPermissionState.unavailable]).
  Future<EventQrPermissionState> requestCamera();

  /// Opens the OS app-settings page — the only recovery path once
  /// permanently denied.
  Future<void> openAppSettings();
}

/// `permission_handler`-backed [EventQrPermissionGate].
class PermissionHandlerEventQrPermissionGate implements EventQrPermissionGate {
  const PermissionHandlerEventQrPermissionGate();

  @override
  Future<EventQrPermissionState> checkCamera() async {
    return _map(await ph.Permission.camera.status);
  }

  @override
  Future<EventQrPermissionState> requestCamera() async {
    return _map(await ph.Permission.camera.request());
  }

  @override
  Future<void> openAppSettings() async {
    await ph.openAppSettings();
  }

  EventQrPermissionState _map(ph.PermissionStatus status) {
    switch (status) {
      case ph.PermissionStatus.granted:
      case ph.PermissionStatus.limited:
        return EventQrPermissionState.granted;
      case ph.PermissionStatus.permanentlyDenied:
        return EventQrPermissionState.permanentlyDenied;
      case ph.PermissionStatus.restricted:
      case ph.PermissionStatus.provisional:
        return EventQrPermissionState.unavailable;
      case ph.PermissionStatus.denied:
        return EventQrPermissionState.denied;
    }
  }
}
