part of '../composition_root.dart';

mixin RemoteCompositionLocalSecurity on RemoteCompositionRootBase {
  @override
  Future<String> _loadOrCreateDbKey() async {
    const keyName = 'db_key';
    final existing = _dbKeyLoader == null
        ? await _keyValue!.read(keyName)
        : await _dbKeyLoader();

    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final dbFile = File(p.join(config.databaseDirectory, 'helix_remote.db'));
    if (dbFile.existsSync()) {
      _lastError =
          'Database exists but its key is missing from secure storage.';
      _setState(RemoteStartupState.resetRequired);
      throw StateError(_lastError!);
    }

    final random = math.Random.secure();
    final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final newKey = _bytesToHex(keyBytes);
    await _keyValue!.write(keyName, newKey);
    return newKey;
  }

  @override
  Future<Uint8List> _loadOrCreateAttachmentWrappingKey() async {
    const keyName = 'attachment_key_wrapping_key';
    final existing = await _keyValue!.read(keyName);
    if (existing != null && existing.isNotEmpty) {
      return Uint8List.fromList(
        base64Url.decode(base64Url.normalize(existing)),
      );
    }
    final random = math.Random.secure();
    final keyBytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    await _keyValue!.write(keyName, base64Url.encode(keyBytes));
    return keyBytes;
  }

  @override
  String _generateId() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return _bytesToHex(bytes);
  }

  @override
  void _validate() {
    if (config.displayName.isEmpty) {
      throw StateError('RemoteProductConfig.displayName must not be empty');
    }
    if (config.packageId.isEmpty) {
      throw StateError('RemoteProductConfig.packageId must not be empty');
    }
    if (config.secureStoragePrefix.isEmpty) {
      throw StateError(
        'RemoteProductConfig.secureStoragePrefix must not be empty',
      );
    }
    if (!config.secureStoragePrefix.endsWith('_')) {
      throw StateError(
        'RemoteProductConfig.secureStoragePrefix must end with "_"',
      );
    }
    if (config.methodChannelNamespace.isEmpty) {
      throw StateError(
        'RemoteProductConfig.methodChannelNamespace must not be empty',
      );
    }
    if (config.logNamespace.isEmpty) {
      throw StateError('RemoteProductConfig.logNamespace must not be empty');
    }
    if (config.databaseDirectory.isEmpty) {
      throw StateError(
        'RemoteProductConfig.databaseDirectory must not be empty',
      );
    }
  }

  Future<void> performReset() async {
    LocalNotificationService.setCallActionHandler(null);
    _runtimeSnapshotSub?.cancel();
    _runtimeSnapshotSub = null;
    _callStatusSub?.cancel();
    _callStatusSub = null;
    _outboxChangeSub?.cancel();
    _outboxChangeSub = null;
    await _callService?.endActiveCall();
    await _runtimeCoordinator?.dispose();
    _runtimeCoordinator = null;
    await disconnectWebSocket();
    await _callService?.dispose();
    _callService = null;
    await _messagingService?.dispose();
    _messagingService = null;
    _groupService = null;
    _attachmentService = null;
    await _syncEngine?.dispose();
    _syncEngine = null;
    _syncGateway = null;
    await _restClient?.close();
    _restClient = null;

    _database?.close();
    _database?.deleteFiles();
    _database = null;

    final cacheDir = Directory(devConfig.attachmentCacheDir);
    if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);

    final store = _keyValue;
    if (store != null) {
      for (final key in _resetKeys) {
        await store.delete(key);
      }
    }
    _keyValue = null;
    _keyStorage = null;
    _accessToken = null;
    _lastError = null;

    _setState(RemoteStartupState.idle);
  }

  Future<void> dispose() {
    return _disposeFuture ??= _disposeOnce();
  }

  Future<void> _disposeOnce() async {
    LocalNotificationService.setCallActionHandler(null);
    _runtimeSnapshotSub?.cancel();
    _runtimeSnapshotSub = null;
    _callStatusSub?.cancel();
    _callStatusSub = null;
    _outboxChangeSub?.cancel();
    _outboxChangeSub = null;
    _setState(RemoteStartupState.idle);
    unawaited(_stateController.close());
    unawaited(_callStatusController.close());
    // Only tears down the local subscription and SDK handle - it does not
    // deregister with the server. Disposing the root happens on app shutdown
    // and account switch, where the device should keep receiving call wakes.
    // Deregistration belongs to sign-out alone (_purgeLocalSessionOnly).
    await _boundedDispose(_pushRegistration?.dispose());
    _pushRegistration = null;
    await _boundedDispose(_runtimeCoordinator?.dispose());
    _runtimeCoordinator = null;
    await _boundedDispose(disconnectWebSocket());
    unawaited(_callService?.dispose());
    await _boundedDispose(_messagingService?.dispose());
    _messagingService = null;
    _groupService = null;
    _callService = null;
    _attachmentService = null;
    await _boundedDispose(_syncEngine?.dispose());
    _syncEngine = null;
    _syncGateway = null;
    await _boundedDispose(_restClient?.close());
    _restClient = null;
    _database?.close();
    _database = null;
    _keyStorage = null;
    _keyValue = null;
    _lastError = null;
  }

  Future<void> _boundedDispose(Future<void>? cleanup) async {
    if (cleanup == null) return;
    try {
      await cleanup;
    } catch (e) {
      _lastError = 'Remote cleanup did not finish cleanly.';
    }
  }
}
