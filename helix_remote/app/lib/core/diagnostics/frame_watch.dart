import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:helix_remote/core/diagnostics/anomaly_log.dart';

/// Watches frame times, so a phone that stutters or freezes says so in the
/// server log without anyone holding it.
///
/// A frame is slow when its build and raster work together take longer than
/// [slowFrame]; a run of [minSlowFrames] slow frames, or one frame that took
/// [freeze], is recorded as a `state` anomaly. Reports are at most one per
/// [reportEvery] (a freeze is never held back), so a busy phone cannot flood
/// the log; slow frames in between are counted into the next report.
abstract final class FrameWatch {
  /// 60 fps is 16.7 ms a frame; this leaves a busy but healthy phone alone.
  static const slowFrame = Duration(milliseconds: 100);

  /// A frame this long is a freeze a person notices.
  static const freeze = Duration(seconds: 1);

  static const reportEvery = Duration(minutes: 15);
  static const minSlowFrames = 3;

  static bool _installed = false;
  static DateTime Function() now = DateTime.now;
  static DateTime? _lastReportAt;
  static int _slow = 0;
  static Duration _worst = Duration.zero;

  /// Starts watching. Safe to call more than once.
  static void install() {
    if (_installed) return;
    _installed = true;
    SchedulerBinding.instance.addTimingsCallback(_timings);
  }

  static void _timings(List<FrameTiming> timings) => observe([
    for (final timing in timings) timing.buildDuration + timing.rasterDuration,
  ]);

  /// Counts one batch of frame work times and records a report when it is
  /// due. The callback fires about once a second while frames are drawn.
  @visibleForTesting
  static void observe(Iterable<Duration> frameWork) {
    for (final work in frameWork) {
      if (work < slowFrame) continue;
      _slow++;
      if (work > _worst) _worst = work;
    }
    if (_slow == 0) return;
    final frozen = _worst >= freeze;
    if (!frozen && _slow < minSlowFrames) return;
    final at = now();
    final last = _lastReportAt;
    if (!frozen && last != null && at.difference(last) < reportEvery) return;
    AnomalyLog.state(
      'frames',
      'slow frames',
      fields: {'slow': '$_slow', 'worst_ms': '${_worst.inMilliseconds}'},
    );
    _lastReportAt = at;
    _slow = 0;
    _worst = Duration.zero;
  }

  @visibleForTesting
  static void resetForTest() {
    _installed = false;
    now = DateTime.now;
    _lastReportAt = null;
    _slow = 0;
    _worst = Duration.zero;
  }
}
