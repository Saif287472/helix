// Phase 06 — HXA-009.
//
// Contract-driven route parity for production Remote outbound operations. Each
// operation below must be present in OpenAPI and mounted by the backend; schema
// validation may reject the minimal body, but 404/405 means a broken contract.

import 'dart:io';

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'test_registration.dart';

void main() {
  test(
    'P06-W04: production outbound operations resolve to backend routes',
    () async {
      final server = BackendServer.create(
        sqliteDb: sqlite3.openInMemory(),
        jwtSecret: 'phase06_contract_route_parity_secret',
        rateLimitMaxTokens: 1000,
        rateLimitRefillRate: 1000,
      );
      await server.start('127.0.0.1', 0);
      final port = server.httpServer!.port;
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.stop();
      });

      final material = await registerTestAccount(
        client: client,
        host: '127.0.0.1',
        port: port,
        db: server.db,
        accountId: 'phase06_acc',
        username: 'phase06',
        deviceId: 'phase06_device',
        deviceName: 'Phase 06 Device',
      );
      final login = await loginTestAccount(
        client: client,
        host: '127.0.0.1',
        port: port,
        accountId: 'phase06_acc',
        deviceId: 'phase06_device',
        deviceSigningKeyPair: material.deviceSigningKeyPair,
      );
      final token = login['token'] as String;
      final openApiPaths = _openApiPaths();

      for (final operation in _operations) {
        expect(
          openApiPaths,
          contains('/${operation.path}'),
          reason: '${operation.type} is missing from OpenAPI',
        );

        final request = await client.openUrl(
          operation.method,
          Uri.parse('http://127.0.0.1:$port/api/v1/${operation.path}'),
        );
        request.headers.contentType = ContentType.json;
        request.headers.set('Authorization', 'Bearer $token');
        request.write(operation.body);
        final response = await request.close();
        await response.drain<void>();

        expect(
          response.statusCode,
          isNot(anyOf(404, 405)),
          reason:
              '${operation.type} ${operation.method} /api/v1/${operation.path}',
        );
        server.rateLimiter.reset('127.0.0.1');
      }
    },
  );
}

final _operations = <_Operation>[
  const _Operation('SEND_MESSAGE', 'POST', 'messages/send'),
  const _Operation(
    'CREATE_CONVERSATION',
    'POST',
    'messages/conversations/create',
  ),
  const _Operation('DELETE_MESSAGE', 'POST', 'messages/delete'),
  const _Operation('EDIT_MESSAGE', 'POST', 'messages/edit'),
  const _Operation('REACTION', 'POST', 'messages/reactions'),
  const _Operation('DELIVERY_RECEIPT', 'POST', 'messages/receipts'),
  const _Operation('READ_RECEIPT', 'POST', 'messages/receipts'),
  const _Operation('TYPING', 'POST', 'messages/typing'),
  const _Operation('CONTACT_REQUEST', 'POST', 'contacts/requests'),
  const _Operation(
    'CONTACT_REQUEST_ACCEPT',
    'POST',
    'contacts/requests/accept',
  ),
  const _Operation(
    'CONTACT_REQUEST_REJECT',
    'POST',
    'contacts/requests/reject',
  ),
  const _Operation(
    'CONTACT_REQUEST_CANCEL',
    'POST',
    'contacts/requests/cancel',
  ),
  const _Operation('CONTACT_REMOVE', 'POST', 'contacts/remove'),
  const _Operation('CONTACT_BLOCK', 'POST', 'contacts/block'),
  const _Operation('CONTACT_UNBLOCK', 'POST', 'contacts/unblock'),
  const _Operation('PRIVACY_UPDATE', 'POST', 'contacts/privacy'),
  const _Operation('PRESENCE_UPDATE', 'POST', 'contacts/presence'),
  const _Operation('PROFILE_UPDATE', 'POST', 'accounts/profile'),
  const _Operation('SAFETY_REPORT', 'POST', 'contacts/report'),
  const _Operation('group_create', 'POST', 'groups/create'),
  const _Operation('group_invite', 'POST', 'groups/invite'),
  const _Operation('group_invite_respond', 'POST', 'groups/invite/respond'),
  const _Operation('group_update', 'POST', 'groups/update'),
  const _Operation('group_member_role', 'POST', 'groups/member-role'),
  const _Operation('group_leave', 'POST', 'groups/leave'),
  const _Operation('group_remove_member', 'POST', 'groups/remove'),
  const _Operation('group_delete', 'POST', 'groups/delete'),
];

class _Operation {
  const _Operation(this.type, this.method, this.path);

  final String type;
  final String method;
  final String path;
  String get body => '{';
}

Set<String> _openApiPaths() {
  for (final candidate in [
    '../contracts/remote-rest-openapi/openapi.yaml',
    '../../contracts/remote-rest-openapi/openapi.yaml',
    'contracts/remote-rest-openapi/openapi.yaml',
  ]) {
    final file = File(candidate);
    if (!file.existsSync()) continue;
    final text = file.readAsStringSync();
    return RegExp(
      r'^  (/[^:]+):$',
      multiLine: true,
    ).allMatches(text).map((match) => match.group(1)!).toSet();
  }
  throw StateError('Unable to locate remote OpenAPI contract');
}
