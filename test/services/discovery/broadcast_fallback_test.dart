import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/services/discovery/discovery.dart';

void main() {
  const self = DiscoveryConfig(
    peerId: 'ABCDEF23GH',
    callsign: 'BRAVO-7',
    channelHashPrefix: 'e3c6f2d1',
    signalingPort: 41234,
  );

  test('beacon payload is JSON with spec TXT fields only', () {
    final bytes = UdpBeaconTransport.encodeBeacon(self);
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(map.keys.toSet(), {'v', 't', 'peer', 'cs', 'ch', 'p'});
    expect(map['v'], 1);
    expect(map['t'], 'BEACON');
    expect(map['peer'], self.peerId);
    expect(map['cs'], self.callsign);
    expect(map['ch'], self.channelHashPrefix);
    expect(map['p'], self.signalingPort);
    expect(utf8.decode(bytes), isNot(contains('07')));
    expect(utf8.decode(bytes), isNot(contains('region')));
  });

  test('beacon round-trip and malformed inputs return null', () {
    final bytes = UdpBeaconTransport.encodeBeacon(self);
    final peer = UdpBeaconTransport.decodeBeacon(bytes, host: '10.0.0.4');
    expect(peer, isNotNull);
    expect(peer!.peerId, self.peerId);
    expect(peer.callsign, self.callsign);
    expect(peer.channelHashPrefix, self.channelHashPrefix);
    expect(peer.port, self.signalingPort);
    expect(peer.host, '10.0.0.4');
    expect(peer.source, DiscoverySource.udp);

    expect(UdpBeaconTransport.decodeBeacon(utf8.encode('not-json')), isNull);
    expect(UdpBeaconTransport.decodeBeacon(utf8.encode('[]')), isNull);
    expect(
      UdpBeaconTransport.decodeBeacon(
        utf8.encode('{"v":2,"t":"BEACON","peer":"X","cs":"A","ch":"aa","p":1}'),
      ),
      isNull,
    );
    expect(
      UdpBeaconTransport.decodeBeacon(
        utf8.encode('{"v":1,"t":"NOPE","peer":"X","cs":"A","ch":"aa","p":1}'),
      ),
      isNull,
    );
  });

  test('2 s interval for 30 s after tune — 16 beacons then stop', () async {
    final transport = FakeBeaconTransport();
    final clock = FakeDiscoveryScheduler();
    var elapsed = false;
    final fallback = BroadcastFallback(
      transport: transport,
      scheduler: clock,
      onPeer: (_) {},
      onWindowElapsed: () => elapsed = true,
      onError: (_) {},
    );

    await fallback.start(self);
    expect(transport.sendCount, 1);
    expect(fallback.isActive, isTrue);

    clock.advance(const Duration(seconds: 28));
    expect(transport.sendCount, 15);
    expect(elapsed, isFalse);

    clock.advance(const Duration(seconds: 2));
    expect(elapsed, isTrue);
    expect(fallback.isActive, isFalse);
    expect(transport.sendCount, 16);

    final after = transport.sendCount;
    clock.advance(const Duration(seconds: 10));
    expect(transport.sendCount, after);
  });
}

class FakeBeaconTransport implements BeaconTransport {
  int sendCount = 0;
  bool started = false;
  Object? startError;
  void Function(DiscoveredPeer peer)? onPeer;

  @override
  Future<void> start({
    required DiscoveryConfig self,
    required void Function(DiscoveredPeer peer) onPeer,
    required void Function(Object error) onError,
  }) async {
    if (startError != null) throw startError!;
    started = true;
    this.onPeer = onPeer;
  }

  @override
  void send() {
    if (started) sendCount++;
  }

  @override
  Future<void> stop() async {
    started = false;
    onPeer = null;
  }
}
