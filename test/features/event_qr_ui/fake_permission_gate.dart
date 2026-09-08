import 'package:keryx/features/event_qr_ui/event_qr_permission_gate.dart';

/// Hand-written [EventQrPermissionGate] double — `permission_handler` has
/// no fake/mock platform-channel backend, so every camera-permission test
/// drives this instead of the real plugin.
class FakePermissionGate implements EventQrPermissionGate {
  FakePermissionGate({EventQrPermissionState initial = EventQrPermissionState.granted})
    : _state = initial;

  EventQrPermissionState _state;

  /// What [requestCamera] resolves to. Defaults to [_state]'s current
  /// value at construction; tests may override to simulate a grant/deny
  /// after a request.
  EventQrPermissionState? requestResult;

  int checkCalls = 0;
  int requestCalls = 0;
  int openSettingsCalls = 0;

  @override
  Future<EventQrPermissionState> checkCamera() async {
    checkCalls++;
    return _state;
  }

  @override
  Future<EventQrPermissionState> requestCamera() async {
    requestCalls++;
    _state = requestResult ?? _state;
    return _state;
  }

  @override
  Future<void> openAppSettings() async {
    openSettingsCalls++;
  }
}
