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
  _Operation('SEND_MESSAGE', 'POST', 'messages/send'),
  _Operation('CREATE_CONVERSATION', 'POST', 'messages/conversations/create'),
  _Operation('DELETE_MESSAGE', 'POST', 'messages/delete'),
  _Operation('EDIT_MESSAGE', 'POST', 'messages/edit'),
  _Operation('REACTION', 'POST', 'messages/reactions'),
  _Operation('DELIVERY_RECEIPT', 'POST', 'messages/receipts'),
  _Operation('READ_RECEIPT', 'POST', 'messages/receipts'),
  _Operation('TYPING', 'POST', 'messages/typing'),
  _Operation('CONTACT_REQUEST', 'POST', 'contacts/requests'),
  _Operation('CONTACT_REQUEST_ACCEPT', 'POST', 'contacts/requests/accept'),
  _Operation('CONTACT_REQUEST_REJECT', 'POST', 'contacts/requests/reject'),
  _Operation('CONTACT_REQUEST_CANCEL', 'POST', 'contacts/requests/cancel'),
  _Operation('CONTACT_REMOVE', 'POST', 'contacts/remove'),
  _Operation('CONTACT_BLOCK', 'POST', 'contacts/block'),
  _Operation('CONTACT_UNBLOCK', 'POST', 'contacts/unblock'),
  _Operation('USERNAME_CHANGE', 'POST', 'accounts/username'),
  _Operation('PRIVACY_UPDATE', 'POST', 'contacts/privacy'),
  _Operation('PRESENCE_UPDATE', 'POST', 'contacts/presence'),
  _Operation('PROFILE_UPDATE', 'POST', 'accounts/profile'),
  _Operation('SAFETY_REPORT', 'POST', 'contacts/report'),
  _Operation('group_create', 'POST', 'groups/create'),
  _Operation('group_invite', 'POST', 'groups/invite'),
  _Operation('group_invite_respond', 'POST', 'groups/invite/respond'),
  _Operation('group_update', 'POST', 'groups/update'),
  _Operation('group_member_role', 'POST', 'groups/member-role'),
  _Operation('group_leave', 'POST', 'groups/leave'),
  _Operation('group_remove_member', 'POST', 'groups/remove'),
  _Operation('group_delete', 'POST', 'groups/delete'),
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
