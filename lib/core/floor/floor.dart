/// Floor-control runtime (KRX-041 / KRX-042 / KRX-043).
///
/// Consumes TASK-006 protocol messages over an injected transport and
/// drives the TASK-004 reducer via [DispatchRadio] effects.
library;

export 'arbiter.dart';
export 'clock.dart';
export 'effects.dart';
export 'emergency.dart';
export 'floor_engine.dart';
export 'transport.dart';
