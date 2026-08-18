import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/core/protocol/protocol.dart';
import 'package:keryx/core/state/radio_state.dart';

/// Stable peerIds (RFC 4648 alphabet A–Z2–7; no 0/1/8/9).
const aId = 'AAA2222222';
const bId = 'BBB2222222';
const cId = 'CCC2222222';

void main() {
  late FloorRig rig;

  setUp(() {
    rig = FloorRig();
  });

  tearDown(() {
    rig.dispose();
  });

  test('lowest peerId is arbiter; re-elected on churn', () {
    final a = rig.spawn(aId);
    final b = rig.spawn(bId);
    final c = rig.spawn(cId);
    rig.roster([a, b, c]);

    expect(a.arbiterId, aId);
    expect(a.isLocalArbiter, isTrue);
    expect(b.isLocalArbiter, isFalse);
    expect(a.tape.whereType<ArbiterChanged>().last.peerId, aId);
    expect(b.tape.whereType<ArbiterChanged>().last.peerId, aId);
    expect(c.tape.whereType<ArbiterChanged>().last.peerId, aId);

    rig.hub.detach(aId);
    a.dispose();
    b.updateRoster({bId, cId});
    c.updateRoster({bId, cId});
    expect(b.arbiterId, bId);
    expect(b.isLocalArbiter, isTrue);
    expect(c.isLocalArbiter, isFalse);
  });

  test('solo peer self-grants and drives reducer idle → txRequest → tx → idle', () {
    final a = rig.spawn(aId);
    final reducer = const RadioReducer();
    var state = const RadioState(phase: RadioPhase.idle);
    a.effects.listen((effect) {
      if (effect is DispatchRadio) {
        state = reducer.reduce(state, effect.event);
      }
    });

    a.requestTransmit();
    expect(state.phase, RadioPhase.tx);
    expect(a.isTransmitting, isTrue);
    expect(a.holder, aId);
    expect(rig.sent.whereType<TxGrant>(), hasLength(1));
    expect(rig.sent.whereType<TxStart>().single.peer, aId);
    expect(a.tape.whereType<GrantTone>(), hasLength(1));

    a.releaseTransmit();
    expect(state.phase, RadioPhase.idle);
    expect(a.isTransmitting, isFalse);
    expect(a.holder, isNull);
    expect(rig.sent.whereType<TxEnd>().single.peer, aId);
  });

  test('arbiter grants a remote requester; remote TX_START drives RX', () {
    final a = rig.spawn(aId);
    final b = rig.spawn(bId);
    rig.roster([a, b]);

    b.requestTransmit();

    expect(b.isTransmitting, isTrue);
    expect(a.holder, bId);
    expect(b.holder, bId);
    expect(
      a.tape.whereType<DispatchRadio>().map((e) => e.event.runtimeType),
      [RemoteFloorStarted],
    );
    expect(
      b.tape.whereType<DispatchRadio>().map((e) => e.event.runtimeType),
      [RequestTransmit, TransmitGranted],
    );

    b.releaseTransmit();
    expect(a.holder, isNull);
    expect(
      a.tape.whereType<DispatchRadio>().last.event,
      isA<RemoteFloorEnded>(),
    );
  });

  test('idempotent re-grant of the same holder does not disrupt TX', () {
    final a = rig.spawn(aId);
    final b = rig.spawn(bId);
    rig.roster([a, b]);
    b.requestTransmit();
    final tonesBefore = b.tape.whereType<GrantTone>().length;
    final grantsBefore = rig.sent.whereType<TxGrant>().length;

    b.requestTransmit(); // already TX — local no-op
    expect(b.isTransmitting, isTrue);
    expect(b.tape.whereType<GrantTone>(), hasLength(tonesBefore));
    expect(rig.sent.whereType<TxGrant>(), hasLength(grantsBefore));

    // A retry of TX_REQ from the live holder is re-granted, remaining lease.
    rig.clock.elapse(const Duration(seconds: 1));
    rig.hub.inject(
      aId,
      TxReq(peer: bId, prio: FloorPrio.normal, ts: 0),
    );
    expect(b.isTransmitting, isTrue);
    expect(b.tape.whereType<GrantTone>(), hasLength(tonesBefore));
    expect(rig.sent.whereType<TxGrant>().length, grantsBefore + 1);
    expect(
      rig.sent.whereType<TxGrant>().last.leaseMs,
      FloorTiming.defaultGrantLease.inMilliseconds - 1000,
    );
  });

  test('busy deny when floor is held (lockout off still cannot barge)', () {
    final a = rig.spawn(aId);
    final b = rig.spawn(bId, lockout: false);
    final c = rig.spawn(cId, lockout: false);
    rig.roster([a, b, c]);

    b.requestTransmit();
    c.requestTransmit();

    expect(b.isTransmitting, isTrue);
    expect(c.isTransmitting, isFalse);
    expect(c.tape.whereType<DenyBuzz>().single.reason, FloorDenyReason.busy);
    expect(
      c.tape.whereType<DispatchRadio>().map((e) => e.event.runtimeType),
      [RemoteFloorStarted, RequestTransmit, TransmitDenied],
    );
    expect(
      rig.sent.whereType<TxDeny>().single.reason,
      FloorDenyReason.busy,
    );
  });

  test('busy lockout (default on) denies locally without TX_REQ', () {
    final a = rig.spawn(aId);
    final b = rig.spawn(bId);
    final c = rig.spawn(cId); // lockout default on
    rig.roster([a, b, c]);

    b.requestTransmit();
    final reqsBefore = rig.sent.whereType<TxReq>().length;
    c.requestTransmit();

    expect(c.tape.whereType<DenyBuzz>().single.reason, FloorDenyReason.lockout);
    expect(rig.sent.whereType<TxReq>(), hasLength(reqsBefore));
    expect(
      c.tape.whereType<DispatchRadio>().map((e) => e.event.runtimeType),
      [RemoteFloorStarted, RequestTransmit, TransmitDenied],
    );
  });

  test('TOT warns at T-5 s and hard-cuts at 0, releasing the floor', () {
    final a = rig.spawn(aId, tot: FloorEngine.minTot);
    a.requestTransmit();
    expect(a.isTransmitting, isTrue);

    rig.clock.elapse(const Duration(seconds: 24));
    expect(a.tape.whereType<TotWarn>(), isEmpty);

    rig.clock.elapse(const Duration(seconds: 1));
    expect(a.tape.whereType<TotWarn>(), hasLength(1));
    expect(a.isTransmitting, isTrue);

    rig.clock.elapse(const Duration(seconds: 5));
    expect(a.tape.whereType<TotCut>(), hasLength(1));
    expect(a.isTransmitting, isFalse);
    expect(a.holder, isNull);
    expect(
      a.tape.whereType<DispatchRadio>().last.event,
      isA<EndTransmit>(),
    );
    expect(rig.sent.whereType<TxEnd>(), isNotEmpty);
  });

  test('lease expiry frees a crashed speaker without TX_END from them', () {
    final tot = FloorEngine.minTot;
    final a = rig.spawn(aId, tot: tot);
    final b = rig.spawn(bId, tot: tot);
    final c = rig.spawn(cId, tot: tot);
    rig.roster([a, b, c]);

    b.requestTransmit();
    expect(a.holder, bId);

    // Crash B: detach without TX_END. Dispose so its TOT cut cannot fire.
    rig.hub.detach(bId);
    b.dispose();

    rig.clock.elapse(FloorTiming.grantLease(tot) - const Duration(milliseconds: 1));
    expect(a.holder, bId);

    rig.clock.elapse(const Duration(milliseconds: 1));
    expect(a.holder, isNull);
    expect(
      a.tape.whereType<DispatchRadio>().last.event,
      isA<RemoteFloorEnded>(),
    );

    c.requestTransmit();
    expect(c.isTransmitting, isTrue);
  });

  test('emergency TX_REQ(prio=1) pre-empts a live lease and pins EMG', () {
    final a = rig.spawn(aId);
    final b = rig.spawn(bId);
    final c = rig.spawn(cId);
    rig.roster([a, b, c]);

    b.requestTransmit();
    expect(b.isTransmitting, isTrue);

    c.requestTransmit(emergency: true);

    expect(c.isTransmitting, isTrue);
    expect(b.isTransmitting, isFalse);
    expect(a.holder, cId);
    expect(c.isEmergencyPinned, isTrue);
    expect(c.emergencyPeer, cId);
    expect(a.emergencyPeer, cId);
    expect(b.emergencyPeer, cId);
    expect(rig.sent.whereType<Emg>().single.peer, cId);
    expect(
      rig.sent.whereType<TxReq>().where((m) => m.prio == FloorPrio.emergency),
      isNotEmpty,
    );
    expect(
      b.tape.whereType<DispatchRadio>().map((e) => e.event.runtimeType),
      [RequestTransmit, TransmitGranted, EndTransmit, RemoteFloorStarted],
    );

    c.clearEmergency();
    expect(c.isEmergencyPinned, isFalse);
    expect(a.isEmergencyPinned, isFalse);
    expect(rig.sent.whereType<EmgClr>().single.peer, cId);
  });

  test('emergency overrides busy lockout', () {
    final a = rig.spawn(aId);
    final b = rig.spawn(bId);
    final c = rig.spawn(cId); // lockout on
    rig.roster([a, b, c]);

    b.requestTransmit();
    c.requestTransmit(emergency: true);

    expect(c.isTransmitting, isTrue);
    expect(c.tape.whereType<DenyBuzz>(), isEmpty);
    expect(c.isEmergencyPinned, isTrue);
  });

  test('TX_REQ retries 150 ms × 3 then give-up deny', () {
    final a = rig.spawn(aId);
    final b = rig.spawn(bId);
    rig.roster([a, b]);

    // Partition: drop everything so A never sees B's request.
    rig.hub.drop = (from, to, msg) => true;

    b.requestTransmit();
    expect(rig.sent.whereType<TxReq>(), hasLength(1));

    rig.clock.elapse(FloorTiming.txReqRetry);
    expect(rig.sent.whereType<TxReq>(), hasLength(2));

    rig.clock.elapse(FloorTiming.txReqRetry);
    expect(rig.sent.whereType<TxReq>(), hasLength(3));
    expect(b.tape.whereType<DenyBuzz>(), isEmpty);

    rig.clock.elapse(FloorTiming.txReqRetry);
    expect(rig.sent.whereType<TxReq>(), hasLength(3));
    expect(b.tape.whereType<DenyBuzz>().single.reason, isNull);
    expect(
      b.tape.whereType<DispatchRadio>().last.event,
      isA<TransmitDenied>(),
    );
    expect(b.isTransmitting, isFalse);
  });

  test('arbiter loss self-heals: new arbiter grants within 500 ms', () {
    final a = rig.spawn(aId);
    final b = rig.spawn(bId);
    final c = rig.spawn(cId);
    rig.roster([a, b, c]);

    // Drop A's inbound so the first TX_REQ is unanswered.
    rig.hub.drop = (from, to, msg) => to == aId || from == aId;

    c.requestTransmit();
    expect(c.isTransmitting, isFalse);
    expect(rig.sent.whereType<TxReq>(), hasLength(1));

    // A departs. B is the new arbiter (BBB < CCC).
    rig.hub.drop = null;
    rig.hub.detach(aId);
    a.dispose();
    b.updateRoster({bId, cId});
    c.updateRoster({bId, cId});
    expect(b.isLocalArbiter, isTrue);

    rig.clock.elapse(FloorTiming.arbiterReelectionSettle);
    expect(c.isTransmitting, isTrue);
    expect(b.holder, cId);
    expect(
      rig.clock.now().difference(DateTime.utc(2026, 1, 1)) <=
          FloorTiming.arbiterReelectionSettle,
      isTrue,
    );
  });

  test('grant lease equals configured TOT + 2 s', () {
    const tot = Duration(seconds: 45);
    final a = rig.spawn(aId, tot: tot);
    final b = rig.spawn(bId, tot: tot);
    rig.roster([a, b]);
    b.requestTransmit();

    final grant = rig.sent.whereType<TxGrant>().single;
    expect(grant.leaseMs, FloorTiming.grantLease(tot).inMilliseconds);
    expect(grant.leaseMs, 47000);
  });

  test('floor-idle debounce emits after 750 ms of free floor', () {
    final a = rig.spawn(aId);
    a.requestTransmit();
    a.releaseTransmit();
    expect(a.tape.whereType<FloorIdleSettled>(), isEmpty);

    rig.clock.elapse(FloorTiming.floorIdleDebounce - const Duration(milliseconds: 1));
    expect(a.tape.whereType<FloorIdleSettled>(), isEmpty);

    rig.clock.elapse(const Duration(milliseconds: 1));
    expect(a.tape.whereType<FloorIdleSettled>(), hasLength(1));
  });

  test('tot outside 30–120 s is rejected; dispose is idempotent', () {
    final sink = _NullTransport();
    expect(
      () => FloorEngine(
        localPeerId: aId,
        transport: sink,
        clock: rig.clock,
        tot: const Duration(seconds: 29),
      ),
      throwsArgumentError,
    );
    expect(
      () => FloorEngine(
        localPeerId: aId,
        transport: sink,
        clock: rig.clock,
        tot: const Duration(seconds: 121),
      ),
      throwsArgumentError,
    );
    expect(
      () => FloorEngine(
        localPeerId: '',
        transport: sink,
        clock: rig.clock,
      ),
      throwsArgumentError,
    );

    final a = rig.spawn(aId);
    a.dispose();
    a.dispose();
    expect(() => a.requestTransmit(), throwsStateError);
  });

  test('timing constants used by the engine match the locked §8.6 table', () {
    expect(FloorTiming.txReqRetry, const Duration(milliseconds: 150));
    expect(FloorTiming.txReqAttempts, 3);
    expect(FloorTiming.arbiterReelectionSettle, const Duration(milliseconds: 500));
    expect(FloorTiming.grantLeasePadding, const Duration(seconds: 2));
    expect(FloorTiming.defaultTot, const Duration(seconds: 60));
    expect(FloorTiming.defaultGrantLease, const Duration(seconds: 62));
    expect(FloorTiming.floorIdleDebounce, const Duration(milliseconds: 750));
    expect(FloorEngine.minTot, const Duration(seconds: 30));
    expect(FloorEngine.maxTot, const Duration(seconds: 120));
    expect(FloorEngine.totWarnLead, const Duration(seconds: 5));
  });

  test('VirtualClock fires equal-deadline timers in schedule order', () {
    final clock = VirtualClock();
    final order = <int>[];
    clock.schedule(const Duration(milliseconds: 10), () => order.add(1));
    clock.schedule(const Duration(milliseconds: 10), () => order.add(2));
    clock.elapse(const Duration(milliseconds: 10));
    expect(order, [1, 2]);
  });
}

