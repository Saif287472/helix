import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as crypto_pkg;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
import 'package:helix_remote/app/remote_account_validation.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/app/remote_error_copy.dart';
import 'package:helix_remote/app/remote_ice_config_provider.dart';
import 'package:helix_remote/app/remote_message_protector.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/app/remote_rest_client.dart';
import 'package:helix_remote/app/remote_runtime_coordinator.dart';
import 'package:helix_remote/app/remote_sync_gateway.dart';
import 'package:helix_remote/app/remote_websocket_client.dart';
import 'package:helix_remote/services/local_notification_service.dart';
import 'package:helix_remote/services/message_latency_tracer.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';
import 'package:helix_remote_crypto/helix_remote_crypto.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote/services/app_logger.dart';
import 'package:helix_remote_groups/helix_remote_groups.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';
import 'package:path/path.dart' as p;

part 'composition_root/call_signaling_gateway.dart';
part 'composition_root/lifecycle.dart';
part 'composition_root/local_security.dart';
part 'composition_root/pending_registration.dart';
part 'composition_root/registration.dart';
part 'composition_root/runtime.dart';
part 'composition_root/session.dart';

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

enum _RefreshFailureKind { none, missingSession, authRequired, transient }

const _pendingRegistrationKey = 'registration.pending';

const _resetKeys = [
  'access_token',
  'refresh_token',
  'access_token.pending',
  'refresh_token.pending',
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
  _pendingRegistrationKey,
  'db_key',
  'attachment_key_wrapping_key',
];

