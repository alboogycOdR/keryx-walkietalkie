import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/services/platform/platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRadioServicePlatform platform;
  late ChannelRadioServiceController controller;

  setUp(() {
    platform = FakeRadioServicePlatform();
    controller = ChannelRadioServiceController(platform: platform);
  });

  tearDown(() async {
    await controller.dispose();
    await platform.dispose();
  });

  test('start requires a non-empty channel label', () async {
    await expectLater(
      controller.start(channelLabel: '  '),
      throwsA(isA<ArgumentError>()),
    );
    expect(platform.calls, isEmpty);
  });

  test('start/stop hit the platform and expose PTT availability', () async {
    platform.pttActionEnabled = true;
    final info = await controller.start(channelLabel: 'CH 01', subtitle: 'BRAVO-7');
    expect(info.pttActionEnabled, isTrue);
    expect(controller.pttActionEnabled, isTrue);
    expect(controller.isRunning, isTrue);
    expect(platform.running, isTrue);
    expect(platform.channelLabel, 'CH 01');
    expect(platform.subtitle, 'BRAVO-7');
    expect(platform.wakeLockHeld, isFalse);
    expect(platform.audioFocusHeld, isFalse);

    await controller.stop();
    expect(controller.isRunning, isFalse);
    expect(platform.running, isFalse);
    expect(platform.userPowerOff, isTrue);
    expect(platform.calls, [
      RadioServiceConstants.methodStart,
      RadioServiceConstants.methodStop,
    ]);
  });

  test('setPhase before start throws; idle/rx/tx map wake lock and focus', () async {
    await expectLater(
      controller.setPhase(RadioTransportPhase.rx),
      throwsA(isA<StateError>()),
    );

    await controller.start(channelLabel: 'CH 07');

    await controller.setPhase(RadioTransportPhase.rx);
    expect(platform.phase, RadioTransportPhase.rx);
    expect(platform.wakeLockHeld, isTrue);
    expect(platform.audioFocusHeld, isTrue);

    await controller.setPhase(RadioTransportPhase.tx);
    expect(platform.wakeLockHeld, isTrue);
    expect(platform.audioFocusHeld, isTrue, reason: 'TX keeps an already-held RX duck');

    await controller.setPhase(RadioTransportPhase.idle);
    expect(platform.wakeLockHeld, isFalse);
    expect(platform.audioFocusHeld, isFalse);

    await controller.setPhase(RadioTransportPhase.tx);
    expect(platform.wakeLockHeld, isTrue);
    expect(platform.audioFocusHeld, isFalse, reason: 'TX does not request its own focus');

    await controller.stop();
    expect(platform.wakeLockHeld, isFalse);
    expect(platform.audioFocusHeld, isFalse);
    expect(platform.calls, [
      RadioServiceConstants.methodStart,
      '${RadioServiceConstants.methodSetPhase}:rx',
      '${RadioServiceConstants.methodSetPhase}:tx',
      '${RadioServiceConstants.methodSetPhase}:idle',
      '${RadioServiceConstants.methodSetPhase}:tx',
      RadioServiceConstants.methodStop,
    ]);
  });

  test('start does not schedule periodic work', () async {
    await controller.start(channelLabel: 'CH 01');
    final before = List<String>.from(platform.calls);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(platform.calls, before);
    expect(platform.wakeLockHeld, isFalse);
    expect(platform.audioFocusHeld, isFalse);
  });

  test('OEM kill without user stop emits serviceKilled', () async {
    await controller.start(channelLabel: 'CH 01');
    final killed = expectLater(
      controller.events,
      emitsThrough(isA<RadioServiceKilled>()),
    );
    platform.simulateOemKill();
    await killed;
    expect(controller.isRunning, isFalse);
    expect(platform.userPowerOff, isFalse);
  });

  test('start after a dirty kill flag emits serviceKilled', () async {
    platform.killedDirty = true;
    final killed = expectLater(
      controller.events,
      emitsThrough(isA<RadioServiceKilled>()),
    );
    await controller.start(channelLabel: 'CH 12');
    await killed;
  });

  test('user stop does not emit serviceKilled', () async {
    final seen = <RadioServiceEvent>[];
    final sub = controller.events.listen(seen.add);
    await controller.start(channelLabel: 'CH 01');
    await controller.stop();
    await Future<void>.delayed(Duration.zero);
    expect(seen.whereType<RadioServiceKilled>(), isEmpty);
    await sub.cancel();
  });

  test('notification PTT and power-off actions surface as events', () async {
    await controller.start(channelLabel: 'CH 01');
    final ptt = expectLater(
      controller.events,
      emitsThrough(isA<RadioServicePttAction>()),
    );
    platform.simulatePttAction();
    await ptt;

    final powerOff = expectLater(
      controller.events,
      emitsThrough(isA<RadioServicePowerOffAction>()),
    );
    platform.simulatePowerOffAction();
    await powerOff;
    expect(controller.isRunning, isFalse);
    expect(platform.audioFocusHeld, isFalse);
  });

  test('updateNotification rewrites the channel label', () async {
    await controller.start(channelLabel: 'CH 01');
    await controller.updateNotification(
      channelLabel: 'CH 99',
      subtitle: 'Monitor',
    );
    expect(platform.channelLabel, 'CH 99');
    expect(platform.subtitle, 'Monitor');
    await expectLater(
      controller.updateNotification(channelLabel: ''),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('dispose is terminal; stop is idempotent before start', () async {
    await controller.stop();
    expect(platform.calls, isEmpty);
    await controller.start(channelLabel: 'CH 01');
    await controller.dispose();
    await expectLater(
      controller.start(channelLabel: 'CH 02'),
      throwsA(isA<StateError>()),
    );
  });

  test('start failure is logged and leaves the controller stopped', () async {
    platform.startError = StateError('native refused');
    await expectLater(
      controller.start(channelLabel: 'CH 01'),
      throwsA(isA<StateError>()),
    );
    expect(controller.isRunning, isFalse);
  });

  test('radioServiceEventFromMap covers kill/ptt/power-off/error/unknown', () {
    expect(
      radioServiceEventFromMap({'type': 'serviceKilled'}),
      isA<RadioServiceKilled>(),
    );
    expect(
      radioServiceEventFromMap({'type': 'pttAction'}),
      isA<RadioServicePttAction>(),
    );
    expect(
      radioServiceEventFromMap({'type': 'powerOffAction'}),
      isA<RadioServicePowerOffAction>(),
    );
    expect(
      radioServiceEventFromMap({'type': 'error', 'message': 'boom'}),
      isA<RadioServiceFailed>(),
    );
    expect(radioServiceEventFromMap({'type': 'nope'}), isNull);
  });

  test('RadioTransportPhase wire names are idle|rx|tx', () {
    expect(RadioTransportPhase.idle.wireName, RadioServiceConstants.phaseIdle);
    expect(RadioTransportPhase.rx.wireName, RadioServiceConstants.phaseRx);
    expect(RadioTransportPhase.tx.wireName, RadioServiceConstants.phaseTx);
    expect(RadioTransportPhase.fromWire('rx'), RadioTransportPhase.rx);
    expect(() => RadioTransportPhase.fromWire('RX_ACTIVE'), throwsArgumentError);
  });

  test('ChannelRadioServicePlatform start/stop/setPhase hit the method channel', () async {
    const methods = MethodChannel(RadioServiceConstants.methodChannel);
    const events = EventChannel(RadioServiceConstants.eventChannel);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, (call) async {
          calls.add(call);
          if (call.method == RadioServiceConstants.methodStart) {
            return {RadioServiceConstants.resultPttActionEnabled: false};
          }
          return null;
        });

    final channel = ChannelRadioServicePlatform(methods: methods, events: events);
    final info = await channel.start(channelLabel: 'CH 03', subtitle: 'MON');
    expect(info.pttActionEnabled, isFalse);
    await channel.setPhase(RadioTransportPhase.rx);
    await channel.updateNotification(channelLabel: 'CH 04');
    await channel.stop();

    expect(calls.map((c) => c.method), [
      RadioServiceConstants.methodStart,
      RadioServiceConstants.methodSetPhase,
      RadioServiceConstants.methodUpdateNotification,
      RadioServiceConstants.methodStop,
    ]);
    final startArgs = calls.first.arguments as Map;
    expect(startArgs[RadioServiceConstants.argChannelLabel], 'CH 03');
    expect(startArgs[RadioServiceConstants.argSubtitle], 'MON');
    final phaseArgs = calls[1].arguments as Map;
    expect(phaseArgs[RadioServiceConstants.argPhase], 'rx');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, null);
  });

  test('ChannelRadioServicePlatform parses event-channel maps', () async {
    const methods = MethodChannel(RadioServiceConstants.methodChannel);
    const events = EventChannel(RadioServiceConstants.eventChannel);
    late MockStreamHandlerEventSink sink;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          events,
          MockStreamHandler.inline(
            onListen: (Object? args, MockStreamHandlerEventSink eventSink) {
              sink = eventSink;
            },
          ),
        );

    final channel = ChannelRadioServicePlatform(methods: methods, events: events);
    final received = expectLater(
      channel.events,
      emitsInOrder([
        isA<RadioServiceKilled>(),
        isA<RadioServiceFailed>(),
      ]),
    );
    sink.success({RadioServiceConstants.eventTypeKey: RadioServiceConstants.eventServiceKilled});
    sink.success('not-a-map');
    await received;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(events, null);
  });
}
