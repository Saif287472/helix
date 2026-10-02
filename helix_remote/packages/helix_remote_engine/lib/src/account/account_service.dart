import 'dart:async';
import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/account/key_maintenance.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/crypto/local_identity.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_engine/src/settings_keys.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Registration, sign-in and linking: everything that ends with this
/// database holding an account identity, a device identity, prekeys and a
/// session (CRYPTO_V2.md §2, §2a, §11).
///
/// All of it is the "new device" side. Approving another device's link is
/// `DeviceService.approveLink`; signing out is `Engine.signOut`.
///
/// Secrets never leave this class in a log or an error: passwords are used
/// to derive keys and dropped; only the HKDF-derived auth key is sent
/// (CRYPTO_V2.md §11).
final class AccountService {
  AccountService(this._ctx, {required this._onSignedIn});

  final EngineContext _ctx;
  final Future<void> Function() _onSignedIn;

  /// This device's account row, or null when signed out.
  Future<SelfAccountRow?> current() => _ctx.db.accountDao.current();

  Stream<SelfAccountRow?> watch() => _ctx.db.accountDao.watchCurrent();

  bool get isSignedIn => _ctx.isSignedIn;

  // ------------------------------------------------------ phone codes

  /// Texts a 6-digit code to [phoneNumber] (Helix Global).
  Future<PhoneChallengeResponse> requestPhoneCode(
    String phoneNumber, {
    PhonePurpose purpose = PhonePurpose.register,
  }) => _ctx.api.identity.phoneChallenge(
    PhoneChallengeRequest(phoneNumber: phoneNumber, purpose: purpose),
  );

  /// Checks the code. The result carries the single-use verification token
  /// for [register], and whether the number already has an account (and
  /// its id, which a takeover needs to certify the new device).
  Future<PhoneVerifyResponse> verifyPhone(String challengeId, String code) =>
      _ctx.api.identity.phoneVerify(
        PhoneVerifyRequest(challengeId: challengeId, code: code),
      );

  // ------------------------------------------------------ registration

  /// Creates an account (or, with [replaceExisting], takes over the
  /// number's account under a new identity key) and signs this device in.
  ///
  /// Helix Global needs a [verificationToken] from [verifyPhone]; a
  /// personal server needs an [inviteCode]. A [password] is optional but
  /// lets the account be recovered on a new device without another device
  /// (it wraps the identity key; the server only learns the derived auth
  /// key). For a takeover pass the [accountId] [verifyPhone] returned.
  Future<void> register({
    String? verificationToken,
    String? inviteCode,
    String? password,
    String? accountId,
    bool replaceExisting = false,
    String? phoneNumber,
    String? deviceName,
  }) async {
    await _requireEmpty();
    final now = _ctx.now();
    final id = accountId ?? _ctx.ids.next();
    final aik = await Ed25519KeyPair.generate(_ctx.random);
    final keys = await LocalDeviceKeys.create(
      accountIdentityKey: aik,
      address: DeviceAddress(id, _ctx.ids.next()),
      createdAt: now,
      random: _ctx.random,
    );
    final prekeys = await KeyMaintenance.initial(
      signingKey: keys.signingKey,
      random: _ctx.random,
      now: now,
      oneTimeCount: _ctx.config.initialOneTimePrekeys,
    );
    final setup = password == null
        ? null
        : await _passwordSetup(password, aik, id);
    final response = await _ctx.api.identity.register(
      RegisterRequest(
        accountId: id,
        identityKey: aik.publicKey,
        device: await keys.registration(
          name: deviceName ?? _ctx.config.deviceName,
          platform: _ctx.config.platform,
        ),
        prekeys: prekeys.toUpload(),
        verificationToken: verificationToken,
        inviteCode: inviteCode,
        password: setup,
        termsVersion: HelixLegalDocuments.termsVersion,
        replaceExisting: replaceExisting,
      ),
    );
    await _persist(
      keys: keys,
      accountKey: aik,
      prekeys: prekeys,
      session: response.session,
      profileKey: newSymmetricKey(_ctx.random),
      phoneNumber: phoneNumber,
    );
  }

  Future<PasswordSetup> _passwordSetup(
    String password,
    Ed25519KeyPair aik,
    String accountId,
  ) async {
    const kdf = KdfParams();
    final salt = PasswordKeys.newSalt(_ctx.random);
    final keys = await PasswordKeys.derive(
      password: password,
      salt: salt,
      params: kdf,
    );
    return PasswordSetup(
      kdf: kdf,
      salt: salt,
      authKey: keys.authKey,
      wrappedIdentityKey: await keys.wrapIdentityKey(
        identityKeySeed: aik.seed,
        accountId: accountId,
        random: _ctx.random,
      ),
    );
  }

  // ------------------------------------------------------ password sign-in

