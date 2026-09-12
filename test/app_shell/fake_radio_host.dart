import 'dart:async';

import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';

/// Hand-written [RadioHost] double for `lib/app_shell/**` widget tests —
/// same reasoning as `test/features/face/face_screen_test.dart`'s
/// `FakeSessionHost`: no real transport/platform I/O can run under
/// `flutter test`, and [RadioHost] is TASK-045's own documented seam for
/// exactly this ("trivially unit-testable with fakes"). Records every call
/// so a test can assert the shell/screens delegate to the host and never
/// synthesize a result themselves (Technical §5.1), and that navigation
/// alone never calls a host lifecycle method (VT-001).
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
  /// would after e.g. a permission-denied or service-fault event.
  void emit(RadioHostSnapshot snapshot) {
    _snapshot = snapshot;
    _changes.add(snapshot);
  }

  @override
  Future<void> start() async => startCalls++;

  @override
  Future<void> powerOff() async => powerOffCalls++;

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
