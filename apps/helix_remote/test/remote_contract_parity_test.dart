// Phase 06 — HXA-009, HXA-021.
//
// Verifies app outbound operation metadata stays aligned with the
// authoritative OpenAPI contract, and that client serialization supplies
// operation-specific fields shared endpoints cannot infer on their own.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/remote_sync_gateway.dart';

void main() {
  test('P06-W01: every app outbound operation path exists in OpenAPI', () {
    final paths = _openApiPaths();
    for (final operation in RemoteOutboundOperation.values) {
      expect(
        paths,
        contains('/${operation.path}'),
        reason: '${operation.type} points at ${operation.path}',
      );
    }
  });

  test('P06-W02: known corrected operation paths do not regress', () {
    final registry = RemoteOutboundOperationRegistry();
    expect(registry.require('USERNAME_CHANGE').path, 'accounts/username');
    expect(registry.require('PROFILE_UPDATE').path, 'accounts/profile');
    expect(registry.require('SAFETY_REPORT').path, 'contacts/report');
    expect(registry.require('EDIT_MESSAGE').path, 'messages/edit');
    expect(registry.require('REACTION').path, 'messages/reactions');
    expect(registry.require('DELIVERY_RECEIPT').path, 'messages/receipts');
    expect(registry.require('READ_RECEIPT').path, 'messages/receipts');
    expect(registry.require('TYPING').path, 'messages/typing');
  });

  test('P06-W03: receipt serialization preserves shared endpoint type', () {
    final basePayload = {
      'message_id': 'msg_1',
      'conversation_id': 'conv_1',
      'account_id': 'acc_1',
      'device_id': 'dev_1',
    };

    expect(
      buildRemoteOutboundBody('DELIVERY_RECEIPT', basePayload)['receipt_type'],
      'DELIVERY',
    );
    expect(
      buildRemoteOutboundBody('READ_RECEIPT', basePayload)['receipt_type'],
      'READ',
    );
  });
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
