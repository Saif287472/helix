import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as crypto_pkg;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/app/remote_message_protector.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/app/remote_rest_client.dart';
import 'package:helix_remote/app/remote_sync_gateway.dart';
import 'package:helix_remote/app/remote_websocket_client.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';
import 'package:helix_remote_crypto/helix_remote_crypto.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_groups/helix_remote_groups.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';
import 'package:path/path.dart' as p;

abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureStorageStore implements KeyValueStore {
  SecureStorageStore({required this._prefix})
    : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final String _prefix;

  @override
  Future<String?> read(String key) => _storage.read(key: '$_prefix$key');

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: '$_prefix$key', value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: '$_prefix$key');
}

class RemoteProductConfig {
  const RemoteProductConfig({
    required this.displayName,
    required this.packageId,
    required this.secureStoragePrefix,
    required this.methodChannelNamespace,
    required this.logNamespace,
    required this.databaseDirectory,
  });

  final String displayName;
  final String packageId;
  final String secureStoragePrefix;
  final String methodChannelNamespace;
  final String logNamespace;
  final String databaseDirectory;
}

enum RemoteStartupState {
  idle,
  loadingConfiguration,
  openingSecureStorage,
  firstRunInitialization,
  openingDatabase,
  restoringSession,
  unauthenticated,
  authenticatedAndSyncing,
  ready,
  recoverableFailure,
  resetRequired,
}

class RemoteCompositionRoot {
  RemoteCompositionRoot._({
    required this.config,
    required this.devConfig,
    this._dbKeyLoader,
    this._keyValueStore,
  });

  factory RemoteCompositionRoot.production({
    required String databaseDirectory,
    RemoteDevelopmentConfig? devConfig,
  }) {
    final config = RemoteProductConfig(
      displayName: 'Helix Remote',
      packageId: 'com.helix.remote',
      secureStoragePrefix: 'helix_remote_v1_',
      methodChannelNamespace: 'com.helix.remote',
      logNamespace: 'helix_remote',
      databaseDirectory: databaseDirectory,
    );
    final dev =
        devConfig ??
        RemoteDevelopmentConfig.fromDartDefine(
          databaseDirectory: databaseDirectory,
          attachmentCacheDir: p.join(databaseDirectory, 'attachments_cache'),
        );
    final root = RemoteCompositionRoot._(config: config, devConfig: dev);
    root._validate();
    return root;
  }

  factory RemoteCompositionRoot.withConfig(
    RemoteProductConfig config, {
    RemoteDevelopmentConfig? devConfig,
    Future<String?> Function()? dbKeyLoader,
    KeyValueStore? keyValueStore,
  }) {
    final dev =
        devConfig ??
        RemoteDevelopmentConfig.fromDartDefine(
          databaseDirectory: config.databaseDirectory,
          attachmentCacheDir: p.join(
            config.databaseDirectory,
            'attachments_cache',
          ),
        );
    final root = RemoteCompositionRoot._(
      config: config,
      devConfig: dev,
      dbKeyLoader: dbKeyLoader,
      keyValueStore: keyValueStore,
    );
    root._validate();
    return root;
  }

  final RemoteProductConfig config;
  final RemoteDevelopmentConfig devConfig;
  final Future<String?> Function()? _dbKeyLoader;
  final KeyValueStore? _keyValueStore;

  RemoteStartupState _state = RemoteStartupState.idle;
  RemoteStartupState get startupState => _state;

  String? _lastError;
  String? get lastError => _lastError;

  String? _accessToken;
  KeyValueStore? _keyValue;
  RemoteSecureKeyStorage? _keyStorage;
  HelixRemoteDatabase? _database;
  HelixRemoteRestClient? _restClient;
  RemoteWebSocketClient? _wsClient;
  RemoteSyncGatewayImpl? _syncGateway;
  RemoteSyncEngine? _syncEngine;
  RemoteMessagingService? _messagingService;
  RemoteAttachmentService? _attachmentService;
  RemoteCallService? _callService;
  RemoteGroupService? _groupService;

  RemoteSecureKeyStorage get keyStorage =>
      _requireReady(_keyStorage, 'keyStorage');
  HelixRemoteDatabase get database => _requireReady(_database, 'database');
  HelixRemoteRestClient get restClient =>
      _requireReady(_restClient, 'restClient');
  RemoteSyncGatewayImpl get syncGateway =>
      _requireReady(_syncGateway, 'syncGateway');
  RemoteSyncEngine get syncEngine => _requireReady(_syncEngine, 'syncEngine');
  RemoteMessagingService get messagingService =>
      _requireReady(_messagingService, 'messagingService');
  RemoteAttachmentService get attachmentService =>
      _requireReady(_attachmentService, 'attachmentService');
  RemoteCallService get callService =>
      _requireReady(_callService, 'callService');
  RemoteGroupService get groupService =>
      _requireReady(_groupService, 'groupService');

