import 'dart:async';
import 'dart:developer';

import 'package:keryx/core/protocol/protocol.dart';
import 'package:keryx/core/state/radio_state.dart';

import 'arbiter.dart';
import 'clock.dart';
import 'effects.dart';
import 'emergency.dart';
import 'transport.dart';

/// Per-channel floor-control engine (KRX-041 / KRX-042 / KRX-043).
///
/// Consumes and emits TASK-006 [FloorMessage]s over [FloorTransport].
/// Drives the TASK-004 reducer by emitting [DispatchRadio] effects — it
/// never writes [RadioState] itself. Fully deterministic under
/// [VirtualClock].
class FloorEngine {
  FloorEngine({
    required this.localPeerId,
    required FloorTransport transport,
    required FloorClock clock,
    Duration tot = FloorTiming.defaultTot,
    this.busyLockout = true,
  }) : _transport = transport,
       _clock = clock,
       _tot = tot {
    if (localPeerId.isEmpty) {
      throw ArgumentError.value(localPeerId, 'localPeerId', 'must not be empty');
    }
    _assertTot(tot);
    _peers.add(localPeerId);
    _incoming = transport.incoming.listen(
      _onMessage,
      onError: (Object error, StackTrace stack) {
        log(
          'transport error: $error',
          name: _logName,
          error: error,
          stackTrace: stack,
        );
      },
    );
  }

  static const _logName = 'keryx.floor';

  /// FR-023: TOT is configurable 30–120 s.
  static const Duration minTot = Duration(seconds: 30);
  static const Duration maxTot = Duration(seconds: 120);
  static const Duration totWarnLead = Duration(seconds: 5);

  final String localPeerId;
  final FloorTransport _transport;
  final FloorClock _clock;
  final EmergencyPin _emg = EmergencyPin();
  final Set<String> _peers = <String>{};
  final StreamController<FloorEffect> _effects =
      StreamController<FloorEffect>.broadcast(sync: true);

  Duration _tot;
  bool busyLockout;
  bool _disposed = false;

  StreamSubscription<FloorMessage>? _incoming;

  _Phase _phase = _Phase.idle;
  String? _holder;
  DateTime? _leaseExpiresAt;
  bool _emergencyRequest = false;
  int _txReqAttempts = 0;

  FloorTimer? _retryTimer;
  FloorTimer? _leaseTimer;
  FloorTimer? _totWarnTimer;
  FloorTimer? _totCutTimer;
  FloorTimer? _idleTimer;

  /// Side-effect stream. SFX / haptics / [RadioReducer] subscribe here.
  Stream<FloorEffect> get effects => _effects.stream;

  Duration get tot => _tot;

  set tot(Duration value) {
    _assertTot(value);
    _tot = value;
  }

  /// Current lease holder, or `null` if the floor is free (or the lease
  /// has expired).
  String? get holder => _liveHolder;

  /// Lexicographically lowest peer in the current roster.
  String? get arbiterId => Arbiter.elect(_peers);

  bool get isLocalArbiter => arbiterId == localPeerId;

  bool get isTransmitting => _phase == _Phase.tx;

  bool get isFloorIdle => _phase == _Phase.idle && _liveHolder == null;

  bool get isEmergencyPinned => _emg.isPinned;

  String? get emergencyPeer => _emg.peer;

  /// Replace the channel roster. [peers] must include [localPeerId].
  /// Election is recomputed immediately (self-heal ≤ 500 ms is the time
  /// until the new arbiter answers the next `TX_REQ`).
  void updateRoster(Set<String> peers) {
    _checkOpen();
    if (!peers.contains(localPeerId)) {
      throw ArgumentError('roster must include localPeerId ($localPeerId)');
    }
    for (final id in peers) {
      if (id.isEmpty) {
        throw ArgumentError.value(id, 'peers', 'peerId must not be empty');
      }
    }
    _peers
      ..clear()
      ..addAll(peers);
    final elected = arbiterId;
    if (elected != null) {
      _emit(ArbiterChanged(elected));
    }
    log(
      'roster=${_peers.length} arbiter=$elected local=$localPeerId',
      name: _logName,
    );
  }

  /// Local PTT press. [emergency] is the FR-025 long-press path.
  void requestTransmit({bool emergency = false}) {
    _checkOpen();
    if (_phase == _Phase.tx || _phase == _Phase.awaiting) {
      if (emergency && !_emg.isPinned) {
        _pinEmergency(localPeerId, broadcast: true);
      }
      return;
    }

    if (emergency) {
      _pinEmergency(localPeerId, broadcast: true);
    }

    final remoteHold = _liveHolder != null && _liveHolder != localPeerId;
    if (!emergency && busyLockout && remoteHold) {
      log('lockout deny (holder=$_holder)', name: _logName);
      _emit(const DispatchRadio(RequestTransmit()));
      _emit(const DispatchRadio(TransmitDenied()));
      _emit(const DenyBuzz(FloorDenyReason.lockout));
      return;
    }

    _emergencyRequest = emergency;
    _phase = _Phase.awaiting;
    _emit(const DispatchRadio(RequestTransmit()));
    _txReqAttempts = 0;
    if (isLocalArbiter) {
      _arbitrate(
        requester: localPeerId,
        prio: emergency ? FloorPrio.emergency : FloorPrio.normal,
      );
    } else {
      _sendTxReq();
    }
  }

