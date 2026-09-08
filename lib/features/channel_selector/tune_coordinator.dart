import 'dart:async';

import 'package:keryx/core/presentation/presentation.dart'
    show RadioViewIntents, TuningTarget;
import 'package:keryx/core/radio_host/radio_host.dart'
    show RadioHostOutcome, TuneResult;
import 'package:keryx/core/state/radio_state.dart' show RadioPhase;

/// Recovery-policy classification of a terminal [TuneResult] (Technical §6:
/// "do not invent rollback support if the underlying operation has already
/// torn down the previous chain; implement an explicit recovery policy and
/// test it"). The policy adopted here: never fabricate success or a rolled-
/// back channel — the authoritative channel/code always come straight off
/// `RadioState` via whatever this screen is projecting elsewhere; this
/// coordinator only classifies the terminal outcome so the UI can offer a
/// plain-language message and, for a retryable failure, a Retry action that
/// re-submits the exact same target (never a different one, never reordered
/// ahead of a fresher request).
enum TuneOutcomeKind { success, invalid, cancelled, retryableFailure }

class TuneOutcome {
  const TuneOutcome(this.kind, this.target, {this.message});

  final TuneOutcomeKind kind;
  final TuningTarget target;

  /// Diagnostic detail only — never rendered verbatim (Technical §3: "The
  /// UI must not parse exception text to determine state").
  final String? message;
}

/// Owns the presentation-side half of Technical §6's tune-serialization
/// migration: `RadioHost.tune` already serializes competing calls at the
/// host ("Concurrent calls run strictly in submission order — a call never
/// observes another call's partially-applied state"), so every call this
/// coordinator submits eventually runs, in order, and the last one to run
/// determines the final authoritative channel — "latest requested target
/// wins" is satisfied by construction once every earlier call is guaranteed
/// to complete safely rather than corrupt state, which the host contract
/// already guarantees.
///
/// What the host does **not** track is a request's *lifecycle* — TASK-046's
/// `RadioViewState.pendingTuningTarget` is explicitly caller-supplied for
/// exactly this reason. This class is that caller: it tracks whether a
/// request is in flight or deferred so a screen can render the requested
/// target distinct from the authoritative one (UX-FR-009), block competing
/// tune actions while one is outstanding (Design §2.3), and defer dispatch
/// entirely while TX is active so a tune request can never interrupt an
/// in-progress transmission (UX-FR-030) — only the most recently deferred
/// target survives, so "latest wins" holds across the TX boundary too.
class TuneCoordinator {
  TuneCoordinator({required RadioViewIntents intents}) : _intents = intents;

  final RadioViewIntents _intents;

  TuningTarget? _inFlight;
  TuningTarget? _deferred;

  final StreamController<TuneOutcome> _outcomes =
      StreamController<TuneOutcome>.broadcast();

  bool _disposed = false;

  /// Monotonic dispatch counter. VT-021: "rapid A→B→C requests with
  /// deferred fakes completing in different orders yield one deterministic
  /// final target… no stale state adoption." In production `RadioHost.tune`
  /// itself serializes so responses can only ever arrive in submission
  /// order — this guard exists so the coordinator is correct even under a
  /// double-dispatch race (e.g. a second tap landing before a rebuild
  /// disables the button) or a test double that resolves out of order: only
  /// the response whose generation matches the most recently dispatched
  /// request is adopted into [_inFlight]/[outcomes]; anything older is
  /// dropped silently rather than clearing busy state or emitting a stale
  /// outcome over a newer one.
  int _generation = 0;

  /// The value a caller should feed straight into
  /// `RadioViewState.project(pendingTuningTarget: ...)` — non-null exactly
  /// while a request is in flight at the host or waiting out an active
  /// transmission.
  TuningTarget? get pendingTarget => _inFlight ?? _deferred;

  /// True while any tune action should be blocked (Design §2.3: "A pending
  /// retune shows progress and prevents competing tune actions").
  bool get isBusy => pendingTarget != null;

  Stream<TuneOutcome> get outcomes => _outcomes.stream;

  /// Requests a retune to [channel]/[code]. `currentPhase` is read at call
  /// time (not cached) so this always sees the live TX state.
  void request({
    required int channel,
    required int code,
    required RadioPhase currentPhase,
  }) {
    if (_disposed) return;
    final target = TuningTarget(channel: channel, privacyCode: code);
    if (_isTransmitting(currentPhase)) {
      // UX-FR-030: never interrupt TX. Only the latest deferred target is
      // kept — an earlier deferred request that hasn't been superseded by
      // a terminal state is simply replaced, matching "latest wins".
      _deferred = target;
      return;
    }
    _dispatch(target);
  }

  /// Re-submits the exact same [target] after a retryable failure — never
  /// invents a different destination and never a rollback.
  void retry(TuningTarget target, {required RadioPhase currentPhase}) {
    request(
      channel: target.channel,
      code: target.privacyCode,
      currentPhase: currentPhase,
    );
  }

  /// Call whenever the host's [RadioPhase] changes. Releases a deferred
  /// request the instant TX ends; a no-op in every other case (including
  /// while a request is already in flight, or while still transmitting).
  void onPhaseChanged(RadioPhase phase) {
    if (_disposed) return;
    if (_isTransmitting(phase)) return;
    final deferred = _deferred;
    if (deferred == null) return;
    _deferred = null;
    _dispatch(deferred);
  }

  bool _isTransmitting(RadioPhase phase) =>
      phase == RadioPhase.tx || phase == RadioPhase.txRequest;

  void _dispatch(TuningTarget target) {
    _inFlight = target;
    final int gen = ++_generation;
    unawaited(_run(target, gen));
  }

  Future<void> _run(TuningTarget target, int gen) async {
    final TuneResult result = await _intents.tune(
      target.channel,
      target.privacyCode,
    );
    if (_disposed) return;
    // Stale response: a newer request has already been dispatched (or
    // deferred) since this one. Drop it — do not clear `_inFlight` (it now
    // belongs to the newer request) and do not surface its outcome, which
    // would otherwise flash a superseded result over the current one.
    if (gen != _generation) return;
    _inFlight = null;
    final TuneOutcomeKind kind = switch (result.outcome) {
      RadioHostOutcome.success => TuneOutcomeKind.success,
      RadioHostOutcome.validationFailure => TuneOutcomeKind.invalid,
      RadioHostOutcome.cancelled => TuneOutcomeKind.cancelled,
      RadioHostOutcome.transportFailure => TuneOutcomeKind.retryableFailure,
      // tune() never returns unavailableRoute (radio_host_contract.dart's
      // own dartdoc: "there is always a channel/code numeral to accept or
      // reject") — treated as retryable defensively rather than asserting,
      // so an unexpected future addition fails safe, not silently.
      RadioHostOutcome.unavailableRoute => TuneOutcomeKind.retryableFailure,
    };
    if (!_outcomes.isClosed) {
      _outcomes.add(TuneOutcome(kind, target, message: result.message));
    }
  }

  /// Idempotent. Closes the outcome stream; does not cancel an in-flight
  /// host call (the host's own serialization already guarantees it
  /// completes safely without a listener).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_outcomes.close());
  }
}