  T _requireReady<T>(T? value, String name) {
    if (value == null) {
      throw StateError(
        'RemoteCompositionRoot.$name is not available '
        '(state: $_state). Call initialize() and await it first.',
      );
    }
    return value;
  }

  Future<void> initialize() async {
    if (_state == RemoteStartupState.ready) return;
    if (_state == RemoteStartupState.authenticatedAndSyncing) return;

    try {
      _state = RemoteStartupState.loadingConfiguration;
      _validate();

      _state = RemoteStartupState.openingSecureStorage;
      _keyValue =
          _keyValueStore ??
          SecureStorageStore(prefix: config.secureStoragePrefix);
      _keyStorage = RemoteSecureKeyStorage();

      _state = RemoteStartupState.firstRunInitialization;
      final dbKey = await _loadOrCreateDbKey();

      _state = RemoteStartupState.openingDatabase;
      final dbDir = Directory(config.databaseDirectory);
      if (!dbDir.existsSync()) {
        dbDir.createSync(recursive: true);
      }
      final dbFile = File(p.join(config.databaseDirectory, 'helix_remote.db'));
      final db = HelixRemoteDatabase(dbFile, password: dbKey);
      db.initialize();
      _database = db;

      _state = RemoteStartupState.restoringSession;
      _restClient = HelixRemoteRestClientImpl(
        baseUri: devConfig.restBaseUri,
        timeoutMs: devConfig.requestTimeoutMs,
      );
      _syncGateway = RemoteSyncGatewayImpl(
        baseUri: devConfig.restBaseUri,
        timeoutMs: devConfig.requestTimeoutMs,
        tokenProvider: () => _accessToken,
      );
      void onCallSignal(Map<String, dynamic> p) {
        _callService?.processInboundSignal(RemoteCallSignal.fromJson(p));
      }

      _syncEngine = RemoteSyncEngine(db, onCallSignal: onCallSignal);

      final conversationKeys = <String, String>{};
      String keySeedProvider(String conversationId) {
        return conversationKeys.putIfAbsent(
          conversationId,
          RemoteMessageProtectorImpl.generateSeed,
        );
      }

      _messagingService = RemoteMessagingService(
        db: db,
        syncEngine: _syncEngine!,
        gateway: _syncGateway!,
        protector: RemoteMessageProtectorImpl(keySeedProvider: keySeedProvider),
        restClient: _restClient!,
      );

      final attachmentCacheDir = Directory(devConfig.attachmentCacheDir);
      if (!attachmentCacheDir.existsSync()) {
        attachmentCacheDir.createSync(recursive: true);
      }
      final attachmentWrappingKey = await _loadOrCreateAttachmentWrappingKey();
      _attachmentService = RemoteAttachmentService(
        baseUrl: devConfig.restBaseUri.toString(),
        authToken: '',
        db: db,
        tempDir: attachmentCacheDir,
        wrappingKey: attachmentWrappingKey,
      );

      final restClient = _restClient!;
      _callService = RemoteCallService(
        db: db,
        engine: RemoteWebRtcCallEngine(),
        signalingGateway: _RemoteRestCallSignalingGateway(restClient),
      );

      String groupKeyProvider(String groupId, int epoch) {
        return 'gk_${_hexBytes(List<int>.generate(16, (_) => math.Random.secure().nextInt(256)))}_$epoch';
      }

      _groupService = RemoteGroupService(
        db: db,
        generateId: _generateId,
        encryptionKeyProvider: groupKeyProvider,
      );

      _state = RemoteStartupState.unauthenticated;
    } catch (e) {
      _state = RemoteStartupState.recoverableFailure;
      _lastError = e.toString();
      rethrow;
    }
  }

