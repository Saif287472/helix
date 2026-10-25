import 'package:helix_remote_db/helix_remote_db.dart';

/// When incoming attachments are fetched by themselves ("auto-download"),
/// and when only on request ("download now"). A setting is the largest size
/// fetched automatically, in bytes: [never] (0) means only on request,
/// [unlimited] (-1) means always.
///
/// The engine does not know whether the device is on Wi-Fi or mobile data;
/// the app changes these settings when that changes (the conventional
/// "on Wi-Fi" / "on mobile data" pages), and the engine reads them when a
/// message arrives.
///
/// Thumbnails (a few KiB) are always fetched, whatever the setting.
abstract final class MediaSettings {
  static const never = 0;
  static const unlimited = -1;

  static const autoDownloadImages = Setting<int>(
    'media.auto_download.images',
    10 * 1024 * 1024,
  );

  /// Voice notes.
  static const autoDownloadAudio = Setting<int>(
    'media.auto_download.audio',
    10 * 1024 * 1024,
  );

  /// Videos and video notes.
  static const autoDownloadVideo = Setting<int>(
    'media.auto_download.video',
    never,
  );

  /// Documents and anything of an unknown kind.
  static const autoDownloadDocuments = Setting<int>(
    'media.auto_download.documents',
    never,
  );

  /// The setting that governs an attachment of [kind] (a `MediaItemKind`
  /// wire name, or `sticker`).
  static Setting<int> forKind(String kind) => switch (kind) {
    'image' || 'gif' || 'sticker' => autoDownloadImages,
    'voice_note' => autoDownloadAudio,
    'video' || 'video_note' => autoDownloadVideo,
    _ => autoDownloadDocuments,
  };

  /// The kinds the Storage page counts, and "free up space" frees, as photos
  /// and videos. One mapping for all three views (AUD-12m-4): [groupOf].
  static const photoVideoKinds = {
    'image',
    'video',
    'video_note',
    'gif',
    'sticker',
  };

  /// How the Storage page groups an attachment of [kind]: photos and videos,
  /// voice notes, or files - which is also where a kind from a newer client
  /// lands, so what is counted as a file is what "free up files" frees.
  static MediaKindGroup groupOf(String kind) => photoVideoKinds.contains(kind)
      ? MediaKindGroup.photoVideo
      : kind == 'voice_note'
      ? MediaKindGroup.voice
      : MediaKindGroup.file;

  /// Whether an attachment of [size] bytes is fetched by itself under
  /// [limit].
  static bool allows(int limit, int size) =>
      limit == unlimited || (limit > 0 && size <= limit);
}

/// What the Storage page shows an attachment as ([MediaSettings.groupOf]).
enum MediaKindGroup { photoVideo, voice, file }
