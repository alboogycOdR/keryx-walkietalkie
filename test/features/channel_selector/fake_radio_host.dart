import 'dart:async';

import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/features/event_qr/event_link.dart';

/// Hand-written [RadioHost] double for `lib/features/channel_selector/**`
/// tests — same reasoning `test/features/talk/fake_radio_host.dart`
/// documents: no real transport/platform I/O can run under `flutter test`,
/// and [RadioHost] is TASK-045's own documented seam for exactly this.
///
/// Unlike a simple auto-resolving fake, [tune] can be held open on demand
/// (see [holdNextTune]) so tests can drive VT-021's "deferred fakes
/// completing in different orders" scenario directly.
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

  /// While true, [tune] returns a [Completer]-backed future instead of
  /// resolving immediately — appended to [pendingTunes] in submission
  /// order so a test can complete them in any order it likes.
  bool holdTunes = false;
  final List<Completer<TuneResult>> pendingTunes = <Completer<TuneResult>>[];

  /// Result [tune] resolves with when [holdTunes] is false. Defaults to
  /// success.
  TuneResult autoResult = const TuneResult.success();

  @override
  RadioHostSnapshot get current => _snapshot;

  @override
  Stream<RadioHostSnapshot> get changes => _changes.stream;

  /// Test-only mutator — pushes a new snapshot exactly like a real host
  /// would.
  void emit(RadioHostSnapshot snapshot) {
    _snapshot = snapshot;
    _changes.add(snapshot);
  }

  @override
  Future<void> start() async => startCalls++;

  @override
  Future<void> powerOff() async => powerOffCalls++;

  @override
  Future<TuneResult> tune(int channel, int code) {
    tuneCalls.add((channel, code));
    if (!holdTunes) return Future<TuneResult>.value(autoResult);
    final completer = Completer<TuneResult>();
    pendingTunes.add(completer);
    return completer.future;
  }

  /// Completes the tune call at [index] (submission order) with [result].
  void completeTune(int index, TuneResult result) {
    pendingTunes[index].complete(result);
  }

  @override
  Future<void> applySettings(KeryxSettings settings) async {
    applySettingsCalls.add(settings);
  }

  @override
  Future<JoinResult> joinEvent(EventLinkPayload payload) async {
    joinEventCalls.add(payload);
    return const JoinResult.success();
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
