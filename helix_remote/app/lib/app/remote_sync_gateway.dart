import 'dart:convert';
import 'dart:io';
import 'package:helix_remote/app/remote_endpoints.dart';
import 'package:helix_remote_api/api/realtime_envelope.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';

class RemoteSyncGatewayImpl implements SyncGateway {
  RemoteSyncGatewayImpl({
    required Uri baseUri,
    required int timeoutMs,
    String? Function()? tokenProvider,
    Future<bool> Function()? refreshAuth,
    HttpClient? httpClient,
  }) : _endpoints = RemoteApiEndpoints(baseUri),
       _tokenProvider = tokenProvider,
       _refreshAuth = refreshAuth,
       _timeout = Duration(milliseconds: timeoutMs),
       _httpClient =
           httpClient ??
           (() {
             final client = HttpClient();
             client.connectionTimeout = Duration(milliseconds: timeoutMs);
             return client;
           })();

  final RemoteApiEndpoints _endpoints;
  final String? Function()? _tokenProvider;
  final Future<bool> Function()? _refreshAuth;
  final Duration _timeout;
  final HttpClient _httpClient;
  final RemoteOutboundOperationRegistry _registry =
      RemoteOutboundOperationRegistry();

  String? get _authHeader {
    final token = _tokenProvider?.call();
    if (token == null) return null;
    return 'Bearer $token';
  }

  @override
  Future<List<RemoteRealtimeEnvelope>> fetchInboundEvents({
    required int sinceSequence,
  }) => _fetchInboundEvents(sinceSequence: sinceSequence, allowRefresh: true);

  Future<List<RemoteRealtimeEnvelope>> _fetchInboundEvents({
    required int sinceSequence,
    required bool allowRefresh,
  }) async {
    final uri = _endpoints.api(
      'messages/device-events',
      queryParameters: {'since_sequence': sinceSequence.toString()},
    );
    final req = await _httpClient.getUrl(uri);
    req.headers.set('Content-Type', 'application/json');
    final auth = _authHeader;
    if (auth != null) {
      req.headers.set('Authorization', auth);
    }
    final resp = await req.close().timeout(_timeout);
    if (allowRefresh &&
        _isAuthFailure(resp.statusCode) &&
        await _refreshAuthOnce()) {
      await resp.drain<void>();
      return _fetchInboundEvents(
        sinceSequence: sinceSequence,
        allowRefresh: false,
      );
    }
    if (resp.statusCode != 200) {
      throw HttpException(
        'Sync fetch failed with status ${resp.statusCode}',
        uri: uri,
      );
    }

    final body = await resp.transform(utf8.decoder).join().timeout(_timeout);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final events = data['events'] as List<dynamic>?;
    if (events == null) return [];
    return events.map((e) {
      return RemoteRealtimeEnvelope.fromJson(e as Map<String, dynamic>);
    }).toList();
  }

  @override
  Future<void> sendOutboundOperation({
    required String opId,
    required String type,
    required Map<String, dynamic> payload,
  }) => _sendOutboundOperation(
    opId: opId,
    type: type,
    payload: payload,
    allowRefresh: true,
  );

  Future<void> _sendOutboundOperation({
    required String opId,
    required String type,
    required Map<String, dynamic> payload,
    required bool allowRefresh,
  }) async {
    final operation = _registry.require(type);
    final uri = _endpoints.api(operation.path);
    final req = await _httpClient.openUrl(operation.method, uri);
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('X-Correlation-Id', opId);
    req.headers.set('Idempotency-Key', opId);
    final auth = _authHeader;
    if (auth != null) {
      req.headers.set('Authorization', auth);
    }

    final body = buildRemoteOutboundBody(type, payload);
    req.add(utf8.encode(jsonEncode(body)));

    final resp = await req.close().timeout(_timeout);
    if (allowRefresh &&
        _isAuthFailure(resp.statusCode) &&
        await _refreshAuthOnce()) {
      await resp.drain<void>();
      return _sendOutboundOperation(
        opId: opId,
        type: type,
        payload: payload,
        allowRefresh: false,
      );
    }
    if (resp.statusCode >= 400) {
      final errBody = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);
      throw HttpException(
        'Operation $type failed with status ${resp.statusCode}: $errBody',
        uri: uri,
      );
    }
  }

  bool _isAuthFailure(int statusCode) => statusCode == 401 || statusCode == 403;

  Future<bool> _refreshAuthOnce() =>
      _refreshAuth?.call() ?? Future.value(false);
}

Map<String, dynamic> buildRemoteOutboundBody(
  String type,
  Map<String, dynamic> payload,
) {
  switch (type) {
    case 'SEND_MESSAGE':
      return payload;
    case 'DELIVERY_RECEIPT':
      return {...payload, 'receipt_type': 'DELIVERY'};
    case 'READ_RECEIPT':
      return {...payload, 'receipt_type': 'READ'};
    default:
      return payload;
  }
}

