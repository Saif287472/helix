part of '../composition_root.dart';

mixin RemoteCompositionSession on RemoteCompositionRootBase {
  @override
  void setAuthenticated(String accessToken) {
    _applyAccessToken(accessToken);
    _setState(RemoteStartupState.authenticatedAndSyncing);
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
      _lastRefreshFailureKind = _RefreshFailureKind.missingSession;
      await _transitionToAuthRequired();
      return false;
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
        _lastRefreshFailureKind = _RefreshFailureKind.authRequired;
        await _transitionToAuthRequired();
        return false;
      }

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
      return true;
    } on RemoteRestException catch (e) {
      if (_isAuthFailure(e.statusCode)) {
        _lastRefreshFailureKind = _RefreshFailureKind.authRequired;
        _lastError = RemoteUserErrorCopy.authExpired();
        await _transitionToAuthRequired();
        return false;
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
    await store.write('refresh_token.pending', refreshToken);
    await store.write('access_token.pending', accessToken);
    await store.write('refresh_token', refreshToken);
    await store.write('access_token', accessToken);
    await store.delete('refresh_token.pending');
    await store.delete('access_token.pending');
  }

  bool _isAuthFailure(int? statusCode) =>
      statusCode == 401 || statusCode == 403;

  /// Promotes `.pending` tokens to main keys if an interrupted rotation left
  /// them behind, then deletes the `.pending` entries.
  ///
  /// Called once at the start of [tryRestoreSession] so a crash mid-rotation
  /// does not leave stale or mismatched tokens. If both main and pending keys
  /// exist, the pending ones are always at least as fresh (they were written
  /// first in [_persistRotatedTokens]).
  Future<void> _recoverInterruptedTokenRotation(KeyValueStore store) async {
    final pendingAccess = await store.read('access_token.pending');
    final pendingRefresh = await store.read('refresh_token.pending');
    if (pendingAccess == null && pendingRefresh == null) return;
    if (pendingAccess != null) await store.write('access_token', pendingAccess);
    if (pendingRefresh != null) {
      await store.write('refresh_token', pendingRefresh);
    }
    await store.delete('access_token.pending');
    await store.delete('refresh_token.pending');
  }

  @override
  Future<bool> tryRestoreSession() async {
    if (_state != RemoteStartupState.unauthenticated) return false;
    final store = _keyValue;
    if (store == null) return false;
    await _recoverInterruptedTokenRotation(store);
    final storedAccessToken = await store.read('access_token');
    final storedRefreshToken = await store.read('refresh_token');
    if (storedAccessToken == null ||
        storedAccessToken.isEmpty ||
        storedRefreshToken == null ||
        storedRefreshToken.isEmpty) {
      return false;
    }
    final accountId = await store.read('account_id');
    if (accountId == null || accountId.isEmpty) return false;
    final username = await store.read('username');
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
    final hasUser = username != null;
    final hasKey = pubKey != null;
    final hasDeviceId = deviceIdStr != null;
    final hasDeviceKey =
        deviceSigningPubKey != null && deviceAgreementPubKey != null;
    final hasDevicePriv = deviceAgreementPrivStr != null;
    final hasSession = hasUser && hasKey && hasDeviceId && hasDeviceKey;
    final refreshed = await refreshAccessToken();
    if (!refreshed) {
      if (_lastRefreshFailureKind == _RefreshFailureKind.transient) {
        _setState(RemoteStartupState.recoverableFailure);
      }
      return false;
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
          username: username,
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
    return true;
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
