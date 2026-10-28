import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Counts the wake-ups that arrived while the app was in front. A feature that
/// should read something again when the server wakes the phone (the plan page)
/// watches it; core stays out of the features' way and only counts.
final pushWakeTickProvider = NotifierProvider<PushWakeTick, int>(
  PushWakeTick.new,
);

final class PushWakeTick extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}
