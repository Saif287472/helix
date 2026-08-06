part of '../composition_root.dart';

mixin RemoteCompositionLifecycle on RemoteCompositionRootBase {
  Future<void> _refreshAttachmentLimits(
    HelixRemoteRestClient restClient,
  ) async {
    try {
      final info = await restClient.getServerInfo();
      final limit = info['max_attachment_bytes'];
      if (limit is int && limit > 0) {
        _attachmentService?.maxAttachmentBytes = limit;
      }
    } catch (_) {
      // Non-fatal: the default stands until the next successful fetch.
    }
  }

  @override
  void _setState(RemoteStartupState state) {
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }

  Future<void> initialize() async {
    if (_state == RemoteStartupState.ready) return;
    if (_state == RemoteStartupState.authenticatedAndSyncing) return;

    try {
      _setState(RemoteStartupState.loadingConfiguration);
      _validate();

      _setState(RemoteStartupState.openingSecureStorage);
      _keyValue =
          _keyValueStore ??
          SecureStorageStore(prefix: config.secureStoragePrefix);
      _keyStorage = const RemoteSecureKeyStorage();

      _setState(RemoteStartupState.firstRunInitialization);
      final dbKey = await _loadOrCreateDbKey();

      _setState(RemoteStartupState.openingDatabase);
      final dbDir = Directory(config.databaseDirectory);
      if (!dbDir.existsSync()) {
        dbDir.createSync(recursive: true);
      }
      final dbFile = File(p.join(config.databaseDirectory, 'helix_remote.db'));
      final db = HelixRemoteDatabase(dbFile, password: dbKey);
      db.initialize();
      _database = db;

      _setState(RemoteStartupState.restoringSession);
      _restClient = HelixRemoteRestClientImpl(
        baseUri: devConfig.restBaseUri,
        timeoutMs: devConfig.requestTimeoutMs,
        refreshAuth: refreshAccessToken,
      );
      _syncGateway = RemoteSyncGatewayImpl(
        baseUri: devConfig.restBaseUri,
        timeoutMs: devConfig.requestTimeoutMs,
        tokenProvider: () => _accessToken,
        refreshAuth: refreshAccessToken,
      );
      void onCallSignal(Map<String, dynamic> p) {
        final signal = RemoteCallSignal.fromJson(p);
        AppLogger.instance.info(
          'CALL_SIGNAL',
          'received ${signal.signalType} via sync cid=${_callSignalCid(signal)}',
        );
        _dispatchInboundCallSignal(_callService, signal);
      }

      _syncEngine = RemoteSyncEngine(
        db,
        onCallSignal: onCallSignal,
        onTrace: (msgId, stage) {
          if (stage == 'send_attempt' || stage == 'server_ack') {
            final t = MessageLatencyRegistry.instance.findSend(msgId);
            if (t != null) {
              t.connectionState =
                  _runtimeCoordinator?.snapshot.state.name ?? 'unknown';
              t.mark(stage);
              if (stage == 'server_ack') {
                unawaited(MessageLatencyRegistry.instance.completeSend(msgId));
              }
            }
          } else {
            // receiver stages: receiver_db_save, state_update
            final t = MessageLatencyRegistry.instance.receiverTrace(msgId);
            t.mark(stage);
          }
        },
      );

      String keySeedProvider(String conversationId) {
        return db.getOrCreateLocalHistorySessionSeed(conversationId);
      }

      final keyStorage = _requireReady(_keyStorage, 'keyStorage');
      Future<Uint8List> prekeyResolver(String privateKeyRef) async {
        final record = await keyStorage.readKeyRecord(privateKeyRef);
        if (record == null) {
          throw StateError('Private key not found: $privateKeyRef');
        }
        return base64Url.decode(base64Url.normalize(record.value));
      }

      _messagingService = RemoteMessagingService(
        db: db,
        syncEngine: _syncEngine!,
        gateway: _syncGateway!,
        protector: RemoteMessageProtectorImpl(keySeedProvider: keySeedProvider),
        restClient: _restClient!,
        prekeyResolver: prekeyResolver,
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

      // The server is the source of truth for attachment limits, so an
      // operator can change them in .env without an app release and the
      // client's error message can never disagree with what the upload
      // endpoint will accept. Best-effort: a server that doesn't report
      // them (or is briefly unreachable) leaves the built-in default in
      // place rather than blocking startup on a non-essential fetch.
      unawaited(_refreshAttachmentLimits(restClient));

      final iceConfigProvider = RemoteIceConfigProvider(
        restClient: restClient,
        baseConfig: devConfig.callIceConfig,
      );
      _callService = RemoteCallService(
        db: db,
        engine: RemoteWebRtcCallEngine(
          iceConfig: devConfig.callIceConfig,
          iceConfigProvider: iceConfigProvider.getIceConfig,
        ),
        signalingGateway: _RemoteRestCallSignalingGateway(restClient, this),
        iceConfig: devConfig.callIceConfig,
        diagnostics: _logCallServiceDiagnostic,
      );
      _callService!.recoverCallState();
      _callStatusSub?.cancel();
      String? lastIncomingCallNotificationId;
      _callStatusSub = _callService!.callStatusChanges.listen((status) {
        if (status != null &&
            status.state == RemoteCallState.ringing &&
            status.direction == kCallDirectionIncoming) {
          lastIncomingCallNotificationId = status.callId;
          unawaited(
            LocalNotificationService.showIncomingCall(
              callId: status.callId,
              callerDisplayName: status.displayName,
              isVideo: status.isVideo,
            ),
          );
        } else if (status != null) {
          unawaited(LocalNotificationService.cancelIncomingCall(status.callId));
          if (lastIncomingCallNotificationId == status.callId) {
            lastIncomingCallNotificationId = null;
          }
        } else {
          final callId = lastIncomingCallNotificationId;
          if (callId != null) {
            unawaited(LocalNotificationService.cancelIncomingCall(callId));
            lastIncomingCallNotificationId = null;
          }
        }
        if (!_callStatusController.isClosed) _callStatusController.add(status);
      });
      LocalNotificationService.setCallActionHandler((action, callId) {
        final active = _callService?.activeCall;
        if (active == null || active.callId != callId) return;
        if (action == LocalNotificationCallAction.accept) {
          unawaited(_callService?.acceptIncomingCall());
        } else if (action == LocalNotificationCallAction.decline) {
          unawaited(_callService?.declineIncomingCall());
        }
      });

      String groupKeyProvider(String groupId, int epoch) {
        final bytes = List<int>.generate(
          32,
          (_) => math.Random.secure().nextInt(256),
        );
        return _base64Url(bytes);
      }

      _groupService = RemoteGroupService(
        db: db,
        generateId: _generateId,
        encryptionKeyProvider: groupKeyProvider,
      );

      _runtimeCoordinator = RemoteRuntimeCoordinator(
        validateSession: _validateRuntimeSession,
        catchUpInbound: () => _messagingService!.syncInbound(),
        drainOutbox: () => _messagingService!.processOutboundQueue(),
        connectRealtime: connectWebSocket,
        disconnectRealtime: disconnectWebSocket,
        refreshSession: _refreshRuntimeSession,
        startCallSignaling: () async => _callService!.start(),
        purgeLocalSession: _purgeLocalSessionOnly,
      );
      _runtimeSnapshotSub?.cancel();
      _runtimeSnapshotSub = _runtimeCoordinator!.snapshots.listen((snap) {
        if (snap.state == RemoteRuntimeState.ready) {
          markReady();
        } else if (snap.state == RemoteRuntimeState.authRequired &&
            (_state == RemoteStartupState.authenticatedAndSyncing ||
                _state == RemoteStartupState.ready)) {
          _setState(RemoteStartupState.unauthenticated);
        }
      });

      // Drain the outbox immediately whenever a new operation is enqueued,
      // rather than waiting for the next periodic sync or manual refresh.
      _outboxChangeSub?.cancel();
      _outboxChangeSub = _messagingService!.changes.listen((change) {
        if (change.areas.contains(RemoteSyncChangeArea.outbox)) {
          unawaited(_runtimeCoordinator?.drainOutbox());
        }
      });

      _setState(RemoteStartupState.unauthenticated);
    } catch (e) {
      if (_state != RemoteStartupState.resetRequired) {
        _setState(RemoteStartupState.recoverableFailure);
      }
      _lastError = e.toString();
      rethrow;
    }
  }
}