String _bytesToHex(List<int> bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

String _hexBytes(List<int> bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

String _base64Url(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}

void _logCallServiceDiagnostic(String message) {
  final tag = message.startsWith('ice ')
      ? 'CALL_ICE'
      : message.startsWith('engine ')
      ? 'CALL_ENGINE'
      : message.startsWith('timer ')
      ? 'CALL_TIMER'
      : message.startsWith('connection ') ||
            message.startsWith('finish ') ||
            message.startsWith('outgoing ') ||
            message.startsWith('accept ')
      ? 'CALL_STATE'
      : 'CALL_SIGNAL';
  AppLogger.instance.info(tag, message);
}

String _callSignalCid(RemoteCallSignal signal) =>
    signal.callId.length > 8 ? signal.callId.substring(0, 8) : signal.callId;

String _callMapCid(Map<String, dynamic>? payload) {
  final callId = payload?['call_id'] as String? ?? '';
  return callId.length > 8 ? callId.substring(0, 8) : callId;
}

String _callPayloadSummary(Map<String, dynamic> payload) {
  final signalType = payload['signal_type'] as String? ?? 'unknown';
  final sdp = payload['sdp'] as String?;
  final candidate = payload['candidate'] as String?;
  final candidateType = _candidateTypeFromString(candidate);
  return 'type=$signalType cid=${_callMapCid(payload)} '
      'sdp_len=${sdp?.length ?? 0} '
      'candidate_type=$candidateType '
      'target_device=${payload['target_device_id'] != null} '
      'caller_device=${payload['caller_device_id'] != null}';
}

String _candidateTypeFromString(String? candidate) {
  if (candidate == null) return 'none';
  if (candidate.isEmpty) return 'end';
  final match = RegExp(r' typ ([A-Za-z0-9_-]+)').firstMatch(candidate);
  return match?.group(1) ?? 'unknown';
}

void _dispatchInboundCallSignal(
  RemoteCallService? service,
  RemoteCallSignal signal,
) {
  final future = service?.processInboundSignal(signal);
  if (future == null) return;
  unawaited(
    future.catchError((Object error, StackTrace stack) {
      AppLogger.instance.error(
        'CALL_SIGNAL',
        'processing ${signal.signalType} failed '
            'cid=${_callSignalCid(signal)} error=$error',
        stack,
      );
    }),
  );
}

String _registrationTranscript({
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

Uint8List _base64UrlDecode(String str) {
  final padded = str.length % 4 == 3
      ? '$str='
      : str.length % 4 == 2
      ? '$str=='
      : str;
  return Uint8List.fromList(base64Url.decode(padded));
}

abstract class RemoteCompositionRootBase {
  RemoteProductConfig get config;
  RemoteDevelopmentConfig get devConfig;
  Future<String?> Function()? get _dbKeyLoader;
  KeyValueStore? get _keyValueStore;

  RemoteStartupState get _state;
  set _state(RemoteStartupState value);
  StreamController<RemoteStartupState> get _stateController;
  String? get _lastError;
  set _lastError(String? value);
  String? get _accessToken;
  set _accessToken(String? value);
  KeyValueStore? get _keyValue;
  set _keyValue(KeyValueStore? value);
  RemoteSecureKeyStorage? get _keyStorage;
  set _keyStorage(RemoteSecureKeyStorage? value);
  HelixRemoteDatabase? get _database;
  set _database(HelixRemoteDatabase? value);
  HelixRemoteRestClient? get _restClient;
  set _restClient(HelixRemoteRestClient? value);
  RemoteWebSocketClient? get _wsClient;
  set _wsClient(RemoteWebSocketClient? value);
  RemoteSyncGatewayImpl? get _syncGateway;
  set _syncGateway(RemoteSyncGatewayImpl? value);
  RemoteSyncEngine? get _syncEngine;
  set _syncEngine(RemoteSyncEngine? value);
  RemoteMessagingService? get _messagingService;
  set _messagingService(RemoteMessagingService? value);
  RemoteAttachmentService? get _attachmentService;
  set _attachmentService(RemoteAttachmentService? value);
  RemoteCallService? get _callService;
  set _callService(RemoteCallService? value);
  // Used by composition mixins; private abstract members are not seen as direct references.
  // ignore: unused_element
  RemoteGroupService? get _groupService;
  set _groupService(RemoteGroupService? value);
  RemoteRuntimeCoordinator? get _runtimeCoordinator;
  set _runtimeCoordinator(RemoteRuntimeCoordinator? value);
  StreamSubscription<RemoteRuntimeSnapshot>? get _runtimeSnapshotSub;
  set _runtimeSnapshotSub(StreamSubscription<RemoteRuntimeSnapshot>? value);
  StreamSubscription<RemoteCallStatus?>? get _callStatusSub;
  set _callStatusSub(StreamSubscription<RemoteCallStatus?>? value);
  StreamSubscription<RemoteSyncChange>? get _outboxChangeSub;
  set _outboxChangeSub(StreamSubscription<RemoteSyncChange>? value);
  StreamController<RemoteCallStatus?> get _callStatusController;
  Future<bool>? get _tokenRefreshInFlight;
  set _tokenRefreshInFlight(Future<bool>? value);
  Future<void>? get _disposeFuture;
  set _disposeFuture(Future<void>? value);
  _RefreshFailureKind get _lastRefreshFailureKind;
  set _lastRefreshFailureKind(_RefreshFailureKind value);

  RemoteRuntimeCoordinator get runtimeCoordinator;
  T _requireReady<T>(T? value, String name);
  void _setState(RemoteStartupState state);
  void _validate();
  Future<String> _loadOrCreateDbKey();
  Future<Uint8List> _loadOrCreateAttachmentWrappingKey();
  String _generateId();
  Future<bool> refreshAccessToken();
  Future<bool> tryRestoreSession();
  void setAuthenticated(String accessToken);
  Future<void> startRuntime();
  Future<void> connectWebSocket();
  Future<void> disconnectWebSocket();
  void markReady();
  Future<void> _refreshRuntimeSession();
  Future<bool> _validateRuntimeSession();
  Future<void> _purgeLocalSessionOnly();
  Future<void> _transitionToAuthRequired();
}

class RemoteCompositionRoot extends RemoteCompositionRootBase
    with
        RemoteCompositionLifecycle,
        RemoteCompositionRegistration,
        RemoteCompositionSession,
        RemoteCompositionRuntime,
        RemoteCompositionLocalSecurity {
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

  @override
  final RemoteProductConfig config;
  @override
  final RemoteDevelopmentConfig devConfig;
  @override
  final Future<String?> Function()? _dbKeyLoader;
  @override
  final KeyValueStore? _keyValueStore;

  @override
  RemoteStartupState _state = RemoteStartupState.idle;
  RemoteStartupState get startupState => _state;
  Stream<RemoteStartupState> get startupStateChanges => _stateController.stream;

  @override
  String? _lastError;
  String? get lastError => _lastError;

  @override
  String? _accessToken;
  @override
  KeyValueStore? _keyValue;
  @override
  RemoteSecureKeyStorage? _keyStorage;
  @override
  HelixRemoteDatabase? _database;
  @override
  HelixRemoteRestClient? _restClient;
  @override
  RemoteWebSocketClient? _wsClient;
  @override
  RemoteSyncGatewayImpl? _syncGateway;
  @override
  RemoteSyncEngine? _syncEngine;
  @override
  RemoteMessagingService? _messagingService;
  @override
  RemoteAttachmentService? _attachmentService;
  @override
  RemoteCallService? _callService;
  @override
  RemoteGroupService? _groupService;
  @override
  RemoteRuntimeCoordinator? _runtimeCoordinator;
  @override
  StreamSubscription<RemoteRuntimeSnapshot>? _runtimeSnapshotSub;
  @override
  StreamSubscription<RemoteCallStatus?>? _callStatusSub;
  @override
  StreamSubscription<RemoteSyncChange>? _outboxChangeSub;
  @override
  final _callStatusController = StreamController<RemoteCallStatus?>.broadcast(
    sync: true,
  );
  @override
  Future<bool>? _tokenRefreshInFlight;
  @override
  Future<void>? _disposeFuture;
  @override
  _RefreshFailureKind _lastRefreshFailureKind = _RefreshFailureKind.none;
  @override
  final _stateController = StreamController<RemoteStartupState>.broadcast(
    sync: true,
  );

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

  /// True when the ICE configuration supports establishing calls.
  /// relay-only + no TURN servers → false (calls would fail to connect).
  bool get callsAvailable {
    final config = devConfig.callIceConfig;
    if (config.ipPrivacy == IpPrivacyMode.relayOnly) {
      final hasStaticTurn = config.iceServers.any(
        (s) => s.url.startsWith('turn:') || s.url.startsWith('turns:'),
      );
      return hasStaticTurn || _restClient != null;
    }
    return true;
  }

  Stream<RemoteCallStatus?> get callStatusChanges =>
      _callStatusController.stream;
  @override
  RemoteRuntimeCoordinator get runtimeCoordinator =>
      _requireReady(_runtimeCoordinator, 'runtimeCoordinator');

  @override
  T _requireReady<T>(T? value, String name) {
    if (value == null) {
      throw StateError(
        'RemoteCompositionRoot.$name is not available '
        '(state: $_state). Call initialize() and await it first.',
      );
    }
    return value;
  }
}
