part of '../composition_root.dart';

mixin RemoteCompositionSession on RemoteCompositionRootBase {
  @override
  void setAuthenticated(String accessToken) {
    _applyAccessToken(accessToken);
    _setState(RemoteStartupState.authenticatedAndSyncing);
    AppLock.attach(
      read: () {
        final settings = _messagingService?.db.getAppLockSettings();
        if (settings == null) return null;
        return (
          enabled: settings.enabled,
          relockAfterSeconds: settings.relockAfterSeconds,
        );
      },
      callActive: () => _callService?.activeCall != null,
    );
  }

  void _applyAccessToken(String accessToken) {
    _accessToken = accessToken;
    _restClient?.accessToken = accessToken;
    if (_attachmentService != null) {
      _attachmentService!.authToken = accessToken;
    }
  }

  @override
  Future<bool> refreshAccessToken() {
    final existing = _tokenRefreshInFlight;
    if (existing != null) return existing;
    final refresh = _refreshAccessTokenOnce();
    _tokenRefreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_tokenRefreshInFlight, refresh)) {
        _tokenRefreshInFlight = null;
      }
    });
  }

  Future<bool> _refreshAccessTokenOnce() async {
    final store = _keyValue;
    final rest = _restClient;
    if (store == null || rest == null) {
      _lastRefreshFailureKind = _RefreshFailureKind.missingSession;
      return false;
    }

    final storedRefreshToken = await store.read('refresh_token');
    if (storedRefreshToken == null || storedRefreshToken.isEmpty) {
      return _recoverSessionWithDeviceKey();
    }

    try {
      final response = await rest.refreshToken(
        refreshToken: storedRefreshToken,
      );
      final accessToken = response['token'] as String?;
      final refreshToken = response['refresh_token'] as String?;
      if (accessToken == null ||
          accessToken.isEmpty ||
          refreshToken == null ||
          refreshToken.isEmpty) {
        return _recoverSessionWithDeviceKey();
      }

      await _adoptSessionTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      return true;
    } on RemoteRestException catch (e) {
      if (_isAuthFailure(e.statusCode)) {
        if (_isTerminalSessionCode(e.serverCode)) {
          return _endSessionForGood();
        }
        // Expired (the device sat unused past the refresh lifetime),
        // replayed after a crash mid-rotation, or otherwise unrecognized:
        // none of these mean the device was signed out, so it proves who it
        // is again with its own key instead of costing the user an SMS code.
        return _recoverSessionWithDeviceKey();
      }
      _lastRefreshFailureKind = _RefreshFailureKind.transient;
      _lastError = _formatRefreshFailure(e);
      return false;
    } catch (e) {
      _lastRefreshFailureKind = _RefreshFailureKind.transient;
      _lastError = RemoteUserErrorCopy.unknownStartup();
      return false;
    }
  }

  Future<void> _adoptSessionTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _persistRotatedTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    final reconnectRealtime = _wsClient?.isConnected ?? false;
    _applyAccessToken(accessToken);
    if (reconnectRealtime) {
      unawaited(
        connectWebSocket().catchError((_) {
          _lastError = 'Realtime reconnect failed after session refresh.';
        }),
      );
    }
    _lastError = null;
    _lastRefreshFailureKind = _RefreshFailureKind.none;
  }

  /// Whether the JWT [token] is still valid for at least [margin], read
  /// from its own `exp` claim. The signature is the server's business; this
  /// only decides whether asking for a new one first is worth a round trip.
  bool _jwtValidFor(String token, Duration margin) {
    final parts = token.split('.');
    if (parts.length != 3) return false;
    try {
      final payload =
          jsonDecode(utf8.decode(_base64UrlDecode(parts[1])))
              as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! int) return false;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return expiresAt.isAfter(DateTime.now().add(margin));
    } catch (_) {
      return false;
    }
  }

  /// Codes after which signing in again with the device key cannot help:
  /// the server has signed this device out or removed the account.
  bool _isTerminalSessionCode(String? code) =>
      code == 'device_revoked' ||
      code == 'account_blocked' ||
      code == 'phone_blocked';

  Future<bool> _endSessionForGood() async {
    _lastRefreshFailureKind = _RefreshFailureKind.authRequired;
    _lastError = RemoteUserErrorCopy.authExpired();
    await _transitionToAuthRequired();
    return false;
  }

  /// Signs this device in again with the Ed25519 key it registered with -
  /// the same challenge login used right after registration. The session's
  /// keys are only purged when the server says the device is actually gone;
  /// a network failure leaves everything in place for the next attempt.
  ///
  /// A server that predates the `device_revoked` code hands a revoked device
  /// a token at login and only refuses it on use. Without the cooldown the
  /// app would sign in, be refused, sign in again, and loop; a second
  /// recovery inside the window is treated as the device being signed out.
  static const _deviceKeySignInCooldown = Duration(minutes: 2);
  DateTime? _lastDeviceKeySignInAt;

  Future<bool> _recoverSessionWithDeviceKey() async {
    final store = _keyValue;
    final rest = _restClient;
    if (store == null || rest == null) {
      _lastRefreshFailureKind = _RefreshFailureKind.missingSession;
      return false;
    }
    final accountId = await store.read('account_id');
    final deviceId = await store.read('device_id');
    final signingPrivate = await store.read('device_signing_private_key');
    final signingPublic = await store.read('device_signing_public_key');
    if (accountId == null ||
        accountId.isEmpty ||
        deviceId == null ||
        deviceId.isEmpty ||
        signingPrivate == null ||
        signingPrivate.isEmpty ||
        signingPublic == null ||
        signingPublic.isEmpty) {
      return _endSessionForGood();
    }

    final last = _lastDeviceKeySignInAt;
    if (last != null &&
        DateTime.now().difference(last) < _deviceKeySignInCooldown) {
      return _endSessionForGood();
    }

    try {
      final challengeResp = await rest.getChallenge(
        accountId: accountId,
        deviceId: deviceId,
      );
      final challenge = challengeResp['challenge'] as String;
      final keyPair = crypto_pkg.SimpleKeyPairData(
        _base64UrlDecode(signingPrivate),
        publicKey: crypto_pkg.SimplePublicKey(
          _base64UrlDecode(signingPublic),
          type: crypto_pkg.KeyPairType.ed25519,
        ),
        type: crypto_pkg.KeyPairType.ed25519,
      );
      final signature = await crypto_pkg.Ed25519().sign(
        utf8.encode(challenge),
        keyPair: keyPair,
      );
      final loginResp = await rest.loginDevice(
        accountId: accountId,
        deviceId: deviceId,
        signature: _base64Url(signature.bytes),
      );
      final accessToken = loginResp['token'] as String?;
      final refreshToken = loginResp['refresh_token'] as String?;
      if (accessToken == null ||
          accessToken.isEmpty ||
          refreshToken == null ||
          refreshToken.isEmpty) {
        return _endSessionForGood();
      }
      _lastDeviceKeySignInAt = DateTime.now();
      await _adoptSessionTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      return true;
    } on RemoteRestException catch (e) {
      if (e.isTransportFailure || !_isLoginRefusal(e.statusCode)) {
        _lastRefreshFailureKind = _RefreshFailureKind.transient;
        _lastError = _formatRefreshFailure(e);
        return false;
      }
      return _endSessionForGood();
    } catch (_) {
      _lastRefreshFailureKind = _RefreshFailureKind.transient;
      _lastError = RemoteUserErrorCopy.unknownStartup();
      return false;
    }
  }

  /// The challenge login refuses with 401/403 (bad signature, unknown or
  /// revoked device, blocked account) - never with a 5xx or 429.
  bool _isLoginRefusal(int? statusCode) =>
      statusCode == 401 || statusCode == 403 || statusCode == 404;

  String _formatRefreshFailure(RemoteRestException error) =>
      RemoteUserErrorCopy.refreshFailure(error, devConfig.restBaseUri);

  @override
  Future<void> _refreshRuntimeSession() async {
    final refreshed = await refreshAccessToken();
    if (!refreshed &&
        _lastRefreshFailureKind == _RefreshFailureKind.authRequired) {
      throw const RemoteRuntimeAuthRequired('Authentication required');
    }
  }

  Future<void> _persistRotatedTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final store = _requireReady(_keyValue, 'keyValue');
    // The pending marker is a single JSON blob written in one atomic `write`
    // call, so a crash can never leave behind a mismatched half-rotated pair
    // (unlike writing the two tokens as separate pending keys).
    await store.write(
      'token_rotation.pending',
      jsonEncode({'access_token': accessToken, 'refresh_token': refreshToken}),
    );
    await store.write('refresh_token', refreshToken);
    await store.write('access_token', accessToken);
    await store.delete('token_rotation.pending');
  }

  bool _isAuthFailure(int? statusCode) =>
      statusCode == 401 || statusCode == 403;

  /// Promotes the pending token pair to the main keys if an interrupted
  /// rotation left it behind, then deletes the pending entry.
  ///
  /// Called once at the start of [tryRestoreSession] so a crash mid-rotation
  /// does not leave stale or mismatched tokens. The pending value is always
  /// a complete `{access_token, refresh_token}` pair (written atomically in
  /// [_persistRotatedTokens]), so recovery can never promote only one half
  /// of a rotated pair.
  Future<void> _recoverInterruptedTokenRotation(KeyValueStore store) async {
    final pending = await store.read('token_rotation.pending');
    if (pending == null) return;
    final tokens = jsonDecode(pending) as Map<String, dynamic>;
    final pendingAccess = tokens['access_token'] as String?;
    final pendingRefresh = tokens['refresh_token'] as String?;
    if (pendingAccess != null) await store.write('access_token', pendingAccess);
    if (pendingRefresh != null) {
      await store.write('refresh_token', pendingRefresh);
    }
    await store.delete('token_rotation.pending');
  }

  @override
  Future<bool> tryRestoreSession() async {
    if (_state != RemoteStartupState.unauthenticated) return false;
    final store = _keyValue;
    if (store == null) return false;
    await _recoverInterruptedTokenRotation(store);
    final accountId = await store.read('account_id');
    if (accountId == null || accountId.isEmpty) return false;
    // Lost tokens alone no longer mean "signed out": while this device still
    // holds its signing key, refreshAccessToken signs it in again with it.
    final storedRefreshToken = await store.read('refresh_token');
    final storedSigningKey = await store.read('device_signing_private_key');
    if ((storedRefreshToken == null || storedRefreshToken.isEmpty) &&
        (storedSigningKey == null || storedSigningKey.isEmpty)) {
      return false;
    }
    final phoneNumber = await store.read('phone_number');
    final pubKey = await store.read('identity_public_key');
    final deviceIdStr = await store.read('device_id');
    final deviceSigningPubKey =
        await store.read('device_signing_public_key') ??
        await store.read('device_public_key');
    final deviceAgreementPubKey =
        await store.read('device_agreement_public_key') ??
        await store.read('device_public_key');
    final deviceAgreementPrivStr =
        await store.read('device_agreement_private_key') ??
        await store.read('device_private_key');
    final hasPhone = phoneNumber != null;
    final hasKey = pubKey != null;
    final hasDeviceId = deviceIdStr != null;
    final hasDeviceKey =
        deviceSigningPubKey != null && deviceAgreementPubKey != null;
    final hasDevicePriv = deviceAgreementPrivStr != null;
    final hasSession = hasPhone && hasKey && hasDeviceId && hasDeviceKey;
    // Open on what this device already has, the way a messenger does: an
    // access token that is still good needs no round trip first, and one that
    // expires later is refreshed by the REST client when it is refused.
    final storedAccessToken = await store.read('access_token');
    if (hasSession &&
        storedAccessToken != null &&
        _jwtValidFor(storedAccessToken, const Duration(minutes: 1))) {
      _applyAccessToken(storedAccessToken);
    } else {
      final refreshed = await refreshAccessToken();
      if (!refreshed) {
        final offline =
            _lastRefreshFailureKind == _RefreshFailureKind.transient;
        if (!offline) return false;
        if (!hasSession ||
            storedAccessToken == null ||
            storedAccessToken.isEmpty) {
          _setState(RemoteStartupState.recoverableFailure);
          return false;
        }
        // Offline (or the server is down): still open the chats on this
        // device. The token is refreshed on the first request that is
        // refused once the server can be reached again.
        _applyAccessToken(storedAccessToken);
      }
    }

    if (hasSession) {
      final ms = _requireReady(_messagingService, 'messagingService');

      if (hasDevicePriv) {
        final devicePrivBytes = _base64UrlDecode(deviceAgreementPrivStr);
        final devicePubBytes = _base64UrlDecode(deviceAgreementPubKey);
        ms.setCryptoKeys(
          devicePrivateKey: devicePrivBytes,
          devicePublicKey: devicePubBytes,
        );
      }

      ms.setupAccount(
        account: RemoteAccount(
          accountId: accountId,
          identityPublicKey: pubKey,
          createdAt: DateTime.now(),
        ),
        device: RemoteDevice(
          deviceId: deviceIdStr,
          deviceName: 'Dev ${deviceIdStr.substring(0, 8)}',
          deviceSigningPublicKey: deviceSigningPubKey,
          deviceAgreementPublicKey: deviceAgreementPubKey,
          createdAt: DateTime.now(),
        ),
      );
    }
    final token = _accessToken;
    if (token == null || token.isEmpty) return false;
    setAuthenticated(token);
    // A cold start with a saved session is "opening the app"; a fresh
    // sign-in just proved who the user is with an SMS code, so it is not.
    AppLock.lockIfEnabled();
    if (hasDeviceId) unawaited(_renameLegacyDeviceName(deviceIdStr));
    return true;
  }

  /// Gives a device registered before real device labels existed a readable
  /// name, once. Only a server-side name still matching the old `Dev dev_xxxx`
  /// default is replaced, so a name the user chose in Device Management is
  /// never overwritten. Best-effort: a failure is retried on the next launch.
  Future<void> _renameLegacyDeviceName(String deviceId) async {
    final rest = _restClient;
    if (rest == null) return;
    try {
      final devices = await rest.listDevices();
      final current = devices.where((d) => d.deviceId == deviceId).firstOrNull;
      if (current == null || !isLegacyDefaultDeviceName(current.deviceName)) {
        return;
      }
      final label = await describeThisDevice(fallback: current.deviceName);
      if (label == current.deviceName) return;
      await rest.renameDevice(deviceId: deviceId, deviceName: label);
    } catch (_) {
      // Cosmetic only; the next launch tries again.
    }
  }

  @override
  Future<bool> _validateRuntimeSession() async {
    if (_accessToken != null) return true;
    if (_state == RemoteStartupState.unauthenticated) {
      return tryRestoreSession();
    }
    return false;
  }
}
