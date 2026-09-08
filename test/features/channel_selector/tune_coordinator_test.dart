import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/presentation/presentation.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/state/radio_state.dart' show RadioPhase;
import 'package:keryx/features/channel_selector/tune_coordinator.dart';

import 'fake_radio_host.dart';

void main() {
  late FakeRadioHost host;
  late TuneCoordinator coordinator;

  setUp(() {
    host = FakeRadioHost();
    coordinator = TuneCoordinator(intents: RadioViewIntents(host));
  });

  tearDown(() => coordinator.dispose());

  group('VT-021 — serialization / latest-wins', () {
    test(
      'rapid A->B->C completing out of order yields exactly one '
      'deterministic final outcome, for the latest target, no stale '
      'adoption',
      () async {
        host.holdTunes = true;
        final outcomes = <TuneOutcome>[];
        coordinator.outcomes.listen(outcomes.add);

        coordinator.request(channel: 1, code: 0, currentPhase: RadioPhase.idle); // A
        coordinator.request(channel: 2, code: 0, currentPhase: RadioPhase.idle); // B
        coordinator.request(channel: 3, code: 0, currentPhase: RadioPhase.idle); // C

        expect(host.tuneCalls, [(1, 0), (2, 0), (3, 0)]);
        // Latest requested target is authoritative in the UI immediately,
        // even before any host call resolves.
        expect(coordinator.pendingTarget, const TuningTarget(channel: 3, privacyCode: 0));

        // Complete out of order: B, then A, then C.
        host.completeTune(1, const TuneResult.success());
        await Future<void>.delayed(Duration.zero);
        host.completeTune(0, const TuneResult.success());
        await Future<void>.delayed(Duration.zero);
        host.completeTune(2, const TuneResult.success());
        await Future<void>.delayed(Duration.zero);

        // Only C's (the latest dispatch's) outcome was adopted — A and B's
        // late/stale responses were dropped, not surfaced.
        expect(outcomes, hasLength(1));
        expect(outcomes.single.target, const TuningTarget(channel: 3, privacyCode: 0));
        expect(outcomes.single.kind, TuneOutcomeKind.success);
        expect(coordinator.pendingTarget, isNull);
        expect(coordinator.isBusy, isFalse);
      },
    );

    test('an out-of-order early resolution does not clear busy state early', () async {
      host.holdTunes = true;
      coordinator.request(channel: 1, code: 0, currentPhase: RadioPhase.idle);
      coordinator.request(channel: 2, code: 0, currentPhase: RadioPhase.idle);

      // Complete the FIRST (stale) call while the second is still pending.
      host.completeTune(0, const TuneResult.success());
      await Future<void>.delayed(Duration.zero);

      // Still busy — the authoritative in-flight target is the second one.
      expect(coordinator.isBusy, isTrue);
      expect(coordinator.pendingTarget, const TuningTarget(channel: 2, privacyCode: 0));
    });
  });

  group('UX-FR-030 — TX serialization', () {
    test('a tune requested during TX is deferred, not dispatched', () {
      coordinator.request(channel: 5, code: 1, currentPhase: RadioPhase.tx);
      expect(host.tuneCalls, isEmpty);
      expect(coordinator.pendingTarget, const TuningTarget(channel: 5, privacyCode: 1));
      expect(coordinator.isBusy, isTrue);
    });

    test('deferred during txRequest as well as tx', () {
      coordinator.request(channel: 5, code: 1, currentPhase: RadioPhase.txRequest);
      expect(host.tuneCalls, isEmpty);
    });

    test('deferred tune dispatches once phase leaves TX', () {
      coordinator.request(channel: 5, code: 1, currentPhase: RadioPhase.tx);
      expect(host.tuneCalls, isEmpty);

      coordinator.onPhaseChanged(RadioPhase.tx); // still transmitting: no-op
      expect(host.tuneCalls, isEmpty);

      coordinator.onPhaseChanged(RadioPhase.idle); // TX ended
      expect(host.tuneCalls, [(5, 1)]);
    });

    test('only the latest deferred target survives multiple TX-time requests', () {
      coordinator.request(channel: 5, code: 1, currentPhase: RadioPhase.tx);
      coordinator.request(channel: 6, code: 2, currentPhase: RadioPhase.tx);
      coordinator.request(channel: 7, code: 3, currentPhase: RadioPhase.tx);
      expect(host.tuneCalls, isEmpty);

      coordinator.onPhaseChanged(RadioPhase.idle);
      expect(host.tuneCalls, [(7, 3)]);
    });
  });

  group('recovery policy', () {
    test('validation failure classifies as invalid, no rollback invented', () async {
      host.autoResult = const TuneResult.validationFailure('bad');
      final outcomes = <TuneOutcome>[];
      coordinator.outcomes.listen(outcomes.add);

      coordinator.request(channel: 5, code: 1, currentPhase: RadioPhase.idle);
      await Future<void>.delayed(Duration.zero);

      expect(outcomes.single.kind, TuneOutcomeKind.invalid);
    });

    test('cancelled classifies as cancelled', () async {
      host.autoResult = const TuneResult.cancelled();
      final outcomes = <TuneOutcome>[];
      coordinator.outcomes.listen(outcomes.add);

      coordinator.request(channel: 5, code: 1, currentPhase: RadioPhase.idle);
      await Future<void>.delayed(Duration.zero);

      expect(outcomes.single.kind, TuneOutcomeKind.cancelled);
    });

    test('transport failure classifies as retryable and retry re-submits the same target', () async {
      host.autoResult = const TuneResult.transportFailure('boom');
      final outcomes = <TuneOutcome>[];
      coordinator.outcomes.listen(outcomes.add);

      coordinator.request(channel: 5, code: 1, currentPhase: RadioPhase.idle);
      await Future<void>.delayed(Duration.zero);
      expect(outcomes.single.kind, TuneOutcomeKind.retryableFailure);

      host.autoResult = const TuneResult.success();
      coordinator.retry(outcomes.single.target, currentPhase: RadioPhase.idle);
      await Future<void>.delayed(Duration.zero);

      expect(host.tuneCalls, [(5, 1), (5, 1)]);
      expect(outcomes.last.kind, TuneOutcomeKind.success);
      expect(outcomes.last.target, const TuningTarget(channel: 5, privacyCode: 1));
    });
  });

  test('dispose is idempotent and closes the outcome stream', () async {
    coordinator.dispose();
    coordinator.dispose();
    expect(await coordinator.outcomes.isEmpty, isTrue);
  });
}
