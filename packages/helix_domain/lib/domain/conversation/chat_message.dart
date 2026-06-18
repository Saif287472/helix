import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Message
// ---------------------------------------------------------------------------

enum MessageDeliveryStatus { sending, delivered, read, failed, disconnected }

enum MessageOrigin { local, remote }

/// A single message reaction (emoji reacted by one origin).
@immutable
class MessageReaction {
  final String emoji;
  final MessageOrigin origin;

  const MessageReaction({required this.emoji, required this.origin});
}

@immutable
class ChatMessage {
  final String messageId;
  final String threadId;
  final MessageOrigin origin;
  final String text;
  final DateTime timestamp;
  final MessageDeliveryStatus deliveryStatus;

  /// True for synthetic in-thread status messages.
  final bool isSystem;

  // -- Reply threading --
  final String? replyToMessageId;

  // -- Edit / delete --
  final DateTime? editedAt;
  final bool isDeleted;

  // -- File attachment --
  final String? fileId;
  final String? fileName;
  final String? mimeType;
  final int? fileSize;
  final String? localFilePath;

  /// True for RAM-only private media (never written to disk).
  final bool isEphemeral;

  /// 0.0–1.0 while transfer is in progress; null when idle or complete.
  final double? transferProgress;

  // -- Reactions: emoji → set of origins --
  final Map<String, Set<MessageOrigin>> reactions;

  bool get isFile => fileId != null;
  bool get isImage => mimeType?.startsWith('image/') ?? false;
  bool get hasReactions => reactions.isNotEmpty;

  const ChatMessage({
    required this.messageId,
    required this.threadId,
    required this.origin,
    required this.text,
    required this.timestamp,
    required this.deliveryStatus,
    this.isSystem = false,
    this.replyToMessageId,
    this.editedAt,
    this.isDeleted = false,
    this.fileId,
    this.fileName,
    this.mimeType,
    this.fileSize,
    this.localFilePath,
    this.isEphemeral = false,
    this.transferProgress,
    this.reactions = const {},
  });

  ChatMessage copyWith({
    MessageDeliveryStatus? deliveryStatus,
    bool? isSystem,
    DateTime? editedAt,
    bool? isDeleted,
    String? localFilePath,
    bool? isEphemeral,
    double? transferProgress,
    bool clearTransferProgress = false,
    Map<String, Set<MessageOrigin>>? reactions,
  }) => ChatMessage(
    messageId: messageId,
    threadId: threadId,
    origin: origin,
    text: text,
    timestamp: timestamp,
    deliveryStatus: deliveryStatus ?? this.deliveryStatus,
    isSystem: isSystem ?? this.isSystem,
    replyToMessageId: replyToMessageId,
    editedAt: editedAt ?? this.editedAt,
    isDeleted: isDeleted ?? this.isDeleted,
    fileId: fileId,
    fileName: fileName,
    mimeType: mimeType,
    fileSize: fileSize,
    localFilePath: localFilePath ?? this.localFilePath,
    isEphemeral: isEphemeral ?? this.isEphemeral,
    transferProgress: clearTransferProgress
        ? null
        : (transferProgress ?? this.transferProgress),
    reactions: reactions ?? this.reactions,
  );

  /// Returns a new ChatMessage with text replaced and editedAt set.
  ChatMessage withEdit(String newText) => ChatMessage(
    messageId: messageId,
    threadId: threadId,
    origin: origin,
    text: newText,
    timestamp: timestamp,
    deliveryStatus: deliveryStatus,
    isSystem: isSystem,
    replyToMessageId: replyToMessageId,
    editedAt: DateTime.now(),
    isDeleted: isDeleted,
    fileId: fileId,
    fileName: fileName,
    mimeType: mimeType,
    fileSize: fileSize,
    localFilePath: localFilePath,
    isEphemeral: isEphemeral,
    transferProgress: transferProgress,
    reactions: reactions,
  );

  /// Returns a new ChatMessage with reaction toggled.
  ChatMessage withReaction(
    String emoji,
    MessageOrigin origin, {
    required bool remove,
  }) {
    final next = Map<String, Set<MessageOrigin>>.from(
      reactions.map((k, v) => MapEntry(k, Set<MessageOrigin>.from(v))),
    );
    if (remove) {
      next[emoji]?.remove(origin);
      if (next[emoji]?.isEmpty ?? false) next.remove(emoji);
    } else {
      (next[emoji] ??= {}).add(origin);
    }
    return copyWith(reactions: next);
  }
}
