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

  group('when a crash is sent (AUD-14h-1)', () {
    testWidgets(
      'a crash that repeats every half second is still sent in time',
      (tester) async {
        final sent = <AnomalyReport>[];
        AnomalyLog.install((report) async => sent.add(report));
        for (var i = 0; i < 10; i++) {
          AnomalyLog.crash(StateError('every frame'), null);
          await tester.pump(const Duration(milliseconds: 500));
          if (i == 4) {
            expect(
              sent,
              isNotEmpty,
              reason: 'the first crash goes at two seconds, storm or not',
            );
          }
        }
        expect(
          [for (final r in sent) ...r.entries].first.fields['repeats'],
          isNotNull,
        );
        expect(AnomalyLog.queued.length, lessThan(5));
        AnomalyLog.install(null); // the timer a pending repeat leaves
      },
    );

    testWidgets('one crash goes within two seconds, and not at once', (
      tester,
    ) async {
      final sent = <AnomalyReport>[];
      AnomalyLog.install((report) async => sent.add(report));
      AnomalyLog.crash(StateError('once'), null);
      await tester.pump(const Duration(milliseconds: 1900));
      expect(sent, isEmpty);
      await tester.pump(const Duration(milliseconds: 200));
      expect(sent, hasLength(1));
    });

    testWidgets(
      'a slow note waits for the regular send, a crash brings it in',
      (tester) async {
        final sent = <AnomalyReport>[];
        AnomalyLog.install((report) async => sent.add(report));
        AnomalyLog.state('slow', 'odd');
        await tester.pump(const Duration(seconds: 19));
        expect(sent, isEmpty);
        await tester.pump(const Duration(seconds: 2));
        expect(sent, hasLength(1));

        AnomalyLog.state('slow again', 'odd');
        await tester.pump(const Duration(seconds: 5));
        AnomalyLog.crash(StateError('now'), null);
        await tester.pump(const Duration(milliseconds: 2100));
        expect(sent, hasLength(2), reason: 'the crash does not wait for 20 s');
      },
    );
  });

  group('whose server hears what (Q10)', () {
    test(
      'an entry goes to the server it was seen under, and only there',
      () async {
        var open = 'https://a.example:443';
        final sentTo = <String, List<String>>{};
        AnomalyLog.install((report) async {
          sentTo.putIfAbsent(AnomalyLog.flushingServer!, () => []).addAll([
            for (final e in report.entries) e.where,
          ]);
        }, server: () => open);
        AnomalyLog.state('seen under a', 'odd');
        open = 'https://b.example:443';
        AnomalyLog.state('seen under b', 'odd');

        await AnomalyLog.flush();
        expect(sentTo, {
          'https://b.example:443': ['seen under b'],
        });
        expect(AnomalyLog.queued.map((e) => e.where), ['seen under a']);

        open = 'https://a.example:443';
        await AnomalyLog.flush();
        expect(sentTo['https://a.example:443'], ['seen under a']);
        expect(AnomalyLog.queued, isEmpty);
      },
    );

    test('what was seen before any session goes to the first server', () async {
      String? open;
      final sent = <String>[];
      AnomalyLog.install(
        (report) async =>
            sent.addAll([for (final e in report.entries) e.where]),
        server: () => open,
      );
      AnomalyLog.state('before sign-in', 'odd');
      await AnomalyLog.flush();
      expect(sent, isEmpty, reason: 'no session, nowhere to send');

      open = 'https://a.example:443';
      await AnomalyLog.flush();
      expect(sent, ['before sign-in']);
    });

    test('the same anomaly under two servers is two entries', () {
      var open = 'https://a.example:443';
      AnomalyLog.install((report) async {}, server: () => open);
      AnomalyLog.state('same', 'odd');
      open = 'https://b.example:443';
      AnomalyLog.state('same', 'odd');
      expect(AnomalyLog.queued, hasLength(2));
    });

    test('two spellings of one address are one server', () {
      expect(
        AnomalyLog.serverKey(Uri.parse('HTTPS://Helix.Example/some/path')),
        AnomalyLog.serverKey(Uri.parse('https://helix.example:443')),
      );
    });
  });
}
