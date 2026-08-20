import 'peer_session.dart';
import 'signaling_constants.dart';

/// Snapshot of the LOCAL signaling layer.
class SignalingState {
  const SignalingState({
    required this.running,
    required this.boundPort,
    required this.sessions,
  });

  static const idle = SignalingState(
    running: false,
    boundPort: 0,
    sessions: [],
  );

  final bool running;
  final int boundPort;
  final List<PeerSession> sessions;

  int get peerCount => sessions.length;

  /// True when remote sessions exceed the 16-peer supported envelope.
  /// Soft: connections are still accepted (KRX-034 / R3).
  bool get capWarning => peerCount > SignalingConstants.lanPeerSoftCap;

  SignalingState copyWith({
    bool? running,
    int? boundPort,
    List<PeerSession>? sessions,
  }) {
    return SignalingState(
      running: running ?? this.running,
      boundPort: boundPort ?? this.boundPort,
      sessions: sessions ?? this.sessions,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SignalingState &&
        other.running == running &&
        other.boundPort == boundPort &&
        other.capWarning == capWarning &&
        _listEquals(other.sessions, sessions);
  }

  @override
  int get hashCode => Object.hash(running, boundPort, sessions.length);

  @override
  String toString() =>
      'SignalingState(running=$running port=$boundPort '
      'n=$peerCount capWarning=$capWarning)';
}

bool _listEquals(List<PeerSession> a, List<PeerSession> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
