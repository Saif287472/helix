// Phase 2 Step 2.1 — outbound operation registry completeness.
//
// `RemoteOutboundOperationRegistry.require()` throws a `StateError` for an
// unrecognised type, and the sync engine classifies `StateError` as a
// *permanent* failure (`_isPermanentOutboundFailure`). So an operation type
// that is enqueued but not registered goes straight to FAILED with no retry,
// while the UI that enqueued it has already told the user it succeeded.
//
// These tests pin the registry against both sides: the operation types the
// code actually enqueues, and the HTTP paths the backend actually registers.

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/remote_sync_gateway.dart';

/// Every operation type string that appears as the second argument to
/// `db.enqueueOperation(...)` / `enqueueOperation(...)` in the app and the
/// shared packages, together with the file it came from.
///
/// Kept as literal source text rather than a runtime scrape: the scrape would
/// pass vacuously if the enqueue call sites changed shape, whereas these
/// strings are the contract itself and a reviewer can see what was added.
const _enqueuedOperationTypes = <String, List<String>>{
  // app/lib/app/remote_messaging_service/*
  'SEND_MESSAGE': ['message_sending.dart'],
  'CREATE_CONVERSATION': ['conversations.dart'],
  'DELETE_MESSAGE': ['message_actions.dart'],
  'EDIT_MESSAGE': ['message_actions.dart'],
  'REACTION': ['message_actions.dart'],
  'DELIVERY_RECEIPT': ['message_sending.dart'],
  'READ_RECEIPT': ['message_sending.dart'],
  'TYPING': ['typing.dart'],
  'CONTACT_REQUEST': ['contacts_privacy.dart'],
  'CONTACT_REQUEST_ACCEPT': ['contacts_privacy.dart'],
  'CONTACT_REQUEST_REJECT': ['contacts_privacy.dart'],
  'CONTACT_REQUEST_CANCEL': ['contacts_privacy.dart'],
  'CONTACT_REMOVE': ['contacts_privacy.dart'],
  'CONTACT_BLOCK': ['contacts_privacy.dart'],
  'CONTACT_UNBLOCK': ['contacts_privacy.dart'],
  'PRIVACY_UPDATE': ['contacts_privacy.dart'],
  'PRESENCE_UPDATE': ['contacts_privacy.dart'],
  'PROFILE_UPDATE': ['contacts_privacy.dart'],
  'SAFETY_REPORT': ['contacts_privacy.dart'],

  // packages/helix_remote_groups/lib/src/group_service.dart
  'group_create': ['group_service.dart'],
  'group_invite': ['group_service.dart'],
  'group_invite_respond': ['group_service.dart'],
  'group_update': ['group_service.dart'],
  'group_member_role': ['group_service.dart'],
  'group_leave': ['group_service.dart'],
  'group_remove_member': ['group_service.dart'],
  'group_delete': ['group_service.dart'],
  'group_set_add_policy': ['group_service.dart'],
  'group_create_join_link': ['group_service.dart'],
  'group_revoke_join_link': ['group_service.dart'],
  'group_join_via_link': ['group_service.dart'],
  'group_approve_join_request': ['group_service.dart'],
  'group_transfer_ownership': ['group_service.dart'],
  'group_admin_delete_message': ['group_service.dart'],
  'group_block_member': ['group_service.dart'],
};

/// Paths the backend registers under the group and messaging routers.
///
/// Mirrors `backend/lib/src/modules/groups.dart` `router` and
/// `backend/lib/src/modules/messaging.dart` `router`.
const _backendGroupPaths = <String>{
  'groups/create',
  'groups/info',
  'groups/members',
  'groups/invite',
  'groups/invite/respond',
  'groups/update',
  'groups/member-role',
  'groups/leave',
  'groups/remove',
  'groups/delete',
  'groups/set-add-policy',
  'groups/create-join-link',
  'groups/revoke-join-link',
  'groups/join-via-link',
  'groups/join-requests',
  'groups/approve-join-request',
  'groups/transfer-ownership',
  'groups/admin-delete-message',
  'groups/block-member',
  'groups/epoch-key/deliver',
};

const _backendMessagingPaths = <String>{
  'messages/conversations/create',
  'messages/send',
  'messages/sync',
  'messages/cursor',
  'messages/delete',
  'messages/edit',
  'messages/reactions',
  'messages/receipts',
  'messages/typing',
  'messages/device-events',
};

