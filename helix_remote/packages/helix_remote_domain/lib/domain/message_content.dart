import 'dart:convert';
import 'dart:isolate';

import 'package:helix_remote_domain/domain/attachment.dart';
import 'package:helix_remote_domain/domain/capabilities.dart';

class RemoteMessageContentEnvelope {
  const RemoteMessageContentEnvelope({
    required this.contentType,
    required this.contentVersion,
    required this.payload,
  });

  static const envelopeType = RemoteCapability.contentEnvelopeV1;
  static const envelopeVersion = 1;

  final String contentType;
  final int contentVersion;
  final Map<String, dynamic> payload;

  String encode() {
    return jsonEncode({
      'type': envelopeType,
      'version': envelopeVersion,
      'content_type': contentType,
      'content_version': contentVersion,
      'payload': payload,
    });
  }

  static Future<RemoteMessageContentEnvelope?> tryDecode(
    String plaintext,
  ) async {
    try {
      final decoded = await Isolate.run(() => jsonDecode(plaintext));
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['type'] != envelopeType || decoded['version'] != 1) {
        return null;
      }
      final contentType = decoded['content_type'];
      final contentVersion = decoded['content_version'];
      final payload = decoded['payload'];
      if (contentType is! String ||
          contentVersion is! int ||
          payload is! Map<String, dynamic>) {
        return null;
      }
      return RemoteMessageContentEnvelope(
        contentType: contentType,
        contentVersion: contentVersion,
        payload: payload,
      );
    } catch (_) {
      return null;
    }
  }
}

class RemoteContentPrivacy {
  const RemoteContentPrivacy({
    this.expiresAt,
    this.deliveryRetentionDeadline,
    this.viewOnce = false,
    this.keepInChat = false,
    this.exportAllowed = true,
    this.externalSaveAllowed = true,
    this.forwardingAllowed = true,
    this.automaticMediaSaveAllowed = true,
    this.aiProcessingAllowed = false,
  });

  final int? expiresAt;
  final int? deliveryRetentionDeadline;
  final bool viewOnce;
  final bool keepInChat;
  final bool exportAllowed;
  final bool externalSaveAllowed;
  final bool forwardingAllowed;
  final bool automaticMediaSaveAllowed;
  final bool aiProcessingAllowed;

  bool get hasPolicy =>
      expiresAt != null ||
      deliveryRetentionDeadline != null ||
      viewOnce ||
      keepInChat ||
      !exportAllowed ||
      !externalSaveAllowed ||
      !forwardingAllowed ||
      !automaticMediaSaveAllowed ||
      aiProcessingAllowed;

  Map<String, dynamic> toJson() => {
    if (expiresAt != null) 'expires_at': expiresAt,
    if (deliveryRetentionDeadline != null)
      'delivery_retention_deadline': deliveryRetentionDeadline,
    'view_once': viewOnce,
    'keep_in_chat': keepInChat,
    'export_allowed': exportAllowed,
    'external_save_allowed': externalSaveAllowed,
    'forwarding_allowed': forwardingAllowed,
    'automatic_media_save_allowed': automaticMediaSaveAllowed,
    'ai_processing_allowed': aiProcessingAllowed,
  };

  static RemoteContentPrivacy? tryParse(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    return RemoteContentPrivacy(
      expiresAt: value['expires_at'] as int?,
      deliveryRetentionDeadline: value['delivery_retention_deadline'] as int?,
      viewOnce: value['view_once'] as bool? ?? false,
      keepInChat: value['keep_in_chat'] as bool? ?? false,
      exportAllowed: value['export_allowed'] as bool? ?? true,
      externalSaveAllowed: value['external_save_allowed'] as bool? ?? true,
      forwardingAllowed: value['forwarding_allowed'] as bool? ?? true,
      automaticMediaSaveAllowed:
          value['automatic_media_save_allowed'] as bool? ?? true,
      aiProcessingAllowed: value['ai_processing_allowed'] as bool? ?? false,
    );
  }
}

class RemoteReplyReference {
  const RemoteReplyReference({
    required this.messageId,
    required this.senderAccountId,
    required this.snippet,
  });

  final String messageId;
  final String senderAccountId;
  final String snippet;

  Map<String, dynamic> toJson() => {
    'message_id': messageId,
    'sender_account_id': senderAccountId,
    'snippet': snippet,
  };

