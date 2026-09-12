import 'package:keryx/core/presentation/talk_target.dart';
import 'package:keryx/services/session/radio_session_controller.dart';

/// v2 (Technical §6.4, TASK-088 additive scope): the v2 start sequence —
/// "load identity -> directory `me` -> presence socket -> current target ->
/// `switchTarget`" — as a standalone seam, **not** a widened `SessionHost`
/// (`lib/features/face/session_host.dart` is outside this task's
/// `Owned_Paths`, and TASK-091..094 have not yet migrated its consumers off
/// the v1 fields/methods it still relies on — Technical §6a).
///
/// Every step is injected as a plain async callback rather than a concrete
/// `DirectoryClient`/`PresenceClient`/contacts-or-groups-store type, so this
/// file does not need to import `lib/services/directory/**`,
/// `lib/core/contacts/**` or `lib/core/groups/**` (each a different task's
/// territory) to exist and be independently testable. Whichever later task
/// wires `KeryxRadioHost` up to a real directory session (Technical §10
/// items 9-10, depending on this one) supplies the real callbacks; this
/// class only orders them correctly and hands the result to
/// [RadioSessionController.switchTarget].
///
/// `KeryxRadioHost`'s existing v1 [start] path is completely untouched by
/// this class — nothing in `keryx_radio_host.dart` constructs or calls this
/// seam yet, so its behaviour when nothing v2 is wired in stays byte-
/// identical (TASK-088 re-scope note §6a's "gated" requirement).
class RadioSessionHostV2 {
  RadioSessionHostV2({
    required this.loadIdentity,
    required this.openPresenceSession,
    required this.resolveCurrentTarget,
    required this.sessionController,
  });

  /// Step 1: load the local device's v2 identity (key pair, peerId). The
  /// return value is intentionally opaque (`Object?`) — this class never
  /// inspects it, only awaits it before proceeding, exactly as Technical
  /// §6.4 orders "load identity" before every later step.
  final Future<Object?> Function() loadIdentity;

  /// Steps 2-3: fetch `/v2/identity/me` and open the presence WebSocket.
  /// Combined into one callback because both are directory-session
  /// bootstrap and neither this class nor its caller needs to observe an
  /// intermediate state between them.
  final Future<void> Function() openPresenceSession;

  /// Step 4: resolve whichever target the app should start on (last-used
  /// contact/group, or `null` if none — a fresh install with no history).
  final Future<TalkTarget?> Function() resolveCurrentTarget;

  /// Step 5: the same controller `KeryxRadioHost` composes for v1 —
  /// [start] hands it the resolved target via
  /// [RadioSessionController.switchTarget].
  final RadioSessionController sessionController;

  bool _started = false;

  /// True once [start] has completed at least once.
  bool get isStarted => _started;

  /// Runs the five-step v2 sequence once. A second call while [isStarted]
  /// is already true re-resolves and re-switches the current target (e.g.
  /// after the app relaunches with new session data) rather than repeating
  /// [loadIdentity]/[openPresenceSession] — cheap idempotency, matching
  /// `KeryxRadioHost.start`'s own "a single boot operation" convention,
  /// without this seam needing that class's generation-counter machinery.
  Future<void> start() async {
    if (!_started) {
      await loadIdentity();
      await openPresenceSession();
      _started = true;
    }
    final target = await resolveCurrentTarget();
    if (target == null) return;
    await sessionController.switchTarget(
      target,
      memberPeerIds: target.memberPeerIds,
    );
  }
}
