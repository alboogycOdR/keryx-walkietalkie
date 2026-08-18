import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/services/discovery/discovery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = DiscoveryConfig(
    peerId: 'ABCDEF23GH',
    callsign: 'BRAVO-7',
    channelHashPrefix: 'aabbccdd',
    signalingPort: 41234,
  );

  late FakeNsdPlatform nsd;
  late FakeBeaconTransport beacon;
  late FakeDiscoveryScheduler clock;
  late NsdDiscoveryService svc;

  setUp(() {
    nsd = FakeNsdPlatform();
    beacon = FakeBeaconTransport();
    clock = FakeDiscoveryScheduler();
    svc = NsdDiscoveryService(
      platform: nsd,
      beaconTransport: beacon,
      scheduler: clock,
    );
  });

  tearDown(() async {
    await svc.dispose();
    await nsd.dispose();
  });

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  Future<void> startHealthy() async {
    await svc.start(config);
    nsd.emit(const NsdLockChanged(held: true));
    nsd.emit(const NsdRegistered(serviceName: 'ABCDEF23GH', port: 41234));
    nsd.emit(const NsdBrowseStarted());
    await flush();
  }

  test('start invokes platform with privacy fields only', () async {
    await svc.start(config);
    expect(nsd.startedArgs, hasLength(1));
    final args = nsd.startedArgs.single;
    expect(args['peerId'], config.peerId);
    expect(args['callsign'], config.callsign);
    expect(args['channelHashPrefix'], config.channelHashPrefix);
    expect(args['protocolVersion'], 1);
    expect(args['signalingPort'], 41234);
    expect(args['serviceType'], DiscoveryConstants.serviceType);
    expect(args.containsKey('channel'), isFalse);
    expect(args.containsKey('code'), isFalse);
    expect(args.containsKey('region'), isFalse);
    expect(svc.state.radioOn, isTrue);
  });

  test('MulticastLock follows start/stop (radio on / power-off)', () async {
    await startHealthy();
    expect(svc.state.multicastLockHeld, isTrue);
    expect(svc.state.nsdActive, isTrue);

    await svc.stop();
    expect(nsd.stopCount, 1);
    expect(svc.state.multicastLockHeld, isFalse);
    expect(svc.state.radioOn, isFalse);
    expect(svc.state.nsdActive, isFalse);
  });

  test('found/lost sequencing; other-channel and self are ignored', () async {
    final found = <DiscoveredPeer>[];
    final lost = <DiscoveredPeer>[];
    svc.peersFound.listen(found.add);
    svc.peersLost.listen(lost.add);

    await startHealthy();

    nsd.emit(
      NsdPeerFound(
        DiscoveredPeer(
          peerId: 'PEER000001',
          callsign: 'SIERRA-19',
          channelHashPrefix: config.channelHashPrefix,
          version: 1,
          host: '10.0.0.8',
          port: 40001,
        ),
      ),
    );
    nsd.emit(
      NsdPeerFound(
        DiscoveredPeer(
          peerId: 'OTHERCHAN1',
          callsign: 'ALPHA-1',
          channelHashPrefix: 'ffffffff',
          version: 1,
          host: '10.0.0.9',
          port: 40002,
        ),
      ),
    );
    nsd.emit(
      NsdPeerFound(
        DiscoveredPeer(
          peerId: config.peerId,
          callsign: config.callsign,
          channelHashPrefix: config.channelHashPrefix,
          version: 1,
          host: '10.0.0.1',
          port: config.signalingPort,
        ),
      ),
    );
    await flush();

    expect(found, hasLength(1));
    expect(found.single.peerId, 'PEER000001');
    expect(found.single.callsign, 'SIERRA-19');
    expect(svc.state.peers, hasLength(1));
    expect(svc.state.heardAnyDiscoveryTraffic, isTrue);
    expect(svc.state.lanTrouble, isFalse);

    nsd.emit(const NsdPeerLost(serviceName: 'PEER000001'));
    await flush();
    expect(lost, hasLength(1));
    expect(lost.single.peerId, 'PEER000001');
    expect(svc.state.peers, isEmpty);
  });

  test('LAN? after both NSD and UDP fail', () async {
    nsd.startError = PlatformException(code: 'nsd_start', message: 'fail');
    await svc.start(config);
    expect(svc.state.nsdFailed, isTrue);
    expect(svc.state.lanTrouble, isFalse);

    await svc.onTuned();
    expect(beacon.sendCount, 1);
    clock.advance(DiscoveryConstants.beaconWindow);
    await flush();

    expect(svc.state.beaconWindowElapsed, isTrue);
    expect(svc.state.lanTrouble, isTrue);
    expect(svc.state.peers, isEmpty);
  });

  test('healthy NSD with zero peers is not LAN?', () async {
    await startHealthy();
    await svc.onTuned();
    clock.advance(DiscoveryConstants.beaconWindow);
    await flush();
    expect(svc.state.nsdActive, isTrue);
    expect(svc.state.peers, isEmpty);
    expect(svc.state.lanTrouble, isFalse);
  });

  test('UDP fallback peer clears LAN? when NSD failed', () async {
    nsd.startError = PlatformException(code: 'nsd_start', message: 'fail');
    await svc.start(config);
    await svc.onTuned();

    beacon.onPeer?.call(
      DiscoveredPeer(
        peerId: 'UDPPEER001',
        callsign: 'DELTA-4',
        channelHashPrefix: config.channelHashPrefix,
        version: 1,
        host: '10.0.0.12',
        port: 40009,
        source: DiscoverySource.udp,
      ),
    );
    await flush();
    clock.advance(DiscoveryConstants.beaconWindow);
    await flush();

    expect(svc.state.heardAnyDiscoveryTraffic, isTrue);
    expect(svc.state.peers.single.peerId, 'UDPPEER001');
    expect(svc.state.lanTrouble, isFalse);
  });

  test('onTuned without start throws; dispose is terminal', () async {
    expect(svc.onTuned, throwsStateError);
    await svc.dispose();
    expect(() => svc.start(config), throwsStateError);
  });

  test('config rejects raw region|ch|code as the prefix', () {
    expect(
      () => DiscoveryConfig(
        peerId: 'X',
        callsign: 'YY',
        channelHashPrefix: 'ZA|07|12',
        signalingPort: 1,
      ).validate(),
      throwsArgumentError,
    );
  });

  test('ChannelNsdPlatform start/stop hit the method channel', () async {
    const methods = MethodChannel(DiscoveryConstants.methodChannel);
    const events = EventChannel(DiscoveryConstants.eventChannel);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, (call) async {
          calls.add(call);
          return null;
        });

    final platform = ChannelNsdPlatform(methods: methods, events: events);
    await platform.start(config);
    await platform.stop();
    expect(calls.map((c) => c.method), ['start', 'stop']);
    final args = calls.first.arguments as Map;
    expect(args['channelHashPrefix'], config.channelHashPrefix);
    expect(args.containsKey('code'), isFalse);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, null);
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
  }
}
