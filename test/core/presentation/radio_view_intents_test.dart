import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/presentation/presentation.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';

/// Records every call it receives instead of doing anything — proves
/// [RadioViewIntents] forwards exactly once, with exactly the given
/// arguments, and never synthesizes a result of its own (Technical §5.1).
class _RecordingRadioHost implements RadioHost {
  final calls = <String>[];

  @override
  RadioHostSnapshot get current => const RadioHostSnapshot();

  @override
  Stream<RadioHostSnapshot> get changes => const Stream.empty();

  @override
  Future<void> start() async {
    calls.add('start');
  }

  @override
  Future<void> powerOff() async {
    calls.add('powerOff');
  }

  KeryxSettings? appliedSettings;
  @override
  Future<void> applySettings(KeryxSettings settings) async {
    calls.add('applySettings');
    appliedSettings = settings;
  }


  @override
  void pressPtt() => calls.add('pressPtt');

  @override
  void releasePtt() => calls.add('releasePtt');

  @override
  void releaseLatch() => calls.add('releaseLatch');

  @override
  Future<void> dispose() async {
    calls.add('dispose');
  }
}

void main() {
  late _RecordingRadioHost host;
  late RadioViewIntents intents;

  setUp(() {
    host = _RecordingRadioHost();
    intents = RadioViewIntents(host);
  });

  test('press() forwards to RadioHost.pressPtt exactly once', () {
    intents.press();
    expect(host.calls, ['pressPtt']);
  });

  test('release() forwards to RadioHost.releasePtt exactly once', () {
    intents.release();
    expect(host.calls, ['releasePtt']);
  });

  test('releaseLatch() forwards to RadioHost.releaseLatch exactly once', () {
    intents.releaseLatch();
    expect(host.calls, ['releaseLatch']);
  });

  test('applySettings() forwards the exact settings instance', () async {
    const settings = KeryxSettings(squelchLevel: 8);
    await intents.applySettings(settings);

    expect(host.calls, ['applySettings']);
    expect(host.appliedSettings, same(settings));
  });


  test(
    'RadioViewIntents never calls any RadioHost method other than the '
    'one its own method name maps to',
    () {
      intents.press();
      intents.release();
      intents.releaseLatch();

      expect(host.calls, ['pressPtt', 'releasePtt', 'releaseLatch']);
      expect(host.calls, isNot(contains('start')));
      expect(host.calls, isNot(contains('powerOff')));
      expect(host.calls, isNot(contains('dispose')));
    });
}
