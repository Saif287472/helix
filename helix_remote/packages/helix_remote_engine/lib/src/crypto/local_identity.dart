import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// This device's keys and ids, loaded from the `identity` and
/// `self_account` rows. The private keys live only in the encrypted
/// database (CRYPTO_V2.md §13: never backed up).
final class LocalIdentity {
  LocalIdentity({
    required this.keys,
    required this.accountKey,
    required this.serverDomain,
  });

  final LocalDeviceKeys keys;

  /// The account identity key (AIK) pair: certifies devices, unwraps the
  /// history backup, is handed to a linked device.
  final Ed25519KeyPair accountKey;

  /// The home server's authority, as in qualified addresses.
  final String serverDomain;

  DeviceAddress get address => keys.address;
  String get accountId => keys.address.account;
  String get deviceId => keys.address.device;

  /// Loads the identity, or null when the database has none (signed out).
  static Future<LocalIdentity?> load(HelixDb db) async {
    final row = await db.cryptoDao.identityKeys();
    final account = await db.accountDao.current();
    if (row == null || account == null) return null;
    final certificate = DeviceCertificate.fromJson(
      JsonReader.decode(utf8.decode(row.deviceCertificate)),
    );
    return LocalIdentity(
      keys: LocalDeviceKeys(
        address: DeviceAddress(row.accountId, row.deviceId),
        accountIdentityKey: row.aikPublic,
        identityKey: X25519KeyPair.restore(row.dikPrivate, row.dikPublic),
        signingKey: Ed25519KeyPair.restore(row.dskPrivate, row.dskPublic),
        certificate: certificate,
      ),
      accountKey: Ed25519KeyPair.restore(row.aikPrivate, row.aikPublic),
      serverDomain: account.serverDomain,
    );
  }

  /// The `identity` row for [keys] and [accountKey]. Written by the account
  /// service in the same transaction as the rest of a new device's state.
  static IdentityCompanion toRow({
    required LocalDeviceKeys keys,
    required Ed25519KeyPair accountKey,
    required DateTime now,
  }) => IdentityCompanion.insert(
    id: const Value(1),
    accountId: keys.address.account,
    deviceId: keys.address.device,
    aikPublic: accountKey.publicKey,
    aikPrivate: accountKey.seed,
    dikPublic: keys.identityKey.publicKey,
    dikPrivate: keys.identityKey.privateKey,
    dskPublic: keys.signingKey.publicKey,
    dskPrivate: keys.signingKey.seed,
    deviceCertificate: Uint8List.fromList(
      utf8.encode(jsonEncode(keys.certificate.toJson())),
    ),
    createdAt: now,
  );

  @override
  String toString() => 'LocalIdentity($address, <redacted>)';
}
