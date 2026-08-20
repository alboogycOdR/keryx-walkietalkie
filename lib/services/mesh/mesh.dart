/// Full-mesh WebRTC audio over TASK-020's LAN signaling sessions (KRX-032,
/// TS §8.3 step 3, §8.5). Consumes [FloorEngine] (TASK-022) for the local
/// track gate and produces the concrete [FloorTransport] `FloorEngine` is
/// constructed with in production — `LoopbackHub` remains test-only.
library;

export 'floor_data_channel_transport.dart';
export 'mesh_config.dart';
export 'mesh_connection.dart';
export 'mesh_controller.dart';
export 'opus_sdp.dart';
export 'rtc_adapter.dart';
export 'rtc_adapter_flutter_webrtc.dart';
export 'rx_gate.dart';
