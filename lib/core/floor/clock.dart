import 'dart:async';

/// Injected clock + scheduler. Production uses wall time; tests use
/// [VirtualClock] so every §8.6 timer is deterministic.
abstract class FloorClock {
  DateTime now();

  /// Fire [callback] after [delay]. A zero delay runs on the next drain,
  /// not inline, so callers can finish mutating state first.
  FloorTimer schedule(Duration delay, void Function() callback);
}

/// Handle for a scheduled callback.
abstract class FloorTimer {
  void cancel();
}

/// `DateTime.now` + real [Timer]s. Used by the host, not by unit tests.
class WallClock implements FloorClock {
  const WallClock();

  @override
  DateTime now() => DateTime.now();

  @override
  FloorTimer schedule(Duration delay, void Function() callback) {
    return _WallTimer(Timer(delay, callback));
  }
}

/// Deterministic clock. [elapse] advances time and fires due callbacks
/// in scheduled order (stable for equal deadlines).
class VirtualClock implements FloorClock {
  VirtualClock([DateTime? start])
    : _now = start ?? DateTime.utc(2026, 1, 1);

  DateTime _now;
  int _seq = 0;
  final List<_Scheduled> _queue = <_Scheduled>[];

  @override
  DateTime now() => _now;

  @override
  FloorTimer schedule(Duration delay, void Function() callback) {
    if (delay.isNegative) {
      throw ArgumentError.value(delay, 'delay', 'must be ≥ 0');
    }
    final item = _Scheduled(
      when: _now.add(delay),
      seq: ++_seq,
      callback: callback,
    );
    _queue.add(item);
    return item;
  }

  /// Advance [duration] and run every callback whose deadline is ≤ the
  /// new now. Callbacks may schedule further work; those due before the
  /// target also run in this call.
  void elapse(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must be ≥ 0');
    }
    final target = _now.add(duration);
    while (true) {
      _queue.removeWhere((item) => item.cancelled);
      if (_queue.isEmpty) {
        _now = target;
        return;
      }
      _queue.sort((a, b) {
        final byWhen = a.when.compareTo(b.when);
        return byWhen != 0 ? byWhen : a.seq.compareTo(b.seq);
      });
      final next = _queue.first;
      if (next.when.isAfter(target)) {
        _now = target;
        return;
      }
      _now = next.when;
      _queue.removeAt(0);
      next.callback();
    }
  }
}

class _Scheduled implements FloorTimer {
  _Scheduled({
    required this.when,
    required this.seq,
    required this.callback,
  });

  final DateTime when;
  final int seq;
  final void Function() callback;
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;
}

class _WallTimer implements FloorTimer {
  _WallTimer(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}
