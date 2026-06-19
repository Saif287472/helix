import 'dart:convert';
import 'dart:io';
import 'package:helix_remote_api/api/realtime_envelope.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';

class RemoteSyncGatewayImpl implements SyncGateway {
  RemoteSyncGatewayImpl({
    required Uri baseUri,
    required int timeoutMs,
    String? Function()? tokenProvider,
    HttpClient? httpClient,
  }) : _baseUri = baseUri,
       _tokenProvider = tokenProvider,
       _httpClient =
           httpClient ??
           (() {
             final client = HttpClient();
             client.connectionTimeout = Duration(milliseconds: timeoutMs);
             return client;
           })();

  final Uri _baseUri;
  final String? Function()? _tokenProvider;
  final HttpClient _httpClient;

  String? get _authHeader {
    final token = _tokenProvider?.call();
    if (token == null) return null;
    return 'Bearer $token';
  }

  @override
  Future<List<RemoteRealtimeEnvelope>> fetchInboundEvents({
    required int sinceSequence,
  }) async {
    final uri = _baseUri.resolve(
      '/api/v1/messages/device-events?since_sequence=$sinceSequence',
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
    final uri = _resolveEndpoint(type);
    final req = await _httpClient.postUrl(uri);
    req.headers.set('Content-Type', 'application/json');
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

  Uri _resolveEndpoint(String type) {
    switch (type) {
      case 'SEND_MESSAGE':
        return _baseUri.resolve('/api/v1/messages/send');
      case 'CREATE_CONVERSATION':
        return _baseUri.resolve('/api/v1/messages/conversations/create');
      case 'DELETE_MESSAGE':
        return _baseUri.resolve('/api/v1/messages/delete');
      case 'EDIT_MESSAGE':
        return _baseUri.resolve('/api/v1/messages/edit');
      case 'REACTION':
        return _baseUri.resolve('/api/v1/messages/reactions');
      case 'DELIVERY_RECEIPT':
      case 'READ_RECEIPT':
        return _baseUri.resolve('/api/v1/messages/receipts');
      case 'TYPING':
        return _baseUri.resolve('/api/v1/messages/typing');
      case 'CONTACT_REQUEST':
        return _baseUri.resolve('/api/v1/contacts/requests');
      case 'CONTACT_REQUEST_ACCEPT':
        return _baseUri.resolve('/api/v1/contacts/requests/accept');
      case 'CONTACT_REQUEST_REJECT':
        return _baseUri.resolve('/api/v1/contacts/requests/reject');
      case 'CONTACT_REQUEST_CANCEL':
        return _baseUri.resolve('/api/v1/contacts/requests/cancel');
      case 'CONTACT_REMOVE':
        return _baseUri.resolve('/api/v1/contacts/remove');
      case 'CONTACT_BLOCK':
        return _baseUri.resolve('/api/v1/contacts/block');
      case 'CONTACT_UNBLOCK':
        return _baseUri.resolve('/api/v1/contacts/unblock');
      case 'USERNAME_CHANGE':
        return _baseUri.resolve('/api/v1/profile/username');
      case 'PRIVACY_UPDATE':
        return _baseUri.resolve('/api/v1/contacts/privacy');
      case 'PRESENCE_UPDATE':
        return _baseUri.resolve('/api/v1/contacts/presence');
      case 'PROFILE_UPDATE':
        return _baseUri.resolve('/api/v1/profile');
      case 'SAFETY_REPORT':
        return _baseUri.resolve('/api/v1/accounts/report');
      default:
        return _baseUri.resolve('/api/v1/messages/send');
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
