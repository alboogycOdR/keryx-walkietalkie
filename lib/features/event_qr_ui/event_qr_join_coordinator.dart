import 'package:keryx/core/radio_host/radio_host.dart' show RadioHost;
import 'package:keryx/core/settings/settings_repository.dart' show KeryxSettings;
import 'package:keryx/core/state/radio_state.dart' show RadioMode;
import 'package:keryx/features/event_qr/event_qr.dart' show EventLinkPayload;

/// Typed outcome of [EventQrJoinCoordinator.join] (Technical §3's own
/// "typed results, never exception text parsed by the UI" rule, applied
/// at this layer too).
enum EventQrJoinOutcome {
  success,
  cancelled,
  forceLocalBlocked,
  routeTransitionFailed,
  joinFailed,
}

class EventQrJoinResult {
  const EventQrJoinResult(this.outcome, [this.message]);

  const EventQrJoinResult.success() : this(EventQrJoinOutcome.success);

  final EventQrJoinOutcome outcome;

  /// Diagnostic detail only — never parsed by the UI to decide state.
  final String? message;

  bool get isSuccess => outcome == EventQrJoinOutcome.success;

  @override
  String toString() => 'EventQrJoinResult($outcome${message != null ? ', $message' : ''})';
}

/// Supplies user approval for a route transition (a confirmation dialog,
/// typically). Returns `true` to proceed, `false` to cancel. The
/// coordinator awaits this and never assumes an answer or a timeout.
typedef RouteTransitionApproval = Future<bool> Function();

/// Host-level join coordinator (Technical §8): "Add a host-level join
/// coordinator that checks effective route and LOCAL-only policy before
/// invoking the existing LINKED-only join." This is the **only** path
/// `event_qr_ui` uses to turn a decoded [EventLinkPayload] into a join —
/// nothing in this feature calls [RadioHost.joinEvent] or
/// [RadioHost.applySettings] directly.
///
/// Force-LOCAL is checked strictly before any settings mutation or host
/// call: when it is enabled, [join] returns
/// [EventQrJoinOutcome.forceLocalBlocked] immediately, without a route
/// -transition prompt and without ever touching the network (Technical
/// §8; UX-FR-062).
class EventQrJoinCoordinator {
  const EventQrJoinCoordinator();

  Future<EventQrJoinResult> join({
    required RadioHost host,
    required EventLinkPayload payload,
    required RadioMode effectiveRoute,
    required KeryxSettings settings,
    required RouteTransitionApproval requestRouteTransitionApproval,
  }) async {
    if (effectiveRoute == RadioMode.linked) {
      return _invokeJoin(host, payload);
    }

    // Not currently linked. force-LOCAL is an absolute block (Technical
    // §8; UX-FR-062) — no transition may be offered or attempted.
    if (settings.forceLocalOnly) {
      return const EventQrJoinResult(EventQrJoinOutcome.forceLocalBlocked);
    }

    final approved = await requestRouteTransitionApproval();
    if (!approved) {
      return const EventQrJoinResult(EventQrJoinOutcome.cancelled);
    }

    try {
      await host.applySettings(settings.copyWith(mode: RadioMode.linked));
    } catch (error) {
      return EventQrJoinResult(EventQrJoinOutcome.routeTransitionFailed, '$error');
    }

    return _invokeJoin(host, payload);
  }

  Future<EventQrJoinResult> _invokeJoin(RadioHost host, EventLinkPayload payload) async {
    final result = await host.joinEvent(payload);
    if (result.isSuccess) {
      return const EventQrJoinResult.success();
    }
    return EventQrJoinResult(EventQrJoinOutcome.joinFailed, result.message);
  }
}
