/// Time source. Everything time-dependent takes a [Clock] so tests can move
/// time instead of sleeping.
abstract interface class Clock {
  DateTime now();
}

final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

/// A clock tests advance by hand.
final class ManualClock implements Clock {
  ManualClock([DateTime? start])
    : _now = (start ?? DateTime.utc(2026, 10, 1)).toUtc();

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration by) => _now = _now.add(by);

  void set(DateTime to) => _now = to.toUtc();
}

/// Monotonic time for intervals a wall-clock step must not disturb (socket
/// frame buckets, idle timers). Unlike [Clock], elapsed time never moves
/// backwards in production: a clock change or an NTP correction is invisible.
abstract interface class Uptime {
  Duration get elapsed;
}

final class StopwatchUptime implements Uptime {
  final Stopwatch _watch = Stopwatch()..start();

  @override
  Duration get elapsed => _watch.elapsed;
}

/// An uptime tests move by hand; [advance] may step it backwards, standing in
/// for a clock that is not monotonic.
final class ManualUptime implements Uptime {
  Duration _elapsed = Duration.zero;

  @override
  Duration get elapsed => _elapsed;

  void advance(Duration by) => _elapsed += by;
}