  static RemoteReplyReference? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final messageId = json['message_id'];
    final senderAccountId = json['sender_account_id'];
    final snippet = json['snippet'];
    if (messageId is! String ||
        senderAccountId is! String ||
        snippet is! String) {
      return null;
    }
    return RemoteReplyReference(
      messageId: messageId,
      senderAccountId: senderAccountId,
      snippet: snippet,
    );
  }
}

class RemoteTextContent {
  const RemoteTextContent({required this.text, this.replyTo, this.privacy});

  static const messageType = RemoteCapability.contentTextV1;

  final String text;
  final RemoteReplyReference? replyTo;
  final RemoteContentPrivacy? privacy;

  String toPlaintext() {
    return RemoteMessageContentEnvelope(
      contentType: messageType,
      contentVersion: 1,
      payload: {
        'text': text,
        if (replyTo != null) 'reply_to': replyTo!.toJson(),
        if (privacy != null && privacy!.hasPolicy) 'privacy': privacy!.toJson(),
      },
    ).encode();
  }

  /// Parse from an already-decoded envelope. Returns null when the envelope
  /// does not carry text content; callers should fall back to treating the
  /// raw plaintext as the message text.
  static RemoteTextContent? fromEnvelope(
    RemoteMessageContentEnvelope envelope,
  ) {
    if (envelope.contentType != messageType) return null;
    final text = envelope.payload['text'];
    if (text is! String) return null;
    return RemoteTextContent(
      text: text,
      replyTo: RemoteReplyReference.tryParse(envelope.payload['reply_to']),
      privacy: RemoteContentPrivacy.tryParse(envelope.payload['privacy']),
    );
  }

  static Future<RemoteTextContent> parse(String plaintext) async {
    final envelope = await RemoteMessageContentEnvelope.tryDecode(plaintext);
    if (envelope != null && envelope.contentType == messageType) {
      return fromEnvelope(envelope) ?? RemoteTextContent(text: plaintext);
    }

    try {
      final decoded = await Isolate.run(() => jsonDecode(plaintext));
      if (decoded is! Map<String, dynamic>) {
        return RemoteTextContent(text: plaintext);
      }
      if (decoded['type'] != messageType &&
          decoded['type'] != 'helix.remote.text.v1') {
        return RemoteTextContent(text: plaintext);
      }
      final text = decoded['text'];
      if (text is! String) return RemoteTextContent(text: plaintext);
      return RemoteTextContent(
        text: text,
        replyTo: RemoteReplyReference.tryParse(decoded['reply_to']),
        privacy: RemoteContentPrivacy.tryParse(decoded['privacy']),
      );
    } catch (_) {
      return RemoteTextContent(text: plaintext);
    }
  }
}

class RemoteAttachmentContent {
  const RemoteAttachmentContent({
    required this.fileId,
    required this.filename,
    required this.fileSize,
    required this.fileHash,
    required this.mimeType,
    required this.keyDeliverySecret,
    this.thumbnailFileId,
    this.thumbnailFileSize,
    this.thumbnailFileHash,
    this.localStatus,
    this.localPath,
    this.privacy,
  });

  static const messageType = RemoteCapability.contentAttachmentV1;
  static const legacyMessageType = 'helix.remote.attachment.v1';

  final String fileId;
  final String filename;
  final int fileSize;
  final String fileHash;
  final String mimeType;
  final String keyDeliverySecret;
  final String? thumbnailFileId;
  final int? thumbnailFileSize;
  final String? thumbnailFileHash;
  final String? localStatus;
  final String? localPath;
  final RemoteContentPrivacy? privacy;

  String get displayText => privacy?.viewOnce == true
      ? 'View once attachment'
      : localStatus == 'MEDIA_CLEARED'
      ? 'Attachment unavailable'
      : 'Attachment: $filename';

  RemoteAttachmentManifest get manifest => RemoteAttachmentManifest(
    fileId: fileId,
    fileSize: fileSize,
    fileHash: fileHash,
    mimeType: mimeType,
    thumbnailFileId: thumbnailFileId,
    thumbnailFileSize: thumbnailFileSize,
    thumbnailFileHash: thumbnailFileHash,
  );

  String toPlaintext() {
    return RemoteMessageContentEnvelope(
      contentType: messageType,
      contentVersion: 1,
      payload: _payload(),
    ).encode();
  }

