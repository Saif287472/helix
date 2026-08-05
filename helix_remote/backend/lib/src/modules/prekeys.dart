import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:helix_remote_backend/src/app_error.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/federation.dart';

class PrekeysModule {
  final BackendDatabase db;
  final FederationClient? federationClient;
  final String? localDomain;

  PrekeysModule(this.db, {this.federationClient, this.localDomain});

  Handler get router {
    final router = Router();
    router.post('/publish', _publishHandler);
    router.get('/bundle', _bundleHandler);
    return withAppErrorHandling(router.call);
  }

  Future<Response> _publishHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }

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
      throw AppError.badRequest('Missing prekey publication fields');
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
  }

  Future<Response> _bundleHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }

    final requestedAccountId = request.url.queryParameters['account_id'];
    final targetAccountId = _localAccountId(requestedAccountId);
    if (targetAccountId == null) {
      throw AppError.badRequest('Missing account_id parameter');
    }

    if (_isExternalAccount(requestedAccountId)) {
      if (federationClient == null) {
        throw AppError.serviceUnavailable('Federation is not configured');
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
      throw AppError.notFound('No active devices found for this account');
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
