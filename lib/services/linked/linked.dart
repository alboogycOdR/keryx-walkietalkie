/// LINKED-path client (KRX-052 / KRX-055, TS §8.4): LiveKit join/publish/
/// subscribe mirroring PTT, floor control over LiveKit data messages, and
/// link-loss/regain handling. Mirrors `lib/services/mesh/mesh.dart`'s role
/// for the LOCAL path.
library;

export 'link_monitor.dart';
export 'linked_controller.dart';
export 'linked_floor_transport.dart';
export 'livekit_adapter.dart';
export 'livekit_client_adapter.dart';
export 'token_client.dart';
