import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/application/hooks.dart';
import 'package:helix_remote_server/src/modules/identity/application/sessions.dart';
import 'package:helix_remote_server/src/modules/identity/config.dart';
import 'package:helix_remote_server/src/modules/identity/data/credential_store.dart';
import 'package:helix_remote_server/src/modules/identity/data/identity_store.dart';
import 'package:helix_remote_server/src/modules/identity/domain/secrets.dart';
import 'package:helix_remote_server/src/platform/bus/event_bus.dart';
import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/ephemeral/ephemeral_store.dart';
import 'package:helix_remote_server/src/platform/observability/log.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';

/// A verified phone number, as held between `verify` and the request that
/// spends the verification token. Never holds the number itself.
final class VerifiedPhone {
  const VerifiedPhone({
    required this.phoneHash,
    required this.discoveryHash,
    required this.last4,
    required this.purpose,
  });

  final Uint8List phoneHash;
  final String discoveryHash;
  final String last4;
  final PhonePurpose purpose;

  String encode() => jsonEncode({
    'ph': encodeBytes(phoneHash),
    'dh': discoveryHash,
    'l4': last4,
    'p': purpose.wire,
  });

  static VerifiedPhone decode(String raw) {
    final j = jsonDecode(raw) as Map<String, Object?>;
    return VerifiedPhone(
      phoneHash: decodeBytes(j['ph']! as String),
      discoveryHash: j['dh']! as String,
      last4: j['l4']! as String,
      purpose: PhonePurpose.values.firstWhere((p) => p.wire == j['p']),
    );
  }
}

/// Dependencies shared by the identity flows.
final class IdentityContext {
  IdentityContext({
    required this.db,
    required this.store,
    required this.credentials,
    required this.ephemeral,
    required this.rateLimiter,
    required this.bus,
    required this.config,
    required this.clock,
    required this.hooks,
    required this.sessions,
    required this.log,
  });

  final Db db;
  final IdentityStore store;
  final CredentialStore credentials;
  final EphemeralStore ephemeral;
  final RateLimiter rateLimiter;
  final EventBus bus;
  final IdentityConfig config;
  final Clock clock;
  final IdentityHooks hooks;
  final SessionIssuer sessions;
  final Log log;

  Uint8List? _discoverySalt;

  // Ephemeral-store key prefixes. Values keyed by a token use the token's
  // hash, so the store never holds a usable bearer secret as a key.
  static const verificationPrefix = 'identity:vt:';
  static const signInPrefix = 'identity:st:';
  static const linkTokenPrefix = 'identity:lt:';
  static const linkPrefix = 'identity:link:';
  static const challengePrefix = 'identity:chal:';

  Uint8List phoneHash(String e164) =>
      hmacSha256(config.phonePepper, utf8.encode(e164));

  Future<Uint8List> discoverySalt() async => _discoverySalt ??= await store
      .setting(db, 'discovery_salt', () => randomBytes(32));

  /// `lowercase hex(HMAC-SHA256(salt, E.164))`, exactly what clients compute
  /// for discovery (people module, `DiscoverySalt`).
  Future<String> discoveryHash(String e164) async {
    final mac = hmacSha256(await discoverySalt(), utf8.encode(e164));
    return mac.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> limit(RateLimitPolicy policy, String key) async {
    final decision = await rateLimiter.hit(policy, key);
    if (!decision.allowed) {
      throw ApiError(ErrorCode.rateLimited, retryAfter: decision.retryAfter);
    }
  }

  /// Reads a verification token without spending it (the caller deletes it
  /// after its transaction commits).
  Future<VerifiedPhone?> verification(String? token) async {
    if (token == null) return null;
    final raw = await ephemeral.get('$verificationPrefix${tokenKey(token)}');
    if (raw == null) {
      throw const ApiError(
        ErrorCode.invalidCode,
        message: 'verification expired or unknown',
      );
    }
    return VerifiedPhone.decode(raw);
  }

  Future<void> spendVerification(String token) =>
      ephemeral.delete('$verificationPrefix${tokenKey(token)}');

  /// Validates a password setup from a client (CRYPTO_V2.md §11).
  void checkPasswordSetup(PasswordSetup p) {
    if (!p.kdf.isAcceptable) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'password.kdf'},
      );
    }
    if (p.salt.length < 16 || p.salt.length > 64) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'password.salt'},
      );
    }
    if (p.authKey.length != 32) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'password.auth_key'},
      );
    }
    if (p.wrappedIdentityKey.nonce.length != 12 ||
        p.wrappedIdentityKey.ciphertext.length < 32 ||
        p.wrappedIdentityKey.ciphertext.length > 256) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'password.wrapped_identity_key'},
      );
    }
  }

  static const _verifierLabel = 'helix.v2.password-verifier';

  Uint8List passwordVerifier(Uint8List verifierSalt, Uint8List authKey) =>
      hmacSha256(verifierSalt, [...utf8.encode(_verifierLabel), ...authKey]);

  Future<void> storePassword(
    SqlSession db,
    String accountId,
    PasswordSetup p,
  ) async {
    final verifierSalt = randomBytes(16);
    await credentials.upsertPassword(
      db,
      accountId: accountId,
      kdf: p.kdf,
      salt: p.salt,
      verifierSalt: verifierSalt,
      verifier: passwordVerifier(verifierSalt, p.authKey),
      wrapped: p.wrappedIdentityKey,
    );
  }

  /// Revokes every active device of an account (identity changes).
  Future<void> revokeAll(Tx tx, String accountId, String reason) async {
    for (final device in await store.activeDevices(tx, accountId)) {
      final revoked = await store.revokeDevice(tx, device.id, reason);
      if (revoked != null) {
        await hooks.deviceRevoked(tx, revoked);
        tx.afterCommit(
          () => bus.publish('device.revoked', {'device': revoked.id}),
        );
      }
    }
  }

  /// Adds a verified device, runs the hooks and mints its session.
  Future<Session> addDevice(
    Tx tx, {
    required String accountId,
    required DeviceRegistration device,
    required PrekeyUpload prekeys,
    required SecurityEventKind event,
    bool notifyOthers = true,
  }) async {
    await store.insertDevice(tx, accountId, device);
    final record = (await store.deviceById(tx, device.deviceId))!;
    await hooks.deviceAdded(tx, record, prekeys);
    await hooks.deviceListChanged(tx, accountId);
    await store.addEvent(
      tx,
      accountId,
      event,
      deviceId: device.deviceId,
      deviceName: device.name,
    );
    if (notifyOthers) {
      await hooks.accountSignal(
        tx,
        accountId,
        AccountSignalEvent(
          signal: AccountSignalKind.newSignIn,
          at: clock.now(),
          device: device.deviceId,
          deviceName: device.name,
        ),
        exceptDevice: device.deviceId,
      );
    }
    return sessions.issue(tx, accountId: accountId, deviceId: device.deviceId);
  }
}
