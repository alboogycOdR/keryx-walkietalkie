/// Presence WebSocket client (Technical §4.2/§4.3): signed upgrade, a
/// `{"status": ...}` send on local status change, a heartbeat every 60 s,
/// and a `Stream<PresenceUpdate>` (plus rotation-notice and alert streams)
/// fed by the server's fan-out. Reconnects with exponential backoff —
/// mirrors `lib/services/linked/link_monitor.dart`'s shape, but
/// self-contained (no `FloorEngine`/host dependency; that wiring is a
/// later task, same split as `LinkedController`/`LinkMonitor`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:keryx/core/identity/keys.dart' show IdentityKeyPair;

import 'directory_signing.dart';
import 'presence_transport.dart';

const _logName = 'keryx.directory.presence';
const _presencePath = '/v2/presence';

/// `{pk, status, talking?, since}` — a contact's or co-member's presence
/// changing, fanned out over Redis pub/sub (Technical §4.3).
class PresenceUpdate {
  const PresenceUpdate({required this.pk, required this.status, this.talking, required this.since});

  final String pk;
  final String status;
  final bool? talking;
  final int since;

  factory PresenceUpdate.fromJson(Map<String, Object?> json) => PresenceUpdate(
    pk: json['pk'] as String,
    status: json['status'] as String,
    talking: json['talking'] as bool?,
    since: json['since'] as int? ?? 0,
  );
}

/// `{type: rotation, group_id, key_version}` — a group's secret rotated;
/// the member must fetch its new sealed copy (Technical §5.3).
class GroupRotationNotice {
  const GroupRotationNotice({required this.groupId, required this.keyVersion});
  final String groupId;
  final int keyVersion;

  factory GroupRotationNotice.fromJson(Map<String, Object?> json) => GroupRotationNotice(
    groupId: json['group_id'] as String,
    keyVersion: json['key_version'] as int,
  );
}

/// `{type: alert, from_pk, since}`.
class AlertNotice {
  const AlertNotice({required this.fromPk, required this.since});
  final String fromPk;
  final int since;

  factory AlertNotice.fromJson(Map<String, Object?> json) =>
      AlertNotice(fromPk: json['from_pk'] as String, since: json['since'] as int? ?? 0);
}

/// Local presence status a caller may push. Wire values match the
/// contract's `status` enum exactly.
enum LocalPresenceStatus {
  available,
  busy,
  dnd,
  offline;

  String get wireValue => name;
}

