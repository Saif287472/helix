part of '../auth.dart';

mixin AuthRegistrationHandlers on AuthModuleBase {
  Future<Response> _registerHandler(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final accountId = body['account_id'] as String?;
      final registrationVersion = body['registration_version'];
      final phoneHash = body['phone_hash'] as String?;
      final otpCode = body['otp_code'] as String?;
      final inviteCode = body['invite_code'] as String?;
      final identityPublicKey = body['account_identity_public_key'] as String?;
      final deviceId = body['device_id'] as String?;
      final deviceSigningPublicKey =
          body['device_signing_public_key'] as String?;
      final deviceAgreementPublicKey =
          body['device_agreement_public_key'] as String?;
      final accountRegistrationSignature =
          body['account_registration_signature'] as String?;
      final deviceRegistrationSignature =
          body['device_registration_signature'] as String?;
      final deviceName = body['device_name'] as String?;

      if (registrationVersion != 3 ||
          accountId == null ||
          phoneHash == null ||
          phoneHash.isEmpty ||
          otpCode == null ||
          inviteCode == null ||
          inviteCode.isEmpty ||
          identityPublicKey == null ||
          deviceId == null ||
          deviceSigningPublicKey == null ||
          deviceAgreementPublicKey == null ||
          accountRegistrationSignature == null ||
          deviceRegistrationSignature == null ||
          deviceName == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing required fields'}),
        );
      }

      final displayName = (body['display_name'] as String?)?.trim() ?? '';
      if (displayName.isEmpty || displayName.length > 80) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Display name must be 1–80 characters'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final keyValidation = await _validateRegistrationKeys(
        accountId: accountId,
        phoneHash: phoneHash,
        accountIdentityPublicKey: identityPublicKey,
        deviceId: deviceId,
        deviceSigningPublicKey: deviceSigningPublicKey,
        deviceAgreementPublicKey: deviceAgreementPublicKey,
        deviceName: deviceName,
        accountRegistrationSignature: accountRegistrationSignature,
        deviceRegistrationSignature: deviceRegistrationSignature,
      );
      if (keyValidation != null) {
        return Response.badRequest(body: jsonEncode({'error': keyValidation}));
      }

      final phoneOwner = db.getAccountByPhoneHash(phoneHash);
      final existingAccount = db.getAccount(accountId);

      if (existingAccount == null) {
        // A brand-new account: this phone number must not already belong
        // to a different account, and both the invite and the OTP just
        // requested for it must check out before we create anything.
        if (phoneOwner != null) {
          return Response(
            409,
            body: jsonEncode({'error': 'Phone number is already registered'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final now = _now().millisecondsSinceEpoch;
        final invite = db.getInviteByCodeHash(hashInviteCode(inviteCode));
        if (invite == null ||
            invite['status'] != 'PENDING' ||
            (invite['expires_at'] as int) < now) {
          return Response(
            403,
            body: jsonEncode({'error': 'Invalid or expired invite code'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final otpResult = _verifyPhoneOtp(phoneHash: phoneHash, code: otpCode);
        if (otpResult.error != null) {
          return Response(
            403,
            body: jsonEncode({'error': otpResult.error}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        // Redeem last, only once every other check has passed, so a wrong
        // OTP guess never burns a scarce invite credential.
        final redeemed = db.redeemInviteCredential(
          inviteId: invite['invite_id'] as String,
          accountId: accountId,
          now: now,
        );
        if (!redeemed) {
          return Response(
            403,
            body: jsonEncode({'error': 'Invite code already used'}),
          );
        }

        db.createAccount(
          accountId,
          _reservedUsername(accountId),
          identityPublicKey,
          phoneHash: phoneHash,
        );
        db.upsertAccountProfile(accountId: accountId, displayName: displayName);
        db.markOtpConsumed(otpResult.challengeId!, now);
        db.logAudit(
          accountId,
          deviceId,
          'ACCOUNT_REGISTERED',
          request.context['client_ip'] as String?,
          null,
        );
      } else {
        if (_isRegistrationReplay(
          existingAccount: existingAccount,
          phoneHash: phoneHash,
          identityPublicKey: identityPublicKey,
          displayName: displayName,
          deviceId: deviceId,
          deviceSigningPublicKey: deviceSigningPublicKey,
          deviceAgreementPublicKey: deviceAgreementPublicKey,
          deviceName: deviceName,
        )) {
          return Response.ok(
            jsonEncode({
              'message': 'Registration successful',
              'account_id': accountId,
              'device_id': deviceId,
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
        return Response.forbidden(
          jsonEncode({
            'error':
                'Existing accounts must link devices from an active device',
          }),
        );
      }

      db.registerDevice(
        deviceId,
        accountId,
        deviceSigningPublicKey,
        deviceAgreementPublicKey,
        deviceName,
      );
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
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  /// `accounts.username` remains UNIQUE NOT NULL for schema-compatibility
  /// reasons (see accounts_devices_repository.dart) but is never shown to
  /// or settable by users anymore. Phone-based registrations fill it with
  /// a reserved value that can never collide with a real username, since
  /// real usernames could never start with `helix_` even when the concept
  /// existed.
  String _reservedUsername(String accountId) => 'helix_$accountId';

  bool _isRegistrationReplay({
    required Map<String, dynamic> existingAccount,
    required String phoneHash,
    required String identityPublicKey,
    required String displayName,
    required String deviceId,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
    required String deviceName,
  }) {
    if (existingAccount['phone_hash'] != phoneHash ||
        existingAccount['identity_public_key'] != identityPublicKey) {
      return false;
    }
    final profile = db.getAccountProfile(
      existingAccount['account_id'] as String,
    );
    if (profile != null && profile['display_name'] != displayName) {
      return false;
    }
    Map<String, dynamic>? existingDevice;
    for (final device in db.getDevices(
      existingAccount['account_id'] as String,
    )) {
      if (device['device_id'] == deviceId) {
        existingDevice = device;
        break;
      }
    }
    if (existingDevice == null) return false;
    return existingDevice['device_signing_public_key'] ==
            deviceSigningPublicKey &&
        existingDevice['device_agreement_public_key'] ==
            deviceAgreementPublicKey &&
        existingDevice['device_name'] == deviceName;
  }

  Future<String?> _validateRegistrationKeys({
    required String accountId,
    required String phoneHash,
    required String accountIdentityPublicKey,
    required String deviceId,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
    required String deviceName,
    required String accountRegistrationSignature,
    required String deviceRegistrationSignature,
  }) async {
    final accountKey = _decodePublicKey(accountIdentityPublicKey);
    final signingKey = _decodePublicKey(deviceSigningPublicKey);
    final agreementKey = _decodePublicKey(deviceAgreementPublicKey);
    if (accountKey == null) return 'Invalid account identity key';
    if (signingKey == null) return 'Invalid device signing key';
    if (agreementKey == null) return 'Invalid device agreement key';
    if (deviceSigningPublicKey == deviceAgreementPublicKey) {
      return 'Device signing and agreement keys must be distinct';
    }

    final transcript = _registrationTranscript(
      accountId: accountId,
      phoneHash: phoneHash,
      accountIdentityPublicKey: accountIdentityPublicKey,
      deviceId: deviceId,
      deviceSigningPublicKey: deviceSigningPublicKey,
      deviceAgreementPublicKey: deviceAgreementPublicKey,
      deviceName: deviceName,
    );
    final accountOk = await _verifyEd25519(
      publicKeyBytes: accountKey,
      signedPayload: transcript,
      signatureBase64: accountRegistrationSignature,
    );
    if (!accountOk) return 'Invalid account registration signature';
    final deviceOk = await _verifyEd25519(
      publicKeyBytes: signingKey,
      signedPayload: transcript,
      signatureBase64: deviceRegistrationSignature,
    );
    if (!deviceOk) return 'Invalid device registration signature';
    return null;
  }

  List<int>? _decodePublicKey(String value) {
    try {
      final bytes = base64Url.decode(base64Url.normalize(value));
      return bytes.length == 32 ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _verifyEd25519({
    required List<int> publicKeyBytes,
    required String signedPayload,
    required String signatureBase64,
  }) async {
    try {
      final publicKey = crypto.SimplePublicKey(
        publicKeyBytes,
        type: crypto.KeyPairType.ed25519,
      );
      final signatureBytes = base64Url.decode(
        base64Url.normalize(signatureBase64),
      );
      return _ed25519.verify(
        utf8.encode(signedPayload),
        signature: crypto.Signature(signatureBytes, publicKey: publicKey),
      );
    } catch (_) {
      return false;
    }
  }

  String _registrationTranscript({
    required String accountId,
    required String phoneHash,
    required String accountIdentityPublicKey,
    required String deviceId,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
    required String deviceName,
  }) {
    return [
      'helix.remote.registration.v3',
      accountId,
      phoneHash,
      accountIdentityPublicKey,
      deviceId,
      deviceSigningPublicKey,
      deviceAgreementPublicKey,
      deviceName,
    ].join('\n');
  }
}
