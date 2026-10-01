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
