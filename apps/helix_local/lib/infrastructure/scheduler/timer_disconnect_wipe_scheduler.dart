import 'dart:async';
import 'package:helix_protocol/application/contracts/use_cases.dart';

class TimerDisconnectWipeScheduler implements DisconnectWipeScheduler {
  final Map<String, Timer> _timers = {};

  @override
  void scheduleWipe(String threadId, Duration delay, void Function() onWipe) {
    _timers[threadId]?.cancel();
    _timers[threadId] = Timer(delay, () {
      _timers.remove(threadId);
      onWipe();
    });
  }

  @override
  void cancelWipe(String threadId) {
    _timers.remove(threadId)?.cancel();
  }

  @override
  void cancelAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}
