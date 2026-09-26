import 'package:test/test.dart';
import 'package:helix_remote_api/api.dart';
import 'package:helix_remote_domain/models.dart';

void main() {
  group('Remote Domain Models Serialization', () {
    test('RemoteAccount fromJson and toJson', () {
      final json = {
        'account_id': 'acc_123',
        'identity_public_key': 'hexkey',
        'created_at': '2026-06-19T06:00:00.000Z',
        'status': 'Active',
      };
      final account = RemoteAccount.fromJson(json);
      expect(account.accountId, 'acc_123');
      expect(account.identityPublicKey, 'hexkey');
      expect(account.createdAt, DateTime.utc(2026, 6, 19, 6, 0, 0));
      expect(account.toJson()['account_id'], 'acc_123');
    });

    test('RemoteDevice fromJson and toJson', () {
      final json = {
        'device_id': 'device2',
        'device_name': 'My Laptop',
        'device_signing_public_key': 'signing_pubkey',
        'device_agreement_public_key': 'agreement_pubkey',
        'created_at': '2026-06-19T06:00:00.000Z',
        'status': 'Active',
      };
      final device = RemoteDevice.fromJson(json);
      expect(device.deviceId, 'device2');
      expect(device.deviceName, 'My Laptop');
      expect(device.deviceSigningPublicKey, 'signing_pubkey');
      expect(device.deviceAgreementPublicKey, 'agreement_pubkey');
      expect(device.toJson()['device_id'], 'device2');
    });

    test('RemoteContact fromJson and toJson', () {
      final json = {
        'peer_account_id': 'peer_1',
        'nickname': 'Bob',
        'status': 'Accepted',
      };
      final contact = RemoteContact.fromJson(json);
      expect(contact.peerAccountId, 'peer_1');
      expect(contact.nickname, 'Bob');
      expect(contact.status, 'Accepted');
      expect(contact.toJson()['nickname'], 'Bob');
    });

    test('RemoteConversation fromJson and toJson', () {
      final json = {
        'conversation_id': 'conv_1',
        'type': 'OneToOne',
        'title': 'Chat with Bob',
        'created_at': '2026-06-19T06:00:00.000Z',
        'last_activity_sequence': 42,
      };
      final conv = RemoteConversation.fromJson(json);
      expect(conv.conversationId, 'conv_1');
      expect(conv.lastActivitySequence, 42);
      expect(conv.toJson()['last_activity_sequence'], 42);
    });

    test('RemoteMessage fromJson and toJson', () {
      final json = {
        'message_id': 'msg_1',
        'conversation_id': 'conv_1',
        'sender_account_id': 'sender_1',
        'sender_device_id': 'device1',
        'ciphertext': 'encrypted_stuff',
      };
      final msg = RemoteMessage.fromJson(json);
      expect(msg.messageId, 'msg_1');
      expect(msg.senderDeviceId, 'device1');
      expect(msg.toJson()['ciphertext'], 'encrypted_stuff');
    });

    test('RemoteAttachmentManifest fromJson and toJson', () {
      final json = {
        'file_id': 'file_1',
        'file_size': 1024,
        'file_hash': 'sha256hash',
        'mime_type': 'image/png',
      };
      final attachment = RemoteAttachmentManifest.fromJson(json);
      expect(attachment.fileId, 'file_1');
      expect(attachment.fileSize, 1024);
      expect(attachment.toJson()['mime_type'], 'image/png');
    });

    test('RemoteGroup fromJson and toJson', () {
      final json = {
        'conversation_id': 'conv_group',
        'group_name': 'Team Dev',
        'avatar_uri': 'https://avatar',
        'group_public_key': 'grouppubkey',
      };
      final group = RemoteGroup.fromJson(json);
      expect(group.conversationId, 'conv_group');
      expect(group.groupName, 'Team Dev');
      expect(group.avatarUri, 'https://avatar');
      expect(group.toJson()['group_public_key'], 'grouppubkey');
    });

    test('RemoteCallHistoryEntry fromJson and toJson', () {
      final json = {
        'call_id': 'call_1',
        'conversation_id': 'conv_1',
        'direction': 'Incoming',
        'start_time': '2026-06-19T06:00:00.000Z',
        'duration_seconds': 120,
      };
      final call = RemoteCallHistoryEntry.fromJson(json);
      expect(call.callId, 'call_1');
      expect(call.durationSeconds, 120);
      expect(call.toJson()['duration_seconds'], 120);
    });

    test('RemoteSyncCursor fromJson and toJson', () {
      final json = {'conversation_id': 'conv_1', 'last_server_sequence': 100};
      final cursor = RemoteSyncCursor.fromJson(json);
      expect(cursor.conversationId, 'conv_1');
      expect(cursor.lastServerSequence, 100);
      expect(cursor.toJson()['last_server_sequence'], 100);
    });
  });

  group('Realtime envelope gate covers every type the backend sends', () {
    // The mirror of the backend's WS emissions, by source file. A type missing
    // from the gate is flagged `isUnrecognized`, which makes the sync engine
    // skip it before reaching the handler written for it - so the event looks
    // wired and is dropped anyway, and nothing else fails.
    //
    // This is a hand-maintained mirror rather than a generated one, so it only
    // catches an omission if someone remembers to touch it. That is still worth
    // more than nothing: it is the check that would have caught the device
    // pairing, group join-request and group epoch key events all being
    // unreachable at once.
    const backendEmittedTypes = <String, String>{
      'chat_message': 'modules/messaging.dart',
      'message_deleted': 'modules/messaging.dart',
      'message_edited': 'modules/messaging.dart',
      'reaction_added': 'modules/messaging.dart',
      'read_receipt': 'modules/messaging.dart',
      'delivery_receipt': 'modules/messaging.dart',
      'typing': 'modules/messaging.dart',
      'membership_changed': 'modules/groups/membership.dart',
      'membership_changed_admin': 'modules/groups/membership.dart',
      'group_created': 'modules/groups/lifecycle.dart',
      'group_deleted': 'modules/groups/lifecycle.dart',
      'group_admin_event': 'modules/groups/lifecycle.dart',
      'group_invite': 'modules/groups/membership.dart',
      'group_key_updated': 'modules/groups/membership.dart',
      'group_join_requested': 'modules/groups/join_links.dart',
      'group_join_request_resolved': 'modules/groups/join_links.dart',
      'group_add_policy_changed': 'modules/groups/join_links.dart',
      'group_epoch_key': 'modules/groups/epoch_keys.dart',
      'contact_updated': 'modules/contacts.dart',
      'contact_removed': 'modules/contacts.dart',
      'profile_updated': 'modules/profile.dart',
      'pending_device_link': 'modules/devices.dart',
      'device_linked': 'modules/devices.dart',
      'device_revoked': 'modules/devices.dart',
      'DEVICE_REVOKED': 'modules/accounts_devices_repository.dart',
      'scheduled_call_invite': 'modules/group_calls.dart',
      'scheduled_call_cancelled': 'modules/group_calls.dart',
    };

    backendEmittedTypes.forEach((type, source) {
      test('recognises $type (sent by $source)', () {
        final envelope = RemoteRealtimeEnvelope.fromJson({
          'event_id': 'evt_1',
          'schema_version': 1,
          'timestamp': 1781848900000,
          'type': type,
          'payload': const <String, dynamic>{},
        });
        expect(
          envelope.isUnrecognized,
          isFalse,
          reason:
              'The backend sends "$type" ($source) but the envelope gate does '
              'not list it, so the sync engine drops the event before its '
              'handler runs. Add it to supportedTypes.',
        );
      });
    });

    test('still flags a genuinely unknown type', () {
      // The gate has to stay a gate, or graceful degradation is lost.
      final envelope = RemoteRealtimeEnvelope.fromJson({
        'event_id': 'evt_1',
        'schema_version': 1,
        'timestamp': 1781848900000,
        'type': 'some_type_from_a_future_server',
        'payload': const <String, dynamic>{},
      });
      expect(envelope.isUnrecognized, isTrue);
    });

    test('room-level group-call frames are not gated, by design', () {
      // These are dispatched raw by RemoteWebSocketClient and consumed by
      // RemoteGroupCallService, so they must not look like replayable sync
      // events. If one ever appears in the gate, the raw path has been broken.
      for (final type in const [
        'call_signal',
        'participant_joined',
        'participant_left',
        'participant_kicked',
        'room_ended',
        'screen_sharing_changed',
      ]) {
        final envelope = RemoteRealtimeEnvelope.fromJson({
          'event_id': 'gcevt_1',
          'schema_version': 1,
          'timestamp': 1781848900000,
          'type': type,
          'payload': const <String, dynamic>{'room_id': 'room_1'},
        });
        expect(
          envelope.isUnrecognized,
          isTrue,
          reason: '"$type" is dispatched raw, not through the sync engine.',
        );
      }
    });
  });

  group('Remote Realtime Envelope & Graceful Degradation', () {
    test('Standard Chat Message Envelope', () {
      final json = {
        'event_id': '469018e6-e910-4100-84cf-d84bf27ad9a6',
        'schema_version': 1,
        'timestamp': 1781848800000,
        'type': 'chat_message',
        'server_sequence': 14,
        'payload': {
          'conversation_id': '8c59f0f9-a35c-41fb-992a-3023e3e29f8f',
          'sender_account_id': 'acc_01h9w2m8g8qpr88v75v1w7jx8q',
          'sender_device_id': 'device1',
          'ciphertext': 'opaquebase64ciphertextbytes',
          'message_id': 'msg_01h9w2m8g8qpr88v75v1w7jx8q',
        },
      };
      final envelope = RemoteRealtimeEnvelope.fromJson(json);
      expect(envelope.eventId, '469018e6-e910-4100-84cf-d84bf27ad9a6');
      expect(envelope.schemaVersion, 1);
      expect(envelope.serverSequence, 14);
      expect(envelope.type, 'chat_message');
      expect(envelope.isUnrecognized, false);
      expect(
        envelope.payload['conversation_id'],
        '8c59f0f9-a35c-41fb-992a-3023e3e29f8f',
      );
    });

    test('Graceful degradation on Unrecognized Event Type (P8-042)', () {
      final json = {
        'event_id': 'a90f1111-e910-4100-84cf-d84bf27ad9a6',
        'schema_version': 1,
        'timestamp': 1781848900000,
        'type': 'future_event_type',
        'server_sequence': 15,
        'payload': {'some_data': 'goes here'},
      };
      final envelope = RemoteRealtimeEnvelope.fromJson(json);
      expect(envelope.eventId, 'a90f1111-e910-4100-84cf-d84bf27ad9a6');
      expect(envelope.type, 'future_event_type');
      expect(envelope.serverSequence, 15);
      expect(envelope.isUnrecognized, true);
      // Payload is parsed as a map, but flagged unrecognized so client can skip it safely.
      expect(envelope.payload['some_data'], 'goes here');
    });

    test('Graceful degradation on Unrecognized Schema Version (P8-042)', () {
      final json = {
        'event_id': 'a90f2222-e910-4100-84cf-d84bf27ad9a6',
        'schema_version': 2, // higher version than current v1
        'timestamp': 1781848900000,
        'type': 'chat_message',
        'server_sequence': 16,
        'payload': {'something': 'different'},
      };
      final envelope = RemoteRealtimeEnvelope.fromJson(json);
      expect(envelope.eventId, 'a90f2222-e910-4100-84cf-d84bf27ad9a6');
      expect(envelope.schemaVersion, 2);
      expect(envelope.isUnrecognized, true);
    });
  });

  group('Compatibility Fixtures Validation (P8-039)', () {
    test('loads and decodes rest_register_response.json', () {
      final data = RemoteCompatibilityFixtures.loadFixture(
        'rest_register_response.json',
      );
      expect(data['message'], 'Registration successful');
      expect(data['account_id'], 'acc_01h9w2m8g8qpr88v75v1w7jx8q');
      expect(data['device_id'], 'device1');
    });

    test('loads and decodes rest_login_response.json', () {
      final data = RemoteCompatibilityFixtures.loadFixture(
        'rest_login_response.json',
      );
      expect(data['message'], 'Login successful');
      expect(data['token'], isNotEmpty);
      expect(data['refresh_token'], isNotEmpty);
      expect(data.containsKey('access_token'), isFalse);
    });

    test('loads and decodes rest_prekey_bundle.json', () {
      final data = RemoteCompatibilityFixtures.loadFixture(
        'rest_prekey_bundle.json',
      );
      expect(data['account_id'], 'acc_01h9w2m8g8qpr88v75v1w7jx8q');
      final devices = data['devices'] as List<dynamic>;
      final device = devices.single as Map<String, dynamic>;
      expect(device['device_id'], 'device1');
      expect(device['identity_key'], isNotEmpty);
      expect(device['device_key'], isNotEmpty);
      expect(device['signed_prekey'], isA<Map<String, dynamic>>());
      expect(device['one_time_prekey'], isA<Map<String, dynamic>>());
    });

    test('loads and decodes realtime_chat_message.json', () {
      final data = RemoteCompatibilityFixtures.loadFixture(
        'realtime_chat_message.json',
      );
      _expectRealtimeEnvelopeShape(data);
      final envelope = RemoteRealtimeEnvelope.fromJson(data);
      expect(envelope.eventId, '469018e6-e910-4100-84cf-d84bf27ad9a6');
      expect(envelope.type, 'chat_message');
      expect(envelope.isUnrecognized, false);
      expect(
        envelope.payload['ciphertext'],
        'opaquebase64ciphertextbytesherefromdoubleratchetpayload',
      );
    });

    test(
      'loads, decodes, and gracefully degrades realtime_unknown_event.json',
      () {
        final data = RemoteCompatibilityFixtures.loadFixture(
          'realtime_unknown_event.json',
        );
        _expectRealtimeEnvelopeShape(data);
        final envelope = RemoteRealtimeEnvelope.fromJson(data);
        expect(envelope.eventId, 'a90f1111-e910-4100-84cf-d84bf27ad9a6');
        expect(envelope.type, 'new_unrecognized_type');
        expect(envelope.isUnrecognized, true);
      },
    );
  });
}

void _expectRealtimeEnvelopeShape(Map<String, dynamic> data) {
  expect(data['event_id'], isA<String>());
  expect(data['schema_version'], isA<int>());
  expect(data['timestamp'], isA<int>());
  expect(data['type'], isA<String>());
  expect(data['payload'], isA<Map<String, dynamic>>());
}
