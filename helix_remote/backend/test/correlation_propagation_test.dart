// Phase 9.9 — distributed tracing.
//
// §23 recorded observability as weak with a specific reason: "correlation IDs
// are generated but not propagated to a trace store". The middleware minted an
// id and echoed it in the response header, and nothing else ever saw it —
// RedactedLogger even had a `correlationId` parameter that no caller in
// lib/src filled in.
//
// Propagation is a zone value rather than a parameter threaded through every
// module, precisely because the parameter approach had already been tried and
// silently went unused.

import 'dart:async';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:helix_remote_backend/helix_remote_backend.dart';

void main() {
  group('zone-scoped correlation id', () {
    test('is absent outside a request', () {
      // Background work — the outbox worker, the attachment sweep, startup —
      // has no request to correlate with, and must not inherit a stale id
      // from whichever request happened to run before it.
      expect(currentCorrelationId, isNull);
    });

    test('is visible to everything the request calls', () async {
      String? seenSynchronously;
      String? seenAfterAwait;
      String? seenInsideCallback;

      await runWithCorrelationId('trace-abc-123', () async {
        seenSynchronously = currentCorrelationId;
        await Future<void>.delayed(Duration.zero);
        seenAfterAwait = currentCorrelationId;
        await Future(() {
          seenInsideCallback = currentCorrelationId;
        });
      });

      expect(seenSynchronously, equals('trace-abc-123'));
      // The await boundary is the point of using a zone: a plain variable
      // would be lost here, and this is where module code actually runs.
      expect(seenAfterAwait, equals('trace-abc-123'));
      expect(seenInsideCallback, equals('trace-abc-123'));
      expect(currentCorrelationId, isNull, reason: 'must not leak outward');
    });

    test('stamps log lines emitted while handling the request', () {
      final sink = ServerLogSink();
      installServerLog(sink);
      addTearDown(resetServerLogForTesting);

      runWithCorrelationId('trace-xyz-789', () {
        logServerWarning('something went sideways');
      });
      logServerWarning('unrelated background warning');

      final lines = sink.tail(50);
      expect(
        lines.where((line) => line.contains('something went sideways')).single,
        contains('[cid=trace-xyz-789]'),
      );
      expect(
        lines.where((line) => line.contains('unrelated background')).single,
        isNot(contains('[cid=')),
      );
    });
  });

  group('over HTTP', () {
    late BackendServer server;
    late int port;
    late HttpClient client;

    setUp(() async {
      server = BackendServer.create(
        sqliteDb: sqlite3.openInMemory(),
        jwtSecret: 'test_jwt_secret_for_correlation_propagation',
        rateLimitMaxTokens: 1000,
        rateLimitRefillRate: 1000,
      );
      await server.start('127.0.0.1', 0);
      port = server.httpServer!.port;
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.stop();
    });

    Future<HttpClientResponse> get(String path, {String? correlationId}) async {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port$path'),
      );
      if (correlationId != null) {
        request.headers.set('X-Correlation-Id', correlationId);
      }
      return request.close();
    }

    test('a supplied id of the expected shape is honoured', () async {
      const supplied = 'clientsuppliedtraceid01';
      final response = await get(
        '/api/v1/health/live',
        correlationId: supplied,
      );
      await response.drain<void>();

      expect(response.headers.value('x-correlation-id'), equals(supplied));
    });

    test('a malformed id is replaced rather than echoed', () async {
      // The id reaches both the log and the response header, so echoing an
      // arbitrary client string back would make it a log-poisoning channel
      // and put attacker-chosen bytes in a header.
      //
      // CRLF is not among the cases below: dart:io's HttpHeaders.set refuses
      // to send it, so it cannot reach the server from this client at all.
      // What is tested is the shape rule the server applies to everything
      // that does arrive — too short, over-long, and disallowed characters.
      for (final malformed in <String>[
        'short',
        'has spaces in it and more',
        'semi;colons&ampersands=here!!',
        'x' * 200,
      ]) {
        final response = await get(
          '/api/v1/health/live',
          correlationId: malformed,
        );
        await response.drain<void>();

        final returned = response.headers.value('x-correlation-id');
        expect(returned, isNotNull, reason: 'rejected input: $malformed');
        expect(
          returned,
          isNot(equals(malformed)),
          reason: '$malformed must not be echoed back',
        );
        expect(
          RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(returned!),
          isTrue,
          reason: 'replacement for $malformed must be well formed',
        );
      }
    });

    test('every request gets an id even when none is supplied', () async {
      final first = await get('/api/v1/health/live');
      await first.drain<void>();
      final second = await get('/api/v1/health/live');
      await second.drain<void>();

      final a = first.headers.value('x-correlation-id');
      final b = second.headers.value('x-correlation-id');
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a, isNot(equals(b)), reason: 'ids must not be reused');
    });

    test('an error response carries the id the log line will have', () async {
      // This is the loop the feature exists to close: a user reports a
      // failure with the id their client saw, and the operator greps the
      // server log for it.
      final response = await get('/api/v1/ops/metrics');
      await response.drain<void>();

      expect(response.statusCode, anyOf(equals(401), equals(403)));
      expect(response.headers.value('x-correlation-id'), isNotNull);
    });
  });
}
