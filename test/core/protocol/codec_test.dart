import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/protocol/protocol.dart';

const _peer = 'J7K2M9Q4PX';

/// Frozen wire fixtures. Changing these is a breaking protocol change.
const goldens = <String, String>{
  'TX_REQ':
      '{"v":1,"t":"TX_REQ","peer":"J7K2M9Q4PX","prio":0,"ts":1710000000000}',
  'TX_REQ_EMG':
      '{"v":1,"t":"TX_REQ","peer":"J7K2M9Q4PX","prio":1,"ts":1710000000000}',
  'TX_GRANT': '{"v":1,"t":"TX_GRANT","peer":"J7K2M9Q4PX","lease_ms":62000}',
  'TX_DENY_BUSY': '{"v":1,"t":"TX_DENY","peer":"J7K2M9Q4PX","reason":"BUSY"}',
  'TX_DENY_LOCKOUT':
      '{"v":1,"t":"TX_DENY","peer":"J7K2M9Q4PX","reason":"LOCKOUT"}',
  'TX_START': '{"v":1,"t":"TX_START","peer":"J7K2M9Q4PX"}',
  'TX_END': '{"v":1,"t":"TX_END","peer":"J7K2M9Q4PX"}',
  'PRESENCE':
      '{"v":1,"t":"PRESENCE","peer":"J7K2M9Q4PX","cs":"BRAVO-7","seq":3}',
  'RCHK': '{"v":1,"t":"RCHK","peer":"J7K2M9Q4PX","quality":7}',
  'RCHK_ACK': '{"v":1,"t":"RCHK_ACK","peer":"J7K2M9Q4PX","quality":7}',
  'EMG': '{"v":1,"t":"EMG","peer":"J7K2M9Q4PX"}',
  'EMG_CLR': '{"v":1,"t":"EMG_CLR","peer":"J7K2M9Q4PX"}',
};

final fixtures = <FloorMessage, String>{
  const TxReq(peer: _peer, prio: FloorPrio.normal, ts: 1710000000000):
      goldens['TX_REQ']!,
  const TxReq(peer: _peer, prio: FloorPrio.emergency, ts: 1710000000000):
      goldens['TX_REQ_EMG']!,
  const TxGrant(peer: _peer, leaseMs: 62000): goldens['TX_GRANT']!,
  const TxDeny(peer: _peer, reason: FloorDenyReason.busy):
      goldens['TX_DENY_BUSY']!,
  const TxDeny(peer: _peer, reason: FloorDenyReason.lockout):
      goldens['TX_DENY_LOCKOUT']!,
  const TxStart(peer: _peer): goldens['TX_START']!,
  const TxEnd(peer: _peer): goldens['TX_END']!,
  const Presence(peer: _peer, cs: 'BRAVO-7', seq: 3): goldens['PRESENCE']!,
  const Rchk(peer: _peer, quality: 7): goldens['RCHK']!,
  const RchkAck(peer: _peer, quality: 7): goldens['RCHK_ACK']!,
  const Emg(peer: _peer): goldens['EMG']!,
  const EmgClr(peer: _peer): goldens['EMG_CLR']!,
};