  Map<String, dynamic> toMessageJson() => {
    'type': legacyMessageType,
    'version': 1,
    ..._payload(),
  };

  Map<String, dynamic> _payload() => {
    'filename': filename,
    'manifest': manifest.toJson(),
    'key_delivery': {
      'scheme': 'x3dh-message-envelope',
      'secret': keyDeliverySecret,
    },
    if (privacy != null && privacy!.hasPolicy) 'privacy': privacy!.toJson(),
  };

  RemoteAttachmentContent withLocalState({
    required String? status,
    required String? path,
  }) {
    return RemoteAttachmentContent(
      fileId: fileId,
      filename: filename,
      fileSize: fileSize,
      fileHash: fileHash,
      mimeType: mimeType,
      keyDeliverySecret: keyDeliverySecret,
      thumbnailFileId: thumbnailFileId,
      thumbnailFileSize: thumbnailFileSize,
      thumbnailFileHash: thumbnailFileHash,
      localStatus: status,
      localPath: path,
      privacy: privacy,
    );
  }

  /// Parse from an already-decoded envelope (no legacy JSON fallback).
  static RemoteAttachmentContent? fromEnvelope(
    RemoteMessageContentEnvelope envelope,
  ) {
    if (envelope.contentType != messageType) return null;
    return _fromPayload(envelope.payload);
  }

  static Future<RemoteAttachmentContent?> tryParse(String plaintext) async {
    final envelope = await RemoteMessageContentEnvelope.tryDecode(plaintext);
    if (envelope != null && envelope.contentType == messageType) {
      return _fromPayload(envelope.payload);
    }

    try {
      final decoded = await Isolate.run(() => jsonDecode(plaintext));
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['type'] != legacyMessageType &&
          decoded['type'] != messageType) {
        return null;
      }
      return _fromPayload(decoded);
    } catch (_) {
      return null;
    }
  }

  static RemoteAttachmentContent? _fromPayload(Map<String, dynamic> payload) {
    try {
      final manifest = RemoteAttachmentManifest.fromJson(
        payload['manifest'] as Map<String, dynamic>,
      );
      final keyDelivery = payload['key_delivery'] as Map<String, dynamic>;
      return RemoteAttachmentContent(
        fileId: manifest.fileId,
        filename: payload['filename'] as String,
        fileSize: manifest.fileSize,
        fileHash: manifest.fileHash,
        mimeType: manifest.mimeType,
        keyDeliverySecret: keyDelivery['secret'] as String,
        thumbnailFileId: manifest.thumbnailFileId,
        thumbnailFileSize: manifest.thumbnailFileSize,
        thumbnailFileHash: manifest.thumbnailFileHash,
        privacy: RemoteContentPrivacy.tryParse(payload['privacy']),
      );
    } catch (_) {
      return null;
    }
  }
}

class RemoteMediaContent {
  const RemoteMediaContent({
    required this.kind,
    required this.attachment,
    this.caption = '',
    this.durationMs,
    this.waveform = const [],
    this.items = const [],
    this.privacy,
  });

  static const voiceNoteKind = 'voice_note';
  static const instantVideoKind = 'instant_video_note';
  static const imageKind = 'image';
  static const videoKind = 'video';
  static const documentKind = 'document';
  static const livePhotoKind = 'live_photo';
  static const scannerDocumentKind = 'scanner_document';
  static const cameraCaptureKind = 'camera_capture';
  static const collectionKind = 'media_collection';

  final String kind;
  final RemoteAttachmentContent attachment;
  final String caption;
  final int? durationMs;
  final List<int> waveform;
  final List<RemoteMediaCollectionItem> items;
  final RemoteContentPrivacy? privacy;

  String get displayText {
    if (caption.trim().isNotEmpty) return caption.trim();
    switch (kind) {
      case voiceNoteKind:
        return 'Voice note';
      case instantVideoKind:
        return 'Video note';
      case collectionKind:
        return 'Media collection (${items.length + 1})';
      case scannerDocumentKind:
        return 'Scanned document';
      case cameraCaptureKind:
        return 'Camera capture';
      case livePhotoKind:
        return 'Live Photo';
      default:
        return attachment.displayText;
    }
  }

