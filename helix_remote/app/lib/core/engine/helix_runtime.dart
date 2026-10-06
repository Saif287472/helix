import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:helix_remote/core/engine/backup_policy.dart';
import 'package:helix_remote/core/engine/server_policy.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/platform/engine_lease.dart';
import 'package:helix_remote/core/platform/network_probe.dart';
import 'package:helix_remote/core/platform/picker_cleanup.dart';
import 'package:helix_remote/core/platform/tls_pinning.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart' show SecureCryptoRandom;
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show DevicePlatform;

/// One live device: the encrypted database, the API client for one server and
/// the engine that ties them together.
///
/// The app builds exactly one of these at a time. Changing server (sign-out,
/// or an invite code naming a personal server) closes it and opens the next,
/// so two engines never hold the database file.
///
/// The engine decides whether it runs a socket, timers, or nothing at all;
/// see [Engine.start]. This class only owns lifetimes.
final class HelixRuntime {
  HelixRuntime._({
    required this.db,
    required this.api,
    required this.engine,
    required this.serverUrl,
    required EngineLease? lease,
    required _WipeRecord wipe,
    required Future<void> Function() runHardWipe,
  }) : _lease = lease,
       _wipe = wipe,
       _runHardWipe = runHardWipe;

  /// Opens the database at [dbFile] with [key] and starts an engine against
  /// [serverUrl].
  ///
  /// Throws [DbEncryptionException] when the key is wrong or the file is
  /// plaintext, and [KeyUnavailable] when there is no key at all for an
  /// existing database — both leave the caller's next step clear.
  ///
  /// Also throws [InsecureServerUrl] for a server that is not https (outside a
  /// debug build's development hosts), and [EngineAlreadyRunning] when another
  /// engine owns the database (see [EngineLease]). Both are checked before the
  /// database is opened.
  ///
  /// A runtime for Helix Global is certificate-pinned ([TlsPinPolicy]); the
  /// REST client and the realtime socket both go through the pinned client.
  ///
  /// [blobs] is where attachments live (`AppBlobStore` in the app);
  /// [mediaProcessor] makes their thumbnails, BlurHash, sizes and lengths
  /// (`FlutterMediaProcessor`; the engine's header-only default when null).
  ///
  /// With [headless] the engine starts no socket and no timers, which is what
  /// the FCM background isolate and a one-shot CLI want: they call
  /// [Engine.syncOnce] themselves and there is nothing left running to close.
  ///
  /// **Hard wipe.** The engine deletes every row and vacuums on sign-out and on
  /// a revocation that wipes; the rest is this app's (`Engine(hardWipe:)`, see
  /// [hardWipe]): the database is closed and its files overwritten and
  /// deleted, the SQLCipher key leaves [keys] (which is what makes anything
  /// left on the flash unreadable), and the avatar, downloaded attachments and
  /// the file picker's copies go. [keys] defaults to the platform keystore;
  /// [afterWipe] replaces the last two steps (tests).
  static Future<HelixRuntime> open({
    required File dbFile,
    required DatabaseKey key,
    required Uri serverUrl,
    required PhoneBook phoneBook,
    required EngineConfig config,
    BlobStore? blobs,
    MediaProcessor? mediaProcessor,
    bool headless = false,
    NetworkProbe network = const DeviceNetworkProbe(),
    TlsPinPolicy? pinning,
    SecureKeyStore? keys,
    Future<void> Function()? afterWipe,
  }) async {
    final problem = ServerPolicy.check(serverUrl);
    if (problem != null) throw InsecureServerUrl(problem);

    final lease = await EngineLease.acquire(
      File('${dbFile.path}.lease'),
      role: headless ? LeaseRole.headless : LeaseRole.foreground,
    );
    try {
      return await _open(
        lease: lease,
        dbFile: dbFile,
        key: key,
        serverUrl: serverUrl,
        phoneBook: phoneBook,
        config: config,
        blobs: blobs,
        mediaProcessor: mediaProcessor,
        headless: headless,
        network: network,
        pinning: pinning ?? TlsPinPolicy.forThisBuild(),
        afterWipe: afterWipe ?? appWipe(keys ?? SecureKeyStore()),
      );
    } on Object {
      await lease.release();
      rethrow;
    }
  }

  static Future<HelixRuntime> _open({
    required EngineLease lease,
    required File dbFile,
    required DatabaseKey key,
    required Uri serverUrl,
    required PhoneBook phoneBook,
    required EngineConfig config,
    required BlobStore? blobs,
    required MediaProcessor? mediaProcessor,
    required bool headless,
    required NetworkProbe network,
    required TlsPinPolicy pinning,
    required Future<void> Function() afterWipe,
  }) async {
    final db = await HelixDb.open(dbFile, key: key);
    final wipe = _WipeRecord();
    Future<void> runHardWipe() => hardWipe(
      db: db,
      dbFile: dbFile,
      afterWipe: afterWipe,
      onDatabaseDestroyed: () => wipe.databaseDestroyed = true,
    );
    final pinned = pinning.appliesTo(serverUrl);
    HelixApi build() => HelixApi(
      baseUrl: serverUrl,
      sessions: DbSessionTokenStore(db),
      clientName: config.deviceName,
      sockets: pinned ? pinning.socketFactory : defaultSocketFactory,
    );
    // The REST client makes its `HttpClient` when it is constructed, so a
    // pinned runtime builds it inside the pinning scope.
    final api = pinned ? pinning.run(build) : build();
    final engine = Engine(
      api: api,
      db: db,
      clock: DateTime.now,
      random: SecureCryptoRandom(),
      config: config,
      phoneBook: phoneBook,
      backupOptions: backupOptionsFor(db: db, api: api, network: network),
      // Without a file store the engine cannot send attachments and leaves
      // incoming ones undownloaded.
      blobs: blobs,
      mediaProcessor: mediaProcessor,
      hardWipe: runHardWipe,
    );
    await engine.start(realtime: !headless, background: !headless);
    return HelixRuntime._(
      db: db,
      api: api,
      engine: engine,
      serverUrl: serverUrl,
      lease: lease,
      wipe: wipe,
      runHardWipe: runHardWipe,
    );
  }

