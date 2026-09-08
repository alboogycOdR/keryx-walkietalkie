import 'dart:async';

import 'package:keryx/core/presentation/presentation.dart' show RadioViewIntents;
import 'package:keryx/core/radio_host/radio_host.dart'
    show RadioHost, RadioHostSnapshot;
import 'package:keryx/core/settings/settings_repository.dart' show KeryxSettings;
import 'package:keryx/core/state/radio_state.dart' show RadioState;

import 'session_settings.dart';

/// Outcome of one proposed settings write.
enum SettingsApplyStatus { appliedPresentation, appliedSession, cancelled, deferred }

class SettingsApplyResult {
  const SettingsApplyResult(this.status, {this.pending});

  final SettingsApplyStatus status;
  final KeryxSettings? pending;

  bool get isDeferred => status == SettingsApplyStatus.deferred;
}

/// Defer-until-idle + FIFO serialize policy (Technical §7).
///
/// **Policy (documented for the dossier and README):**
/// 1. Presentation-only fields persist immediately and call
///    `RadioHost.applySettings`, which is a no-rebuild at the host
///    (`_sessionAffectingFieldsChanged` false). Zero session
///    reconstruction (VT-003).
/// 2. Session-affecting fields require an explanatory confirmation.
///    They are then persisted and applied through the host.
/// 3. If [isLocallyTransmitting] is true at apply time, the confirmed
///    snapshot is **queued** and `applySettings` is **not** invoked.
///    Teardown never starts while the engine reports TX — no hot-mic
///    window (PTS §8.5). The next idle observation flushes the queue.
/// 4. Overlapping proposes chain FIFO so two session-affecting writes
///    cannot interleave reconstructions (VT-003 serialized).
/// 5. This coordinator never calls `joinEvent` or any other WAN path.
///    Force-LOCAL therefore cannot initiate WAN from Settings.
class SettingsApplyCoordinator {
  SettingsApplyCoordinator({
    required this.host,
    required this.save,
  }) : intents = RadioViewIntents(host);

  final RadioHost host;
  final RadioViewIntents intents;
  final Future<KeryxSettings> Function(KeryxSettings settings) save;

  Future<void> _chain = Future<void>.value();
  KeryxSettings? _pending;

  KeryxSettings? get pending => _pending;

  Future<SettingsApplyResult> propose({
    required KeryxSettings current,
    required KeryxSettings next,
    required RadioHostSnapshot snapshot,
    required RadioState radio,
    required Future<bool> Function() confirmSession,
  }) {
    final Completer<SettingsApplyResult> completer =
        Completer<SettingsApplyResult>();
    _chain = _chain.then((_) async {
      try {
        completer.complete(
          await _proposeUnlocked(
            current: current,
            next: next,
            snapshot: snapshot,
            radio: radio,
            confirmSession: confirmSession,
          ),
        );
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  /// Apply a previously deferred snapshot now that TX has ended.
  Future<SettingsApplyResult> flushDeferred({
    required RadioHostSnapshot snapshot,
    required RadioState radio,
  }) {
    final Completer<SettingsApplyResult> completer =
        Completer<SettingsApplyResult>();
    _chain = _chain.then((_) async {
      try {
        completer.complete(
          await _flushUnlocked(snapshot: snapshot, radio: radio),
        );
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  void cancelDeferred() {
    _pending = null;
  }

  Future<SettingsApplyResult> _proposeUnlocked({
    required KeryxSettings current,
    required KeryxSettings next,
    required RadioHostSnapshot snapshot,
    required RadioState radio,
    required Future<bool> Function() confirmSession,
  }) async {
    if (current == next &&
        current.relayUrl == next.relayUrl &&
        current.tokenServiceUrl == next.tokenServiceUrl &&
        current.region == next.region) {
      // Structural == on KeryxSettings may be identity-based; still
      // cheap-path when nothing session- or presentation-related moved.
      if (!sessionAffectingFieldsChanged(current, next) &&
          current.squelchLevel == next.squelchLevel &&
          current.rogerBeep == next.rogerBeep &&
          current.latchMode == next.latchMode &&
          current.characterDspIntensity == next.characterDspIntensity &&
          current.dimMode == next.dimMode) {
        return const SettingsApplyResult(SettingsApplyStatus.cancelled);
      }
    }

    final bool session = sessionAffectingFieldsChanged(current, next);
    if (!session) {
      await _commit(next);
      return const SettingsApplyResult(SettingsApplyStatus.appliedPresentation);
    }

    final bool confirmed = await confirmSession();
    if (!confirmed) {
      return const SettingsApplyResult(SettingsApplyStatus.cancelled);
    }

    if (isLocallyTransmitting(snapshot: snapshot, radio: radio)) {
      _pending = next;
      return SettingsApplyResult(
        SettingsApplyStatus.deferred,
        pending: next,
      );
    }

    await _commit(next);
    return const SettingsApplyResult(SettingsApplyStatus.appliedSession);
  }

  Future<SettingsApplyResult> _flushUnlocked({
    required RadioHostSnapshot snapshot,
    required RadioState radio,
  }) async {
    final KeryxSettings? pending = _pending;
    if (pending == null) {
      return const SettingsApplyResult(SettingsApplyStatus.cancelled);
    }
    if (isLocallyTransmitting(snapshot: snapshot, radio: radio)) {
      return SettingsApplyResult(
        SettingsApplyStatus.deferred,
        pending: pending,
      );
    }
    await _commit(pending);
    _pending = null;
    return const SettingsApplyResult(SettingsApplyStatus.appliedSession);
  }

  Future<void> _commit(KeryxSettings next) async {
    final KeryxSettings saved = await save(next);
    await intents.applySettings(saved);
  }
}