  /// Signs in on this (new) device with the account's phone number and
  /// password: the server returns the password-wrapped identity key and a
  /// single-use sign-in token; this device unwraps the key, creates and
  /// certifies its own device keys and registers them (CRYPTO_V2.md §11).
  ///
  /// Lockout and wrong-password answers arrive as `ApiException`
  /// (`password_locked`, `invalid_credentials`).
  Future<void> signInWithPassword({
    required String phoneNumber,
    required String password,
    String? deviceName,
  }) async {
    await _requireEmpty();
    final params = await _ctx.api.identity.passwordParams(phoneNumber);
    final PasswordKeys keys;
    try {
      keys = await PasswordKeys.derive(
        password: password,
        salt: params.salt,
        params: params.kdf,
      );
    } on CryptoV2Exception {
      throw const SignInException(
        SignInFailure.untrustedAccountKey,
        'the server asked for weaker password hashing than Helix allows',
      );
    }
    final step = await _ctx.api.identity.passwordSignIn(
      PasswordSignInRequest(phoneNumber: phoneNumber, authKey: keys.authKey),
    );
    final Ed25519KeyPair aik;
    try {
      aik = await keys.unwrapIdentityKey(
        wrapped: step.wrappedIdentityKey,
        accountId: step.accountId,
        expectedPublicKey: step.identityKey,
      );
    } on CryptoV2Exception {
      throw const SignInException(
        SignInFailure.untrustedAccountKey,
        'the identity key the server returned does not open with this password',
      );
    }
    await _addDevice(
      accountId: step.accountId,
      accountKey: aik,
      deviceName: deviceName,
      signInToken: step.signInToken,
      phoneNumber: phoneNumber,
    );
  }

  // --------------------------------------------------------- linking

  /// Starts linking this (new) device to an existing account (CRYPTO_V2.md
  /// §2a): shows [NewDeviceLink.code] as a QR code, then [NewDeviceLink.complete]
  /// waits for a signed-in device to approve it.
  Future<NewDeviceLink> beginLink({String? deviceName}) async {
    await _requireEmpty();
    final ephemeral = await X25519KeyPair.generate(_ctx.random);
    final created = await _ctx.api.identity.createLink(
      LinkCreateRequest(ephemeralKey: ephemeral.publicKey),
    );
    final code = LinkCode(
      serverOrigin: _ctx.api.transport.baseUrl.origin,
      linkId: created.linkId,
      ephemeralKey: ephemeral.publicKey,
    ).encode();
    return NewDeviceLink._(this, created, ephemeral, code, deviceName);
  }

  Future<void> _completeLink(NewDeviceLink link) async {
    final cancel = link._cancel;
    while (true) {
      if (cancel.isCancelled) {
        throw const SignInException(
          SignInFailure.linkExpired,
          'link cancelled',
        );
      }
      if (!link.expiresAt.isAfter(_ctx.now())) {
        throw const SignInException(SignInFailure.linkExpired);
      }
      final LinkPollResponse poll;
      try {
        poll = await _ctx.api.identity.pollLink(
          link._created.linkId,
          pollToken: link._created.pollToken,
          cancel: cancel,
        );
      } on RequestCancelledException {
        throw const SignInException(
          SignInFailure.linkExpired,
          'link cancelled',
        );
      }
      switch (poll.status) {
        case LinkStatus.pending:
          continue;
        case LinkStatus.expired:
          throw const SignInException(SignInFailure.linkExpired);
        case LinkStatus.approved:
          final sealed = poll.provision;
          final token = poll.linkToken;
          if (sealed == null || token == null) {
            throw const SignInException(SignInFailure.linkExpired);
          }
          final ProvisionMessage provision;
          try {
            provision = await Provisioning.open(
              ephemeralKey: link._ephemeral,
              linkId: link._created.linkId,
              sealed: sealed,
            );
          } on CryptoV2Exception {
            throw const SignInException(
              SignInFailure.untrustedAccountKey,
              'the approval could not be opened',
            );
          }
          await _addDevice(
            accountId: provision.accountId,
            accountKey: await Ed25519KeyPair.fromSeed(
              provision.identityKeySeed,
            ),
            deviceName: link._deviceName,
            linkToken: token,
            profileKey: provision.profileKey,
          );
          return;
      }
    }
  }

  // ----------------------------------------------------------- shared