  String get contentType {
    switch (kind) {
      case voiceNoteKind:
        return RemoteCapability.contentVoiceNoteV1;
      case instantVideoKind:
        return RemoteCapability.contentInstantVideoV1;
      case collectionKind:
        return RemoteCapability.contentMediaCollectionV1;
      default:
        return RemoteCapability.contentMediaWithCaptionV1;
    }
  }

  String toPlaintext() {
    return RemoteMessageContentEnvelope(
      contentType: contentType,
      contentVersion: 1,
      payload: _payload(),
    ).encode();
  }

  Map<String, dynamic> _payload() => {
    'kind': kind,
    'attachment': attachment._payload(),
    if (caption.trim().isNotEmpty) 'caption': caption.trim(),
    if (durationMs != null) 'duration_ms': durationMs,
    if (waveform.isNotEmpty) 'waveform': waveform,
    if (items.isNotEmpty) 'items': items.map((item) => item.toJson()).toList(),
    if (privacy != null && privacy!.hasPolicy) 'privacy': privacy!.toJson(),
  };

  static Future<RemoteMediaContent?> tryParse(String plaintext) async {
    final envelope = await RemoteMessageContentEnvelope.tryDecode(plaintext);
    if (envelope == null) return null;
    return fromEnvelope(envelope);
  }

  /// Parse from an already-decoded envelope.
  static RemoteMediaContent? fromEnvelope(
    RemoteMessageContentEnvelope envelope,
  ) {
    if (!{
      RemoteCapability.contentVoiceNoteV1,
      RemoteCapability.contentInstantVideoV1,
      RemoteCapability.contentMediaWithCaptionV1,
      RemoteCapability.contentMediaCollectionV1,
    }.contains(envelope.contentType)) {
      return null;
    }
    try {
      final payload = envelope.payload;
      final attachment = RemoteAttachmentContent._fromPayload(
        payload['attachment'] as Map<String, dynamic>,
      );
      if (attachment == null) return null;
      final rawItems = payload['items'];
      return RemoteMediaContent(
        kind: payload['kind'] as String,
        attachment: attachment,
        caption: payload['caption'] as String? ?? '',
        durationMs: payload['duration_ms'] as int?,
        waveform: (payload['waveform'] as List? ?? const [])
            .whereType<int>()
            .toList(),
        items: rawItems is List
            ? rawItems
                  .map(RemoteMediaCollectionItem.tryParse)
                  .whereType<RemoteMediaCollectionItem>()
                  .toList()
            : const [],
        privacy: RemoteContentPrivacy.tryParse(payload['privacy']),
      );
    } catch (_) {
      return null;
    }
  }
}

class RemoteMediaCollectionItem {
  const RemoteMediaCollectionItem({
    required this.kind,
    required this.attachment,
    this.caption = '',
    this.durationMs,
    this.waveform = const [],
  });

  final String kind;
  final RemoteAttachmentContent attachment;
  final String caption;
  final int? durationMs;
  final List<int> waveform;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'attachment': attachment._payload(),
    if (caption.trim().isNotEmpty) 'caption': caption.trim(),
    if (durationMs != null) 'duration_ms': durationMs,
    if (waveform.isNotEmpty) 'waveform': waveform,
  };

  static RemoteMediaCollectionItem? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final attachment = RemoteAttachmentContent._fromPayload(
      json['attachment'] as Map<String, dynamic>,
    );
    if (attachment == null) return null;
    return RemoteMediaCollectionItem(
      kind: json['kind'] as String,
      attachment: attachment,
      caption: json['caption'] as String? ?? '',
      durationMs: json['duration_ms'] as int?,
      waveform: (json['waveform'] as List? ?? const [])
          .whereType<int>()
          .toList(),
    );
  }
}

class RemotePollOption {
  const RemotePollOption({required this.optionId, required this.text});

  final String optionId;
  final String text;

  Map<String, dynamic> toJson() => {'option_id': optionId, 'text': text};

  static RemotePollOption? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['option_id'];
    final text = json['text'];
    if (id is! String || text is! String) return null;
    return RemotePollOption(optionId: id, text: text);
  }
}

class RemotePollContent {
  const RemotePollContent({
    required this.pollId,
    required this.question,
    required this.options,
    required this.creatorAccountId,
    required this.createdAt,
    this.allowMultipleVotes = false,
    this.closedAt,
  });

  static const messageType = RemoteCapability.contentPollV1;