  Future<void> registerAndLogin(String username) async {
    if (_state != RemoteStartupState.unauthenticated) {
      throw StateError('Cannot register in state $_state');
    }
    final rest = _requireReady(_restClient, 'restClient');
    final store = _requireReady(_keyValue, 'keyValue');
    final ms = _requireReady(_messagingService, 'messagingService');

    final identityEd25519 = crypto_pkg.Ed25519();
    final identityKeyPair = await identityEd25519.newKeyPair();
    final identityPubKey = await identityKeyPair.extractPublicKey();

    final deviceSigningEd25519 = crypto_pkg.Ed25519();
    final deviceSigningKeyPair = await deviceSigningEd25519.newKeyPair();
    final deviceSigningPubKey = await deviceSigningKeyPair.extractPublicKey();

    final x25519 = crypto_pkg.X25519();
    final deviceAgreementKeyPair = await x25519.newKeyPair();
    final deviceAgreementPubKey = await deviceAgreementKeyPair
        .extractPublicKey();

    final accountId = _hexBytes(identityPubKey.bytes.sublist(0, 8));
    final deviceId =
        'dev_${_hexBytes(deviceSigningPubKey.bytes.sublist(0, 4))}';
    final deviceName = 'Dev ${deviceId.substring(0, 8)}';

    final accountIdStr = accountId;
    final deviceIdStr = deviceId;
    final identityPrivList = await identityKeyPair.extractPrivateKeyBytes();
    final deviceSigningPrivList = await deviceSigningKeyPair
        .extractPrivateKeyBytes();
    final deviceAgreementPrivList = await deviceAgreementKeyPair
        .extractPrivateKeyBytes();
    final identityPrivBytes = Uint8List.fromList(identityPrivList);
    final deviceSigningPrivBytes = Uint8List.fromList(deviceSigningPrivList);
    final deviceAgreementPrivBytes = Uint8List.fromList(
      deviceAgreementPrivList,
    );

    final identityPubKeyBytes = Uint8List.fromList(identityPubKey.bytes);
    final deviceSigningPubKeyBytes = Uint8List.fromList(
      deviceSigningPubKey.bytes,
    );
    final deviceAgreementPubKeyBytes = Uint8List.fromList(
      deviceAgreementPubKey.bytes,
    );
    final pubKeyStr = _base64Url(identityPubKeyBytes);
    final deviceSigningPubKeyStr = _base64Url(deviceSigningPubKeyBytes);
    final deviceAgreementPubKeyStr = _base64Url(deviceAgreementPubKeyBytes);
    final identityPrivStr = _base64Url(identityPrivBytes);
    final deviceSigningPrivStr = _base64Url(deviceSigningPrivBytes);
    final deviceAgreementPrivStr = _base64Url(deviceAgreementPrivBytes);
    final registrationTranscript = _registrationTranscript(
      accountId: accountIdStr,
      username: username,
      accountIdentityPublicKey: pubKeyStr,
      deviceId: deviceIdStr,
      deviceSigningPublicKey: deviceSigningPubKeyStr,
      deviceAgreementPublicKey: deviceAgreementPubKeyStr,
      deviceName: deviceName,
    );
    final accountRegistrationSignature = await identityEd25519.sign(
      utf8.encode(registrationTranscript),
      keyPair: identityKeyPair,
    );
    final deviceRegistrationSignature = await deviceSigningEd25519.sign(
      utf8.encode(registrationTranscript),
      keyPair: deviceSigningKeyPair,
    );

    await rest.registerAccount(
      accountId: accountIdStr,
      username: username,
      accountIdentityPublicKey: pubKeyStr,
      deviceId: deviceIdStr,
      deviceSigningPublicKey: deviceSigningPubKeyStr,
      deviceAgreementPublicKey: deviceAgreementPubKeyStr,
      accountRegistrationSignature: _base64Url(
        accountRegistrationSignature.bytes,
      ),
      deviceRegistrationSignature: _base64Url(
        deviceRegistrationSignature.bytes,
      ),
      deviceName: deviceName,
    );

    final challengeResp = await rest.getChallenge(
      accountId: accountIdStr,
      deviceId: deviceIdStr,
    );
    final challenge = challengeResp['challenge'] as String;
    final sig = await deviceSigningEd25519.sign(
      utf8.encode(challenge),
      keyPair: deviceSigningKeyPair,
    );
    final sigStr = _base64Url(sig.bytes);

    final loginResp = await rest.loginDevice(
      accountId: accountIdStr,
      deviceId: deviceIdStr,
      signature: sigStr,
    );

    final accessToken = loginResp['token'] as String;
    final refreshToken = loginResp['refresh_token'] as String? ?? '';

    await store.write('access_token', accessToken);
    await store.write('refresh_token', refreshToken);
    await store.write('account_id', accountIdStr);
    await store.write('username', username);
    await store.write('identity_public_key', pubKeyStr);
    await store.write('identity_private_key', identityPrivStr);
    await store.write('device_id', deviceIdStr);
    await store.write('device_signing_public_key', deviceSigningPubKeyStr);
    await store.write('device_signing_private_key', deviceSigningPrivStr);
    await store.write('device_agreement_public_key', deviceAgreementPubKeyStr);
    await store.write('device_agreement_private_key', deviceAgreementPrivStr);

    ms.setCryptoKeys(
      devicePrivateKey: deviceAgreementPrivBytes,
      devicePublicKey: deviceAgreementPubKeyBytes,
    );

    ms.setupAccount(
      account: RemoteAccount(
        accountId: accountIdStr,
        username: username,
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

    setAuthenticated(accessToken);
    try {
      await connectWebSocket();
    } catch (e) {
      _lastError = 'Registered, but WebSocket connect failed: $e';
    }
  }

  void setAuthenticated(String accessToken) {
    _accessToken = accessToken;
    _restClient?.accessToken = accessToken;
    if (_attachmentService != null) {
      _attachmentService!.authToken = accessToken;
    }
    _state = RemoteStartupState.authenticatedAndSyncing;
  }

  Future<bool> tryRestoreSession() async {
    if (_state != RemoteStartupState.unauthenticated) return false;
    final store = _keyValue;
    if (store == null) return false;
    final token = await store.read('access_token');
    if (token == null || token.isEmpty) return false;
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
    setAuthenticated(token);
    try {
      await connectWebSocket();
    } catch (e) {
      _lastError = 'Session restored but WebSocket reconnect failed: $e';
    }
    return true;
  }

  Future<void> connectWebSocket() async {
    final token = _accessToken;
    if (token == null) return;

    final wsClient = RemoteWebSocketClient(
      wsUri: devConfig.webSocketUri,
      token: token,
      onEvent: (envelope) {
        _syncEngine?.handleIncomingEnvelope(envelope);
      },
      onRawSignal: (payload) {
        _callService?.processInboundSignal(RemoteCallSignal.fromJson(payload));
      },
      onError: (error) {
        _lastError = error;
      },
      onDone: () {},
    );
    await wsClient.connect();
    _wsClient = wsClient;
  }

  Future<void> revokeCurrentDeviceAndPurgeSession() async {
    final store = _requireReady(_keyValue, 'keyValue');
    final deviceId = await store.read('device_id');
    if (deviceId != null && deviceId.isNotEmpty) {
      await _restClient?.revokeDevice(deviceId);
    }
    disconnectWebSocket();
    for (final key in [
      'access_token',
      'refresh_token',
      'account_id',
      'username',
      'identity_public_key',
      'identity_private_key',
      'device_id',
      'device_public_key',
      'device_private_key',
      'device_signing_public_key',
      'device_signing_private_key',
      'device_agreement_public_key',
      'device_agreement_private_key',
    ]) {
      await store.delete(key);
    }
    _accessToken = null;
    _restClient?.accessToken = null;
    _state = RemoteStartupState.unauthenticated;
  }

  void disconnectWebSocket() {
    _wsClient?.disconnect();
    _wsClient = null;
  }

  void markReady() {
    if (_state == RemoteStartupState.authenticatedAndSyncing) {
      _state = RemoteStartupState.ready;
    }
  }

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
      _state = RemoteStartupState.resetRequired;
      throw StateError(_lastError!);
    }

    final random = math.Random.secure();
    final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final newKey = _bytesToHex(keyBytes);
    await _keyValue!.write(keyName, newKey);
    return newKey;
  }

