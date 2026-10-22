/// What downloaded attachments take on this device, split the way the
/// Storage page shows it.
final class MediaStorageUsage {
  const MediaStorageUsage({
    this.photosVideosBytes = 0,
    this.voiceNoteBytes = 0,
    this.filesBytes = 0,
  });

  /// Images, videos, video notes and GIFs.
  final int photosVideosBytes;

  final int voiceNoteBytes;

  /// Documents, and kinds from a newer client (they download as files).
  final int filesBytes;

  int get totalBytes => photosVideosBytes + voiceNoteBytes + filesBytes;
}

/// Downloaded media of one chat that a "free up space" action can remove.
/// Voice notes are not offered on their own and are left out.
final class ChatStorageUsage {
  const ChatStorageUsage({
    required this.conversationId,
    this.photosVideosBytes = 0,
    this.filesBytes = 0,
  });

  final String conversationId;
  final int photosVideosBytes;
  final int filesBytes;

  int get totalBytes => photosVideosBytes + filesBytes;
}

/// What a "free up space" action removes from one chat: its photos and
/// videos, or its documents. Messages and their pointers stay either way.
enum FreeKind { photosVideos, documents }
