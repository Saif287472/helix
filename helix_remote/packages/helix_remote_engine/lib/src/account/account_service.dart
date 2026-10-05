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

  // ------------------------------------------------------ recovery code

  /// Asks the server about a recovery code (an operator issued it; it is good
  /// for 48 hours and one use). A valid one says whether the redeem needs the
  /// SMS verification of the account's phone number and which account it is
  /// for; an invalid one only `valid: false`.
  Future<RecoveryLookupResponse> lookupRecoveryCode(String recoveryCode) =>
      _ctx.api.identity.recoveryLookup(recoveryCode);

  /// Recovers the account onto this (new) device with a recovery code
  /// (CRYPTO_V2.md §2: AIK rotation; REST_V2.md `recovery/redeem`).
  ///
  /// The account keeps its id and phone number but gets a **new identity
  /// key**: this device makes it, certifies its own device keys with it and
  /// the server moves the account over, signs every other device out (they
  /// find out as revocations), deletes the password and the history backup
  /// (both were keyed to the old identity), and tells the account's contacts
  /// about the key change, so their safety numbers change and they see it.
  /// Nothing of the old account's messages or sessions comes along; contacts
  /// start fresh sessions with this device.
  ///
  /// When the server has SMS and the account has a phone number, the redeem
  /// needs a [verificationToken] for that number: [requestPhoneCode] with
  /// `PhonePurpose.recover`, then [verifyPhone]. Without it this throws
  /// `SignInException(verificationRequired)` before touching anything. An
  /// optional new [password] wraps the new identity key as in [register]
  /// (the old password is gone either way).
  ///
  /// The account id comes from the lookup (`account_id`); [accountId] (what
  /// [verifyPhone] returned) is used when an older server does not send it.
  /// Server refusals arrive as `ApiException` (`invalid_code`, rate limits).
  Future<void> recoverWithCode({
    required String recoveryCode,
    String? verificationToken,
    String? password,
    String? accountId,
    String? phoneNumber,
    String? deviceName,
  }) async {
    await _requireEmpty();
    final lookup = await lookupRecoveryCode(recoveryCode);
    if (!lookup.valid) {
      throw const SignInException(
        SignInFailure.invalidRecoveryCode,
        'the recovery code is not valid',
      );
    }
    if (lookup.verificationRequired && verificationToken == null) {
      throw const SignInException(
        SignInFailure.verificationRequired,
        'verify the account phone number first',
      );
    }
    final id = lookup.accountId ?? accountId;
    if (id == null) {
      throw const SignInException(
        SignInFailure.unknownAccount,
        'the server did not say which account the code is for',
      );
    }
    final now = _ctx.now();
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
    final session = await _ctx.api.identity.recoveryRedeem(
      RecoveryRedeemRequest(
        recoveryCode: recoveryCode,
        identityKey: aik.publicKey,
        device: await keys.registration(
          name: deviceName ?? _ctx.config.deviceName,
          platform: _ctx.config.platform,
        ),
        prekeys: prekeys.toUpload(),
        verificationToken: verificationToken,
        password: password == null
            ? null
            : await _passwordSetup(password, aik, id),
      ),
    );
    await _persist(
      keys: keys,
      accountKey: aik,
      prekeys: prekeys,
      session: session,
      profileKey: newSymmetricKey(_ctx.random),
      phoneNumber: phoneNumber,
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

  // ------------------------------------------------------ change password

  /// Sets or changes the account password from this signed-in device
  /// (`PUT /v1/account/password`).
  ///
  /// The new password is turned into an auth key and a wrapped copy of the
  /// account identity key on this device; the server sees only those. Changing
  /// an existing password needs the proof the server asks for: the
  /// [currentPassword] (this device derives its auth key from the server's
  /// stored parameters for [phoneNumber], else the number this device signed
  /// in with) or a [verificationToken] from a fresh phone verification.
  /// Setting a first password needs neither.
  ///
  /// Wrong-password and lockout answers arrive as `ApiException`
  /// (`invalid_credentials`, `password_locked`); the new password never
  /// leaves this method except as the derived keys.
  Future<void> changePassword({
    required String newPassword,
    String? currentPassword,
    String? verificationToken,
    String? phoneNumber,
  }) async {
    final self = _ctx.identity;
    final currentAuthKey = currentPassword == null
        ? null
        : await _authKeyOf(currentPassword, phoneNumber);
    await _ctx.api.identity.setPassword(
      SetPasswordRequest(
        password: await _passwordSetup(
          newPassword,
          self.accountKey,
          self.accountId,
        ),
        currentAuthKey: currentAuthKey,
        verificationToken: verificationToken,
      ),
    );
  }

  /// The auth key of [password] under the server's stored parameters for
  /// [phoneNumber] (default: the number this device signed in with).
  Future<Uint8List> _authKeyOf(String password, String? phoneNumber) async {
    final number =
        phoneNumber ?? (await _ctx.db.accountDao.current())?.phoneNumber;
    if (number == null) {
      throw const SignInException(
        SignInFailure.wrongPassword,
        'the phone number is needed to check the current password',
      );
    }
    final params = await _ctx.api.identity.passwordParams(number);
    try {
      return (await PasswordKeys.derive(
        password: password,
        salt: params.salt,
        params: params.kdf,
      )).authKey;
    } on CryptoV2Exception {
      throw const SignInException(
        SignInFailure.untrustedAccountKey,
        'the server asked for weaker password hashing than Helix allows',
      );
    }
  }

  // ---------------------------------------------------- delete account

  /// Deletes the account on the server (`DELETE /v1/account`), proving
  /// ownership the way the server accepts for this account:
  ///
  /// - an account with a password: the [password] (its auth key is derived
  ///   here; the password never leaves the device), or a [verificationToken]
  ///   from a fresh phone verification;
  /// - an account with a number on a server that sends texts: a
  ///   [verificationToken] for that number (single use);
  /// - any other account (no password, no number or no SMS): neither is
  ///   given, and this device signs a fresh server challenge with its
  ///   signing key (`deleteAccountSignatureBody`).
  ///
  /// The caller picks by what the user can supply: a password when the
  /// account has one, else the token when the server texts, else none. The
  /// server's `invalid_credentials` answer lists what it would have
  /// accepted (`details.accepted`). This only deletes the account on the
  /// server; `Engine.deleteAccount` also wipes this device.
  Future<void> deleteAccount({
    String? password,
    String? verificationToken,
    String? phoneNumber,
  }) async {
    final self = _ctx.identity;
    if (password != null) {
      await _ctx.api.compliance.deleteAccount(
        currentAuthKey: await _authKeyOf(password, phoneNumber),
      );
    } else if (verificationToken != null) {
      await _ctx.api.compliance.deleteAccount(
        verificationToken: verificationToken,
      );
    } else {
      final challenge = await _ctx.api.identity.deviceChallenge(
        DeviceChallengeRequest(
          accountId: self.accountId,
          deviceId: self.deviceId,
        ),
      );
      await _ctx.api.compliance.deleteAccount(
        deviceProof: DeviceKeyProof(
          challengeId: challenge.challengeId,
          challenge: challenge.challenge,
          signature: await self.keys.signingKey.sign(
            deleteAccountSignatureBody(challenge.challenge),
          ),
        ),
      );
    }
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

  Future<LinkProposal> _awaitApproval(NewDeviceLink link) async {
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
            // Checks the approver's certificate and its signature over this
            // link; nothing is stored yet.
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
          return LinkProposal._(
            () async => _addDevice(
              accountId: provision.accountId,
              accountKey: await Ed25519KeyPair.fromSeed(
                provision.identityKeySeed,
              ),
              deviceName: link._deviceName,
              linkToken: token,
              profileKey: provision.profileKey,
            ),
            accountId: provision.accountId,
            phoneMask: provision.phoneMask,
            helixName: provision.helixName,
            fingerprint: Provisioning.keyCode(provision.identityKey),
            approverDeviceId: provision.approverDeviceId,
          );
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

/// Asked by [NewDeviceLink.complete] once an approval has arrived and
/// checked out, before anything is kept: show the user the account
/// ([LinkProposal.phoneMask], [LinkProposal.helixName]) and answer whether
/// it is theirs.
typedef LinkConfirm = Future<bool> Function(LinkProposal proposal);

/// The account a signed-in device offers this new device (CRYPTO_V2.md §2a).
///
/// The approval is cryptographically bound to the link (the approver is a
/// certified device of [accountId] and signed this link), but anyone who
/// saw the link's QR code can approve it with an account of their own, so
/// the user has to recognise the account: [phoneMask] and [helixName] are
/// what the approver claims, [fingerprint] is the account key's short form
/// for comparing with the approving device. Nothing is stored until
/// [accept]; [reject] (or dropping the proposal) leaves the device empty.
final class LinkProposal {
  LinkProposal._(
    this._accept, {
    required this.accountId,
    required this.phoneMask,
    required this.helixName,
    required this.fingerprint,
    required this.approverDeviceId,
  });

  final String accountId;

  /// The account's phone number, masked (`+88017*****01`), as the approver
  /// states it; null when the account has none.
  final String? phoneMask;

  /// The account's `~Helix name`, as the approver states it.
  final String? helixName;

  /// 20 hex digits of the account key's hash, in groups of four.
  final String fingerprint;
  final String approverDeviceId;

  final Future<void> Function() _accept;
  bool _used = false;

  /// Registers this device with the account and keeps the keys.
  Future<void> accept() {
    if (_used) throw StateError('this proposal was already answered');
    _used = true;
    return _accept();
  }

  /// Declines: nothing was stored.
  void reject() => _used = true;
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

  /// Waits for a signed-in device to approve and returns what it offers,
  /// after checking the approval (the approver is a certified device of the
  /// account and signed this link). Nothing is stored yet: the UI shows the
  /// proposal and calls [LinkProposal.accept] or [LinkProposal.reject].
  /// Throws `SignInException(linkExpired)` on expiry or [cancel].
  Future<LinkProposal> awaitApproval() => _account._awaitApproval(this);

  /// [awaitApproval], then [confirm]: registers this device only if it
  /// answers true (`SignInException(linkDeclined)` otherwise). There is no
  /// variant without the question, because a link approved by someone else
  /// would silently put this device on their account.
  Future<void> complete({required LinkConfirm confirm}) async {
    final proposal = await awaitApproval();
    if (!await confirm(proposal)) {
      proposal.reject();
      throw const SignInException(
        SignInFailure.linkDeclined,
        'the account was not confirmed',
      );
    }
    await proposal.accept();
  }

  void cancel() => _cancel.cancel();
}
