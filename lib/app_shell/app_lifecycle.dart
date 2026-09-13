import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Observes the app's foreground (resume) transitions app-wide, exposed as a
/// broadcast [Stream] so every interested owner (TASK-104's registration
/// retry, TASK-105's contacts refresh) can subscribe without each installing
/// its own [WidgetsBindingObserver] — mirrors `talk_screen.dart`'s existing
/// per-screen use of the same observer pattern, just hoisted to app scope so
/// it fires even while Talk isn't the active tab.
///
/// Only [AppLifecycleState.resumed] is surfaced: "foreground" here means
/// "the user is back and connectivity may have returned", not every
/// lifecycle transition.
class AppForegroundObserver extends WidgetsBindingObserver {
  AppForegroundObserver() {
    WidgetsBinding.instance.addObserver(this);
  }

  final StreamController<void> _controller = StreamController<void>.broadcast();

  /// Emits once per transition into [AppLifecycleState.resumed].
  Stream<void> get onForeground => _controller.stream;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_controller.isClosed) {
      _controller.add(null);
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.close());
  }
}

/// A single app-wide [AppForegroundObserver], torn down with the provider
/// scope. Never `autoDispose` — exactly one observer must exist for the
/// app's lifetime, the same convention every other single-instance provider
/// in `lib/app_shell/**` follows.
final appForegroundProvider = Provider<Stream<void>>((ref) {
  final observer = AppForegroundObserver();
  ref.onDispose(observer.dispose);
  return observer.onForeground;
});
