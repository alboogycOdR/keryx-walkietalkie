/// Radio session — host composition layer (KRX-060/062, TASK-035).
///
/// Composes LOCAL (discovery + signaling + mesh) and LINKED (LiveKit)
/// transport lifecycles behind one `RadioSessionController`, so
/// `FaceScreen` (TASK-037) does not have to know either exists. Mirrors
/// `lib/services/mesh/mesh.dart` / `lib/services/linked/linked.dart`'s
/// barrel-per-service-directory convention.
library;

export 'linked_proxy_floor_transport.dart';
export 'radio_session_controller.dart';
export 'station_info.dart';
