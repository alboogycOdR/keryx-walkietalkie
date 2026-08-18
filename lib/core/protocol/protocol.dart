/// Floor-control protocol v1 wire layer (KRX-040 / TS §8.6).
///
/// Transport-agnostic JSON codec. LOCAL data channels and LiveKit data
/// messages both consume this; the runtime engine is TASK-022.
library;

export 'codec.dart';
export 'messages.dart';
export 'timing.dart';