  /// Local PTT release (or latch unlock). Ignored if we do not hold TX.
  void releaseTransmit() {
    _checkOpen();
    if (_phase == _Phase.awaiting) {
      _cancelRetry();
      _phase = _Phase.idle;
      _emergencyRequest = false;
      return;
    }
    if (_phase != _Phase.tx) return;
    _endLocalTx();
  }

  /// Sender-side EMG clear (FR-025). No-op if we are not the pin holder.
  void clearEmergency() {
    _checkOpen();
    if (_emg.peer != localPeerId) return;
    _emg.clear(localPeerId);
    _send(EmgClr(peer: localPeerId));
    _emit(EmgCleared(localPeerId));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelRetry();
    _cancelLease();
    _cancelTot();
    _cancelIdle();
    _incoming?.cancel();
    _incoming = null;
    if (!_effects.isClosed) {
      _effects.close();
    }
  }

  // --- inbound ----------------------------------------------------------

  void _onMessage(FloorMessage message) {
    if (_disposed) return;
    // `peer` is the *subject*. TX_GRANT / TX_DENY name the grantee / denied
    // requester, so those must not be treated as echoes of our own send.
    switch (message) {
      case TxReq():
        if (message.peer == localPeerId) return;
        if (isLocalArbiter) {
          _arbitrate(requester: message.peer, prio: message.prio);
        }
      case TxGrant():
        _onGrant(message);
      case TxDeny():
        _onDeny(message);
      case TxStart():
        if (message.peer == localPeerId) return;
        _onRemoteStart(message.peer);
      case TxEnd():
        if (message.peer == localPeerId) return;
        _onRemoteEnd(message.peer);
      case Emg():
        if (message.peer == localPeerId) return;
        _pinEmergency(message.peer, broadcast: false);
      case EmgClr():
        if (message.peer == localPeerId) return;
        if (_emg.clear(message.peer)) {
          _emit(EmgCleared(message.peer));
        }
      case Presence() || Rchk() || RchkAck():
        break;
    }
  }

  void _onGrant(TxGrant grant) {
    final remaining = Duration(milliseconds: grant.leaseMs);
    if (remaining.isNegative) return;
    _installLease(grant.peer, remaining);

    if (grant.peer == localPeerId) {
      if (_phase != _Phase.tx) {
        _enterTx();
      }
      return;
    }

    if (_phase == _Phase.tx) {
      log('pre-empted by ${grant.peer}', name: _logName);
      _cancelTot();
      _phase = _Phase.idle;
      _send(TxEnd(peer: localPeerId));
      _emit(const DispatchRadio(EndTransmit()));
    }
  }

  void _onDeny(TxDeny deny) {
    if (deny.peer != localPeerId) return;
    if (_phase != _Phase.awaiting) return;
    _cancelRetry();
    _phase = _Phase.idle;
    _emergencyRequest = false;
    _emit(const DispatchRadio(TransmitDenied()));
    _emit(DenyBuzz(deny.reason));
  }

  void _onRemoteStart(String peer) {
    if (_phase == _Phase.tx) {
      _cancelTot();
      _phase = _Phase.idle;
      _send(TxEnd(peer: localPeerId));
      _emit(const DispatchRadio(EndTransmit()));
    }
    _holder ??= peer;
    _cancelIdle();
    if (_phase != _Phase.rx) {
      _phase = _Phase.rx;
      _emit(const DispatchRadio(RemoteFloorStarted()));
    }
  }

  void _onRemoteEnd(String peer) {
    // A TX_END from a pre-empted speaker must not tear down the new lease.
    if (_holder != null && _holder != peer) return;
    if (_holder == peer) {
      _clearLease();
    }
    if (_phase == _Phase.rx) {
      _phase = _Phase.idle;
      _emit(const DispatchRadio(RemoteFloorEnded()));
      _armIdle();
    }
  }

  // --- arbiter + local TX ----------------------------------------------

  void _arbitrate({required String requester, required int prio}) {
    final verdict = Arbiter.decide(
      requester: requester,
      prio: prio,
      holder: _holder,
      now: _clock.now(),
      leaseExpiresAt: _leaseExpiresAt,
      lease: FloorTiming.grantLease(_tot),
    );
    switch (verdict) {
      case ArbiterGrant():
        _installLease(verdict.peer, verdict.remaining);
        _send(
          TxGrant(peer: verdict.peer, leaseMs: verdict.remaining.inMilliseconds),
        );
        if (verdict.peer == localPeerId && _phase != _Phase.tx) {
          _enterTx();
        }
      case ArbiterDeny():
        _send(TxDeny(peer: verdict.peer, reason: verdict.reason));
        if (verdict.peer == localPeerId && _phase == _Phase.awaiting) {
          _phase = _Phase.idle;
          _emergencyRequest = false;
          _emit(const DispatchRadio(TransmitDenied()));
          _emit(DenyBuzz(verdict.reason));
        }
    }
  }

