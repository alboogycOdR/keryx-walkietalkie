/// Keeps Contacts in sync with the directory for the app's lifetime
/// (TASK-105 §1): `ContactsListController.refresh()`
/// (`lib/features/contacts/contacts_list_controller.dart`) has to actually
/// be called somewhere other than the tab's own `load()`/action call
/// sites, or the receiving phone never learns about an incoming/accepted
/// request unless it happens to reopen Contacts.
///
/// One owner, read once at shell init
/// (`ref.watch(contactsSyncProvider)` — a `watch`, not `read`, purely so a
/// widget test can rebuild it deterministically; the class itself is
/// still only constructed once, same single-instance convention as
/// `radioHostProvider`/`presenceBootstrapProvider`). Fires: immediately,
/// on every `appForegroundProvider` event (TASK-104's shared observer — no
/// second `WidgetsBindingObserver` for that signal), and on a repeating
/// timer while the app is foregrounded. The timer is gated by
/// [WidgetsBinding]'s own `lifecycleState`, queried rather than a second
/// lifecycle subscription, so it never fires while backgrounded.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_lifecycle.dart';
import 'directory_providers.dart';

const contactsSyncInterval = Duration(seconds: 30);

class ContactsSync {
  ContactsSync(this._ref) {
    // No immediate refresh here: `ContactsListController.load()` (called
    // when the Contacts tab itself is built — `contacts_tab_screen.dart`,
    // and it is mounted immediately since `mobile_app_shell.dart`'s
    // `IndexedStack` keeps every branch alive) already covers "on load"
    // (Description §1's own list); duplicating it here raced a real
    // network refresh against tests that boot the shell without expecting
    // Contacts to make a request of its own (`mobile_app_shell_test.dart`'s
    // Groups-tab case).
    _foregroundSub = _ref.read(appForegroundProvider).listen((_) {
      unawaited(_refresh());
      _restartTimer();
    });
    _restartTimer();
  }

  final Ref _ref;
  Timer? _timer;
  StreamSubscription<void>? _foregroundSub;

  Future<void> _refresh() async {
    final controller = await _ref.read(contactsControllerProvider.future);
    if (controller == null) return;
    try {
      await controller.refreshFromServer();
    } catch (_) {
      // Offline / not yet registered — leave disk state untouched
      // (ContactsController.refreshFromServer's own contract).
    }
  }

  /// `null` (no lifecycle callback has ever arrived — true for the very
  /// first moments of a real app's cold start, and for the entire run of a
  /// widget test, which never dispatches one) is deliberately treated as
  /// **not** foregrounded: this is what keeps the periodic timer from ever
  /// being armed under `flutter test` (there [WidgetsBinding.lifecycleState]
  /// never leaves `null`, so no test is left with a real 30 s [Timer]
  /// outliving it — the pending-timer invariant every other widget test in
  /// this shell relies on). On a real device the engine reports the
  /// initial [AppLifecycleState.resumed] within the first frame or two,
  /// and [appForegroundProvider] carries it into [_restartTimer] as soon as
  /// it lands — the *first* refresh (`load()`'s own immediate call) already
  /// covers "the receiving phone must see a request" for the instant before
  /// the timer arms, so this costs nothing but the periodic re-poll being a
  /// beat late on cold start.
  bool get _isForeground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (!_isForeground) return;
    _timer = Timer.periodic(contactsSyncInterval, (_) {
      if (_isForeground) {
        unawaited(_refresh());
      } else {
        _timer?.cancel();
        _timer = null;
      }
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    unawaited(_foregroundSub?.cancel());
  }
}

final contactsSyncProvider = Provider<void>((ref) {
  final sync = ContactsSync(ref);
  ref.onDispose(sync.dispose);
});
