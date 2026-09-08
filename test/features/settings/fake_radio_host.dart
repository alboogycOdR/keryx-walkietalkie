import 'dart:async';

import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/features/event_qr/event_link.dart';
import 'package:keryx/features/settings/session_settings.dart';

/// Hand-written [RadioHost] double — Verification §2: no sockets or plugins.
class FakeRadioHost implements RadioHost {
  RadioHostSnapshot _snapshot = const RadioHostSnapshot();
  final StreamController<RadioHostSnapshot> _changes =
      StreamController<RadioHostSnapshot>.broadcast();

  final List<String> methodLog = <String>[];
  final List<KeryxSettings> applySettingsCalls = <KeryxSettings>[];
  final List<EventLinkPayload> joinEventCalls = <EventLinkPayload>[];

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
  }

  @override
  Future<void> powerOff() async {
    methodLog.add('powerOff');
  }

  @override
  Future<TuneResult> tune(int channel, int code) async {
    methodLog.add('tune');
    return const TuneResult.success();
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
  }

  @override
  void releasePtt() {
    methodLog.add('releasePtt');
  }

  @override
  void releaseLatch() {
    methodLog.add('releaseLatch');
  }

  @override
  Future<void> dispose() async {
    methodLog.add('dispose');
    await _changes.close();
  }
}

/// Counts real session reconstructions the way [KeryxRadioHost] does:
/// only when session-affecting fields change. Disposes the previous
/// fake session (closes its listener) so VT-003 can assert cleanup.
class ReconstructingFakeHost extends FakeRadioHost {
  ReconstructingFakeHost(this.applied) : session = FakeSession();

  KeryxSettings applied;
  FakeSession? session;
  final List<FakeSession> disposedSessions = <FakeSession>[];
  int reconstructions = 0;
  Completer<void>? gate;

  @override
  Future<void> applySettings(KeryxSettings settings) async {
    final Completer<void>? hold = gate;
    if (hold != null) {
      await hold.future;
    }
    if (sessionAffectingFieldsChanged(applied, settings)) {
      reconstructions++;
      final FakeSession? previous = session;
      previous?.dispose();
      if (previous != null) {
        disposedSessions.add(previous);
      }
      session = FakeSession();
    }
    applied = settings;
    await super.applySettings(settings);
  }
}

class FakeSession {
  FakeSession() : changes = StreamController<void>.broadcast();

  final StreamController<void> changes;
  bool disposed = false;

  void dispose() {
    disposed = true;
    changes.close();
  }
}