class RemoteOutboundOperationRegistry {
  RemoteOutboundOperation require(String type) {
    final operation = RemoteOutboundOperation.valuesByType[type];
    if (operation == null) {
      throw StateError('Unknown Remote outbound operation: $type');
    }
    return operation;
  }

  Iterable<String> get knownTypes => RemoteOutboundOperation.valuesByType.keys;
}

class RemoteOutboundOperation {
  const RemoteOutboundOperation._({
    required this.type,
    required this.method,
    required this.path,
  });

  final String type;
  final String method;
  final String path;

  static const values = [
    RemoteOutboundOperation._(
      type: 'SEND_MESSAGE',
      method: 'POST',
      path: 'messages/send',
    ),
    RemoteOutboundOperation._(
      type: 'CREATE_CONVERSATION',
      method: 'POST',
      path: 'messages/conversations/create',
    ),
    RemoteOutboundOperation._(
      type: 'DELETE_MESSAGE',
      method: 'POST',
      path: 'messages/delete',
    ),
    RemoteOutboundOperation._(
      type: 'EDIT_MESSAGE',
      method: 'POST',
      path: 'messages/edit',
    ),
    RemoteOutboundOperation._(
      type: 'REACTION',
      method: 'POST',
      path: 'messages/reactions',
    ),
    RemoteOutboundOperation._(
      type: 'DELIVERY_RECEIPT',
      method: 'POST',
      path: 'messages/receipts',
    ),
    RemoteOutboundOperation._(
      type: 'READ_RECEIPT',
      method: 'POST',
      path: 'messages/receipts',
    ),
    RemoteOutboundOperation._(
      type: 'TYPING',
      method: 'POST',
      path: 'messages/typing',
    ),
    RemoteOutboundOperation._(
      type: 'CONTACT_REQUEST',
      method: 'POST',
      path: 'contacts/requests',
    ),
    RemoteOutboundOperation._(
      type: 'CONTACT_REQUEST_ACCEPT',
      method: 'POST',
      path: 'contacts/requests/accept',
    ),
    RemoteOutboundOperation._(
      type: 'CONTACT_REQUEST_REJECT',
      method: 'POST',
      path: 'contacts/requests/reject',
    ),
    RemoteOutboundOperation._(
      type: 'CONTACT_REQUEST_CANCEL',
      method: 'POST',
      path: 'contacts/requests/cancel',
    ),
    RemoteOutboundOperation._(
      type: 'CONTACT_REMOVE',
      method: 'POST',
      path: 'contacts/remove',
    ),
    RemoteOutboundOperation._(
      type: 'CONTACT_BLOCK',
      method: 'POST',
      path: 'contacts/block',
    ),
    RemoteOutboundOperation._(
      type: 'CONTACT_UNBLOCK',
      method: 'POST',
      path: 'contacts/unblock',
    ),
    RemoteOutboundOperation._(
      type: 'USERNAME_CHANGE',
      method: 'POST',
      path: 'accounts/username',
    ),
    RemoteOutboundOperation._(
      type: 'PRIVACY_UPDATE',
      method: 'POST',
      path: 'contacts/privacy',
    ),
    RemoteOutboundOperation._(
      type: 'PRESENCE_UPDATE',
      method: 'POST',
      path: 'contacts/presence',
    ),
    RemoteOutboundOperation._(
      type: 'PROFILE_UPDATE',
      method: 'POST',
      path: 'accounts/profile',
    ),
    RemoteOutboundOperation._(
      type: 'SAFETY_REPORT',
      method: 'POST',
      path: 'contacts/report',
    ),
    RemoteOutboundOperation._(
      type: 'group_create',
      method: 'POST',
      path: 'groups/create',
    ),
    RemoteOutboundOperation._(
      type: 'group_invite',
      method: 'POST',
      path: 'groups/invite',
    ),
    RemoteOutboundOperation._(
      type: 'group_invite_respond',
      method: 'POST',
      path: 'groups/invite/respond',
    ),
    RemoteOutboundOperation._(
      type: 'group_update',
      method: 'POST',
      path: 'groups/update',
    ),
    RemoteOutboundOperation._(
      type: 'group_member_role',
      method: 'POST',
      path: 'groups/member-role',
    ),
    RemoteOutboundOperation._(
      type: 'group_leave',
      method: 'POST',
      path: 'groups/leave',
    ),
    RemoteOutboundOperation._(
      type: 'group_remove_member',
      method: 'POST',
      path: 'groups/remove',
    ),
    RemoteOutboundOperation._(
      type: 'group_delete',
      method: 'POST',
      path: 'groups/delete',
    ),
  ];

  static final valuesByType = {
    for (final operation in values) operation.type: operation,
  };
}
