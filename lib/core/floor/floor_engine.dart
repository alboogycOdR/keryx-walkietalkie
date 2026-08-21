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
    String? callsign,
  }) : _transport = transport,
       _clock = clock,
       _tot = tot,
       callsign = (callsign == null || callsign.isEmpty)
           ? localPeerId
           : callsign,
       _joinedAt = clock.now() {
    if (localPeerId.isEmpty) {
      throw ArgumentError.value(
        localPeerId,
        'localPeerId',
        'must not be empty',
      );
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
    _armPresenceHeartbeat();
  }

  static const _logName = 'keryx.floor';

  /// FR-023: TOT is configurable 30–120 s.
  static const Duration minTot = Duration(seconds: 30);
  static const Duration maxTot = Duration(seconds: 120);
  static const Duration totWarnLead = Duration(seconds: 5);

  final String localPeerId;

  /// Display callsign carried on outgoing `PRESENCE.cs`. Defaults to
  /// [localPeerId] so existing constructors stay valid; hosts that know
  /// the real callsign may pass it.
  final String callsign;
  final FloorTransport _transport;
  final FloorClock _clock;
  final DateTime _joinedAt;
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
  int _presenceSeq = 0;
  bool _othersSeen = false;
  bool _firstOccupant = false;
  /// Host has called [updateRoster] at least once. Constructor-default
  /// `{self}` is not a channel join — soak delivers the real roster on
  /// the same delayed channel as `PRESENCE`.
  bool _rosterDeclared = false;
  /// Holders whose lease we already ran to expiry. `PRESENCE` snapshots
  /// must not resurrect them; `TX_GRANT` / `TX_START` still can (a new
  /// session after the previous lease died).
  final Set<String> _expiredHolders = <String>{};

  /// Start of the current connected-observation window. Null until the
  /// first inbound [FloorMessage]. Reset when inbound resumes after a
  /// silence longer than [FloorTiming.presenceHeartbeat] (partition).
  DateTime? _observingSince;
  DateTime? _lastInboundAt;

  /// Peers whose latest `PRESENCE` advertised an idle floor. Direct idle
  /// proof (the §8.6 exception) requires every other rostered peer to
  /// appear here and `_liveHolder == null`.
  final Set<String> _idleWitnesses = <String>{};

  FloorTimer? _retryTimer;
  FloorTimer? _leaseTimer;
  FloorTimer? _totWarnTimer;
  FloorTimer? _totCutTimer;
  FloorTimer? _idleTimer;
  FloorTimer? _presenceTimer;

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
    final hasOthers = peers.any((id) => id != localPeerId);
    if (hasOthers && !_othersSeen) {
      _othersSeen = true;
      // First occupant: we spent a full presenceHeartbeat alone before
      // anyone else appeared, so we cannot have missed a live lease.
      // A FaceScreen-style `updateRoster({self})` at boot does NOT count
      // — that would make every production late-joiner skip the guard.
      _firstOccupant = !_clock.now().isBefore(
        _joinedAt.add(FloorTiming.presenceHeartbeat),
      );
    }
    _rosterDeclared = true;
    _peers
      ..clear()
      ..addAll(peers);
    _idleWitnesses.removeWhere((id) => !_peers.contains(id));
    final elected = arbiterId;
    if (elected != null) {
      _emit(ArbiterChanged(elected));
    }
    log(
      'roster=${_peers.length} arbiter=$elected local=$localPeerId',
      name: _logName,
    );
    // Live snapshot, not a cached copy — late joiners learn the holder
    // on the same roster fan-out that elects them.
    _emitPresence();
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

    final joinGuarded = !Arbiter.maySelfGrant(
      rosterSize: _peers.length,
      firstOccupant: _firstOccupant,
      joinedAt: _joinedAt,
      now: _clock.now(),
      rosterConverged: _rosterConverged,
      observingSince: _observingSince,
      linkReachable: !_linkPaused,
    );
    final remoteHold = _liveHolder != null && _liveHolder != localPeerId;
    // A join-guarded local arbiter must emit TX_DENY(BUSY) rather than
    // the local LOCKOUT shortcut. Non-arbiters keep the existing lockout
    // path — they are not the late-joiner self-grant case.
    if (!emergency &&
        busyLockout &&
        remoteHold &&
        !(joinGuarded && isLocalArbiter)) {
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
    _cancelPresence();
    _incoming?.cancel();
    _incoming = null;
    if (!_effects.isClosed) {
      _effects.close();
    }
  }

  // --- inbound ----------------------------------------------------------

  void _onMessage(FloorMessage message) {
    if (_disposed) return;
    // Any delivered message means we are currently able to receive —
    // this is the only partition signal the engine has (the soak
    // harness never tells FloorEngine about SimNetwork partitions).
    _noteLinkActivity();
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
      case Presence():
        _onPresence(message);
      case Rchk() || RchkAck():
        break;
    }
  }

  void _onGrant(TxGrant grant) {
    final remaining = Duration(milliseconds: grant.leaseMs);
    if (remaining.isNegative) return;

    if (grant.peer == localPeerId) {
      final live = _liveHolder;
      // A delayed/blind arbiter can grant us while we already have proof
      // someone else holds (PRESENCE / TX_START / an earlier GRANT).
      // Entering TX here is a double-grant; ignore unless emergency.
      if (live != null && live != localPeerId && !_emergencyRequest) {
        log(
          'ignore self-grant; live holder=$live',
          name: _logName,
        );
        return;
      }
      // Still in the (possibly paused) join-guard window with no idle
      // proof: a GRANT decided while we were blind must not enter TX.
      if (_inJoinGuardWindow && live == null && !_hasDirectIdleProof) {
        log('ignore self-grant; join-guard / link paused', name: _logName);
        return;
      }
      _installLease(grant.peer, remaining);
      if (_phase != _Phase.tx) {
        _enterTx();
      }
      return;
    }

    _installLease(grant.peer, remaining);

    if (_phase == _Phase.tx) {
      log('pre-empted by ${grant.peer}', name: _logName);
      _cancelTot();
      _phase = _Phase.idle;
      _send(TxEnd(peer: localPeerId));
      _emit(const DispatchRadio(EndTransmit()));
    } else if (_phase == _Phase.awaiting) {
      _cancelRetry();
      _emergencyRequest = false;
      _phase = _Phase.rx;
      _emit(const DispatchRadio(TransmitDenied()));
      _emit(const DenyBuzz(FloorDenyReason.busy));
      _emit(const DispatchRadio(RemoteFloorStarted()));
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
    } else if (_phase == _Phase.awaiting) {
      _cancelRetry();
      _emergencyRequest = false;
      _emit(const DispatchRadio(TransmitDenied()));
      _emit(const DenyBuzz(FloorDenyReason.busy));
    }
    // TX_START does not carry a lease. If we have no live expiry for this
    // speaker, install TOT+2s from now so a crashed sender cannot be
    // held forever (`_liveHolder` treats a null expiry as immortal).
    // Do not extend an existing timed lease — TX_GRANT / PRESENCE are
    // the remaining-time authorities.
    if (_liveHolder != peer || _leaseExpiresAt == null) {
      if (_liveHolder == null || _liveHolder == peer) {
        _installLease(peer, FloorTiming.grantLease(_tot), announce: false);
      } else {
        _holder ??= peer;
      }
    }
    _idleWitnesses.remove(peer);
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
    // Late-joiner guard (TS §8.6): do not grant *ourselves* until one
    // presenceHeartbeat has elapsed (unless first occupant / alone).
    // Granting a remote requester is unchanged — a fresh channel's first
    // PTT from a non-arbiter must still complete synchronously, and a
    // late joiner that has adopted `PRESENCE.holder` will BUSY/pre-empt
    // via the existing decide() path.
    // While the join-guard window is open and we have no live holder and
    // no idle proof, do not grant anyone — a late-joiner arbiter granting
    // a third peer is the same double-grant class as self-grant.
    if (_inJoinGuardWindow && _liveHolder == null && !_hasDirectIdleProof) {
      _denyBusy(requester);
      return;
    }
    if (requester == localPeerId &&
        !Arbiter.maySelfGrant(
          rosterSize: _peers.length,
          firstOccupant: _firstOccupant,
          joinedAt: _joinedAt,
          now: _clock.now(),
          rosterConverged: _rosterConverged,
          observingSince: _observingSince,
          linkReachable: !_linkPaused,
        ) &&
        !_hasDirectIdleProof) {
      _denyBusy(requester);
      return;
    }
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
          TxGrant(
            peer: verdict.peer,
            leaseMs: verdict.remaining.inMilliseconds,
          ),
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

  void _installLease(String peer, Duration remaining, {bool announce = true}) {
    _expiredHolders.remove(peer);
    _holder = peer;
    _leaseExpiresAt = _clock.now().add(remaining);
    _cancelLease();
    if (remaining <= Duration.zero) {
      _onLeaseExpired();
      return;
    }
    _leaseTimer = _clock.schedule(remaining, _onLeaseExpired);
    _cancelIdle();
    if (announce) _emitPresence();
  }

  void _onLeaseExpired() {
    if (_holder == null) return;
    log('lease expired holder=$_holder', name: _logName);
    _expiredHolders.add(_holder!);
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

  void _clearLease({bool announce = true}) {
    _holder = null;
    _leaseExpiresAt = null;
    _cancelLease();
    if (announce) _emitPresence();
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

  void _cancelPresence() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
  }

  /// Join-guard window independent of current roster size — a late
  /// joiner whose `updateRoster` has not landed yet still has size 1.
  ///
  /// Wall-clock since [_joinedAt] is not enough: time spent unable to
  /// receive (partition) must not count, and a currently unreachable
  /// peer stays guarded even after 5 s of wall time. Inbound after a
  /// heartbeat-long gap restarts [_observingSince] so a heal does not
  /// immediately self-grant.
  bool get _inJoinGuardWindow {
    if (_firstOccupant) return false;
    if (_linkPaused) return true;
    final started = _observingSince ?? _joinedAt;
    return _clock.now().isBefore(
      started.add(FloorTiming.presenceHeartbeat),
    );
  }

  /// True when we have never received a [FloorMessage], or the last one
  /// was more than one [FloorTiming.presenceHeartbeat] ago. Matches
  /// `SimNetwork.setPartitioned` from the engine's point of view: a
  /// partitioned peer sends and receives nothing.
  bool get _linkPaused {
    final last = _lastInboundAt;
    if (last == null) return true;
    return _clock.now().difference(last) > FloorTiming.presenceHeartbeat;
  }

  void _noteLinkActivity() {
    final now = _clock.now();
    final last = _lastInboundAt;
    if (last != null &&
        now.difference(last) > FloorTiming.presenceHeartbeat) {
      _observingSince = now;
      // Witnesses collected before the partition are stale — the
      // transmitter we missed would have advertised `holder`, not idle.
      _idleWitnesses.clear();
    } else {
      _observingSince ??= now;
    }
    _lastInboundAt = now;
  }

  /// Host-declared roster, or the construction instant (no clock has
  /// elapsed). Production hosts call [updateRoster] before the user can
  /// PTT (FaceScreen `_boot`). VirtualClock fixtures that PTT without
  /// elapsing (linked `_soloEngine`) still need a synchronous solo
  /// grant. Any later undeclared PTT is the soak residual and is denied.
  bool get _rosterConverged =>
      _rosterDeclared || !_clock.now().isAfter(_joinedAt);

  /// Direct proof the floor is idle (§8.6 exception to the join guard):
  /// host-declared solo, first occupant, or every other rostered peer
  /// has advertised idle via `PRESENCE` and we have no live holder.
  /// Constructor-default `{self}` is not proof — the host must have
  /// called [updateRoster]. A burst from a *subset* of peers cannot
  /// satisfy this — the transmitter would be the missing witness,
  /// advertising `holder` rather than idle.
  bool get _hasDirectIdleProof {
    if (_liveHolder != null) return false;
    if (!_rosterConverged) return false;
    if (_peers.length <= 1) return true;
    if (_firstOccupant) return true;
    // Idle witnesses collected before a partition are not proof — the
    // live holder is the missing witness, and we could not hear them.
    if (_linkPaused) return false;
    for (final id in _peers) {
      if (id == localPeerId) continue;
      if (!_idleWitnesses.contains(id)) return false;
    }
    return true;
  }

  void _denyBusy(String requester) {
    _send(TxDeny(peer: requester, reason: FloorDenyReason.busy));
    if (requester == localPeerId && _phase == _Phase.awaiting) {
      _phase = _Phase.idle;
      _emergencyRequest = false;
      _emit(const DispatchRadio(TransmitDenied()));
      _emit(const DenyBuzz(FloorDenyReason.busy));
    }
  }

  void _armPresenceHeartbeat() {
    _presenceTimer?.cancel();
    _presenceTimer = _clock.schedule(FloorTiming.presenceHeartbeat, () {
      if (_disposed) return;
      _emitPresence();
      _armPresenceHeartbeat();
    });
  }

  void _emitPresence() {
    if (_disposed) return;
    _presenceSeq += 1;
    final live = _liveHolder;
    int? remainingMs;
    if (live != null) {
      final expires = _leaseExpiresAt;
      remainingMs = expires == null
          ? 0
          : expires.difference(_clock.now()).inMilliseconds;
      if (remainingMs < 0) remainingMs = 0;
    }
    _send(
      Presence(
        peer: localPeerId,
        cs: callsign,
        seq: _presenceSeq,
        holder: live,
        leaseRemainingMs: live == null ? null : remainingMs,
      ),
    );
  }

  void _onPresence(Presence presence) {
    if (presence.peer == localPeerId) return;
    final remoteHolder = presence.holder;
    final remainingMs = presence.leaseRemainingMs;
    if (remoteHolder == null || remainingMs == null) {
      _idleWitnesses.add(presence.peer);
      // Idle snapshot. Honour only from the peer we currently believe
      // holds — a blind joiner also sends idle PRESENCE.
      if (_liveHolder != null && presence.peer == _liveHolder) {
        _clearLease(announce: false);
        if (_phase == _Phase.rx) {
          _phase = _Phase.idle;
          _emit(const DispatchRadio(RemoteFloorEnded()));
          _armIdle();
        }
      }
      return;
    }
    _idleWitnesses.remove(presence.peer);
    _idleWitnesses.remove(remoteHolder);
    final remaining = Duration(milliseconds: remainingMs);
    if (remaining <= Duration.zero) return;
    // A delayed snapshot must not resurrect a holder whose lease we
    // already expired. TX_GRANT / TX_START can start a new session.
    if (_expiredHolders.contains(remoteHolder) && _liveHolder != remoteHolder) {
      return;
    }

    if (_phase == _Phase.tx) {
      // A late joiner can solo-grant before updateRoster lands (engine
      // still sees roster size 1). If PRESENCE then reports a remote
      // live lease during the join-guard window, that solo grant was
      // premature — yield so we do not double-hold.
      if (remoteHolder != localPeerId && _inJoinGuardWindow) {
        _cancelTot();
        _phase = _Phase.idle;
        if (_holder == localPeerId) {
          _clearLease(announce: false);
        }
        _send(TxEnd(peer: localPeerId));
        _emit(const DispatchRadio(EndTransmit()));
        _installLease(remoteHolder, remaining, announce: false);
        _phase = _Phase.rx;
        _emit(const DispatchRadio(RemoteFloorStarted()));
      }
      return;
    }

    final live = _liveHolder;
    if (live == null) {
      _installLease(remoteHolder, remaining, announce: false);
      if (remoteHolder != localPeerId && _phase != _Phase.rx) {
        _phase = _Phase.rx;
        _emit(const DispatchRadio(RemoteFloorStarted()));
      }
      return;
    }
    if (live == remoteHolder) {
      // Do not extend a live lease from a snapshot — a stale
      // `lease_remaining_ms` would keep a crashed speaker's grant alive.
      return;
    }
    // Conflicting holder while we already have one: TX_GRANT / TX_START
    // are authoritative; ignore the snapshot.
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