void main() {
  test('all ten §8.6 types exist with the spec field set', () {
    expect(FloorMsgType.all, [
      'TX_REQ',
      'TX_GRANT',
      'TX_DENY',
      'TX_START',
      'TX_END',
      'PRESENCE',
      'RCHK',
      'RCHK_ACK',
      'EMG',
      'EMG_CLR',
    ]);
    expect(FloorMsgType.all, hasLength(10));

    expect(fixtures.keys.map((m) => m.type).toSet(), FloorMsgType.all.toSet());

    final req = fixtures.keys.whereType<TxReq>().first;
    expect(req.peer, _peer);
    expect(req.prio, FloorPrio.normal);
    expect(req.ts, 1710000000000);

    final grant = fixtures.keys.whereType<TxGrant>().single;
    expect(grant.leaseMs, FloorTiming.defaultGrantLease.inMilliseconds);

    final deny = fixtures.keys.whereType<TxDeny>().toList();
    expect(deny.map((d) => d.reason.wire).toSet(), {'BUSY', 'LOCKOUT'});

    final presence = fixtures.keys.whereType<Presence>().single;
    expect(presence.cs, 'BRAVO-7');
    expect(presence.seq, 3);

    final rchk = fixtures.keys.whereType<Rchk>().single;
    expect(rchk.quality, 7);
  });

  test('encode is JSON with v and t on every message', () {
    for (final message in fixtures.keys) {
      final wire = FloorCodec.encode(message);
      final map = jsonDecode(wire) as Map<String, dynamic>;
      expect(map['v'], kFloorProtocolVersion);
      expect(map['t'], message.type);
      expect(map['peer'], message.peer);
    }
  });

  test('golden wire strings are frozen', () {
    fixtures.forEach((message, golden) {
      expect(FloorCodec.encode(message), golden, reason: message.type);
    });
  });

  test('round-trip every message type', () {
    fixtures.forEach((message, golden) {
      expect(FloorCodec.decode(golden), message, reason: message.type);
      expect(
        FloorCodec.decode(FloorCodec.encode(message)),
        message,
        reason: message.type,
      );
    });
  });

  test('TX_REQ prio is 0 normal / 1 emergency', () {
    final normal = FloorCodec.decode(goldens['TX_REQ']!) as TxReq;
    final emergency = FloorCodec.decode(goldens['TX_REQ_EMG']!) as TxReq;
    expect(normal.prio, FloorPrio.normal);
    expect(emergency.prio, FloorPrio.emergency);
    expect(FloorPrio.isValid(0), isTrue);
    expect(FloorPrio.isValid(1), isTrue);
    expect(FloorPrio.isValid(2), isFalse);
    expect(
      FloorCodec.decode(
        '{"v":1,"t":"TX_REQ","peer":"J7K2M9Q4PX","prio":2,"ts":1}',
      ),
      isNull,
    );
    expect(
      () => FloorCodec.encode(const TxReq(peer: _peer, prio: 2, ts: 1)),
      throwsArgumentError,
    );
  });

  test('unknown protocol versions are ignored', () {
    for (final v in [0, 2, 99]) {
      expect(
        FloorCodec.decode('{"v":$v,"t":"TX_START","peer":"J7K2M9Q4PX"}'),
        isNull,
        reason: 'v=$v',
      );
    }
  });

  test('unknown message types are ignored', () {
    expect(
      FloorCodec.decode('{"v":1,"t":"TX_YEET","peer":"J7K2M9Q4PX"}'),
      isNull,
    );
    expect(
      FloorCodec.decode('{"v":1,"t":"PROTOBUF","peer":"J7K2M9Q4PX"}'),
      isNull,
    );
  });

  test('malformed input is ignored and never throws', () {
    const bad = <String>[
      '',
      '   ',
      'not-json',
      '{',
      '[]',
      'null',
      '1',
      '"TX_REQ"',
      '{"t":"TX_START","peer":"J7K2M9Q4PX"}',
      '{"v":1,"peer":"J7K2M9Q4PX"}',
      '{"v":"1","t":"TX_START","peer":"J7K2M9Q4PX"}',
      '{"v":1,"t":"TX_START"}',
      '{"v":1,"t":"TX_START","peer":""}',
      '{"v":1,"t":"TX_START","peer":1}',
      '{"v":1,"t":"TX_REQ","peer":"J7K2M9Q4PX","prio":0}',
      '{"v":1,"t":"TX_REQ","peer":"J7K2M9Q4PX","ts":1}',
      '{"v":1,"t":"TX_GRANT","peer":"J7K2M9Q4PX"}',
      '{"v":1,"t":"TX_GRANT","peer":"J7K2M9Q4PX","lease_ms":-1}',
      '{"v":1,"t":"TX_DENY","peer":"J7K2M9Q4PX","reason":"busy"}',
      '{"v":1,"t":"TX_DENY","peer":"J7K2M9Q4PX","reason":"GONE"}',
      '{"v":1,"t":"TX_DENY","peer":"J7K2M9Q4PX"}',
      '{"v":1,"t":"PRESENCE","peer":"J7K2M9Q4PX","cs":"","seq":1}',
      '{"v":1,"t":"PRESENCE","peer":"J7K2M9Q4PX","seq":1}',
      '{"v":1,"t":"RCHK","peer":"J7K2M9Q4PX"}',
      '{"v":1,"t":"RCHK","peer":"J7K2M9Q4PX","quality":"S7"}',
    ];
    for (final wire in bad) {
      expect(() => FloorCodec.decode(wire), returnsNormally, reason: wire);
      expect(FloorCodec.decode(wire), isNull, reason: wire);
    }
  });

  test('extra unknown fields on a known v1 message are ignored', () {
    expect(
      FloorCodec.decode(
        '{"v":1,"t":"TX_START","peer":"J7K2M9Q4PX","future":true}',
      ),
      const TxStart(peer: _peer),
    );
  });

  test('integer-valued JSON numbers coerce (1.0 → 1)', () {
    expect(
      FloorCodec.decode(
        '{"v":1.0,"t":"TX_REQ","peer":"J7K2M9Q4PX","prio":0.0,"ts":1710000000000}',
      ),
      const TxReq(peer: _peer, prio: 0, ts: 1710000000000),
    );
  });

  test('encode rejects empty peer / empty callsign / negative lease', () {
    expect(
      () => FloorCodec.encode(const TxStart(peer: '')),
      throwsArgumentError,
    );
    expect(
      () => FloorCodec.encode(const Presence(peer: _peer, cs: '', seq: 1)),
      throwsArgumentError,
    );
    expect(
      () => FloorCodec.encode(const TxGrant(peer: _peer, leaseMs: -1)),
      throwsArgumentError,
    );
  });

  test('PRESENCE optional holder/lease_remaining_ms round-trip together', () {
    const occupied = Presence(
      peer: _peer,
      cs: 'BRAVO-7',
      seq: 3,
      holder: 'AAA2222222',
      leaseRemainingMs: 55000,
    );
    final wire = FloorCodec.encode(occupied);
    expect(wire, contains('"holder":"AAA2222222"'));
    expect(wire, contains('"lease_remaining_ms":55000'));
    expect(FloorCodec.decode(wire), occupied);
    expect(FloorCodec.decode(FloorCodec.encode(occupied)), occupied);
  });

  test('old-format PRESENCE (missing holder and lease) still decodes', () {
    const idle = Presence(peer: _peer, cs: 'BRAVO-7', seq: 3);
    expect(FloorCodec.decode(goldens['PRESENCE']!), idle);
    expect(FloorCodec.encode(idle), goldens['PRESENCE']);
    final decoded = FloorCodec.decode(goldens['PRESENCE']!) as Presence;
    expect(decoded.holder, isNull);
    expect(decoded.leaseRemainingMs, isNull);
  });

  test('PRESENCE omits both fields when idle and keeps them paired', () {
    const idle = Presence(peer: _peer, cs: 'BRAVO-7', seq: 1);
    final idleMap = jsonDecode(FloorCodec.encode(idle)) as Map<String, dynamic>;
    expect(idleMap.containsKey('holder'), isFalse);
    expect(idleMap.containsKey('lease_remaining_ms'), isFalse);

    // Partial pair → idle (forward-compatible, does not reject the message).
    final holderOnly =
        FloorCodec.decode(
              '{"v":1,"t":"PRESENCE","peer":"J7K2M9Q4PX","cs":"BRAVO-7","seq":1,'
              '"holder":"AAA2222222"}',
            )
            as Presence;
    expect(holderOnly.holder, isNull);
    expect(holderOnly.leaseRemainingMs, isNull);

    final leaseOnly =
        FloorCodec.decode(
              '{"v":1,"t":"PRESENCE","peer":"J7K2M9Q4PX","cs":"BRAVO-7","seq":1,'
              '"lease_remaining_ms":1000}',
            )
            as Presence;
    expect(leaseOnly.holder, isNull);
    expect(leaseOnly.leaseRemainingMs, isNull);

    final negative =
        FloorCodec.decode(
              '{"v":1,"t":"PRESENCE","peer":"J7K2M9Q4PX","cs":"BRAVO-7","seq":1,'
              '"holder":"AAA2222222","lease_remaining_ms":-1}',
            )
            as Presence;
    expect(negative.holder, isNull);
    expect(negative.leaseRemainingMs, isNull);
  });

  test('encode rejects PRESENCE holder/lease pair mismatches', () {
    expect(
      () => FloorCodec.encode(
        const Presence(
          peer: _peer,
          cs: 'BRAVO-7',
          seq: 1,
          holder: 'AAA2222222',
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => FloorCodec.encode(
        const Presence(
          peer: _peer,
          cs: 'BRAVO-7',
          seq: 1,
          leaseRemainingMs: 1000,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => FloorCodec.encode(
        const Presence(
          peer: _peer,
          cs: 'BRAVO-7',
          seq: 1,
          holder: 'AAA2222222',
          leaseRemainingMs: -1,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('protocol library is transport-agnostic and Flutter-free', () {
    final root = Directory.current;
    final files = Directory(
      'lib/core/protocol',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.dart'));
    expect(files, isNotEmpty);
    final forbidden = RegExp(
      r'''package:(flutter|flutter_webrtc|livekit_client)/''',
    );
    for (final file in files) {
      final src = file.readAsStringSync();
      expect(forbidden.hasMatch(src), isFalse, reason: file.path);
    }
    // Keep the check rooted so a cwd surprise fails loudly.
    expect(root.existsSync(), isTrue);
  });
}
