import 'package:helix_remote_crypto/v2.dart' show AttachmentCrypto;
import 'package:helix_remote_engine/src/util/backoff.dart';
import 'package:meta/meta.dart';

/// Tunables of the transfer queue. Defaults are the product values; tests
/// shorten them.
@immutable
final class TransferConfig {
  const TransferConfig({
    this.chunkBytes = 512 * 1024,
    this.encryptionChunkBytes = AttachmentCrypto.defaultChunkSize,
    this.maxUploads = 2,
    this.maxDownloads = 3,
    this.lease = const Duration(seconds: 60),
    this.backoff = const Backoff(
      initial: Duration(seconds: 3),
      max: Duration(minutes: 5),
    ),
    this.maxAge = const Duration(days: 3),
    this.idlePoll = const Duration(minutes: 1),
    this.maxDownloadBytes = 2 * 1024 * 1024 * 1024,
    this.maxThumbnailBytes = 512 * 1024,
    this.sweepInterval = const Duration(minutes: 10),
    this.sweepGrace = const Duration(minutes: 10),
    this.forwardReuseWindow = const Duration(days: 20),
  });

  /// Bytes per request, up and down. A transfer records its progress after
  /// each one, so this is also how much is repeated after an interruption.
  final int chunkBytes;

  /// STREAM chunk size of uploads (CRYPTO_V2.md §12).
  final int encryptionChunkBytes;

  /// Transfers running at once, per direction.
  final int maxUploads;
  final int maxDownloads;

  /// How long a claimed job stays claimed if its worker dies. A running job
  /// renews it, so this is also how long a crash delays the resume.
  final Duration lease;

  /// Delays between attempts after a failure that may pass (no network, a
  /// busy server). The job's progress is kept.
  final Backoff backoff;

  /// A transfer that kept failing for this long is given up on (the UI
  /// offers a retry).
  final Duration maxAge;

  /// With nothing queued the worker still looks at the queue this often: an
  /// FCM isolate may have queued a download that this isolate's change stream
  /// cannot see.
  final Duration idlePoll;

  /// Larger incoming attachments are never fetched: a hostile pointer could
  /// otherwise fill the disk.
  final int maxDownloadBytes;

  /// Thumbnails larger than this are not fetched.
  final int maxThumbnailBytes;

  /// How often leftover files (staged bytes of finished or cancelled
  /// transfers, files of removed messages) are cleaned up, and how old a
  /// file must be before it can be taken for leftover.
  final Duration sweepInterval;
  final Duration sweepGrace;

  /// Forwarding reuses the original object while the message is younger
  /// than this; the server keeps objects 30 days, so an older one is
  /// uploaded again from the local copy.
  final Duration forwardReuseWindow;

  TransferConfig copyWith({
    int? chunkBytes,
    int? encryptionChunkBytes,
    int? maxUploads,
    int? maxDownloads,
    Duration? lease,
    Backoff? backoff,
    Duration? maxAge,
    Duration? idlePoll,
    int? maxDownloadBytes,
    int? maxThumbnailBytes,
    Duration? sweepInterval,
    Duration? sweepGrace,
    Duration? forwardReuseWindow,
  }) => TransferConfig(
    chunkBytes: chunkBytes ?? this.chunkBytes,
    encryptionChunkBytes: encryptionChunkBytes ?? this.encryptionChunkBytes,
    maxUploads: maxUploads ?? this.maxUploads,
    maxDownloads: maxDownloads ?? this.maxDownloads,
    lease: lease ?? this.lease,
    backoff: backoff ?? this.backoff,
    maxAge: maxAge ?? this.maxAge,
    idlePoll: idlePoll ?? this.idlePoll,
    maxDownloadBytes: maxDownloadBytes ?? this.maxDownloadBytes,
    maxThumbnailBytes: maxThumbnailBytes ?? this.maxThumbnailBytes,
    sweepInterval: sweepInterval ?? this.sweepInterval,
    sweepGrace: sweepGrace ?? this.sweepGrace,
    forwardReuseWindow: forwardReuseWindow ?? this.forwardReuseWindow,
  );
}
