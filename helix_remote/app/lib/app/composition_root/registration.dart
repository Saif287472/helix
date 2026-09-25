part of '../composition_root.dart';

const _discoverySaltKey = 'contacts.discovery_salt';

mixin RemoteCompositionRegistration on RemoteCompositionRootBase {
  /// Fetches and caches the per-deployment discovery salt used to hash
  /// phone numbers (see `phone_hashing.dart`). Cached hard once fetched -
  /// this must never be re-fetched/rotated client-side, since that would
  /// silently change every phone hash this device computes.
  Future<String> _getOrFetchDiscoverySalt({
    required KeyValueStore store,
    required HelixRemoteRestClient rest,
  }) async {
    final cached = await store.read(_discoverySaltKey);
    if (cached != null && cached.isNotEmpty) return cached;
    final response = await rest.fetchDiscoverySalt();
    final salt = response['salt'] as String;
    await store.write(_discoverySaltKey, salt);
    return salt;
  }

  /// Requests a one-time verification code for [phoneNumber]. The server
  /// sends the code via SMS (BulkSMSBD). If SMS delivery is not configured
  /// on the server, the request will fail with a 503.
  Future<void> requestOtp(String phoneNumber) async {
    final rest = _requireReady(_restClient, 'restClient');
    final store = _requireReady(_keyValue, 'keyValue');
    final normalizedPhone = RemoteAccountValidation.normalizePhoneNumber(
      phoneNumber,
    );
    final salt = await _getOrFetchDiscoverySalt(store: store, rest: rest);
    final hash = phoneHash(salt, normalizedPhone);
    await rest.requestPhoneOtp(
      phoneHash: hash,
      phoneNumber: normalizedPhone,
    );
  }

  /// Validates an invite code without consuming it, so the UI can fail fast
  /// on a bad/expired code before starting the phone+OTP signup flow.
  Future<Map<String, dynamic>> lookupInvite(String inviteCode) async {
    final rest = _requireReady(_restClient, 'restClient');
    return rest.lookupInvite(inviteCode: inviteCode);
  }

  /// Self-issues a free invite for Helix Global's signup path and fires a
  /// local notification with the code, tappable to auto-fill.
  Future<String> requestGlobalAutoInvite() async {
    final rest = _requireReady(_restClient, 'restClient');
    final response = await rest.autoIssueGlobalInvite();
    final code = response['invite_code'] as String;
    await LocalNotificationService.showInviteCode(code: code);
    return code;
  }

  Future<void> registerAndLogin({
    required String phoneNumber,
    required String displayName,
    required String otpCode,
    required String inviteCode,
  }) async {
    if (_state != RemoteStartupState.unauthenticated) {
      throw StateError('Cannot register in state $_state');
    }
    final normalizedPhone = RemoteAccountValidation.normalizePhoneNumber(
      phoneNumber,
    );
    final normalizedDisplayName = RemoteAccountValidation.normalizeDisplayName(
      displayName,
    );
    final phoneError = RemoteAccountValidation.phoneNumberError(
      normalizedPhone,
    );
    if (phoneError != null) throw StateError(phoneError);
    final displayNameError = RemoteAccountValidation.displayNameError(
      normalizedDisplayName,
    );
    if (displayNameError != null) throw StateError(displayNameError);

    final rest = _requireReady(_restClient, 'restClient');
    final store = _requireReady(_keyValue, 'keyValue');
    final ms = _requireReady(_messagingService, 'messagingService');

    final salt = await _getOrFetchDiscoverySalt(store: store, rest: rest);
    final normalizedPhoneHash = phoneHash(salt, normalizedPhone);

    final pendingRegistration = await _loadOrCreatePendingRegistration(
      store: store,
      phoneNumber: normalizedPhone,
      phoneHash: normalizedPhoneHash,
      displayName: normalizedDisplayName,
    );
    final deviceSigningEd25519 = crypto_pkg.Ed25519();

    final accountIdStr = pendingRegistration.accountId;
    final deviceIdStr = pendingRegistration.deviceId;
    final deviceName = pendingRegistration.deviceName;
    final pubKeyStr = pendingRegistration.accountIdentityPublicKey;
    final deviceSigningPubKeyStr = pendingRegistration.deviceSigningPublicKey;
    final deviceAgreementPubKeyStr =
        pendingRegistration.deviceAgreementPublicKey;
    final identityPrivStr = pendingRegistration.identityPrivateKey;
    final deviceSigningPrivStr = pendingRegistration.deviceSigningPrivateKey;
    final deviceAgreementPrivStr =
        pendingRegistration.deviceAgreementPrivateKey;
    final deviceAgreementPrivBytes =
        pendingRegistration.deviceAgreementPrivateBytes;
    final deviceAgreementPubKeyBytes =
        pendingRegistration.deviceAgreementPublicBytes;

    await rest.registerAccount(
      accountId: accountIdStr,
      phoneHash: normalizedPhoneHash,
      otpCode: otpCode,
      inviteCode: inviteCode,
      displayName: normalizedDisplayName,
      accountIdentityPublicKey: pubKeyStr,
      deviceId: deviceIdStr,
      deviceSigningPublicKey: deviceSigningPubKeyStr,
      deviceAgreementPublicKey: deviceAgreementPubKeyStr,
      accountRegistrationSignature:
          pendingRegistration.accountRegistrationSignature,
      deviceRegistrationSignature:
          pendingRegistration.deviceRegistrationSignature,
      deviceName: deviceName,
      // Display-only hint for the admin console - never the full number.
      // normalizedPhone is always '+' followed only by digits (see
      // RemoteAccountValidation.normalizePhoneNumber), so its last 4
      // characters are always digits.
      phoneLast4: normalizedPhone,
    );

    final challengeResp = await rest.getChallenge(
      accountId: accountIdStr,
      deviceId: deviceIdStr,
    );
    final challenge = challengeResp['challenge'] as String;
    final sig = await deviceSigningEd25519.sign(
      utf8.encode(challenge),
      keyPair: pendingRegistration.deviceSigningKeyPair,
    );
    final sigStr = _base64Url(sig.bytes);

    final loginResp = await rest.loginDevice(
      accountId: accountIdStr,
      deviceId: deviceIdStr,
      signature: sigStr,
    );

    final accessToken = loginResp['token'] as String;
    final refreshToken = loginResp['refresh_token'] as String? ?? '';
    rest.accessToken = accessToken;

    await store.write('access_token', accessToken);
    await store.write('refresh_token', refreshToken);
    await store.write('account_id', accountIdStr);
    await store.write('phone_number', normalizedPhone);
    await store.write('identity_public_key', pubKeyStr);
    await store.write('identity_private_key', identityPrivStr);
    await store.write('device_id', deviceIdStr);
    await store.write('device_signing_public_key', deviceSigningPubKeyStr);
    await store.write('device_signing_private_key', deviceSigningPrivStr);
    await store.write('device_agreement_public_key', deviceAgreementPubKeyStr);
    await store.write('device_agreement_private_key', deviceAgreementPrivStr);

    await _publishInitialPrekeys(
      rest: rest,
      secureKeys: _requireReady(_keyStorage, 'keyStorage'),
      accountIdentityKeyPair: pendingRegistration.identityKeyPair,
      deviceId: deviceIdStr,
    );

    ms.setCryptoKeys(
      devicePrivateKey: deviceAgreementPrivBytes,
      devicePublicKey: deviceAgreementPubKeyBytes,
    );

    ms.setupAccount(
      account: RemoteAccount(
        accountId: accountIdStr,
        identityPublicKey: pubKeyStr,
        createdAt: DateTime.now(),
      ),
      device: RemoteDevice(
        deviceId: deviceIdStr,
        deviceName: deviceName,
        deviceSigningPublicKey: deviceSigningPubKeyStr,
        deviceAgreementPublicKey: deviceAgreementPubKeyStr,
        createdAt: DateTime.now(),
      ),
    );

    ms.setDisplayName(normalizedDisplayName);
    await _clearPendingRegistration(store);
    setAuthenticated(accessToken);
    await startRuntime();
    await reconcileContactsAndRequests();
  }

  Future<void> recoverAccount({
    required String accountId,
    required String recoveryCode,
    String? phoneHash,
  }) async {
    final rest = _requireReady(_restClient, 'restClient');
    final store = _requireReady(_keyValue, 'keyValue');
    final ms = _requireReady(_messagingService, 'messagingService');

    final ed25519 = crypto_pkg.Ed25519();
    final identityKeyPair = await ed25519.newKeyPair();
    final identityPubKey = await identityKeyPair.extractPublicKey();

    final deviceSigningKeyPair = await ed25519.newKeyPair();
    final deviceSigningPubKey = await deviceSigningKeyPair.extractPublicKey();

    final x25519 = crypto_pkg.X25519();
    final deviceAgreementKeyPair = await x25519.newKeyPair();
    final deviceAgreementPubKey =
        await deviceAgreementKeyPair.extractPublicKey();

    final deviceIdStr =
        'dev_${_bytesToHex(deviceSigningPubKey.bytes.sublist(0, 4))}';
    final deviceName = 'Dev ${deviceIdStr.substring(0, 8)}';

    final identityPubKeyStr = _base64Url(identityPubKey.bytes);
    final identityPrivStr = _base64Url(
      await identityKeyPair.extractPrivateKeyBytes(),
    );
    final deviceSigningPubKeyStr = _base64Url(deviceSigningPubKey.bytes);
    final deviceSigningPrivStr = _base64Url(
      await deviceSigningKeyPair.extractPrivateKeyBytes(),
    );
    final deviceAgreementPubKeyStr = _base64Url(deviceAgreementPubKey.bytes);
    final deviceAgreementPrivStr = _base64Url(
      await deviceAgreementKeyPair.extractPrivateKeyBytes(),
    );
    final deviceAgreementPrivBytes =
        await deviceAgreementKeyPair.extractPrivateKeyBytes();
    final deviceAgreementPubKeyBytes = deviceAgreementPubKey.bytes;

    final redeemResp = await rest.redeemRecovery(
      accountId: accountId,
      recoveryCode: recoveryCode,
      deviceId: deviceIdStr,
      deviceSigningPublicKey: deviceSigningPubKeyStr,
      deviceAgreementPublicKey: deviceAgreementPubKeyStr,
      deviceName: deviceName,
      accountIdentityPublicKey: identityPubKeyStr,
      phoneHash: phoneHash,
    );

    final accessToken = redeemResp['access_token'] as String;
    final refreshToken = redeemResp['refresh_token'] as String? ?? '';
    final displayName = redeemResp['display_name'] as String? ?? 'Helix User';
    rest.accessToken = accessToken;

    await store.write('access_token', accessToken);
    await store.write('refresh_token', refreshToken);
    await store.write('account_id', accountId);
    if (phoneHash != null && phoneHash.isNotEmpty) {
      await store.write('phone_hash', phoneHash);
    }
    await store.write('identity_public_key', identityPubKeyStr);
    await store.write('identity_private_key', identityPrivStr);
    await store.write('device_id', deviceIdStr);
    await store.write('device_signing_public_key', deviceSigningPubKeyStr);
    await store.write('device_signing_private_key', deviceSigningPrivStr);
    await store.write('device_agreement_public_key', deviceAgreementPubKeyStr);
    await store.write('device_agreement_private_key', deviceAgreementPrivStr);

    await _publishInitialPrekeys(
      rest: rest,
      secureKeys: _requireReady(_keyStorage, 'keyStorage'),
      accountIdentityKeyPair: identityKeyPair,
      deviceId: deviceIdStr,
    );

    ms.setCryptoKeys(
      devicePrivateKey: Uint8List.fromList(deviceAgreementPrivBytes),
      devicePublicKey: Uint8List.fromList(deviceAgreementPubKeyBytes),
    );

    ms.setupAccount(
      account: RemoteAccount(
        accountId: accountId,
        identityPublicKey: identityPubKeyStr,
        createdAt: DateTime.now(),
      ),
      device: RemoteDevice(
        deviceId: deviceIdStr,
        deviceName: deviceName,
        deviceSigningPublicKey: deviceSigningPubKeyStr,
        deviceAgreementPublicKey: deviceAgreementPubKeyStr,
        createdAt: DateTime.now(),
      ),
    );

    ms.setDisplayName(displayName);
    await _clearPendingRegistration(store);
    setAuthenticated(accessToken);
    await startRuntime();
    await reconcileContactsAndRequests();
  }

  Future<void> reconcileContactsAndRequests() async {
    final rest = _restClient;
    final ms = _messagingService;
    if (rest == null || ms == null) return;
    try {
      final contacts = await rest.fetchContacts();
      for (final c in contacts) {
        final peerAccountId = c['account_id'] as String?;
        if (peerAccountId == null || peerAccountId.isEmpty) continue;
        final nickname =
            c['nickname'] as String? ?? c['display_name'] as String? ?? '';
        final status = (c['status'] as String? ?? 'Accepted').toLowerCase();
        final effectiveStatus = status == 'accepted'
            ? 'Accepted'
            : (status == 'pending_received'
                ? 'PendingReceived'
                : 'PendingSent');
        ms.db.upsertContact(
          RemoteContact(
            peerAccountId: peerAccountId,
            nickname: nickname,
            status: effectiveStatus,
          ),
        );
      }

      final requests = await rest.fetchContactRequests();
      final myAccountId = await _keyValue?.read('account_id');
      for (final r in requests) {
        final reqId = r['request_id'] as String? ?? '';
        final fromId = r['from_account_id'] as String? ?? '';
        final toId = r['to_account_id'] as String? ?? '';
        final rawStatus = (r['status'] as String? ?? 'PENDING').toUpperCase();
        final isSent = fromId == myAccountId;
        final peerId = isSent ? toId : fromId;
        if (peerId.isEmpty) continue;

        final effectiveStatus = rawStatus == 'ACCEPTED'
            ? 'Accepted'
            : (rawStatus == 'REJECTED'
                ? 'Rejected'
                : (rawStatus == 'CANCELLED' ? 'Cancelled' : 'Pending'));

        ms.db.upsertContactRequest(
          RemoteContactRequest(
            requestId: reqId,
            peerAccountId: peerId,
            direction: isSent ? 'sent' : 'received',
            status: effectiveStatus,
            updatedAt: r['updated_at'] as int? ??
                DateTime.now().millisecondsSinceEpoch,
            nickname: r['nickname'] as String? ?? '',
          ),
        );

        if (rawStatus == 'ACCEPTED') {
          final existing = ms.db.getContact(peerId);
          ms.db.upsertContact(
            RemoteContact(
              peerAccountId: peerId,
              nickname:
                  existing?.nickname ?? r['nickname'] as String? ?? '',
              status: 'Accepted',
            ),
          );
        }
      }

      ms.notifyContactsChanged();
    } catch (e) {
      AppLogger.instance.warn('reconcileContacts', 'Failed: $e');
    }
  }

  Future<_PendingRegistration> _loadOrCreatePendingRegistration({
    required KeyValueStore store,
    required String phoneNumber,
    required String phoneHash,
    required String displayName,
  }) async {
    final existing = await _readPendingRegistration(store);
    if (existing != null &&
        existing.phoneHash == phoneHash &&
        existing.displayName == displayName) {
      return existing;
    }
    if (existing != null) {
      await _clearPendingRegistration(store);
    }
    final created = await _PendingRegistration.create(
      phoneNumber: phoneNumber,
      phoneHash: phoneHash,
      displayName: displayName,
    );
    await store.write(_pendingRegistrationKey, jsonEncode(created.toJson()));
    return created;
  }

  Future<_PendingRegistration?> _readPendingRegistration(
    KeyValueStore store,
  ) async {
    final encoded = await store.read(_pendingRegistrationKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return _PendingRegistration.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
    } catch (_) {
      await _clearPendingRegistration(store);
      return null;
    }
  }

  Future<void> _clearPendingRegistration(KeyValueStore store) =>
      store.delete(_pendingRegistrationKey);

  Future<void> _publishInitialPrekeys({
    required HelixRemoteRestClient rest,
    required RemoteSecureKeyStorage secureKeys,
    required crypto_pkg.SimpleKeyPair accountIdentityKeyPair,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc();
    final manager = RemotePrekeyManager();
    final publication = await manager.createPublication(
      accountIdentitySigningKey: accountIdentityKeyPair,
      signedPrekeyId: now.millisecondsSinceEpoch,
      firstOneTimePrekeyId: now.millisecondsSinceEpoch + 1,
      oneTimePrekeyCount: 10,
      now: now,
    );

    final signedPrivateRef =
        'prekey_${deviceId}_signed_${publication.signedPrekeyId}';
    await secureKeys.writeKeyRecord(
      signedPrivateRef,
      RemoteSecureKeyRecord(
        role: 'signed_prekey_private',
        version: 1,
        deviceId: deviceId,
        value: publication.signedPrekeyPrivate,
        createdAt: publication.createdAt,
        rotationState: 'active',
        metadata: {
          'key_id': publication.signedPrekeyId,
          'expires_at': publication.expiresAt.millisecondsSinceEpoch,
        },
      ),
    );
    _database?.saveLocalPrekey(
      keyId: publication.signedPrekeyId,
      role: 'signed_prekey',
      deviceId: deviceId,
      publicKey: publication.signedPrekeyPublic,
      privateKeyRef: signedPrivateRef,
      signature: publication.signedPrekeySignature,
      createdAt: publication.createdAt.millisecondsSinceEpoch,
      expiresAt: publication.expiresAt.millisecondsSinceEpoch,
      rotationState: 'active',
    );

    for (final oneTimePrekey in publication.oneTimePrekeys) {
      final privateRef = 'prekey_${deviceId}_otk_${oneTimePrekey.keyId}';
      await secureKeys.writeKeyRecord(
        privateRef,
        RemoteSecureKeyRecord(
          role: 'one_time_prekey_private',
          version: 1,
          deviceId: deviceId,
          value: oneTimePrekey.privateKey,
          createdAt: publication.createdAt,
          rotationState: 'active',
          metadata: {'key_id': oneTimePrekey.keyId},
        ),
      );
      _database?.saveLocalPrekey(
        keyId: oneTimePrekey.keyId,
        role: 'one_time_prekey',
        deviceId: deviceId,
        publicKey: oneTimePrekey.publicKey,
        privateKeyRef: privateRef,
        createdAt: publication.createdAt.millisecondsSinceEpoch,
        rotationState: 'active',
      );
    }

    await rest.uploadPreKeys(
      signedPrekeyId: publication.signedPrekeyId,
      signedPrekey: publication.signedPrekeyPublic,
      signedPrekeySignature: publication.signedPrekeySignature,
      oneTimePrekeys: publication.oneTimePrekeyPublicPayloads(),
    );
  }
}