class PresenceClient {
  PresenceClient({
    required Uri baseUrl,
    required IdentityKeyPair keyPair,
    PresenceTransport transport = const IoPresenceTransport(),
    Duration heartbeatInterval = const Duration(seconds: 60),
    Duration initialBackoff = const Duration(seconds: 1),
    Duration maxBackoff = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) : _baseUrl = baseUrl,
       _keyPair = keyPair,
       _transport = transport,
       _heartbeatInterval = heartbeatInterval,
       _initialBackoff = initialBackoff,
       _maxBackoff = maxBackoff,
       _maxAttempts = maxAttempts;

  final Uri _baseUrl;
  final IdentityKeyPair _keyPair;
  final PresenceTransport _transport;
  final Duration _heartbeatInterval;
  final Duration _initialBackoff;
  final Duration _maxBackoff;
  final int _maxAttempts;

  final _updates = StreamController<PresenceUpdate>.broadcast();
  final _rotations = StreamController<GroupRotationNotice>.broadcast();
  final _alerts = StreamController<AlertNotice>.broadcast();
  final _connectionState = StreamController<bool>.broadcast();

  PresenceSocket? _socket;
  StreamSubscription<String>? _messagesSub;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool _disposed = false;
  bool _stopped = false;
  LocalPresenceStatus? _pendingStatus;

  Stream<PresenceUpdate> get updates => _updates.stream;
  Stream<GroupRotationNotice> get rotationNotices => _rotations.stream;
  Stream<AlertNotice> get alerts => _alerts.stream;

  /// `true` once connected, `false` on every disconnect (including the
  /// final give-up after [maxAttempts]).
  Stream<bool> get connectionState => _connectionState.stream;

  bool get isConnected => _socket != null;

  /// True once [maxAttempts] consecutive reconnect attempts have all
  /// failed and no further attempt is scheduled.
  bool get gaveUp => _gaveUp;
  bool _gaveUp = false;

  Future<void> start() async {
    _checkDisposed();
    _stopped = false;
    _gaveUp = false;
    _attempt = 0;
    await _connect();
  }

  /// Sends `{"status": status}` if connected; otherwise remembered and
  /// sent as soon as the next connection succeeds (a status change made
  /// while offline must not be silently dropped).
  void setStatus(LocalPresenceStatus status) {
    final socket = _socket;
    if (socket == null) {
      _pendingStatus = status;
      return;
    }
    socket.send(jsonEncode({'status': status.wireValue}));
  }

  Future<void> stop() async {
    _stopped = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _teardownSocket();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _updates.close();
    await _rotations.close();
    await _alerts.close();
    await _connectionState.close();
  }

  Future<void> _connect() async {
    if (_disposed || _stopped) return;
    try {
      final headers = await signedDirectoryHeaders(
        keyPair: _keyPair,
        method: 'GET',
        path: _presencePath,
        body: '',
      );
      final socket = await _transport.connect(
        url: _baseUrl.resolve(_presencePath.substring(1)),
        headers: headers,
      );
      _socket = socket;
      _attempt = 0;
      _gaveUp = false;
      _emitConnected(true);
      _messagesSub = socket.messages.listen(_onMessage, onError: (Object _) {});
      unawaited(
        socket.done.then((_) {
          if (!_disposed && !_stopped) _onSocketClosed();
        }),
      );
      _startHeartbeat();
      final pending = _pendingStatus;
      if (pending != null) {
        socket.send(jsonEncode({'status': pending.wireValue}));
        _pendingStatus = null;
      }
    } on Object catch (error, stack) {
      developer.log('presence connect failed: $error', name: _logName, error: error, stackTrace: stack);
      _onSocketClosed();
    }
  }

  void _onSocketClosed() {
    if (_disposed || _stopped) return;
    final wasConnected = _socket != null;
    _teardownSocketSync();
    if (wasConnected) _emitConnected(false);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _stopped) return;
    _attempt++;
    if (_attempt > _maxAttempts) {
      _gaveUp = true;
      developer.log('presence: giving up after $_maxAttempts attempts', name: _logName);
      return;
    }
    final backoffMs = (_initialBackoff.inMilliseconds * (1 << (_attempt - 1))).clamp(
      _initialBackoff.inMilliseconds,
      _maxBackoff.inMilliseconds,
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: backoffMs), () {
      if (!_disposed && !_stopped) unawaited(_connect());
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      _socket?.send(jsonEncode({'type': 'heartbeat'}));
    });
  }

  void _onMessage(String raw) {
    Map<String, Object?> json;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return;
      json = decoded;
    } on FormatException catch (error) {
      developer.log('presence: malformed message: $error', name: _logName);
      return;
    }
    final type = json['type'] as String?;
    switch (type) {
      case 'rotation':
        if (!_rotations.isClosed) _rotations.add(GroupRotationNotice.fromJson(json));
      case 'alert':
        if (!_alerts.isClosed) _alerts.add(AlertNotice.fromJson(json));
      case 'heartbeat':
        break; // server-side echo, if any; nothing to do
      default:
        if (json.containsKey('pk') && json.containsKey('status')) {
          if (!_updates.isClosed) _updates.add(PresenceUpdate.fromJson(json));
        }
    }
  }

  void _emitConnected(bool value) {
    if (!_connectionState.isClosed) _connectionState.add(value);
  }

  Future<void> _teardownSocket() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _messagesSub?.cancel();
    _messagesSub = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.close();
      } on Object catch (error, stack) {
        developer.log('presence: close failed: $error', name: _logName, error: error, stackTrace: stack);
      }
    }
  }

  void _teardownSocketSync() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    unawaited(_messagesSub?.cancel());
    _messagesSub = null;
    _socket = null;
  }

  void _checkDisposed() {
    if (_disposed) throw StateError('PresenceClient is disposed');
  }
}
