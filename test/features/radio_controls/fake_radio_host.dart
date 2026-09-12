import 'dart:async';

import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';

/// Hand-written [RadioHost] double for `lib/features/radio_controls/**`
/// widget tests — same shape/reasoning as
/// `test/features/talk/fake_radio_host.dart` (this feature keeps its own
/// local copy per repo convention rather than sharing one file).
class FakeRadioHost implements RadioHost {
  RadioHostSnapshot _snapshot = const RadioHostSnapshot();
  final _changes = StreamController<RadioHostSnapshot>.broadcast();

  int startCalls = 0;
  int powerOffCalls = 0;
  int disposeCalls = 0;
  final List<(int, int)> tuneCalls = <(int, int)>[];
  int pressPttCalls = 0;
  int releasePttCalls = 0;
  int releaseLatchCalls = 0;
  final List<KeryxSettings> applySettingsCalls = <KeryxSettings>[];
  final List<Object> joinEventCalls = <Object>[];

  @override
  RadioHostSnapshot get current => _snapshot;

  @override
  Stream<RadioHostSnapshot> get changes => _changes.stream;

  /// Test-only mutator — pushes a new snapshot exactly like a real host
  /// would after e.g. a floor engine replacement.
  void emit(RadioHostSnapshot snapshot) {
    _snapshot = snapshot;
    _changes.add(snapshot);
  }

  @override
  Future<void> start() async => startCalls++;

  @override
  Future<void> powerOff() async => powerOffCalls++;

  @override
  Future<TuneResult> tune(int channel, int code) async {
    tuneCalls.add((channel, code));
    return const TuneResult.success();
  }

  @override
  Future<void> applySettings(KeryxSettings settings) async {
    applySettingsCalls.add(settings);
  }


  @override
  void pressPtt() => pressPttCalls++;

  @override
  void releasePtt() => releasePttCalls++;

  @override
  void releaseLatch() => releaseLatchCalls++;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _changes.close();
  }
}
