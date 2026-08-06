import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:helix_remote/services/message_latency_tracer.dart';
import 'package:helix_remote/services/app_logger.dart';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:crypto/crypto.dart' as crypto_hash;
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote/app/remote_account_validation.dart';
import 'package:helix_remote_crypto/helix_remote_crypto.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';

part 'remote_messaging_service/contacts_privacy.dart';
part 'remote_messaging_service/conversations.dart';
part 'remote_messaging_service/core.dart';
part 'remote_messaging_service/history_receipts.dart';
part 'remote_messaging_service/message_crypto.dart';
part 'remote_messaging_service/message_decryption.dart';
part 'remote_messaging_service/message_event_location.dart';
part 'remote_messaging_service/message_sending.dart';
part 'remote_messaging_service/personalization.dart';
part 'remote_messaging_service/sync_outbox.dart';

abstract class RemoteMessageProtector {
  Future<String> encryptText({
    required String conversationId,
    required String messageId,
    required String plaintext,
    required String recipientDeviceId,
  });

  Future<String> decryptText({
    required String conversationId,
    required String messageId,
    required String ciphertext,
  });
}

class SecureSessionUnavailableException implements Exception {
  const SecureSessionUnavailableException(this.reason);

  final String reason;

  @override
  String toString() => 'SecureSessionUnavailableException: $reason';
}

class RemoteDecryptedMessage {
  const RemoteDecryptedMessage({
    required this.messageId,
    required this.conversationId,
    required this.senderAccountId,
    required this.senderDeviceId,
    required this.text,
    required this.status,
    required this.timestamp,
    this.reactions = const [],
    this.edited = false,
    this.attachment,
    this.media,
    this.poll,
    this.event,
    this.location,
    this.sticker,
    this.replyTo,
    this.expiresAt,
    this.retentionDeadline,
    this.viewOnce = false,
    this.viewOnceOpened = false,
    this.keepInChat = false,
    this.exportAllowed = true,
    this.externalSaveAllowed = true,
    this.forwardingAllowed = true,
  });

  final String messageId;
  final String conversationId;
  final String senderAccountId;
  final String senderDeviceId;
  final String text;
  final String status;
  final int timestamp;
  final List<String> reactions;
  final bool edited;
  final RemoteAttachmentContent? attachment;
  final RemoteMediaContent? media;
  final RemotePollContent? poll;
  final RemoteEventContent? event;
  final RemoteLocationContent? location;
  final RemoteStickerContent? sticker;
  final RemoteReplyReference? replyTo;
  final int? expiresAt;
  final int? retentionDeadline;
  final bool viewOnce;
  final bool viewOnceOpened;
  final bool keepInChat;
  final bool exportAllowed;
  final bool externalSaveAllowed;
  final bool forwardingAllowed;
}

class RemoteReactionDetail {
  const RemoteReactionDetail({
    required this.accountId,
    required this.reaction,
    required this.timestamp,
  });

  final String accountId;
  final String reaction;
  final int timestamp;
}

class RemotePushNotificationPreview {
  const RemotePushNotificationPreview({
    required this.conversationId,
    required this.title,
    required this.body,
  });

  final String conversationId;
  final String title;
  final String body;
}

class RemotePrivacySettings {
  const RemotePrivacySettings({
    required this.searchDiscoverable,
    required this.presenceVisibility,
    required this.lastSeenVisibility,
  });

  final bool searchDiscoverable;
  final String presenceVisibility;
  final String lastSeenVisibility;

  Map<String, dynamic> toJson() => {
    'search_discoverable': searchDiscoverable,
    'presence_visibility': presenceVisibility,
    'last_seen_visibility': lastSeenVisibility,
  };
}

class RemotePresenceSnapshot {
  const RemotePresenceSnapshot({
    required this.accountId,
    required this.visibility,
    this.lastSeenAt,
  });

  final String accountId;
  final String visibility;
  final int? lastSeenAt;
}

class RemoteOutboxSummary {
  const RemoteOutboxSummary({
    required this.queuedCount,
    required this.retryScheduledCount,
    required this.failedCount,
    this.nextRetryAt,
  });