  final String pollId;
  final String question;
  final List<RemotePollOption> options;
  final String creatorAccountId;
  final int createdAt;
  final bool allowMultipleVotes;
  final int? closedAt;

  bool get isClosed => closedAt != null && closedAt! > 0;

  String toPlaintext() => RemoteMessageContentEnvelope(
    contentType: messageType,
    contentVersion: 1,
    payload: {
      'poll_id': pollId,
      'question': question,
      'options': options.map((option) => option.toJson()).toList(),
      'creator_account_id': creatorAccountId,
      'created_at': createdAt,
      'allow_multiple_votes': allowMultipleVotes,
      if (closedAt != null) 'closed_at': closedAt,
    },
  ).encode();

  static Future<RemotePollContent?> tryParse(String plaintext) async {
    final envelope = await RemoteMessageContentEnvelope.tryDecode(plaintext);
    if (envelope == null) return null;
    return fromEnvelope(envelope);
  }

  /// Parse from an already-decoded envelope.
  static RemotePollContent? fromEnvelope(
    RemoteMessageContentEnvelope envelope,
  ) {
    if (envelope.contentType != messageType) return null;
    try {
      final options = (envelope.payload['options'] as List)
          .map(RemotePollOption.tryParse)
          .whereType<RemotePollOption>()
          .toList();
      return RemotePollContent(
        pollId: envelope.payload['poll_id'] as String,
        question: envelope.payload['question'] as String,
        options: options,
        creatorAccountId: envelope.payload['creator_account_id'] as String,
        createdAt: envelope.payload['created_at'] as int,
        allowMultipleVotes:
            envelope.payload['allow_multiple_votes'] as bool? ?? false,
        closedAt: envelope.payload['closed_at'] as int?,
      );
    } catch (_) {
      return null;
    }
  }
}

class RemoteEventContent {
  const RemoteEventContent({
    required this.eventId,
    required this.title,
    required this.creatorAccountId,
    required this.startsAt,
    required this.timeZone,
    this.endsAt,
    this.locationText = '',
    this.plusOneAllowed = false,
    this.pinned = false,
    this.attendeeListPrivate = true,
    this.cancelledAt,
  });

  static const messageType = RemoteCapability.contentEventV1;

  final String eventId;
  final String title;
  final String creatorAccountId;
  final int startsAt;
  final int? endsAt;
  final String timeZone;
  final String locationText;
  final bool plusOneAllowed;
  final bool pinned;
  final bool attendeeListPrivate;
  final int? cancelledAt;

  bool get isCancelled => cancelledAt != null && cancelledAt! > 0;

  String toPlaintext() => RemoteMessageContentEnvelope(
    contentType: messageType,
    contentVersion: 1,
    payload: {
      'event_id': eventId,
      'title': title,
      'creator_account_id': creatorAccountId,
      'starts_at': startsAt,
      if (endsAt != null) 'ends_at': endsAt,
      'time_zone': timeZone,
      if (locationText.isNotEmpty) 'location_text': locationText,
      'plus_one_allowed': plusOneAllowed,
      'pinned': pinned,
      'attendee_list_private': attendeeListPrivate,
      if (cancelledAt != null) 'cancelled_at': cancelledAt,
    },
  ).encode();

  static Future<RemoteEventContent?> tryParse(String plaintext) async {
    final envelope = await RemoteMessageContentEnvelope.tryDecode(plaintext);
    if (envelope == null) return null;
    return fromEnvelope(envelope);
  }

  /// Parse from an already-decoded envelope.
  static RemoteEventContent? fromEnvelope(
    RemoteMessageContentEnvelope envelope,
  ) {
    if (envelope.contentType != messageType) return null;
    try {
      return RemoteEventContent(
        eventId: envelope.payload['event_id'] as String,
        title: envelope.payload['title'] as String,
        creatorAccountId: envelope.payload['creator_account_id'] as String,
        startsAt: envelope.payload['starts_at'] as int,
        endsAt: envelope.payload['ends_at'] as int?,
        timeZone: envelope.payload['time_zone'] as String,
        locationText: envelope.payload['location_text'] as String? ?? '',
        plusOneAllowed: envelope.payload['plus_one_allowed'] as bool? ?? false,
        pinned: envelope.payload['pinned'] as bool? ?? false,
        attendeeListPrivate:
            envelope.payload['attendee_list_private'] as bool? ?? true,
        cancelledAt: envelope.payload['cancelled_at'] as int?,
      );
    } catch (_) {
      return null;
    }
  }
}

