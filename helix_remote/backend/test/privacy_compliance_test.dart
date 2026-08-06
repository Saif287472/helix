import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'test_registration.dart';

void main() {
  late BackendServer server;
  late HttpClient client;
  late int port;
  final ed25519 = crypto.Ed25519();

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'phase18_test_secret',
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

  test(
    'P18 data export is authenticated, redacted, and ciphertext-only',
    () async {
      final alice = await _registerAndLogin(
        client,
        port,
        server.db,
        ed25519,
        accountId: 'alice',
        username: 'alice_privacy',
        deviceId: 'alice_device',
      );

      await _postJson(
        client,
        port,
        '/api/v1/messages/conversations/create',
        {
          'conversation_id': 'conv_export',
          'type': 'DIRECT',
          'members': ['alice'],
        },
        token: alice.accessToken,
      );
      final send = await _postJson(client, port, '/api/v1/messages/send', {
        'message_id': 'msg_export',
        'conversation_id': 'conv_export',
        'envelopes': [
          {
            'recipient_device_id': 'alice_device',
            'ciphertext': 'opaque_ciphertext_only',
          },
        ],
      }, token: alice.accessToken);
      expect(send.statusCode, equals(200));

      final export = await _getJson(
        client,
        port,
        '/api/v1/privacy/export',
        token: alice.accessToken,
      );
      expect(export.statusCode, equals(200));

      final exported =
          (jsonDecode(export.body) as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      expect(
        (exported['account'] as Map<String, dynamic>)['account_id'],
        'alice',
      );
      final mailbox = (exported['message_mailbox'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(mailbox.single['ciphertext'], equals('opaque_ciphertext_only'));
      expect(jsonEncode(exported), isNot(contains('plaintext message')));
      expect(jsonEncode(exported), isNot(contains('127.0.0.1')));

      final audit = server.db.getAuditLogs(accountId: 'alice');
      expect(audit.first['client_ip'], equals('127.0.0.0'));
      expect(audit.first['user_agent'], isNull);
    },
  );

  test(
    'P18 account deletion purges server account data and invalidates auth',
    () async {
      final alice = await _registerAndLogin(
        client,
        port,
        server.db,
        ed25519,
        accountId: 'alice_delete',
        username: 'alice_delete_user',
        deviceId: 'alice_delete_device',
      );

      final badDelete = await _deleteJson(
        client,
        port,
        '/api/v1/account/delete',
        {'confirmation': 'DELETE wrong'},
        token: alice.accessToken,
      );
      expect(badDelete.statusCode, equals(400));

      final delete = await _deleteJson(client, port, '/api/v1/account/delete', {
        'confirmation': 'DELETE alice_delete',
      }, token: alice.accessToken);
      expect(delete.statusCode, equals(200));
      expect(server.db.getAccount('alice_delete'), isNull);
      expect(server.db.getDevices('alice_delete'), isEmpty);
      expect(server.db.getAuditLogs(accountId: 'alice_delete'), isEmpty);

      final afterDelete = await _getJson(
        client,
        port,
        '/api/v1/privacy/export',
        token: alice.accessToken,
      );
      expect(afterDelete.statusCode, equals(401));
    },
  );

  test('P18 admin access is least-privilege and audited', () async {
    final alice = await _registerAndLogin(
      client,
      port,
      server.db,
      ed25519,
      accountId: 'alice',
      username: 'alice_admin_denied',
      deviceId: 'alice_device',
    );
    final admin = await _registerAndLogin(
      client,
      port,
      server.db,
      ed25519,
      accountId: 'ops1',
      username: 'admin_user',
      deviceId: 'admin_device',
    );
    // Admin is a stored capability, not a magic account id - the id here is
    // an ordinary one, and the grant is what opens the admin route below.
    server.db.setAccountAdmin('ops1', isAdmin: true);

    final denied = await _getJson(
      client,
      port,
      '/api/v1/privacy/admin/audit',
      token: alice.accessToken,
    );
    expect(denied.statusCode, equals(403));
    expect(
      server.db.getAuditLogs(accountId: 'alice').map((row) => row['action']),
      contains('ADMIN_ACCESS_DENIED'),
    );

    server.db.createReport(
      reportId: 'r_admin',
      reporterAccountId: 'alice',
      subjectAccountId: 'ops1',
      category: 'spam',
      reasonCode: 'test',
      contextHash: 'sha256:abc',
    );

    final action = await _postJson(
      client,
      port,
      '/api/v1/contacts/reports/action',
      {'report_id': 'r_admin', 'action': 'WARNED'},
      token: admin.accessToken,
    );
    expect(action.statusCode, equals(200));

    final audit = await _getJson(
      client,
      port,
      '/api/v1/privacy/admin/audit?account_id=ops1',
      token: admin.accessToken,
    );
    expect(audit.statusCode, equals(200));
    final auditRows =
        (jsonDecode(audit.body) as Map<String, dynamic>)['audit'] as List;
    expect(
      auditRows.map((row) => (row as Map<String, dynamic>)['action']),
      containsAll(['ADMIN_SAFETY_ACTION', 'ADMIN_AUDIT_READ']),
    );
  });

  test('P18 plaintext report and push payloads are rejected', () async {
    final alice = await _registerAndLogin(
      client,
      port,
      server.db,
      ed25519,
      accountId: 'alice',
      username: 'alice_report',
      deviceId: 'alice_device',
    );
    await _registerAndLogin(
      client,
      port,
      server.db,
      ed25519,
      accountId: 'bob',
      username: 'bob_report',
      deviceId: 'bob_device',
    );

    final badReport = await _postJson(client, port, '/api/v1/contacts/report', {
      'subject_account_id': 'bob',
      'category': 'spam',
      'reason_code': 'sent_plaintext',
      'plaintext': 'secret message body',
    }, token: alice.accessToken);
    expect(badReport.statusCode, equals(400));

    expect(
      () => server.db.enqueueOutbox(
        'bad_push',
        'PUSH_NOTIFICATION',
        jsonEncode({'body': 'secret message body'}),
      ),
      throwsArgumentError,
    );
  });

  test('P18 policy and claim documents cover all required release gates', () {
    final root = _repoRoot();
    final requiredDocs = {
      'docs/product/PRIVACY_POLICY.md': [
        'No mandatory address-book upload',
        'No sale of personal data',
        'No plaintext push notification payloads',
      ],
      'docs/product/METADATA_INVENTORY.md': ['Messages', 'Backups', 'Audit'],
      'docs/product/RETENTION_AND_DELETION.md': [
        'Account Deletion Behavior',
        'External Copies',
      ],
      'docs/product/APP_STORE_PRIVACY.md': [
        'Advertising ID is not collected',
        'Required Manual Review Before Submission',
      ],
      'docs/security/REMOTE_SECURITY_AND_COMPLIANCE.md': [
        'Incident Response',
        'Vulnerability Disclosure',
        'Dependency and CVE Response',
        'Production Access and Least Privilege',
        'Marketing Claim Review',
      ],
      'docs/product/PRIVACY_CLAIM_MATRIX.md': [
        'Blocked for strong claim',
        'No plaintext push payload',
        'Production-reviewed cryptography',
      ],
    };

    for (final entry in requiredDocs.entries) {
      final file = File('${root.path}/${entry.key}');
      expect(file.existsSync(), isTrue, reason: entry.key);
      final text = file.readAsStringSync();
      for (final expected in entry.value) {
        expect(text, contains(expected), reason: entry.key);
      }
    }

    final claimMatrix = File(
      '${root.path}/docs/product/PRIVACY_CLAIM_MATRIX.md',
    ).readAsStringSync();
    expect(
      claimMatrix,
      isNot(
        contains(
          '| **Forward Secrecy** | Planned | Handshake-based ephemeral key agreements | Implemented |',
        ),
      ),
    );
  });
}

class _AuthTokens {
  const _AuthTokens({required this.accessToken});
  final String accessToken;
}

class _Response {
  const _Response(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

Future<_AuthTokens> _registerAndLogin(
  HttpClient client,
  int port,
  BackendDatabase db,
  crypto.Ed25519 ed25519, {
  required String accountId,
  required String username,
  required String deviceId,
}) async {
  final material = await createTestRegistrationMaterial(
    accountId: accountId,
    username: username,
    deviceId: deviceId,
    deviceName: deviceId,
  );
  final otpResponse = await _postJson(
    client,
    port,
    '/api/v1/accounts/phone/otp/request',
    {'phone_hash': username},
  );
  final otpCode =
      (jsonDecode(otpResponse.body) as Map<String, dynamic>)['code'] as String;
  final inviteCode = seedTestInvite(db);
  final register = await _postJson(client, port, '/api/v1/accounts/register', {
    ...registrationBody(
      accountId: accountId,
      username: username,
      deviceId: deviceId,
      deviceName: deviceId,
      material: material,
      otpCode: otpCode,
      inviteCode: inviteCode,
    ),
  });
  expect(register.statusCode, equals(200));

  final challenge = await _getJson(
    client,
    port,
    '/api/v1/accounts/challenge?account_id=$accountId&device_id=$deviceId',
  );
  final challengeValue =
      (jsonDecode(challenge.body) as Map<String, dynamic>)['challenge']
          as String;
  final signature = await ed25519.sign(
    utf8.encode(challengeValue),
    keyPair: material.deviceSigningKeyPair,
  );
  final login = await _postJson(client, port, '/api/v1/accounts/login', {
    'account_id': accountId,
    'device_id': deviceId,
    'signature': base64Url.encode(signature.bytes).replaceAll('=', ''),
  });
  expect(login.statusCode, equals(200));
  return _AuthTokens(
    accessToken:
        (jsonDecode(login.body) as Map<String, dynamic>)['token'] as String,
  );
}

Future<_Response> _postJson(
  HttpClient client,
  int port,
  String path,
  Map<String, dynamic> body, {
  String? token,
}) async {
  final request = await client.post('127.0.0.1', port, path);
  request.headers.contentType = ContentType.json;
  if (token != null) request.headers.set('Authorization', 'Bearer $token');
  request.write(jsonEncode(body));
  final response = await request.close();
  return _Response(
    response.statusCode,
    await utf8.decoder.bind(response).join(),
  );
}

Future<_Response> _deleteJson(
  HttpClient client,
  int port,
  String path,
  Map<String, dynamic> body, {
  required String token,
}) async {
  final request = await client.delete('127.0.0.1', port, path);
  request.headers.contentType = ContentType.json;
  request.headers.set('Authorization', 'Bearer $token');
  request.write(jsonEncode(body));
  final response = await request.close();
  return _Response(
    response.statusCode,
    await utf8.decoder.bind(response).join(),
  );
}

Future<_Response> _getJson(
  HttpClient client,
  int port,
  String path, {
  String? token,
}) async {
  final request = await client.get('127.0.0.1', port, path);
  if (token != null) request.headers.set('Authorization', 'Bearer $token');
  final response = await request.close();
  return _Response(
    response.statusCode,
    await utf8.decoder.bind(response).join(),
  );
}

Directory _repoRoot() {
  var dir = Directory.current;
  while (!_isRepoRoot(dir)) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not locate repository root');
    }
    dir = parent;
  }
  return dir;
}

bool _isRepoRoot(Directory dir) =>
    File('${dir.path}/pubspec.yaml').existsSync() &&
    File('${dir.path}/analysis_options.yaml').existsSync();
