import 'dart:convert';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/jwt.dart';

class AuthModule {
  final BackendDatabase db;
  final JwtHelper jwt;
  final Map<String, String> _challenges = {}; // key: "account_id:device_id"
  final crypto.Ed25519 _ed25519 = crypto.Ed25519();

  AuthModule(this.db, this.jwt);

  Router get router {
    final router = Router();

    // Public routes
    router.post('/register', _registerHandler);
    router.get('/challenge', _challengeHandler);
    router.post('/login', _loginHandler);

    // Auth routes (enforced by middleware in main, but we can verify here too)
    router.get('/devices', _listDevicesHandler);
    router.post('/devices/revoke', _revokeDeviceHandler);

    return router;
  }

  Future<Response> _registerHandler(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final accountId = body['account_id'] as String?;
      final username = body['username'] as String?;
      final identityPublicKey = body['identity_public_key'] as String?;
      final deviceId = body['device_id'] as String?;
      final devicePublicKey = body['device_public_key'] as String?;
      final deviceName = body['device_name'] as String?;

      if (accountId == null ||
          username == null ||
          identityPublicKey == null ||
          deviceId == null ||
          devicePublicKey == null ||
          deviceName == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing required fields'}),
        );
      }

      // Check if account already exists
      final existingAccount = db.getAccount(accountId);
      if (existingAccount == null) {
        // Register new account
        db.createAccount(accountId, username, identityPublicKey);
        db.logAudit(
          accountId,
          deviceId,
          'ACCOUNT_REGISTERED',
          request.context['client_ip'] as String?,
          null,
        );
      }

      // Register device
      db.registerDevice(deviceId, accountId, devicePublicKey, deviceName);
      db.logAudit(
        accountId,
        deviceId,
        'DEVICE_REGISTERED',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({
          'message': 'Registration successful',
          'account_id': accountId,
          'device_id': deviceId,
        }),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  Future<Response> _challengeHandler(Request request) async {
    final params = request.url.queryParameters;
    final accountId = params['account_id'];
    final deviceId = params['device_id'];

    if (accountId == null || deviceId == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing account_id or device_id'}),
      );
    }

    final key = '$accountId:$deviceId';
    final random = Random.secure();
    final challengeBytes = List<int>.generate(32, (i) => random.nextInt(256));
    final challenge = base64UrlEncode(challengeBytes);

    _challenges[key] = challenge;

    return Response.ok(jsonEncode({'challenge': challenge}));
  }

  Future<Response> _loginHandler(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final accountId = body['account_id'] as String?;
      final deviceId = body['device_id'] as String?;
      final signatureBase64 = body['signature'] as String?;

      if (accountId == null || deviceId == null || signatureBase64 == null) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'Missing account_id, device_id, or signature',
          }),
        );
      }

      final key = '$accountId:$deviceId';
      final challenge = _challenges[key];
      if (challenge == null) {
        return Response.forbidden(
          jsonEncode({'error': 'Challenge not found or expired'}),
        );
      }

      // Fetch device public key
      final devices = db.getDevices(accountId);
      final device = devices.firstWhere(
        (d) => d['device_id'] == deviceId,
        orElse: () => <String, dynamic>{},
      );

      if (device.isEmpty) {
        return Response.forbidden(
          jsonEncode({'error': 'Device not registered or inactive'}),
        );
      }

      final devicePubKeyStr = device['device_public_key'] as String;

      // Verify signature
      try {
        final publicKeyBytes = base64Url.decode(
          base64Url.normalize(devicePubKeyStr),
        );
        final publicKey = crypto.SimplePublicKey(
          publicKeyBytes,
          type: crypto.KeyPairType.ed25519,
        );

        final signatureBytes = base64Url.decode(
          base64Url.normalize(signatureBase64),
        );
        final signature = crypto.Signature(
          signatureBytes,
          publicKey: publicKey,
        );

        final isValid = await _ed25519.verify(
          utf8.encode(challenge),
          signature: signature,
        );

        if (!isValid) {
          return Response.forbidden(jsonEncode({'error': 'Invalid signature'}));
        }
      } catch (e) {
        return Response.forbidden(
          jsonEncode({
            'error': 'Signature verification failed: ${e.toString()}',
          }),
        );
      }

      // Clear challenge
      _challenges.remove(key);

      // Generate JWT
      final token = jwt.generateToken({
        'account_id': accountId,
        'device_id': deviceId,
      }, const Duration(days: 7));

      db.logAudit(
        accountId,
        deviceId,
        'DEVICE_LOGIN',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({'token': token, 'message': 'Login successful'}),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  Future<Response> _listDevicesHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    final accountId = auth['account_id'] as String;
    final devices = db.getDevices(accountId);

    return Response.ok(jsonEncode({'devices': devices}));
  }

  Future<Response> _revokeDeviceHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return Response.forbidden(jsonEncode({'error': 'Unauthorized'}));
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final deviceToRevoke = body['device_id'] as String?;

      if (deviceToRevoke == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing device_id'}),
        );
      }

      final accountId = auth['account_id'] as String;

      db.revokeDevice(accountId, deviceToRevoke);
      db.logAudit(
        accountId,
        auth['device_id'] as String?,
        'DEVICE_REVOKED',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({'message': 'Device revoked successfully'}),
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  static String base64UrlEncode(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