class RemoteLocationContent {
  const RemoteLocationContent({
    required this.locationId,
    required this.latitudeE7,
    required this.longitudeE7,
    required this.accuracyMeters,
    required this.createdAt,
    this.label = '',
    this.live = false,
    this.expiresAt,
    this.stoppedAt,
  });

  static const messageType = RemoteCapability.contentLocationV1;

  final String locationId;
  final int latitudeE7;
  final int longitudeE7;
  final int accuracyMeters;
  final int createdAt;
  final String label;
  final bool live;
  final int? expiresAt;
  final int? stoppedAt;

  bool get isExpiredOrStopped =>
      (stoppedAt != null && stoppedAt! > 0) ||
      (expiresAt != null &&
          expiresAt! <= DateTime.now().millisecondsSinceEpoch);

  String toPlaintext() => RemoteMessageContentEnvelope(
    contentType: messageType,
    contentVersion: 1,
    payload: {
      'location_id': locationId,
      'latitude_e7': latitudeE7,
      'longitude_e7': longitudeE7,
      'accuracy_meters': accuracyMeters,
      'created_at': createdAt,
      if (label.isNotEmpty) 'label': label,
      'live': live,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (stoppedAt != null) 'stopped_at': stoppedAt,
    },
  ).encode();

  static Future<RemoteLocationContent?> tryParse(String plaintext) async {
    final envelope = await RemoteMessageContentEnvelope.tryDecode(plaintext);
    if (envelope == null) return null;
    return fromEnvelope(envelope);
  }

  /// Parse from an already-decoded envelope.
  static RemoteLocationContent? fromEnvelope(
    RemoteMessageContentEnvelope envelope,
  ) {
    if (envelope.contentType != messageType) return null;
    try {
      return RemoteLocationContent(
        locationId: envelope.payload['location_id'] as String,
        latitudeE7: envelope.payload['latitude_e7'] as int,
        longitudeE7: envelope.payload['longitude_e7'] as int,
        accuracyMeters: envelope.payload['accuracy_meters'] as int,
        createdAt: envelope.payload['created_at'] as int,
        label: envelope.payload['label'] as String? ?? '',
        live: envelope.payload['live'] as bool? ?? false,
        expiresAt: envelope.payload['expires_at'] as int?,
        stoppedAt: envelope.payload['stopped_at'] as int?,
      );
    } catch (_) {
      return null;
    }
  }
}

class RemoteStickerContent {
  const RemoteStickerContent({
    required this.stickerId,
    required this.packId,
    required this.kind,
    required this.attachment,
    this.altText = '',
    this.emoji = '',
  });

  static const messageType = RemoteCapability.contentStickerV1;

  final String stickerId;
  final String packId;
  final String kind;
  final RemoteAttachmentContent attachment;
  final String altText;
  final String emoji;

  String get displayText => emoji.isEmpty ? 'Sticker' : 'Sticker $emoji';

  String toPlaintext() => RemoteMessageContentEnvelope(
    contentType: messageType,
    contentVersion: 1,
    payload: {
      'sticker_id': stickerId,
      'pack_id': packId,
      'kind': kind,
      'attachment': attachment._payload(),
      if (altText.isNotEmpty) 'alt_text': altText,
      if (emoji.isNotEmpty) 'emoji': emoji,
    },
  ).encode();

  static Future<RemoteStickerContent?> tryParse(String plaintext) async {
    final envelope = await RemoteMessageContentEnvelope.tryDecode(plaintext);
    if (envelope == null) return null;
    return fromEnvelope(envelope);
  }

  /// Parse from an already-decoded envelope.
  static RemoteStickerContent? fromEnvelope(
    RemoteMessageContentEnvelope envelope,
  ) {
    if (envelope.contentType != messageType) return null;
    try {
      final attachment = RemoteAttachmentContent._fromPayload(
        envelope.payload['attachment'] as Map<String, dynamic>,
      );
      if (attachment == null) return null;
      return RemoteStickerContent(
        stickerId: envelope.payload['sticker_id'] as String,
        packId: envelope.payload['pack_id'] as String,
        kind: envelope.payload['kind'] as String,
        attachment: attachment,
        altText: envelope.payload['alt_text'] as String? ?? '',
        emoji: envelope.payload['emoji'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