  /// What the app passes the engine for backups and history transfers.
  ///
  /// **History transfers are the person's choice, both ways.** The engine's
  /// defaults are off (a device that has just been linked would otherwise
  /// receive the whole history unasked, and whoever links a device, or holds a
  /// stolen session, could pull it); this app keeps them off: the old device
  /// offers "Send history to this device" after approving a link, and the new
  /// one shows the offer with Accept, Decline and Pause (the restore step and
  /// Settings > Backup > Transfer). Nothing here may switch either to on.
  @visibleForTesting
  static BackupOptions backupOptionsFor({
    required HelixDb db,
    required HelixApi api,
    required NetworkProbe network,
  }) => BackupOptions(
    // gzip is `dart:io`'s, which the engine may not import: without it a
    // history backup fits far fewer messages into the server's 16 MiB.
    gzip: gzip,
    autoTransferToNewDevices: false,
    // Offers wait for the person (automatic import would also make Pause
    // pointless: the engine would start it again at once).
    autoAcceptTransfers: false,
    remote: PolicyBackupRemote(
      ApiBackupRemote(api.backup),
      mayUpload: () async {
        if (await db.settingsDao.get(AppSettings.backupOverMobile)) {
          return true;
        }
        return await network.current() != NetworkKind.mobile;
      },
    ),
  );

  /// The app's half of a hard wipe, run by the engine after it has deleted
  /// every row (see [HardWipe]): close the database, overwrite and delete its
  /// files, then [afterWipe] (the keystore key and the plaintext files).
  ///
  /// Every step is tried even when an earlier one fails, because stopping at
  /// the first error would leave the rest on the phone; the first error is
  /// rethrown afterwards so the caller knows.
  @visibleForTesting
  static Future<void> hardWipe({
    required HelixDb db,
    required File dbFile,
    required Future<void> Function() afterWipe,
    void Function()? onDatabaseDestroyed,
  }) async {
    Object? first;
    StackTrace? firstStack;
    Future<void> step(Future<void> Function() run) async {
      try {
        await run();
      } on Object catch (error, stack) {
        first ??= error;
        firstStack ??= stack;
      }
    }

    // Closed first: a file that is open cannot be overwritten on Windows.
    await step(db.close);
    await step(() => destroyDatabaseFiles(dbFile));
    onDatabaseDestroyed?.call();
    await step(afterWipe);
    if (first != null) Error.throwWithStackTrace(first!, firstStack!);
  }

  /// What this app deletes besides the database after a hard wipe: the
  /// SQLCipher key in [keys], the profile picture and downloaded attachments,
  /// and the file picker's temporary copies. Each part is tried on its own.
  static Future<void> Function() appWipe(SecureKeyStore keys) => () async {
    try {
      await keys.forget();
    } on Object {
      // Tried again by sign-out; the files below must still go.
    }
    await AppPaths.wipeLocalFiles();
    await PickerTemporaryFiles.clear();
  };

  final EngineLease? _lease;
  final _WipeRecord _wipe;
  final Future<void> Function() _runHardWipe;
  final HelixDb db;
  final HelixApi api;
  final Engine engine;
  final Uri serverUrl;

  /// The engine wiped this device (sign-out, deleting the account or a
  /// revocation) and the database file is gone: this runtime is spent, and
  /// whatever opens next gets a new file and a new key.
  bool get wasWiped => _wipe.databaseDestroyed;

  /// Makes sure the hard wipe has run: the engine's own sign-out does it, but
  /// an engine that was already signed out returns early, and the app's
  /// sign-out must leave no database file and no key either way. A no-op once
  /// done.
  Future<void> ensureWiped() async {
    if (!wasWiped) await _runHardWipe();
  }

  /// Closes the engine, then the client and the database, in that order: the
  /// engine owns neither.
  Future<void> close() async {
    try {
      await engine.close();
      await api.close();
      // A wiped database was closed by the wipe.
      if (!wasWiped) await db.close();
    } finally {
      await _lease?.release();
    }
  }
}

/// Set by the hard-wipe hook, read by [HelixRuntime.wasWiped].
final class _WipeRecord {
  bool databaseDestroyed = false;
}

/// The platform this build is running on, as the server records it.
DevicePlatform get currentDevicePlatform => switch (defaultTargetPlatform) {
  TargetPlatform.android => DevicePlatform.android,
  TargetPlatform.iOS => DevicePlatform.ios,
  TargetPlatform.windows => DevicePlatform.windows,
  _ => DevicePlatform.other,
};

/// [EngineConfig] for this device: its name and platform go to the server so
/// the account's other devices can say which phone this is.
EngineConfig engineConfigFor({
  required String deviceName,
  required DevicePlatform platform,
}) => EngineConfig(deviceName: deviceName, platform: platform);
