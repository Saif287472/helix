import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/federation.dart';

class PrekeysModule {
  final BackendDatabase db;
  final FederationClient? federationClient;
  final String? localDomain;

  PrekeysModule(this.db, {this.federationClient, this.localDomain});

  Router get router {
    final router = Router();
    router.post('/publish', _publishHandler);
    router.get('/bundle', _bundleHandler);
    return router;
  }

  Future<Response> _publishHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final signedPrekeyId = body['signed_prekey_id'] as int?;
      final signedPrekey = body['signed_prekey'] as String?;
      final signature = body['signature'] as String?;
      final oneTimePrekeysList = body['one_time_prekeys'] as List?;

      if (signedPrekeyId == null ||
          signedPrekey == null ||
          signature == null ||
          oneTimePrekeysList == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing prekey publication fields'}),
        );
      }

      final accountId = auth['account_id'] as String;
      final deviceId = auth['device_id'] as String;

      final oneTimePrekeys = oneTimePrekeysList.map((otk) {
        final map = otk as Map<String, dynamic>;
        return {
          'key_id': map['key_id'] as int,
          'public_key': map['public_key'] as String,
        };
      }).toList();

      db.publishPrekeys(
        accountId: accountId,
        deviceId: deviceId,
        signedPrekeyId: signedPrekeyId,
        signedPrekey: signedPrekey,
        signature: signature,
        oneTimePrekeys: oneTimePrekeys,
      );

      db.logAudit(
        accountId,
        deviceId,
        'PREKEYS_PUBLISHED',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({'message': 'Prekeys published successfully'}),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  Future<Response> _bundleHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    final requestedAccountId = request.url.queryParameters['account_id'];
    final targetAccountId = _localAccountId(requestedAccountId);
    if (targetAccountId == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing account_id parameter'}),
      );
    }

    try {
      if (_isExternalAccount(requestedAccountId)) {
        if (federationClient == null) {
          return Response(
            503,
            body: jsonEncode({'error': 'Federation is not configured'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
        final bundle = await federationClient!.fetchRemotePrekeyBundle(
          requestedAccountId!,
        );
        db.logAudit(
          auth['account_id'] as String,
          auth['device_id'] as String?,
          'FEDERATED_PREKEY_BUNDLE_REQUEST',
          request.context['client_ip'] as String?,
          null,
        );
        return Response.ok(
          jsonEncode(bundle),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // 1. Get all active devices for the target account
      final devices = db.getDevices(targetAccountId);
      if (devices.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'No active devices found for this account'}),
        );
      }

      final deviceBundles = <Map<String, dynamic>>[];
      for (final device in devices) {
        final deviceId = device['device_id'] as String;
        final bundle = db.getPrekeyBundleForDevice(targetAccountId, deviceId);
        if (bundle != null) {
          deviceBundles.add(bundle);
        }
      }

      db.logAudit(
        auth['account_id'] as String,
        auth['device_id'] as String?,
        'PREKEY_BUNDLE_REQUEST',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({'account_id': targetAccountId, 'devices': deviceBundles}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  bool _isExternalAccount(String? accountId) {
    if (accountId == null) return false;
    final at = accountId.lastIndexOf('@');
    if (at <= 0 || at == accountId.length - 1) return false;
    final domain = accountId.substring(at + 1).toLowerCase();
    return localDomain == null || domain != localDomain!.toLowerCase();
  }

  String? _localAccountId(String? accountId) {
    if (accountId == null || accountId.isEmpty) return null;
    final at = accountId.lastIndexOf('@');
    if (at <= 0 || at == accountId.length - 1) return accountId;
    final domain = accountId.substring(at + 1).toLowerCase();
    if (localDomain != null && domain == localDomain!.toLowerCase()) {
      return accountId.substring(0, at);
    }
    return accountId;
  }
}
