import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late BackendServer server;
  late HttpClient client;
  late int port;
  late String adminToken;
  late String userToken;

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'phase19_test_secret',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
      adminAccountIds: const {'admin'},
      turnUrl: 'turn:turn.test.example:3478',
      wsReconnectsPerMinute: 2,
    );

    server.db.createAccount('admin', 'admin_user', 'admin_key');
    server.db.registerDevice(
      'admin_device',
      'admin',
      'admin_device_key',
      'Admin',
    );
    server.db.createAccount('user1', 'user_one', 'user_key');
    server.db.registerDevice('user_device', 'user1', 'user_device_key', 'User');

    adminToken = server.jwt.generateToken({
      'account_id': 'admin',
      'device_id': 'admin_device',
    }, const Duration(hours: 1));
    userToken = server.jwt.generateToken({
      'account_id': 'user1',
      'device_id': 'user_device',
    }, const Duration(hours: 1));

    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  test('P19 liveness and readiness are public aggregate probes', () async {
    final live = await _getJson(client, port, '/api/v1/health/live');
    expect(live.statusCode, equals(200));
    expect(live.body, contains('helix_remote_backend'));

    final ready = await _getJson(client, port, '/api/v1/health/ready');
    expect(ready.statusCode, equals(200));
    final body = jsonDecode(ready.body) as Map<String, dynamic>;
    expect(body['status'], equals('ready'));
    expect(body['schema_version'], greaterThanOrEqualTo(11));
    expect(jsonEncode(body), isNot(contains('user_device_key')));
  });

  test('P19 admin metrics are least-privilege and content-free', () async {
    server.db.createConversation('conv_metrics', 'DIRECT', null, ['user1']);
    server.db.saveMessage(
      messageId: 'msg_metrics',
      conversationId: 'conv_metrics',
      senderAccountId: 'user1',
      senderDeviceId: 'user_device',
      recipientDeviceId: 'user_device',
      ciphertext: 'opaque_phase19_ciphertext',
    );
    server.db.createAttachment(
      fileId: 'file_metrics',
      accountId: 'user1',
      fileSize: 1234,
      fileHash: 'file_metrics',
    );
    server.db.updateAttachmentProgress('file_metrics', 1234, 'COMPLETED');

    final denied = await _getJson(
      client,
      port,
      '/api/v1/ops/metrics',
      token: userToken,
    );
    expect(denied.statusCode, equals(403));

    final metrics = await _getJson(
      client,
      port,
      '/api/v1/ops/metrics',
      token: adminToken,
    );
    expect(metrics.statusCode, equals(200));
    final body = jsonDecode(metrics.body) as Map<String, dynamic>;
    expect(
      (body['mailbox'] as Map<String, dynamic>)['message_count'],
      equals(1),
    );
    expect(
      (body['attachments'] as Map<String, dynamic>)['total_bytes'],
      equals(1234),
    );
    expect(body['slo_targets'], isA<Map<String, dynamic>>());
    expect(body['alert_thresholds'], isA<Map<String, dynamic>>());
    expect(metrics.body, isNot(contains('opaque_phase19_ciphertext')));
    expect(metrics.body, isNot(contains('user_device_key')));

    final audit = server.db.getAuditLogs(accountId: 'admin');
    expect(
      audit.any((row) => row['action'] == 'ADMIN_OPERABILITY_METRICS_READ'),
      isTrue,
    );
  });

  test('P19 push provider outage retries and dead-letters safe wake hints', () {
    server.outboxWorker.pushProviderAvailable = false;
    server.db.enqueueOutbox(
      'push_outage',
      'PUSH_NOTIFICATION',
      jsonEncode({'notification_type': 'new_message'}),
    );

    for (var i = 0; i < 4; i++) {
      final result = server.outboxWorker.processOnce();
      expect(result['failed'], equals(1));
    }

    final finalResult = server.outboxWorker.processOnce();
    expect(finalResult['dlq'], equals(1));
    final event = server.db.getOutboxEvent('push_outage')!;
    expect(event['status'], equals('DLQ'));
    expect(event['retries'], equals(5));
  });

  test('P19 WebSocket reconnect storms are rejected per device', () async {
    final uri = 'ws://127.0.0.1:$port/api/v1/ws';
    final first = await WebSocket.connect(
      uri,
      headers: {'Authorization': 'Bearer $userToken'},
    );
    await first.close();
    final second = await WebSocket.connect(
      uri,
      headers: {'Authorization': 'Bearer $userToken'},
    );
    await second.close();

    await expectLater(
      WebSocket.connect(uri, headers: {'Authorization': 'Bearer $userToken'}),
      throwsA(isA<WebSocketException>()),
    );

    expect(server.wsRelay.stats()['rejected_reconnects'], equals(1));
  });

  test(
    'P19 operability runbook covers DR, scaling, and communication gates',
    () {
      final doc = _readRepoFile('docs/operations/REMOTE_OPERABILITY_AND_DR.md');

      for (final phrase in [
        'Service-Level Indicators',
        'Service-Level Objectives',
        'Automated Backups',
        'Restore Drills and PITR',
        'Object Storage Recovery',
        'Redis Loss',
        'WebSocket Reconnect Storms',
        'Push Provider Outage',
        'TURN Outage and Regional Fallback',
        'Rate-Limit Tuning',
        'Capacity Tests',
        'Scaling Strategy',
        'Zero-Downtime Migrations',
        'Rolling Compatibility',
        'Emergency Rollback',
        'Status Page and User Communication',
        'Top Failure-Mode Runbooks',
      ]) {
        expect(doc, contains(phrase));
      }
    },
  );
}

Future<_Response> _getJson(
  HttpClient client,
  int port,
  String path, {
  String? token,
}) async {
  final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
  if (token != null) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  return _Response(response.statusCode, body);
}

class _Response {
  const _Response(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

String _readRepoFile(String path) {
  for (final prefix in ['', '..', '../..']) {
    final candidate = prefix.isEmpty ? File(path) : File('$prefix/$path');
    if (candidate.existsSync()) {
      return candidate.readAsStringSync();
    }
  }
  throw FileSystemException('Unable to locate repo file', path);
}
