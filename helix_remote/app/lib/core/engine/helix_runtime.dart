import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:helix_remote/core/engine/backup_policy.dart';
import 'package:helix_remote/core/platform/network_probe.dart';
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
  });

  /// Opens the database at [dbFile] with [key] and starts an engine against
  /// [serverUrl].
  ///
  /// Throws [DbEncryptionException] when the key is wrong or the file is
  /// plaintext, and [KeyUnavailable] when there is no key at all for an
  /// existing database — both leave the caller's next step clear.
  ///
  /// With [headless] the engine starts no socket and no timers, which is what
  /// the FCM background isolate and a one-shot CLI want: they call
  /// [Engine.syncOnce] themselves and there is nothing left running to close.
  static Future<HelixRuntime> open({
    required File dbFile,
    required DatabaseKey key,
    required Uri serverUrl,
    required PhoneBook phoneBook,
    required EngineConfig config,
    bool headless = false,
    NetworkProbe network = const DeviceNetworkProbe(),
  }) async {
    final db = await HelixDb.open(dbFile, key: key);
    final api = HelixApi(
      baseUrl: serverUrl,
      sessions: DbSessionTokenStore(db),
      clientName: config.deviceName,
    );
    final engine = Engine(
      api: api,
      db: db,
      clock: DateTime.now,
      random: SecureCryptoRandom(),
      config: config,
      phoneBook: phoneBook,
      backupOptions: BackupOptions(
        // gzip is `dart:io`'s, which the engine may not import: without it a
        // history backup fits far fewer messages into the server's 16 MiB.
        gzip: gzip,
        // Offers from the account's other devices wait for the person: the
        // restore step and Settings > Backup > Transfer show them, with
        // accept, decline and pause. (Automatic import would make pause
        // pointless: the engine would start it again at once.)
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
      ),
    );
    await engine.start(realtime: !headless, background: !headless);
    return HelixRuntime._(
      db: db,
      api: api,
      engine: engine,
      serverUrl: serverUrl,
    );
  }

  final HelixDb db;
  final HelixApi api;
  final Engine engine;
  final Uri serverUrl;

  /// Closes the engine, then the client and the database, in that order: the
  /// engine owns neither.
  Future<void> close() async {
    await engine.close();
    await api.close();
    await db.close();
  }
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