/// Shared loopback + clock + effect tapes for multi-peer tests.
class FloorRig {
  FloorRig() : clock = VirtualClock(DateTime.utc(2026, 1, 1));

  final VirtualClock clock;
  final LoopbackHub hub = LoopbackHub();
  final List<FloorEngine> engines = <FloorEngine>[];
  final List<FloorMessage> sent = <FloorMessage>[];

  FloorEngine spawn(
    String id, {
    bool lockout = true,
    Duration tot = FloorTiming.defaultTot,
  }) {
    final endpoint = _RecordingEndpoint(hub.attach(id), sent);
    final engine = FloorEngine(
      localPeerId: id,
      transport: endpoint,
      clock: clock,
      busyLockout: lockout,
      tot: tot,
    );
    engine.tape = <FloorEffect>[];
    engine.effects.listen(engine.tape.add);
    engines.add(engine);
    return engine;
  }

  void roster(List<FloorEngine> live) {
    final ids = live.map((e) => e.localPeerId).toSet();
    for (final engine in live) {
      engine.updateRoster(ids);
    }
  }

  void dispose() {
    for (final engine in engines) {
      engine.dispose();
    }
    for (final id in List<String>.of(hub.attached)) {
      hub.detach(id);
    }
  }
}

class _NullTransport implements FloorTransport {
  @override
  Stream<FloorMessage> get incoming => const Stream.empty();

  @override
  void send(FloorMessage message) {}
}

class _RecordingEndpoint implements FloorTransport {
  _RecordingEndpoint(this._inner, this._log);

  final LoopbackEndpoint _inner;
  final List<FloorMessage> _log;

  @override
  Stream<FloorMessage> get incoming => _inner.incoming;

  @override
  void send(FloorMessage message) {
    _log.add(message);
    _inner.send(message);
  }
}

extension on FloorEngine {
  static final _tapes = Expando<List<FloorEffect>>();

  List<FloorEffect> get tape => _tapes[this]!;
  set tape(List<FloorEffect> value) => _tapes[this] = value;
}
