import 'dart:async';

import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/features/event_qr/event_link.dart';

/// Hand-written [RadioHost] double for `lib/features/event_qr_ui/**`
/// tests — same shape/reasoning as `test/features/radio_controls
/// /fake_radio_host.dart` (this feature keeps its own local copy per
/// repo convention rather than sharing one file).
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
  final List<EventLinkPayload> joinEventCalls = <EventLinkPayload>[];

  /// Canned result for the next [joinEvent] call(s). Defaults to success.
  JoinResult joinEventResult = const JoinResult.success();

  /// When non-null, [applySettings] throws this instead of recording a
  /// call — simulates a route-transition failure (VT-023 coverage).
  Object? applySettingsError;

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
    final error = applySettingsError;
    if (error != null) throw error;
    applySettingsCalls.add(settings);
  }

  @override
  Future<JoinResult> joinEvent(EventLinkPayload payload) async {
    joinEventCalls.add(payload);
    return joinEventResult;
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