  final int queuedCount;
  final int retryScheduledCount;
  final int failedCount;
  final DateTime? nextRetryAt;

  bool get hasVisibleWork =>
      queuedCount > 0 || retryScheduledCount > 0 || failedCount > 0;
}

abstract class RemoteMessagingServiceBase {
  HelixRemoteDatabase get db;
  RemoteSyncEngine get syncEngine;
  SyncGateway get gateway;
  RemoteMessageProtector get protector;
  HelixRemoteRestClient get restClient;
  DateTime Function() get _clock;
  StreamSubscription<RemoteSyncChange> get _syncChangeSub;
  StreamController<RemoteSyncChange> get _changeController;

  String? get _accountId;
  set _accountId(String? value);
  String? get _displayName;
  set _displayName(String? value);
  String? get _deviceId;
  set _deviceId(String? value);
  Uint8List? get _devicePrivateKey;
  set _devicePrivateKey(Uint8List? value);
  Uint8List? get _devicePublicKey;
  set _devicePublicKey(Uint8List? value);
  Future<Uint8List> Function(String privateKeyRef)? get _prekeyResolver;
  bool get _readReceiptsEnabled;
  set _readReceiptsEnabled(bool value);
  RemotePrivacySettings get _privacySettings;
  set _privacySettings(RemotePrivacySettings value);
  List<int> get _contactRequestTimestamps;

  void _emitChange(RemoteSyncChange change);
  String _requireAccountId();
  String _requireDeviceId();
  List<String> conversationMemberIds(String conversationId);
  Future<List<Map<String, dynamic>>> _buildX3dhEnvelopes({
    required String conversationId,
    required String messageId,
    required String plaintext,
    required List<String> recipientDeviceIds,
    required String senderAccountId,
    required String senderDeviceId,
  });
  Future<String> _decryptMessage({
    required String conversationId,
    required String messageId,
    required String ciphertext,
  });
}

class RemoteMessagingService extends RemoteMessagingServiceBase
    with
        RemoteMessagingCore,
        RemoteContactsPrivacy,
        RemoteConversationManagement,
        RemoteMessageSending,
        RemoteEventLocationSending,
        RemotePersonalization,
        RemoteMessageCrypto,
        RemoteMessageDecryption,
        RemoteSyncOutbox,
        RemoteHistoryReceipts {
  RemoteMessagingService({
    required this.db,
    required this.syncEngine,
    required this.gateway,
    required this.protector,
    required this.restClient,
    DateTime Function()? clock,
    Future<Uint8List> Function(String privateKeyRef)? prekeyResolver,
  }) : _clock = clock ?? DateTime.now,
       _prekeyResolver = prekeyResolver {
    _syncChangeSub = syncEngine.changes.listen(_emitChange);
  }

  @override
  final HelixRemoteDatabase db;
  @override
  final RemoteSyncEngine syncEngine;
  @override
  final SyncGateway gateway;
  @override
  final RemoteMessageProtector protector;
  @override
  final HelixRemoteRestClient restClient;
  @override
  final DateTime Function() _clock;
  @override
  late final StreamSubscription<RemoteSyncChange> _syncChangeSub;
  @override
  late final StreamController<RemoteSyncChange> _changeController =
      StreamController<RemoteSyncChange>.broadcast(
        onListen: () => _changeListenerCount++,
        onCancel: () => _changeListenerCount--,
      );
  int _changeListenerCount = 0;

  int get debugChangeListenerCount => _changeListenerCount;

  @override
  String? _accountId;
  @override
  String? _displayName;
  @override
  String? _deviceId;

  @override
  Uint8List? _devicePrivateKey;
  @override
  Uint8List? _devicePublicKey;
  @override
  final Future<Uint8List> Function(String privateKeyRef)? _prekeyResolver;

  @override
  bool _readReceiptsEnabled = true;
  @override
  RemotePrivacySettings _privacySettings = const RemotePrivacySettings(
    searchDiscoverable: true,
    presenceVisibility: 'CONTACTS',
    lastSeenVisibility: 'CONTACTS',
  );
  @override
  final List<int> _contactRequestTimestamps = [];
}
