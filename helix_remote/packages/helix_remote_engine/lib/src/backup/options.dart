import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/settings_keys.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:meta/meta.dart';

/// The server calls backup needs. The default talks to the real server
/// ([ApiBackupRemote]); the interface is the seam for tests and for hosts that
/// store the backup elsewhere.
abstract interface class BackupRemote {
  /// Null when there is none.
  Future<HistoryBackup?> history();

  /// `version` must exceed the stored one (`version_conflict` otherwise).
  Future<void> putHistory(HistoryBackup backup);
  Future<void> deleteHistory();

  /// Null when there is none.
  Future<FullBackup?> full();
  Future<void> putFull(FullBackup backup);
  Future<void> deleteFull();
}

/// The media relay a device-to-device transfer rides on: opaque ciphertext
/// objects with random ids (the encryption is the engine's).
abstract interface class RelayStore {
  /// Stores [ciphertext] and returns the object id.
  Future<String> upload(List<int> ciphertext, {CancellationToken? cancel});

  /// The whole object; throws `ApiException(not_found)` when it is gone.
  Future<Uint8List> download(String mediaId, {CancellationToken? cancel});

  /// Best effort; the owner only.
  Future<void> delete(String mediaId);
}

final class ApiBackupRemote implements BackupRemote {
  const ApiBackupRemote(this._client);

  final BackupClient _client;

  @override
  Future<HistoryBackup?> history() => _client.history();

  @override
  Future<void> putHistory(HistoryBackup backup) => _client.putHistory(backup);

  @override
  Future<void> deleteHistory() => _client.deleteHistory();

  @override
  Future<FullBackup?> full() => _client.full();

  @override
  Future<void> putFull(FullBackup backup) => _client.putFull(backup);

  @override
  Future<void> deleteFull() => _client.deleteFull();
}

final class ApiRelayStore implements RelayStore {
  const ApiRelayStore(this._client);

  final MediaClient _client;

  @override
  Future<String> upload(
    List<int> ciphertext, {
    CancellationToken? cancel,
  }) async {
    final target = await _client.createUpload(
      CreateUploadRequest(size: ciphertext.length),
    );
    await _client.upload(target, ciphertext, cancel: cancel);
    return target.mediaId;
  }

  @override
  Future<Uint8List> download(
    String mediaId, {
    CancellationToken? cancel,
  }) async {
    final response = await _client.download(mediaId, cancel: cancel);
    return response.bytes;
  }

  @override
  Future<void> delete(String mediaId) => _client.delete(mediaId);
}

/// Tunables of the backup feature (`Engine(backupOptions: ...)`). The
/// defaults are the product values; tests shorten them.
@immutable
final class BackupOptions {
  const BackupOptions({
    this.gzip,
    this.autoBackup = true,
    this.autoTransferToNewDevices = true,
    this.autoAcceptTransfers = true,
    this.backupInterval = const Duration(days: 1),
    this.retryInterval = const Duration(hours: 1),
    this.pageSize = 400,
    this.frameBytes = 256 * 1024,
    this.segmentBytes = 4 * 1024 * 1024,
    this.maxHistoryBytes = HistoryBackup.maxBytes,
    this.maxFullBytes = 40 * 1024 * 1024,
    this.offerTtl = const Duration(days: 7),
    this.relayTtl = const Duration(hours: 48),
    this.settings = defaultSettings,
    this.remote,
    this.relay,
  });

  /// The settings that belong in a backup: preferences, nothing about
  /// security or devices. The app may add its own (for example the chat
  /// wallpaper) by passing a longer list that starts with [defaultSettings].
  /// A restore applies a value only where this device still has the default.
  static const defaultSettings = <Setting<Object?>>[
    EngineSettings.sendReadReceipts,
    EngineSettings.sendTyping,
    EngineSettings.defaultDisappearingSeconds,
  ];

  /// gzip for archive frames (`dart:io`'s `gzip` works; the engine has no
  /// `dart:io`). Without it frames are stored raw, which fits fewer messages
  /// into the history backup's 16 MiB and cannot read compressed archives
  /// other devices made.
  final Codec<List<int>, List<int>>? gzip;

  /// The first-run default of the "back up automatically" switch.
  final bool autoBackup;

  /// Offer history to a device that has just joined the account.
  final bool autoTransferToNewDevices;

  /// Download and import an offer from another of this account's devices
  /// without asking.
  final bool autoAcceptTransfers;

  /// How often the automatic backup runs, and how soon after a failure.
  final Duration backupInterval;
  final Duration retryInterval;

  /// Messages read per page when exporting.
  final int pageSize;

  /// Raw bytes after which an archive frame is closed.
  final int frameBytes;

  /// Plaintext bytes after which a transfer segment is closed.
  final int segmentBytes;

  /// Archive budget of the history backup (the server's limit) and of the
  /// full backup (leaves room for base64 inside the 64 MiB envelope).
  final int maxHistoryBytes;
  final int maxFullBytes;

  /// An offer nobody accepted is dropped after this long; a sender removes
  /// its relay objects after [relayTtl] (the server expires them in 30 days
  /// anyway).
  final Duration offerTtl;
  final Duration relayTtl;

  final List<Setting<Object?>> settings;

  /// Test and host seams; null means the engine's `HelixApi`.
  final BackupRemote? remote;
  final RelayStore? relay;
}
