part of '../composition_root.dart';

mixin RemoteCompositionRuntime on RemoteCompositionRootBase {
  int _wsReconnectCount = 0;
  bool _pendingCallRecoveryInFlight = false;

  @override
  Future<void> startRuntime() async {
    await _requireReady(_runtimeCoordinator, 'runtimeCoordinator').start();
    if (runtimeCoordinator.snapshot.state == RemoteRuntimeState.ready) {
      markReady();
    }
    // After the runtime is up, so the REST client can authenticate: the
    // push-token endpoint is authenticated and registering earlier just 401s.
    // Not awaited into the startup path's critical section - a slow or failed
    // registration must not delay the app becoming usable.
    unawaited(_startPushRegistration());
    await _recoverPendingCalls(reason: 'startup');
    // Load own profile display name after runtime is running
    try {
      final profile = await _restClient!.getMyProfile();
      final dn = profile['display_name'] as String? ?? '';
      if (dn.isNotEmpty) _messagingService?.setDisplayName(dn);
    } catch (_) {}
  }

  Future<void> _startPushRegistration() async {
    final service = _pushRegistration ??= PushRegistrationService(
      source: FirebasePushTokenSource(),
      // Resolved per call: the REST client is rebuilt when the server URL
      // or session changes, so capturing one here would pin a stale one.
      restClient: () => _requireReady(_restClient, 'restClient'),
    );
    await service.start();
  }

  Future<void> _recoverPendingCalls({required String reason}) async {
    if (_pendingCallRecoveryInFlight) {
      AppLogger.instance.info(
        'CALL_RECOVERY',
        'skipping pending call recovery reason=$reason already_in_flight=true',
      );
      return;
    }
    _pendingCallRecoveryInFlight = true;
    try {
      final response = await _restClient!.getPendingCalls();
      final calls = response['calls'] as List<dynamic>? ?? const [];
      AppLogger.instance.info(
        'CALL_RECOVERY',
        'found ${calls.length} pending call(s) reason=$reason',
      );
      for (final raw in calls) {
        if (raw is! Map<String, dynamic>) continue;
        final callId = raw['call_id'] as String?;
        final sdp = raw['sdp'] as String?;
        if (callId == null || sdp == null || sdp.isEmpty) continue;
        final cid = callId.length > 8 ? callId.substring(0, 8) : callId;
        final active = _callService?.activeCall;
        if (active?.callId == callId) {
          AppLogger.instance.info(
            'CALL_RECOVERY',
            'skipping pending offer cid=$cid reason=$reason already_active=true',
          );
          continue;
        }
        AppLogger.instance.info(
          'CALL_RECOVERY',
          'processing pending offer cid=$cid reason=$reason isVideo=${raw['is_video']}',
        );
        final signal = RemoteCallSignal(
          callId: callId,
          signalType: kSignalOffer,
          callerAccountId: raw['caller_account_id'] as String?,
          callerDeviceId: raw['caller_device_id'] as String?,
          calleeAccountId: raw['callee_account_id'] as String?,
          sdp: sdp,
          isVideo: raw['is_video'] == 1 || raw['is_video'] == true,
          createdAt: raw['created_at'] as int?,
          expiresAt: raw['expires_at'] as int?,
        );
        _dispatchInboundCallSignal(_callService, signal);
      }
      _pendingCallRecoveryInFlight = false;
    } catch (e) {
      _pendingCallRecoveryInFlight = false;
      AppLogger.instance.warn(
        'CALL_RECOVERY',
        'pending call recovery failed: $e',
      );
      // Opportunistic — realtime catch-up still runs.
    }
  }

  @override
  Future<void> connectWebSocket() async {
    final token = _accessToken;
    if (token == null) return;
    await disconnectWebSocket();
    _wsReconnectCount++;

    final cursor = _syncEngine?.inboundSequence ?? 0;
    final wsClient = RemoteWebSocketClient(
      wsUri: devConfig.webSocketUri,
      token: token,
      sinceSequence: cursor,
      connectTimeout: Duration(milliseconds: devConfig.requestTimeoutMs),
      onEvent: (envelope) {
        // --- latency trace: first point on the receiver device ---
        if (envelope.type == 'chat_message') {
          final traceMsgId = envelope.payload['message_id'] as String?;
          if (traceMsgId != null) {
            final t = MessageLatencyRegistry.instance.receiverTrace(traceMsgId);
            t.connectionState =
                _runtimeCoordinator?.snapshot.state.name ?? 'unknown';
            t.wsReconnects = _wsReconnectCount;
            t.mark('receiver_callback');
            // Cross-device gap: server's embedded wall-clock vs. local now.
            // Affected by NTP skew but sufficient to pinpoint a 10-second gap.
            t.noteServerBroadcastTimestamp(envelope.timestamp);
          }
        }

        final applied = _syncEngine?.handleIncomingEnvelope(envelope) ?? false;

        // --- latency trace: schedule ui_display mark in next microtask,
        // which follows state_update and approximates the next render frame ---
        if (applied && envelope.type == 'chat_message') {
          final traceMsgId = envelope.payload['message_id'] as String?;
          if (traceMsgId != null) {
            Future.microtask(() async {
              MessageLatencyRegistry.instance
                  .receiverTrace(traceMsgId)
                  .mark('ui_display');
              await MessageLatencyRegistry.instance.completeReceiver(
                traceMsgId,
              );
            });
          }
        }

        if (!applied) {
          // Only trigger a catch-up HTTP fetch for genuine sequence gaps
          // (where the server sent an event newer than our cursor). Skip for
          // events that are already processed duplicates (seq <= cursor).
          final seq = envelope.serverSequence ?? 0;
          final localCursor = _syncEngine?.inboundSequence ?? 0;
          if (seq > localCursor) {
            unawaited(_runtimeCoordinator?.handleRealtimeGap());
          }
          return;
        }
        // Notify when a new incoming contact request arrives.
        if (envelope.type == 'contact_updated' &&
            envelope.payload['direction'] == 'received' &&
            envelope.payload['status'] == 'PendingReceived') {
          final peer =
              envelope.payload['peer_account_id'] as String? ?? 'unknown';
          unawaited(LocalNotificationService.showContactRequest(peer));
        }
        final conversationId = envelope.payload['conversation_id'] as String?;
        final sequence = envelope.serverSequence;
        if (conversationId != null && sequence != null) {
          _wsClient?.acknowledge(conversationId, sequence);
        }
      },
      onRawSignal: (payload) {
        final signal = RemoteCallSignal.fromJson(payload);
        AppLogger.instance.info(
          'CALL_SIGNAL',
          'received ${signal.signalType} via WS cid=${_callSignalCid(signal)}',
        );
        _dispatchInboundCallSignal(_callService, signal);
      },
      onError: (error) {
        _lastError = error;
        unawaited(_runtimeCoordinator?.handleRealtimeClosed());
      },
      onDone: () {
        unawaited(_runtimeCoordinator?.handleRealtimeClosed());
      },
    );
    await wsClient.connect();
    _wsClient = wsClient;
    await _recoverPendingCalls(reason: 'ws_connect');
  }

  Future<void> revokeCurrentDeviceAndPurgeSession() async {
    final store = _requireReady(_keyValue, 'keyValue');
    final deviceId = await store.read('device_id');
    if (deviceId != null && deviceId.isNotEmpty) {
      await _restClient?.revokeDevice(deviceId);
    }
    await _callService?.endActiveCall();
    await disconnectWebSocket();
    await _purgeLocalSessionOnly();
    _setState(RemoteStartupState.unauthenticated);
  }

  Future<void> logout() async {
    await _runtimeCoordinator?.logoutAndPurge();
    await _callService?.endActiveCall();
    await disconnectWebSocket();
    await _purgeLocalSessionOnly();
    _setState(RemoteStartupState.unauthenticated);
  }

  @override
  Future<void> _transitionToAuthRequired() async {
    await _callService?.endActiveCall();
    await disconnectWebSocket();
    await _purgeLocalSessionOnly();
    _setState(RemoteStartupState.unauthenticated);
  }

  Future<void> purgeAfterAccountDeletion() async {
    await _callService?.endActiveCall();
    await disconnectWebSocket();
    await _purgeLocalSessionOnly();
    _database?.deleteFiles();
    _database = null;
    final cacheDir = Directory(devConfig.attachmentCacheDir);
    if (cacheDir.existsSync()) {
      cacheDir.deleteSync(recursive: true);
    }
    _setState(RemoteStartupState.unauthenticated);
  }

  @override
  Future<void> _purgeLocalSessionOnly() async {
    // Before the credentials go: the deregistration endpoint is
    // authenticated, so once the access token is deleted there is no way to
    // tell the server to stop waking this device. It swallows its own
    // failures - sign-out must not be blocked by an unreachable server.
    await _pushRegistration?.deregister();
    final store = _requireReady(_keyValue, 'keyValue');
    for (final key in [
      'access_token',
      'refresh_token',
      'token_rotation.pending',
      'account_id',
      'phone_number',
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
    if (_attachmentService != null) {
      _attachmentService!.authToken = '';
    }
    // Clear outbox ops that belong to this session — they cannot be retried
    // without a valid session and must not surface after a different sign-in.
    _database?.clearPendingOperations();
    // Dismiss any in-app notifications tied to this session.
    await LocalNotificationService.cancelAll();
  }

  @override
  Future<void> disconnectWebSocket() async {
    await _wsClient?.disconnect();
    _wsClient = null;
  }

  @override
  void markReady() {
    if (_state == RemoteStartupState.authenticatedAndSyncing) {
      _setState(RemoteStartupState.ready);
    }
  }
}
