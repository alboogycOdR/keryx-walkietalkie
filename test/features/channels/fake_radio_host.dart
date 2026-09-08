import 'dart:async';

import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/features/event_qr/event_link.dart';

/// Hand-written [RadioHost] double for Channels landing tests —
/// Verification §2: no real sockets or native plugins. Records every
/// call so tests can assert the landing dispatches tune intents and
/// never starts a 99-channel presence sweep (Design §2.1).
class FakeRadioHost implements RadioHost {
  RadioHostSnapshot _snapshot = const RadioHostSnapshot();
  final StreamController<RadioHostSnapshot> _changes =
      StreamController<RadioHostSnapshot>.broadcast();

  final List<String> methodLog = <String>[];
  int startCalls = 0;
  int powerOffCalls = 0;
  int disposeCalls = 0;
  final List<(int, int)> tuneCalls = <(int, int)>[];
  int pressPttCalls = 0;
  int releasePttCalls = 0;
  int releaseLatchCalls = 0;
  final List<KeryxSettings> applySettingsCalls = <KeryxSettings>[];
  final List<EventLinkPayload> joinEventCalls = <EventLinkPayload>[];

  /// Result [tune] resolves with when [holdTunes] is false. Defaults to
  /// success. TASK-067: lets tests drive the recall-tap's failure/retry
  /// path through [TuneCoordinator] without any real transport.
  TuneResult autoResult = const TuneResult.success();

  /// While true, [tune] returns a [Completer]-backed future instead of
  /// resolving immediately — appended to [pendingTunes] in submission
  /// order so a test can complete them on demand (same convention as
  /// `test/features/channel_selector/fake_radio_host.dart`).
  bool holdTunes = false;
  final List<Completer<TuneResult>> pendingTunes = <Completer<TuneResult>>[];

  @override
  RadioHostSnapshot get current => _snapshot;

  @override
  Stream<RadioHostSnapshot> get changes => _changes.stream;

  void emit(RadioHostSnapshot snapshot) {
    _snapshot = snapshot;
    _changes.add(snapshot);
  }

  @override
  Future<void> start() async {
    methodLog.add('start');
    startCalls++;
  }

  @override
  Future<void> powerOff() async {
    methodLog.add('powerOff');
    powerOffCalls++;
  }

  @override
  Future<TuneResult> tune(int channel, int code) {
    methodLog.add('tune');
    tuneCalls.add((channel, code));
    if (!holdTunes) return Future<TuneResult>.value(autoResult);
    final Completer<TuneResult> completer = Completer<TuneResult>();
    pendingTunes.add(completer);
    return completer.future;
  }

  /// Completes the tune call at [index] (submission order) with [result].
  void completeTune(int index, TuneResult result) {
    pendingTunes[index].complete(result);
  }

  @override
  Future<void> applySettings(KeryxSettings settings) async {
    methodLog.add('applySettings');
    applySettingsCalls.add(settings);
  }

  @override
  Future<JoinResult> joinEvent(EventLinkPayload payload) async {
    methodLog.add('joinEvent');
    joinEventCalls.add(payload);
    return const JoinResult.success();
  }

  @override
  void pressPtt() {
    methodLog.add('pressPtt');
    pressPttCalls++;
  }

  @override
  void releasePtt() {
    methodLog.add('releasePtt');
    releasePttCalls++;
  }

  @override
  void releaseLatch() {
    methodLog.add('releaseLatch');
    releaseLatchCalls++;
  }

  @override
  Future<void> dispose() async {
    methodLog.add('dispose');
    disposeCalls++;
    await _changes.close();
  }
}