void main() {
  final registry = RemoteOutboundOperationRegistry();

  group('every enqueued operation type resolves to a route', () {
    test('no enqueued type is missing from the registry', () {
      final missing = <String>[];
      for (final type in _enqueuedOperationTypes.keys) {
        if (RemoteOutboundOperation.valuesByType[type] == null) {
          missing.add(type);
        }
      }

      expect(
        missing,
        isEmpty,
        reason:
            'an unregistered type makes require() throw StateError, which the '
            'sync engine treats as a PERMANENT failure - the operation goes '
            'straight to FAILED with no retry, after the UI already reported '
            'success.\nMissing: ${missing.join(', ')}',
      );
    });

    test('require() returns the operation rather than throwing', () {
      for (final type in _enqueuedOperationTypes.keys) {
        expect(
          () => registry.require(type),
          returnsNormally,
          reason: 'require($type) must not throw',
        );
      }
    });

    test('the eight F6 group operations are all registered', () {
      // These are the ones that were silently failing while the group screen
      // reported success.
      const f6 = [
        'group_set_add_policy',
        'group_create_join_link',
        'group_revoke_join_link',
        'group_join_via_link',
        'group_approve_join_request',
        'group_transfer_ownership',
        'group_admin_delete_message',
        'group_block_member',
      ];
      for (final type in f6) {
        expect(
          RemoteOutboundOperation.valuesByType[type],
          isNotNull,
          reason: '$type must have a registered route',
        );
      }
    });
  });

  group('the registry matches the backend route table', () {
    test('every group path the registry uses exists on the backend', () {
      final missing = RemoteOutboundOperation.values
          .map((op) => op.path)
          .where((path) => path.startsWith('groups/'))
          .where((path) => !_backendGroupPaths.contains(path))
          .toSet();

      expect(
        missing,
        isEmpty,
        reason: 'the client would POST to a path the server does not serve',
      );
    });

    test('every messaging path the registry uses exists on the backend', () {
      final missing = RemoteOutboundOperation.values
          .map((op) => op.path)
          .where((path) => path.startsWith('messages/'))
          .where((path) => !_backendMessagingPaths.contains(path))
          .toSet();

      expect(missing, isEmpty);
    });

    test('the F6 mappings point at the routes the plan specified', () {
      const expected = <String, String>{
        'group_set_add_policy': 'groups/set-add-policy',
        'group_create_join_link': 'groups/create-join-link',
        'group_revoke_join_link': 'groups/revoke-join-link',
        'group_join_via_link': 'groups/join-via-link',
        'group_approve_join_request': 'groups/approve-join-request',
        'group_transfer_ownership': 'groups/transfer-ownership',
        'group_admin_delete_message': 'groups/admin-delete-message',
        'group_block_member': 'groups/block-member',
      };

      expected.forEach((type, path) {
        final operation = registry.require(type);
        expect(
          operation.path,
          equals(path),
          reason: '$type must POST to $path',
        );
        expect(operation.method, equals('POST'));
      });
    });
  });

  group('registry hygiene', () {
    test('no duplicate operation types', () {
      final seen = <String>[];
      final duplicates = <String>[];
      for (final operation in RemoteOutboundOperation.values) {
        if (seen.contains(operation.type)) duplicates.add(operation.type);
        seen.add(operation.type);
      }
      expect(duplicates, isEmpty);
    });

    test('no duplicate paths pointing at different operations', () {
      // The two receipt operations deliberately share one endpoint and are
      // told apart by the `receipt_type` that `buildRemoteOutboundBody`
      // stamps into the body. Any *other* shared path is a routing bug: two
      // operation types would hit the same handler and be indistinguishable.
      const intentionalSharedPaths = {'messages/receipts'};

      final byPath = <String, String>{};
      final collisions = <String>[];
      for (final operation in RemoteOutboundOperation.values) {
        final existing = byPath[operation.path];
        if (existing != null && existing != operation.type) {
          if (intentionalSharedPaths.contains(operation.path)) continue;
          collisions.add('${operation.path}: $existing vs ${operation.type}');
        }
        byPath[operation.path] = operation.type;
      }
      expect(
        collisions,
        isEmpty,
        reason: 'two operation types sharing a path is a routing bug',
      );
    });

    test('knownTypes is exactly the values table keys', () {
      expect(
        registry.knownTypes.toSet(),
        equals(RemoteOutboundOperation.valuesByType.keys.toSet()),
      );
    });

    test('every path is a non-empty relative path with no leading slash', () {
      for (final operation in RemoteOutboundOperation.values) {
        expect(operation.path, isNotEmpty, reason: operation.type);
        expect(
          operation.path.startsWith('/'),
          isFalse,
          reason: '${operation.type} must be relative: ${operation.path}',
        );
        expect(
          operation.method,
          anyOf('GET', 'POST', 'PUT', 'PATCH', 'DELETE'),
          reason: '${operation.type} has method ${operation.method}',
        );
      }
    });
  });

  group('outbound body construction', () {
    test('receipt operations stamp their receipt type', () {
      expect(
        buildRemoteOutboundBody('DELIVERY_RECEIPT', const {'message_id': 'm'}),
        containsPair('receipt_type', 'DELIVERY'),
      );
      expect(
        buildRemoteOutboundBody('READ_RECEIPT', const {'message_id': 'm'}),
        containsPair('receipt_type', 'READ'),
      );
    });

    test('SEND_MESSAGE and group operations pass the payload through', () {
      const payload = {'group_id': 'g1', 'policy': 'ADMINS_ONLY'};
      expect(
        buildRemoteOutboundBody('group_set_add_policy', payload),
        equals(payload),
      );
      expect(
        buildRemoteOutboundBody('SEND_MESSAGE', payload),
        equals(payload),
      );
    });
  });
}
