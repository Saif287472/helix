part of '../composition_root.dart';

/// What the server says about a phone number before sign-in.
class RemotePasswordLookup {
  const RemotePasswordLookup({
    required this.phoneNumber,
    required this.phoneHash,
    required this.accountExists,
    required this.hasPassword,
    this.kdfParams,
    this.kdfSalt,
  });

  final String phoneNumber;
  final String phoneHash;
  final bool accountExists;
  final bool hasPassword;
  final PasswordKdfParams? kdfParams;
  final String? kdfSalt;
}

/// The password could not unlock this account's encryption key. The server
/// accepted the password, so this means the stored key is from an older
/// password - the user has to reset it with an SMS code.
class RemotePasswordKeyMismatch implements Exception {
  const RemotePasswordKeyMismatch();
  @override
  String toString() => 'RemotePasswordKeyMismatch';
}

mixin RemoteCompositionPassword
    on RemoteCompositionRootBase, RemoteCompositionRegistration {
  Future<String> _phoneHashFor(String normalizedPhone) async {
    final rest = _requireReady(_restClient, 'restClient');
    final store = _requireReady(_keyValue, 'keyValue');
    final salt = await _getOrFetchDiscoverySalt(store: store, rest: rest);
    return phoneHash(salt, normalizedPhone);
  }

  /// Asks the server whether [phoneNumber] has an account and a password,
  /// so onboarding can offer the password instead of spending an SMS code.
  Future<RemotePasswordLookup> lookupPasswordAccount(String phoneNumber) async {
    final rest = _requireReady(_restClient, 'restClient');
    final normalized = RemoteAccountValidation.normalizePhoneNumber(
      phoneNumber,
    );
    final hash = await _phoneHashFor(normalized);
    final response = await rest.getPasswordParams(phoneHash: hash);
    final hasPassword = response['has_password'] == true;
    return RemotePasswordLookup(
      phoneNumber: normalized,
      phoneHash: hash,
      accountExists: response['account_exists'] == true,
      hasPassword: hasPassword,
      kdfParams: hasPassword
          ? PasswordKdfParams.fromJson(
              response['kdf_params'] as Map<String, dynamic>,
            )
          : null,
      kdfSalt: hasPassword ? response['kdf_salt'] as String? : null,
    );
  }

  /// Signs this device in with phone number + password, as an additional
  /// device on the account - every other signed-in device stays signed in.
  Future<void> signInWithPassword({
    required RemotePasswordLookup lookup,
    required String password,
  }) async {
    final params = lookup.kdfParams;
    final salt = lookup.kdfSalt;
    if (!lookup.hasPassword || params == null || salt == null) {
      throw StateError('This account has no password yet');
    }
    final keys = await PasswordVault.deriveKeys(
      password: password,
      salt: salt,
      params: params,
    );
    await signInWithPasswordKeys(lookup: lookup, keys: keys);
  }

  /// [signInWithPassword] with the password already stretched - first-launch
  /// setup checks the password before this root exists and hands over the
  /// keys, so the password itself goes no further than the setup screen.
  Future<void> signInWithPasswordKeys({
    required RemotePasswordLookup lookup,
    required PasswordKeys keys,
  }) async {
    if (_state != RemoteStartupState.unauthenticated) {
      throw StateError('Cannot sign in in state $_state');
    }
    final rest = _requireReady(_restClient, 'restClient');
    final store = _requireReady(_keyValue, 'keyValue');
    final ms = _requireReady(_messagingService, 'messagingService');

    final ed25519 = crypto_pkg.Ed25519();
    final signingKeyPair = await ed25519.newKeyPair();
    final signingPublic = await signingKeyPair.extractPublicKey();
    final agreementKeyPair = await crypto_pkg.X25519().newKeyPair();
    final agreementPublic = await agreementKeyPair.extractPublicKey();
    final deviceId = 'dev_${_bytesToHex(signingPublic.bytes.sublist(0, 6))}';
    final deviceName = await describeThisDevice(
      fallback: 'Dev ${deviceId.substring(0, 8)}',
    );
    final signingPublicStr = _base64Url(signingPublic.bytes);
    final agreementPublicStr = _base64Url(agreementPublic.bytes);
    final transcript = [
      'helix.remote.password-login.v1',
      lookup.phoneHash,
      deviceId,
      signingPublicStr,
      agreementPublicStr,
      deviceName,
    ].join('\n');
    final transcriptSignature = await ed25519.sign(
      utf8.encode(transcript),
      keyPair: signingKeyPair,
    );

    final response = await rest.passwordLogin(
      phoneHash: lookup.phoneHash,
      authKey: keys.authKey,
      deviceId: deviceId,
      deviceName: deviceName,
      deviceSigningPublicKey: signingPublicStr,
      deviceAgreementPublicKey: agreementPublicStr,
      deviceSignature: _base64Url(transcriptSignature.bytes),
    );
    final accountId = response['account_id'] as String;
    final identityPublic = response['account_identity_public_key'] as String;
    final accessToken = response['token'] as String;
    final refreshToken = response['refresh_token'] as String;
    rest.accessToken = accessToken;

    final crypto_pkg.SimpleKeyPair identityKeyPair;
    try {
      final identityPrivate = await PasswordVault.unwrapIdentityKey(
        wrapKey: keys.wrapKey,
        wrapped: response['wrapped_identity_key'] as String,
        identityPublicKey: identityPublic,
      );
      identityKeyPair = await ed25519.newKeyPairFromSeed(identityPrivate);
      final derivedPublic = await identityKeyPair.extractPublicKey();
      if (_base64Url(derivedPublic.bytes) != identityPublic) {
        throw const RemotePasswordKeyMismatch();
      }
    } catch (_) {
      // The device was already registered; take it back off the account so
      // it does not sit in the device list unable to read anything.
      try {
        await rest.revokeDevice(deviceId);
      } catch (_) {}
      rest.accessToken = null;
      throw const RemotePasswordKeyMismatch();
    }

    await store.write('access_token', accessToken);
    await store.write('refresh_token', refreshToken);
    await store.write('account_id', accountId);
    await store.write('phone_number', lookup.phoneNumber);
    await store.write('identity_public_key', identityPublic);
    await store.write(
      'identity_private_key',
      _base64Url(await identityKeyPair.extractPrivateKeyBytes()),
    );
    await store.write('device_id', deviceId);
    await store.write('device_signing_public_key', signingPublicStr);
    await store.write(
      'device_signing_private_key',
      _base64Url(await signingKeyPair.extractPrivateKeyBytes()),
    );
    await store.write('device_agreement_public_key', agreementPublicStr);
    final agreementPrivate = await agreementKeyPair.extractPrivateKeyBytes();
    await store.write(
      'device_agreement_private_key',
      _base64Url(agreementPrivate),
    );

    await _publishInitialPrekeys(
      rest: rest,
      secureKeys: _requireReady(_keyStorage, 'keyStorage'),
      accountIdentityKeyPair: identityKeyPair,
      deviceId: deviceId,
    );

    ms.setCryptoKeys(
      devicePrivateKey: Uint8List.fromList(agreementPrivate),
      devicePublicKey: Uint8List.fromList(agreementPublic.bytes),
    );
    ms.setupAccount(
      account: RemoteAccount(
        accountId: accountId,
        identityPublicKey: identityPublic,
        createdAt: DateTime.now(),
      ),
      device: RemoteDevice(
        deviceId: deviceId,
        deviceName: deviceName,
        deviceSigningPublicKey: signingPublicStr,
        deviceAgreementPublicKey: agreementPublicStr,
        createdAt: DateTime.now(),
      ),
    );
    final displayName = response['display_name'] as String?;
    if (displayName != null && displayName.isNotEmpty) {
      ms.setDisplayName(displayName);
    }
    // Before the app opens, so chats appear with their history rather than
    // filling in afterwards. A failure is retried on the next launch.
    await restoreHistoryBackup();
    setAuthenticated(accessToken);
    await startRuntime();
    await reconcileContactsAndRequests();
  }

  /// Whether the signed-in account has a password. `null` when the server
  /// could not be asked - the caller should not block the user on that.
  Future<bool?> accountHasPassword() async {
    final rest = _restClient;
    if (rest == null || _accessToken == null) return null;
    try {
      final status = await rest.getPasswordStatus();
      return status['has_password'] == true;
    } catch (_) {
      return null;
    }
  }

  /// Sets the account's first password, or changes it. Changing needs either
  /// [currentPassword] or a fresh SMS code ([otpCode], [otpChallengeId]).
  Future<void> setAccountPassword({
    required String newPassword,
    String? currentPassword,
    String? otpCode,
    String? otpChallengeId,
  }) async {
    final error = PasswordVault.passwordError(newPassword);
    if (error != null) throw ArgumentError(error);
    final rest = _requireReady(_restClient, 'restClient');
    final store = _requireReady(_keyValue, 'keyValue');
    final identityPrivate = await store.read('identity_private_key');
    final identityPublic = await store.read('identity_public_key');
    if (identityPrivate == null || identityPublic == null) {
      throw StateError('This device does not hold the account key');
    }

    String? currentAuthKey;
    if (currentPassword != null) {
      final phone = await store.read('phone_number');
      if (phone == null) throw StateError('No phone number on this device');
      final lookup = await lookupPasswordAccount(phone);
      if (lookup.hasPassword) {
        currentAuthKey = (await PasswordVault.deriveKeys(
          password: currentPassword,
          salt: lookup.kdfSalt!,
          params: lookup.kdfParams!,
        )).authKey;
      }
    }

    const params = PasswordKdfParams();
    final salt = PasswordVault.newSalt();
    final keys = await PasswordVault.deriveKeys(
      password: newPassword,
      salt: salt,
      params: params,
    );
    final wrapped = await PasswordVault.wrapIdentityKey(
      wrapKey: keys.wrapKey,
      identityPrivateKey: _base64UrlDecode(identityPrivate),
      identityPublicKey: identityPublic,
    );
    await rest.setPassword(
      kdfParams: params.toJson(),
      kdfSalt: salt,
      authKey: keys.authKey,
      wrappedIdentityKey: wrapped,
      currentAuthKey: currentAuthKey,
      otpCode: otpCode,
      otpChallengeId: otpChallengeId,
    );
  }

  /// Requests an SMS code for the signed-in account's own number, for
  /// resetting a forgotten password from a device that is still signed in.
  Future<RemoteOtpRequestResult> requestOtpForOwnNumber() async {
    final store = _requireReady(_keyValue, 'keyValue');
    final phone = await store.read('phone_number');
    if (phone == null) throw StateError('No phone number on this device');
    return requestOtp(phone);
  }

  /// Signs out every other device on this account. Returns how many.
  Future<int> signOutOtherDevices() =>
      _requireReady(_restClient, 'restClient').revokeOtherDevices();
}
