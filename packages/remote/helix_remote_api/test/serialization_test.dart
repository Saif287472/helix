import 'package:test/test.dart';
import 'package:helix_remote_api/api.dart';
import 'package:helix_remote_domain/models.dart';

void main() {
  group('Remote Domain Models Serialization', () {
    test('RemoteAccount fromJson and toJson', () {
      final json = {
        'account_id': 'acc_123',
        'username': 'alice',
        'identity_public_key': 'hexkey',
        'created_at': '2026-06-19T06:00:00.000Z',
        'status': 'Active',
      };
      final account = RemoteAccount.fromJson(json);
      expect(account.accountId, 'acc_123');
      expect(account.username, 'alice');
      expect(account.createdAt, DateTime.utc(2026, 6, 19, 6, 0, 0));
      expect(account.toJson()['account_id'], 'acc_123');
    });

    test('RemoteDevice fromJson and toJson', () {
      final json = {
        'device_id': 2,
        'device_name': 'My Laptop',
        'device_public_key': 'pubkey',
        'created_at': '2026-06-19T06:00:00.000Z',
        'status': 'Active',
      };
      final device = RemoteDevice.fromJson(json);
      expect(device.deviceId, 2);
      expect(device.deviceName, 'My Laptop');
      expect(device.toJson()['device_id'], 2);
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
        'sender_device_id': 1,
        'ciphertext': 'encrypted_stuff',
      };
      final msg = RemoteMessage.fromJson(json);
      expect(msg.messageId, 'msg_1');
      expect(msg.senderDeviceId, 1);
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
      final json = {
        'conversation_id': 'conv_1',
        'last_server_sequence': 100,
      };
      final cursor = RemoteSyncCursor.fromJson(json);
      expect(cursor.conversationId, 'conv_1');
      expect(cursor.lastServerSequence, 100);
      expect(cursor.toJson()['last_server_sequence'], 100);
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
          'sender_device_id': 1,
          'ciphertext': 'opaquebase64ciphertextbytes',
          'message_id': 'msg_01h9w2m8g8qpr88v75v1w7jx8q'
        }
      };
      final envelope = RemoteRealtimeEnvelope.fromJson(json);
      expect(envelope.eventId, '469018e6-e910-4100-84cf-d84bf27ad9a6');
      expect(envelope.schemaVersion, 1);
      expect(envelope.serverSequence, 14);
      expect(envelope.type, 'chat_message');
      expect(envelope.isUnrecognized, false);
      expect(envelope.payload['conversation_id'], '8c59f0f9-a35c-41fb-992a-3023e3e29f8f');
    });

    test('Graceful degradation on Unrecognized Event Type (P8-042)', () {
      final json = {
        'event_id': 'a90f1111-e910-4100-84cf-d84bf27ad9a6',
        'schema_version': 1,
        'timestamp': 1781848900000,
        'type': 'future_event_type',
        'server_sequence': 15,
        'payload': {
          'some_data': 'goes here'
        }
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
        'payload': {
          'something': 'different'
        }
      };
      final envelope = RemoteRealtimeEnvelope.fromJson(json);
      expect(envelope.eventId, 'a90f2222-e910-4100-84cf-d84bf27ad9a6');
      expect(envelope.schemaVersion, 2);
      expect(envelope.isUnrecognized, true);
    });
  });

  group('Compatibility Fixtures Validation (P8-039)', () {
    test('loads and decodes rest_register_response.json', () {
      final data = RemoteCompatibilityFixtures.loadFixture('rest_register_response.json');
      expect(data['account_id'], 'acc_01h9w2m8g8qpr88v75v1w7jx8q');
      expect(data['created_at'], '2026-06-19T06:00:00Z');
    });

    test('loads and decodes rest_login_response.json', () {
      final data = RemoteCompatibilityFixtures.loadFixture('rest_login_response.json');
      expect(data['device_id'], 1);
      expect(data['access_token'], isNotEmpty);
    });

    test('loads and decodes rest_prekey_bundle.json', () {
      final data = RemoteCompatibilityFixtures.loadFixture('rest_prekey_bundle.json');
      expect(data['account_id'], 'acc_01h9w2m8g8qpr88v75v1w7jx8q');
      expect(data['device_id'], 1);
      expect(data['identity_key'], isNotEmpty);
      expect(data['signed_prekey'], isNotEmpty);
    });

    test('loads and decodes realtime_chat_message.json', () {
      final data = RemoteCompatibilityFixtures.loadFixture('realtime_chat_message.json');
      final envelope = RemoteRealtimeEnvelope.fromJson(data);
      expect(envelope.eventId, '469018e6-e910-4100-84cf-d84bf27ad9a6');
      expect(envelope.type, 'chat_message');
      expect(envelope.isUnrecognized, false);
      expect(envelope.payload['ciphertext'], 'opaquebase64ciphertextbytesherefromdoubleratchetpayload');
    });

    test('loads, decodes, and gracefully degrades realtime_unknown_event.json', () {
      final data = RemoteCompatibilityFixtures.loadFixture('realtime_unknown_event.json');
      final envelope = RemoteRealtimeEnvelope.fromJson(data);
      expect(envelope.eventId, 'a90f1111-e910-4100-84cf-d84bf27ad9a6');
      expect(envelope.type, 'new_unrecognized_type');
      expect(envelope.isUnrecognized, true);
    });
  });
}
