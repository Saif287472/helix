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
    HttpClient? httpClient,
  }) : _endpoints = RemoteApiEndpoints(baseUri),
       _tokenProvider = tokenProvider,
       _httpClient =
           httpClient ??
           (() {
             final client = HttpClient();
             client.connectionTimeout = Duration(milliseconds: timeoutMs);
             return client;
           })();

  final RemoteApiEndpoints _endpoints;
  final String? Function()? _tokenProvider;
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
    final resp = await req.close();
    if (resp.statusCode != 200) {
      throw HttpException(
        'Sync fetch failed with status ${resp.statusCode}',
        uri: uri,
      );
    }

    final body = await resp.transform(utf8.decoder).join();
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

    final body = _buildBody(type, payload);
    req.add(utf8.encode(jsonEncode(body)));

    final resp = await req.close();
    if (resp.statusCode >= 400) {
      final errBody = await resp.transform(utf8.decoder).join();
      throw HttpException(
        'Operation $type failed with status ${resp.statusCode}: $errBody',
        uri: uri,
      );
    }
  }

  Map<String, dynamic> _buildBody(String type, Map<String, dynamic> payload) {
    switch (type) {
      case 'SEND_MESSAGE':
        return payload;
      default:
        return payload;
    }
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
      path: 'profile/username',
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
      path: 'profile',
    ),
    RemoteOutboundOperation._(
      type: 'SAFETY_REPORT',
      method: 'POST',
      path: 'accounts/report',
    ),
  ];

  static final valuesByType = {
    for (final operation in values) operation.type: operation,
  };
}
