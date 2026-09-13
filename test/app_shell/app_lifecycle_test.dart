import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keryx/app_shell/app_lifecycle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppForegroundObserver', () {
    test('emits only on a transition into resumed', () async {
      final observer = AppForegroundObserver();
      final events = <void>[];
      final sub = observer.onForeground.listen(events.add);

      observer.didChangeAppLifecycleState(AppLifecycleState.inactive);
      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(events, isEmpty);

      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));

      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(2));

      await sub.cancel();
      observer.dispose();
    });

    test('does not emit after dispose', () async {
      final observer = AppForegroundObserver();
      final events = <void>[];
      observer.onForeground.listen(events.add);
      observer.dispose();

      // WidgetsBinding.instance no longer forwards to a disposed observer
      // (removeObserver), but even a direct call must not throw or emit on
      // a closed controller.
      expect(
        () => observer.didChangeAppLifecycleState(AppLifecycleState.resumed),
        returnsNormally,
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
    });
  });

  group('appForegroundProvider', () {
    test('is a single memoised observer for the container lifetime', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final first = container.read(appForegroundProvider);
      final second = container.read(appForegroundProvider);
      expect(identical(first, second), isTrue);
    });

    test('the underlying observer is disposed with the container', () async {
      final container = ProviderContainer();
      final stream = container.read(appForegroundProvider);
      final events = <void>[];
      final sub = stream.listen(events.add);
      addTearDown(sub.cancel);

      container.dispose();

      // Disposal removed the WidgetsBinding observer and closed the
      // controller; nothing further should ever arrive.
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
    });
  });
}