  Future<void> _addDevice({
    required String accountId,
    required Ed25519KeyPair accountKey,
    String? deviceName,
    String? signInToken,
    String? linkToken,
    String? phoneNumber,
    Uint8List? profileKey,
  }) async {
    final now = _ctx.now();
    final keys = await LocalDeviceKeys.create(
      accountIdentityKey: accountKey,
      address: DeviceAddress(accountId, _ctx.ids.next()),
      createdAt: now,
      random: _ctx.random,
    );
    final prekeys = await KeyMaintenance.initial(
      signingKey: keys.signingKey,
      random: _ctx.random,
      now: now,
      oneTimeCount: _ctx.config.initialOneTimePrekeys,
    );
    final session = await _ctx.api.identity.addDevice(
      AddDeviceRequest(
        device: await keys.registration(
          name: deviceName ?? _ctx.config.deviceName,
          platform: _ctx.config.platform,
        ),
        prekeys: prekeys.toUpload(),
        signInToken: signInToken,
        linkToken: linkToken,
      ),
    );
    await _persist(
      keys: keys,
      accountKey: accountKey,
      prekeys: prekeys,
      session: session,
      profileKey: profileKey,
      phoneNumber: phoneNumber,
    );
  }

  /// Stores the new device's identity, prekeys, account row and session in
  /// one transaction, then hands over to the engine.
  Future<void> _persist({
    required LocalDeviceKeys keys,
    required Ed25519KeyPair accountKey,
    required InitialPrekeys prekeys,
    required Session session,
    required Uint8List? profileKey,
    String? phoneNumber,
  }) async {
    final now = _ctx.now();
    await _ctx.db.transaction(() async {
      await _ctx.db.cryptoDao.saveIdentity(
        LocalIdentity.toRow(keys: keys, accountKey: accountKey, now: now),
      );
      await _ctx.db.cryptoDao.savePrekeys(prekeys.rows(now));
      await _ctx.db.settingsDao.set(
        EngineState.oneTimePrekeyCounter,
        prekeys.lastOneTimeId,
        now: now,
      );
      await _ctx.db.settingsDao.set(
        EngineState.signedPrekeyCounter,
        prekeys.signed.id,
        now: now,
      );
      await _ctx.db.accountDao.save(
        SelfAccountCompanion.insert(
          accountId: keys.address.account,
          deviceId: keys.address.device,
          serverDomain: _ctx.api.transport.baseUrl.authority,
          phoneNumber: Value(phoneNumber),
          profileKey: Value(profileKey),
          registeredAt: now,
        ),
      );
    });
    await _ctx.api.auth.signedIn(session);
    await _onSignedIn();
  }

  Future<void> _requireEmpty() async {
    if (_ctx.isSignedIn || await _ctx.db.accountDao.current() != null) {
      throw const EngineStateException(
        'this database already holds an account; sign out first',
      );
    }
  }

  // --------------------------------------------- device-key sign-in

  /// Signs this device in again with its own signing key (CRYPTO_V2.md,
  /// REST_V2 "challenges"), used when the refresh token no longer works.
  /// Returns null if the device is unknown or revoked, in which case the
  /// caller should treat the session as ended.
  Future<Session?> deviceKeySignIn(
    IdentityClient identity, {
    required Future<void> Function() onRevoked,
  }) async {
    if (!_ctx.isSignedIn) return null;
    final self = _ctx.identity;
    try {
      final challenge = await identity.deviceChallenge(
        DeviceChallengeRequest(
          accountId: self.accountId,
          deviceId: self.deviceId,
        ),
      );
      return await identity.deviceSignIn(
        DeviceSignInRequest(
          accountId: self.accountId,
          deviceId: self.deviceId,
          challengeId: challenge.challengeId,
          challenge: challenge.challenge,
          signature: await self.keys.signInSignature(challenge.challenge),
        ),
      );
    } on ApiException catch (e) {
      if (e.code == ErrorCode.deviceRevoked) {
        await onRevoked();
      }
      return null;
    }
  }

  /// Takes this device out of the account on the server so it does not
  /// linger in the device list: revoke it, and if that fails at least end
  /// the session. Best effort: offline, the local sign-out goes on.
  Future<void> leaveOnServer() async {
    try {
      await _ctx.api.identity.revokeDevice(_ctx.identity.deviceId);
      return;
    } on HelixApiException {
      // Fall through to ending the session only.
    }
    try {
      await _ctx.api.identity.signOut();
    } on HelixApiException {
      // The local sign-out goes on.
    }
  }
}

/// A link in progress on the new device (CRYPTO_V2.md §2a).
final class NewDeviceLink {
  NewDeviceLink._(
    this._account,
    this._created,
    this._ephemeral,
    this.code,
    this._deviceName,
  );

  final AccountService _account;
  final LinkCreateResponse _created;
  final X25519KeyPair _ephemeral;
  final String? _deviceName;
  final CancellationToken _cancel = CancellationToken();

  /// The text for the QR code: `helix-link:1:<server origin>:<link id>:<key>`.
  final String code;

  /// The link stops working at this time (10 minutes).
  DateTime get expiresAt => _created.expiresAt;

  /// Waits for a signed-in device to approve, then registers this device.
  /// Throws `SignInException(linkExpired)` on expiry or [cancel].
  Future<void> complete() => _account._completeLink(this);

  void cancel() => _cancel.cancel();
}