  Future<Uint8List> _loadOrCreateAttachmentWrappingKey() async {
    const keyName = 'attachment_key_wrapping_key';
    final existing = await _keyValue!.read(keyName);
    if (existing != null && existing.isNotEmpty) {
      return Uint8List.fromList(base64Url.decode(existing));
    }
    final random = math.Random.secure();
    final keyBytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    await _keyValue!.write(keyName, base64Url.encode(keyBytes));
    return keyBytes;
  }

  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _hexBytes(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _base64Url(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _registrationTranscript({
    required String accountId,
    required String username,
    required String accountIdentityPublicKey,
    required String deviceId,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
    required String deviceName,
  }) {
    return [
      'helix.remote.registration.v2',
      accountId,
      username,
      accountIdentityPublicKey,
      deviceId,
      deviceSigningPublicKey,
      deviceAgreementPublicKey,
      deviceName,
    ].join('\n');
  }

  static Uint8List _base64UrlDecode(String str) {
    final padded = str.length % 4 == 3
        ? '$str='
        : str.length % 4 == 2
        ? '$str=='
        : str;
    return Uint8List.fromList(base64Url.decode(padded));
  }

  String _generateId() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return _bytesToHex(bytes);
  }

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

  void dispose() {
    _state = RemoteStartupState.idle;
    disconnectWebSocket();
    _callService?.stop();
    _messagingService = null;
    _groupService = null;
    _callService = null;
    _attachmentService = null;
    _syncEngine = null;
    _syncGateway = null;
    _restClient?.close();
    _restClient = null;
    _database?.close();
    _database = null;
    _keyStorage = null;
    _keyValue = null;
    _lastError = null;
  }
}

class _RemoteRestCallSignalingGateway implements RemoteCallSignalingGateway {
  _RemoteRestCallSignalingGateway(this._restClient);

  final HelixRemoteRestClient _restClient;

  @override
  Future<void> sendCallSignal({
    required String targetPeerId,
    required RemoteCallSignal signal,
  }) async {
    await _restClient.sendCallSignal(
      targetDeviceId: targetPeerId,
      payload: signal.toJson(),
    );
  }
}
