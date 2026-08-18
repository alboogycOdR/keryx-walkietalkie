import 'dart:async';

/// Clock + timer seam so the 2 s / 30 s beacon window is unit-testable.
abstract class DiscoveryScheduler {
  void periodic(Duration interval, void Function() tick);
  void once(Duration delay, void Function() callback);
  void cancelAll();
}

/// Production scheduler backed by [Timer]. Fires [periodic] immediately,
/// then every [interval], matching "beacon at tune, then every 2 s".
class TimerDiscoveryScheduler implements DiscoveryScheduler {
  final List<Timer> _timers = [];

  @override
  void periodic(Duration interval, void Function() tick) {
    tick();
    _timers.add(Timer.periodic(interval, (_) => tick()));
  }

  @override
  void once(Duration delay, void Function() callback) {
    _timers.add(Timer(delay, callback));
  }

  @override
  void cancelAll() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }
}

/// Deterministic scheduler. [advance] fires due periodic ticks and one-shots.
class FakeDiscoveryScheduler implements DiscoveryScheduler {
  Duration elapsed = Duration.zero;
  Duration? _period;
  void Function()? _periodTick;
  Duration _nextPeriodAt = Duration.zero;
  final List<({Duration at, void Function() cb})> _once = [];

  int get periodicTicks => _periodicTicks;
  int _periodicTicks = 0;

  @override
  void periodic(Duration interval, void Function() tick) {
    _period = interval;
    _periodTick = tick;
    _nextPeriodAt = elapsed + interval;
    _periodicTicks++;
    tick();
  }

  @override
  void once(Duration delay, void Function() callback) {
    _once.add((at: elapsed + delay, cb: callback));
  }

  @override
  void cancelAll() {
    _period = null;
    _periodTick = null;
    _once.clear();
  }

  void advance(Duration delta) {
    if (delta < Duration.zero) {
      throw ArgumentError.value(delta, 'delta');
    }
    final target = elapsed + delta;
    while (true) {
      Duration? next;
      var isPeriod = false;
      if (_periodTick != null && _period != null) {
        next = _nextPeriodAt;
        isPeriod = true;
      }
      ({Duration at, void Function() cb})? dueOnce;
      for (final item in _once) {
        if (next == null || item.at < next || (item.at == next && !isPeriod)) {
          next = item.at;
          isPeriod = false;
          dueOnce = item;
        }
      }
      if (next == null || next > target) {
        elapsed = target;
        return;
      }
      elapsed = next;
      if (isPeriod) {
        _periodicTicks++;
        _nextPeriodAt = elapsed + _period!;
        _periodTick!();
      } else if (dueOnce != null) {
        _once.remove(dueOnce);
        dueOnce.cb();
      }
    }
  }
}
