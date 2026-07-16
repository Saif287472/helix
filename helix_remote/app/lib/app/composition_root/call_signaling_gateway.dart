part of '../composition_root.dart';

class _RemoteRestCallSignalingGateway implements RemoteCallSignalingGateway {
  _RemoteRestCallSignalingGateway(this._restClient, this._root);

  final HelixRemoteRestClient _restClient;
  final RemoteCompositionRootBase _root;

  @override
  Future<void> sendCallSignal({
    String? targetAccountId,
    String? targetDeviceId,
    required RemoteCallSignal signal,
  }) async {
    final requestId =
        'call_${signal.callId}_${DateTime.now().microsecondsSinceEpoch}';
    final payload = signal.toJson();
    final tag = signal.signalType;
    final cid = signal.callId.length > 8
        ? signal.callId.substring(0, 8)
        : signal.callId;
    AppLogger.instance.info(
      'CALL_SIGNAL',
      'send begin $tag cid=$cid ${_callPayloadSummary(payload)} '
          'target_account=${targetAccountId != null || signal.calleeAccountId != null} '
          'target_device=${targetDeviceId != null || signal.targetDeviceId != null} '
          'ws_connected=${_root._wsClient?.isConnected == true} '
          'req=${_requestSuffix(requestId)}',
    );

    if (_root._wsClient?.isConnected == true) {
      try {
        final ack = await _root._wsClient!.sendCallSignal(
          requestId: requestId,
          payload: payload,
        );
        _validateCallSignalAck(ack);
        AppLogger.instance.info(
          'CALL_SIGNAL',
          '$tag via WS cid=$cid ack=${ack['status']} '
              'req=${_requestSuffix(requestId)}',
        );
        return;
      } on RemoteCallSignalRejected catch (e) {
        AppLogger.instance.error(
          'CALL_SIGNAL',
          '$tag WS rejected cid=$cid status=${e.status} '
              'reason=${e.reason} req=${_requestSuffix(requestId)}',
        );
        rethrow;
      } catch (e) {
        // Transport-level WebSocket failure. Fall back to REST with the same
        // requestId so the backend deduplication key still works.
        AppLogger.instance.warn(
          'CALL_SIGNAL',
          '$tag WS transport error, falling back to REST '
              'cid=$cid req=${_requestSuffix(requestId)}: $e',
        );
      }
    } else {
      AppLogger.instance.info(
        'CALL_SIGNAL',
        '$tag WS not connected, using REST cid=$cid '
            'req=${_requestSuffix(requestId)}',
      );
    }

    try {
      final response = await _restClient.sendCallSignal(
        targetAccountId: targetAccountId ?? signal.calleeAccountId,
        targetDeviceId: targetDeviceId ?? signal.targetDeviceId,
        payload: payload,
        requestId: requestId,
      );
      _validateCallSignalAck(response);
      AppLogger.instance.info(
        'CALL_SIGNAL',
        '$tag via REST cid=$cid ack=${response['status']} '
            'req=${_requestSuffix(requestId)}',
      );
    } on RemoteCallSignalRejected catch (e) {
      AppLogger.instance.error(
        'CALL_SIGNAL',
        '$tag REST rejected cid=$cid status=${e.status} '
            'reason=${e.reason} req=${_requestSuffix(requestId)}',
      );
      rethrow;
    }
  }

  void _validateCallSignalAck(Map<String, dynamic> ack) {
    final status = ack['status'] as String?;
    const successful = {'delivered', 'partial', 'queued', 'duplicate'};
    if (status != null && successful.contains(status)) return;
    throw RemoteCallSignalRejected(
      status: status ?? 'unknown',
      reason: ack['reason'] as String?,
    );
  }

  String _requestSuffix(String requestId) => requestId.length <= 10
      ? requestId
      : requestId.substring(requestId.length - 10);
}

class RemoteCallSignalRejected implements Exception {
  const RemoteCallSignalRejected({required this.status, this.reason});

  final String status;
  final String? reason;

  @override
  String toString() =>
      'RemoteCallSignalRejected(status: $status, reason: $reason)';
}
