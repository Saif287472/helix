import 'dart:convert';
import 'dart:math' as math;
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
    required this.discoveryIndex,
    required this.last4,
    required this.purpose,
  });

  final Uint8List phoneHash;

  /// The keyed discovery index ([IdentityContext.discoveryIndexOf]), never
  /// the salted hash clients compute.
  final String discoveryIndex;
  final String last4;
  final PhonePurpose purpose;

  String encode() => jsonEncode({
    'ph': encodeBytes(phoneHash),
    'dh': discoveryIndex,
    'l4': last4,
    'p': purpose.wire,
  });

  static VerifiedPhone decode(String raw) {
    final j = jsonDecode(raw) as Map<String, Object?>;
    return VerifiedPhone(
      phoneHash: decodeBytes(j['ph']! as String),
      discoveryIndex: j['dh']! as String,
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

  static const _discoveryIndexLabel = 'helix.v2.discovery-index';

  /// The hash clients send for discovery: `lowercase hex(HMAC-SHA256(salt,
  /// E.164))` under the public salt (people module, `DiscoverySalt`).
  Future<String> clientDiscoveryHash(String e164) async =>
      _hex(hmacSha256(await discoverySalt(), utf8.encode(e164)));

  /// What the database stores and looks up for a client hash:
  /// `hex(HMAC-SHA256(K, client hash))` with `K` derived from the phone
  /// pepper. The salt is public, so a stored client hash would let a stolen
  /// database test phone numbers offline; the index cannot be computed
  /// without the pepper.
  String discoveryIndexFor(String clientHash) => _hex(
    hmacSha256(
      hmacSha256(config.phonePepper, utf8.encode(_discoveryIndexLabel)),
      utf8.encode(clientHash),
    ),
  );

  Future<String> discoveryIndexOf(String e164) async =>
      discoveryIndexFor(await clientDiscoveryHash(e164));

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Turns phone discovery on or off for [accountId]. Off removes the index,
  /// so nothing about the number is stored for discovery. On needs the
  /// account's own number to rebuild it: [phoneNumber] must hash to the
  /// account's verified phone hash. Accounts without a verified number have
  /// nothing to discover and are left alone.
  Future<void> setPhoneDiscoverable(
    Tx tx,
    String accountId, {
    required bool on,
    String? phoneNumber,
  }) async {
    if (!on) {
      await store.setDiscoveryIndex(tx, accountId, null);
      return;
    }
    final (phone, index) = await store.phoneAndIndex(tx, accountId);
    if (phone == null || index != null) return;
    final e164 = phoneNumber == null ? null : requireE164(phoneNumber);
    if (e164 == null || !constantTimeEquals(phoneHash(e164), phone)) {
      throw const ApiError(
        ErrorCode.invalidField,
        message: 'turning discovery back on needs your own phone number',
        details: {'field': 'phone_number'},
      );
    }
    await store.setDiscoveryIndex(tx, accountId, await discoveryIndexOf(e164));
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

  static const passwordMaxFailures = 5;
  static const passwordFirstLock = Duration(minutes: 15);
  static const passwordMaxLock = Duration(hours: 24);

  /// Checks [authKey] against the account's password. Password sign-in and
  /// password change share one failure counter and lockout: 5 failures
  /// lock it for 15 minutes, doubling up to 24 hours. Returns the password
  /// row, or the error to throw once [tx] has committed (so the failure is
  /// recorded). Both null: the account has no password.
  Future<(Row?, ApiError?)> checkPassword(
    Tx tx,
    String accountId,
    Uint8List authKey,
  ) async {
    final row = await credentials.password(tx, accountId, forUpdate: true);
    if (row == null) return (null, null);
    final lockedUntil = row.optTime('locked_until');
    if (lockedUntil != null && lockedUntil.isAfter(clock.now())) {
      return (null, _locked(lockedUntil));
    }
    final ok = constantTimeEquals(
      row.bytes('verifier'),
      passwordVerifier(row.bytes('verifier_salt'), authKey),
    );
    if (!ok) {
      final failures = row.integer('failed_attempts') + 1;
      final lock = failures >= passwordMaxFailures ? _lockFor(failures) : null;
      await credentials.recordPasswordFailure(tx, accountId, failures, lock);
      return (
        null,
        lock == null
            ? const ApiError(ErrorCode.invalidCredentials)
            : _locked(lock),
      );
    }
    await credentials.clearPasswordFailures(tx, accountId);
    return (row, null);
  }

  DateTime _lockFor(int failures) {
    final factor = math.pow(2, math.min(failures - passwordMaxFailures, 10));
    final lock = passwordFirstLock * factor.toInt();
    return clock.now().add(lock > passwordMaxLock ? passwordMaxLock : lock);
  }

  ApiError _locked(DateTime until) => ApiError(
    ErrorCode.passwordLocked,
    details: {'locked_until': toWireTime(until)},
    retryAfter: until.difference(clock.now()),
  );

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
    await hooks.deviceListChanged(tx, accountId, exceptDevice: device.deviceId);
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
