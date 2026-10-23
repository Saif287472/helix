import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/diagnostics/anomaly_log.dart';
import 'package:helix_remote/core/diagnostics/frame_watch.dart';

/// The frame watchdog: what counts as slow, how often it may say so, and
/// that ordinary frames are left alone (`core/diagnostics/frame_watch.dart`).
void main() {
  setUp(() {
    AnomalyLog.resetForTest();
    FrameWatch.resetForTest();
  });
  tearDown(() {
    AnomalyLog.resetForTest();
    FrameWatch.resetForTest();
  });

  Duration ms(int value) => Duration(milliseconds: value);

  test('ordinary frames record nothing', () {
    FrameWatch.observe([ms(4), ms(16), ms(2)]);
    expect(AnomalyLog.queued, isEmpty);
  });

  test('a run of slow frames is one entry, with the count and the worst', () {
    FrameWatch.observe([ms(4), ms(150), ms(120)]);
    expect(AnomalyLog.queued, isEmpty, reason: 'two slow frames are a hitch');

    FrameWatch.observe([ms(30), ms(180)]);
    final entry = AnomalyLog.queued.single;
    expect(entry.kind, 'state');
    expect(entry.where, 'frames');
    expect(entry.fields, {'slow': '3', 'worst_ms': '180'});
  });

  test('one frozen frame is reported at once', () {
    FrameWatch.observe([ms(4), ms(2500)]);
    final entry = AnomalyLog.queued.single;
    expect(entry.fields, {'slow': '1', 'worst_ms': '2500'});
  });

  test('reports stay a quarter of an hour apart; a freeze is not held', () {
    var now = DateTime(2026, 10, 23, 9);
    FrameWatch.now = () => now;
    AnomalyLog.now = () => now;
    FrameWatch.observe([ms(500), ms(500), ms(500)]);
    expect(AnomalyLog.queued, hasLength(1));

    now = now.add(const Duration(minutes: 5));
    FrameWatch.observe([ms(150), ms(150), ms(150)]);
    expect(
      AnomalyLog.queued,
      hasLength(1),
      reason: 'still in the quiet period',
    );

    now = now.add(const Duration(minutes: 11));
    FrameWatch.observe([ms(150), ms(150), ms(150)]);
    expect(AnomalyLog.queued, hasLength(2));
    expect(
      AnomalyLog.queued.last.fields['slow'],
      '6',
      reason: 'the quiet period kept counting',
    );

    now = now.add(const Duration(minutes: 5));
    FrameWatch.observe([ms(1500)]);
    expect(AnomalyLog.queued, hasLength(3));
  });
}
