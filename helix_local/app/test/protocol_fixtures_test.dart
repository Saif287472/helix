import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';

void main() {
  test('protocol v$kProtocolMajor.$kProtocolMinor fixtures decode', () {
    final file = File(
      'test/fixtures/protocol/v$kProtocolMajor.$kProtocolMinor/frames.json',
    );
    expect(file.existsSync(), isTrue);

    final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(root['protocolMajor'], kProtocolMajor);
    expect(root['protocolMinor'], kProtocolMinor);
    expect(root['wireFormat'], 'legacy-cbor-payload');

    final fixtures = root['fixtures'] as List<dynamic>;
    expect(fixtures, hasLength(_expectedTypes.length));

    for (final item in fixtures.cast<Map<String, dynamic>>()) {
      final name = item['name'] as String;
      final expectedType = _expectedTypes[name];
      expect(expectedType, isNotNull, reason: 'Unexpected fixture $name');

      final payload = base64.decode(item['payloadBase64'] as String);
      final decoded = ProtocolFrame.decode(payload);
      expect(decoded.type, expectedType, reason: 'Fixture $name type drifted');
    }
  });
}

const _expectedTypes = <String, int>{
  'request': kTypeRequest,
  'accept': kTypeAccept,
  'reject': kTypeReject,
  'cancel': kTypeCancel,
  'identity': kTypeIdentity,
  'identity_ack': kTypeIdentityAck,
  'capability': kTypeCapability,
  'chat_message': kTypeChatMessage,
  'chat_ack': kTypeChatAck,
  'keepalive': kTypeKeepalive,
  'close': kTypeClose,
  'profile_update': kTypeProfileUpdate,
  'busy': kTypeBusy,
  'version_mismatch': kTypeVersionMismatch,
  'typing_indicator': kTypeTypingIndicator,
  'read_receipt': kTypeReadReceipt,
  'reaction': kTypeReaction,
  'file_transfer': kTypeFileTransfer,
  'edit_message': kTypeEditMessage,
  'delete_message': kTypeDeleteMessage,
  'wipe': kTypeWipe,
  'file_probe': kTypeFileProbe,
  'file_resume': kTypeFileResume,
  'file_complete': kTypeFileComplete,
  'file_cancel': kTypeFileCancel,
  'ephemeral_media': kTypeEphemeralMedia,
  'group_control': kTypeGroupControl,
  'group_message': kTypeGroupMessage,
};
