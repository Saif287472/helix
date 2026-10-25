import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/diagnostics/anomaly_log.dart';
import 'package:helix_remote/core/engine/failure_copy.dart';
import 'package:helix_remote_api/v2.dart'
    show ApiException, NetworkException, RequestFailure;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show AnomalyReport, ErrorCode, Routes;

/// The anomaly log: what is recorded, what is masked, how repeats count up,
/// and how batches go out (`core/diagnostics/anomaly_log.dart`).
void main() {
  setUp(AnomalyLog.resetForTest);
  tearDown(AnomalyLog.resetForTest);

  test('phone numbers, e-mails, tokens and keys are masked in every build', () {
    const jwt =
        'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhbGljZSJ9.c2lnbmF0dXJlLXZhbHVl';
    final masked = AnomalyLog.mask(
      'call +8801711000001 for anna@example.org with Bearer abc.def '
      'token $jwt key ${'A' * 44}',
    );
    expect(masked, isNot(contains('8801711000001')));
    expect(masked, contains('[phone…01]'));
    expect(masked, isNot(contains('anna@example.org')));
    expect(masked, isNot(contains(jwt)));
    expect(masked, isNot(contains('A' * 44)));
    expect(masked, isNot(contains('abc.def')));
    // Short numbers (a status, a line number) are left alone.
    expect(
      AnomalyLog.mask('status 500 at line 12:3'),
      'status 500 at line 12:3',
    );
  });

  test('a debug build keeps the whole message and stack', () {
    AnomalyLog.fullDetail = true;
    AnomalyLog.crash(
      StateError('no element in ${'a long line ' * 40}'),
      StackTrace.fromString(
        '#0 List.first (dart:core/list.dart:1:1)\n'
        '#1 Home.build (package:helix_remote/home.dart:12:3)',
      ),
    );
    final entry = AnomalyLog.queued.single;
    expect(entry.kind, 'crash');
    expect(entry.where, 'StateError');
    expect(entry.message, contains('a long line ' * 39));
    expect(entry.stack, contains('dart:core/list.dart'));
    expect(entry.stack, contains('home.dart:12:3'));
  });

  test('a release build trims the message and keeps only app frames', () {
    AnomalyLog.fullDetail = false;
    AnomalyLog.crash(
      StateError('no element in ${'a long line ' * 40}'),
      StackTrace.fromString(
        '#0 List.first (dart:core/list.dart:1:1)\n'
        '#1 Home.build (package:helix_remote/home.dart:12:3)\n'
        '#2 Card.paint (package:orbit_ui/card.dart:4:1)',
      ),
    );
    final entry = AnomalyLog.queued.single;
    expect(entry.message.length, lessThan(320));
    expect(entry.stack, isNot(contains('dart:core')));
    expect(entry.stack, contains('home.dart:12:3'));
    expect(entry.stack, contains('orbit_ui/card.dart'));
  });

  testWidgets('a layout overflow says which widget and file it came from', (
    tester,
  ) async {
    AnomalyLog.fullDetail = true;
    final previous = FlutterError.onError;
    FlutterError.onError = AnomalyLog.flutterError;
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 40,
            height: 40,
            child: Column(children: [SizedBox(height: 100)]),
          ),
        ),
      ),
    );
    FlutterError.onError = previous;

    final entry = AnomalyLog.queued.single;
    expect(entry.kind, 'crash');
    expect(entry.message, contains('overflowed by 60 pixels'));
    expect(entry.fields['widget'], startsWith('Column anomaly_log_test.dart:'));
    expect(entry.fields['during'], contains('layout'));
  });

  test('a report without a blamed widget names none', () {
    expect(AnomalyLog.culpritOf('Exception: boom'), isNull);
    expect(
      AnomalyLog.culpritOf(
        'The relevant error-causing widget was:\n'
        '  Row Row:file:///J:/p/lib/features/chats/chat_tile.dart:42:7',
      ),
      'Row chat_tile.dart:42',
    );
  });

  test('the same anomaly within a minute counts up instead', () {
    var now = DateTime(2026, 10, 21, 9);
    AnomalyLog.now = () => now;
    AnomalyLog.state('chat.timeline', 'a message without a row');
    now = now.add(const Duration(seconds: 20));
    AnomalyLog.state('chat.timeline', 'a message without a row');
    expect(AnomalyLog.queued.single.fields['repeats'], '2');

    now = now.add(const Duration(minutes: 5));
    AnomalyLog.state('chat.timeline', 'a message without a row');
    expect(AnomalyLog.queued, hasLength(2));
  });

  test('refused requests are told by their route template and request id', () {
    AnomalyLog.request(
      const RequestFailure(
        route: Routes.setHelixName,
        status: 409,
        code: 'name_taken',
        requestId: 'req-1',
      ),
    );
    final entry = AnomalyLog.queued.single;
    expect(entry.kind, 'request');
    expect(entry.where, 'PUT ${Routes.setHelixName.path}');
    expect(entry.message, 'name_taken');
    expect(entry.fields, {'status': '409', 'request_id': 'req-1'});

    // The anomaly route itself is never reported, so a failing send cannot
    // feed itself.
    AnomalyLog.request(
      const RequestFailure(
        route: Routes.anomalies,
        status: 500,
        code: 'internal',
        requestId: 'req-2',
      ),
    );
    expect(AnomalyLog.queued, hasLength(1));
  });

  test('describing a failure records it, unless it is expected', () {
    describeFailure(const NetworkException());
    describeFailure(const ApiException(status: 409, code: ErrorCode.nameTaken));
    expect(AnomalyLog.queued, isEmpty);

    describeFailure(StateError('the engine is not running'));
    final entry = AnomalyLog.queued.single;
    expect(entry.kind, 'failure');
    expect(entry.where, 'StateError');
  });

  test('batches go out once installed; a failed send keeps them', () async {
    for (var i = 0; i < 60; i++) {
      AnomalyLog.state('step $i', 'odd');
    }
    final sent = <AnomalyReport>[];
    var fail = true;
    AnomalyLog.install((report) async {
      if (fail) throw const NetworkException();
      sent.add(report);
    });
    await AnomalyLog.flush();
    expect(sent, isEmpty);
    expect(AnomalyLog.queued, hasLength(60));

    fail = false;
    await AnomalyLog.flush();
    expect([for (final r in sent) r.entries.length], [50, 10]);
    expect(sent.first.platform, isNotEmpty);
    expect(AnomalyLog.queued, isEmpty);
  });

  test('the queue keeps the newest entries', () {
    for (var i = 0; i < AnomalyLog.maxQueued + 5; i++) {
      AnomalyLog.state('step $i', 'odd');
    }
    expect(AnomalyLog.queued, hasLength(AnomalyLog.maxQueued));
    expect(AnomalyLog.queued.first.where, 'step 5');
  });

  test('a burst that overflowed the queue says how much was lost', () async {
    for (var i = 0; i < AnomalyLog.maxQueued + 3; i++) {
      AnomalyLog.state('step $i', 'odd');
    }
    final sent = <AnomalyReport>[];
    AnomalyLog.install((report) async => sent.add(report));
    await AnomalyLog.flush();

    final entries = [for (final report in sent) ...report.entries];
    final note = entries.singleWhere((e) => e.where == 'diagnostics.queue');
    expect(note.message, 'entries dropped');
    expect(note.fields, {'dropped': '3'});
  });
}