  void _sendTxReq() {
    if (_phase != _Phase.awaiting) return;
    _txReqAttempts += 1;
    _send(
      TxReq(
        peer: localPeerId,
        prio: _emergencyRequest ? FloorPrio.emergency : FloorPrio.normal,
        ts: _clock.now().millisecondsSinceEpoch,
      ),
    );
    _retryTimer?.cancel();
    _retryTimer = _clock.schedule(FloorTiming.txReqRetry, () {
      if (_phase != _Phase.awaiting) return;
      if (_txReqAttempts >= FloorTiming.txReqAttempts) {
        _giveUp();
        return;
      }
      _sendTxReq();
    });
  }

  void _giveUp() {
    if (_phase != _Phase.awaiting) return;
    _cancelRetry();
    _phase = _Phase.idle;
    _emergencyRequest = false;
    log('TX_REQ give-up after $_txReqAttempts attempts', name: _logName);
    _emit(const DispatchRadio(TransmitDenied()));
    _emit(const DenyBuzz(null));
  }

  void _enterTx() {
    _cancelRetry();
    _cancelIdle();
    _phase = _Phase.tx;
    _emergencyRequest = false;
    _emit(const DispatchRadio(TransmitGranted()));
    _emit(const GrantTone());
    _send(TxStart(peer: localPeerId));
    _armTot();
  }

  void _endLocalTx() {
    _cancelTot();
    _phase = _Phase.idle;
    if (_holder == localPeerId) {
      _clearLease();
    }
    _send(TxEnd(peer: localPeerId));
    _emit(const DispatchRadio(EndTransmit()));
    _armIdle();
  }

  void _armTot() {
    _cancelTot();
    final warnAfter = _tot - totWarnLead;
    if (warnAfter > Duration.zero) {
      _totWarnTimer = _clock.schedule(warnAfter, () {
        if (_phase == _Phase.tx) _emit(const TotWarn());
      });
    }
    _totCutTimer = _clock.schedule(_tot, () {
      if (_phase != _Phase.tx) return;
      log('TOT cut', name: _logName);
      _emit(const TotCut());
      _endLocalTx();
    });
  }

  // --- lease / idle -----------------------------------------------------

  String? get _liveHolder {
    if (_holder == null) return null;
    final expires = _leaseExpiresAt;
    if (expires != null && !_clock.now().isBefore(expires)) return null;
    return _holder;
  }

  void _installLease(String peer, Duration remaining) {
    _holder = peer;
    _leaseExpiresAt = _clock.now().add(remaining);
    _cancelLease();
    if (remaining <= Duration.zero) {
      _onLeaseExpired();
      return;
    }
    _leaseTimer = _clock.schedule(remaining, _onLeaseExpired);
    _cancelIdle();
  }

  void _onLeaseExpired() {
    if (_holder == null) return;
    log('lease expired holder=$_holder', name: _logName);
    final wasTx = _phase == _Phase.tx && _holder == localPeerId;
    final wasRx = _phase == _Phase.rx;
    _clearLease();
    if (wasTx) {
      _cancelTot();
      _phase = _Phase.idle;
      _send(TxEnd(peer: localPeerId));
      _emit(const DispatchRadio(EndTransmit()));
    } else if (wasRx) {
      _phase = _Phase.idle;
      _emit(const DispatchRadio(RemoteFloorEnded()));
    }
    _armIdle();
  }

  void _clearLease() {
    _holder = null;
    _leaseExpiresAt = null;
    _cancelLease();
  }

  void _armIdle() {
    _cancelIdle();
    _idleTimer = _clock.schedule(FloorTiming.floorIdleDebounce, () {
      if (isFloorIdle) _emit(const FloorIdleSettled());
    });
  }

  void _pinEmergency(String peer, {required bool broadcast}) {
    _emg.pin(peer);
    _emit(EmgPinned(peer));
    if (broadcast) {
      _send(Emg(peer: peer));
    }
  }

  // --- plumbing ---------------------------------------------------------

  void _send(FloorMessage message) {
    try {
      _transport.send(message);
    } on Object catch (error, stack) {
      log(
        'send failed: $error',
        name: _logName,
        error: error,
        stackTrace: stack,
      );
    }
  }

  void _emit(FloorEffect effect) {
    if (_disposed || _effects.isClosed) return;
    _effects.add(effect);
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _cancelLease() {
    _leaseTimer?.cancel();
    _leaseTimer = null;
  }

  void _cancelTot() {
    _totWarnTimer?.cancel();
    _totWarnTimer = null;
    _totCutTimer?.cancel();
    _totCutTimer = null;
  }

  void _cancelIdle() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void _checkOpen() {
    if (_disposed) {
      throw StateError('FloorEngine.dispose() has already been called');
    }
  }

  static void _assertTot(Duration tot) {
    if (tot < minTot || tot > maxTot) {
      throw ArgumentError.value(
        tot,
        'tot',
        'FR-023 requires 30–120 s (got ${tot.inSeconds} s)',
      );
    }
  }
}

enum _Phase { idle, awaiting, tx, rx }
