part of '../auth.dart';

mixin AuthRegistrationHandlers on AuthModuleBase {
  Future<Response> _registerHandler(Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final accountId = body['account_id'] as String?;
    final registrationVersion = body['registration_version'];
    final phoneHash = body['phone_hash'] as String?;
    final otpCode = body['otp_code'] as String?;
    final otpChallengeId = body['otp_challenge_id'] as String?;
    final inviteCode = (body['invite_code'] as String?)?.trim() ?? '';
    final identityPublicKey = body['account_identity_public_key'] as String?;
    final deviceId = body['device_id'] as String?;
    final deviceSigningPublicKey = body['device_signing_public_key'] as String?;
    final deviceAgreementPublicKey =
        body['device_agreement_public_key'] as String?;
    final accountRegistrationSignature =
        body['account_registration_signature'] as String?;
    final deviceRegistrationSignature =
        body['device_registration_signature'] as String?;
    final deviceName = body['device_name'] as String?;

    final isGlobal = globalInstanceMode;

    if (registrationVersion != 3 ||
        accountId == null ||
        phoneHash == null ||
        phoneHash.isEmpty ||
        otpCode == null ||
        identityPublicKey == null ||
        deviceId == null ||
        deviceSigningPublicKey == null ||
        deviceAgreementPublicKey == null ||
        accountRegistrationSignature == null ||
        deviceRegistrationSignature == null ||
        deviceName == null) {
      throw AppError.badRequest('Missing required fields');
    }

    // Personal/self-hosted servers keep their invite-only signup gate. Helix
    // Global bypasses invitations entirely: a valid SMS OTP for the phone
    // number is the only credential needed, both to create a new account and
    // to attach a new device to an existing one.
    if (!isGlobal && inviteCode.isEmpty) {
      throw AppError.badRequest('Missing required fields');
    }

    // Global registration requires an explicit acceptance of the current
    // Terms of Service. Personal/self-hosted servers retain their existing
    // invite-only flow and do not require this field.
    if (globalInstanceMode && body['tos_accepted'] != true) {
      throw AppError.badRequest(
        'Terms of Service acceptance is required',
        code: RemoteErrorCode.termsAcceptanceRequired,
      );
    }
    if (globalInstanceMode) {
      final requestedTosVersion = body['tos_version'];
      if (requestedTosVersion == null) {
        throw AppError.badRequest(
          'The current Terms of Service version is required',
          code: RemoteErrorCode.termsAcceptanceRequired,
        );
      }
      if (requestedTosVersion != HelixLegalDocuments.termsVersion) {
        throw AppError.badRequest(
          'The Terms of Service have been updated; review them and try again',
          code: RemoteErrorCode.termsVersionOutdated,
        );
      }
    }

    // account_id is client-chosen, and the registration transcript is signed
    // with the registrant's own key - so the signature proves the client
    // committed to this id, never that the id is rightfully theirs. Reject
    // reserved and malformed ids before anything is created.
    final accountIdProblem = accountIdError(accountId);
    if (accountIdProblem != null) {
      throw AppError.badRequest(accountIdProblem);
    }

    final displayName = (body['display_name'] as String?)?.trim() ?? '';
    if (displayName.isEmpty || displayName.length > 80) {
      throw AppError.badRequest('Display name must be 1–80 characters');
    }

    // Optional, display-only hint for the admin console's Users screen -
    // never the full number, never used for identity/lookup (phone_hash
    // is what does that). Not part of the signed registration transcript
    // below for the same reason display_name isn't: it's not
    // security-relevant, just cosmetic. Silently dropped rather than
    // rejecting registration if malformed, and left empty for older
    // clients that don't send it yet.
    final rawPhoneLast4 =
        (body['phone_number'] ?? body['phone_last4']) as String?;
    final phoneLast4 =
        rawPhoneLast4 != null &&
            RegExp(r'^\+?[0-9]{2,18}$').hasMatch(rawPhoneLast4.trim())
        ? rawPhoneLast4.trim()
        : '';

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
      throw AppError.badRequest(keyValidation);
    }

    final phoneOwner = db.getAccountByPhoneHash(phoneHash);
    final existingAccount = db.getAccount(accountId);
    final now = _now().millisecondsSinceEpoch;

    if (existingAccount != null) {
      // The client re-proposed an account id that already exists. This is
      // only ever a lost-response retry of a registration this device
      // already completed; anything else must go through the device-link
      // path below so an attacker cannot claim somebody else's account id.
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
            'existing_account': false,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
      throw AppError.forbidden(
        'Existing accounts must link devices from an active device',
      );
    }

    // A brand-new account id was proposed, so the client believes it is
    // signing up. Refuse a permanently blocked number outright (see
    // OperabilityModule._blockUser) before any OTP or invite work below -
    // no valid credential should let a blocked number back in.
    if (db.isPhoneHashBlocked(phoneHash)) {
      throw AppError.forbidden('This phone number is blocked');
    }

    // Decide between "this phone owns an account already" (Global passwordless
    // device link) and "this phone is signing up for the first time". The
    // decision is made server-side from the phone hash; the client never
    // learns an account id from a phone number before the OTP proves control
    // of that number.
    final phoneAccountId = phoneOwner?['account_id'] as String?;
    final isPhoneDeviceLink = isGlobal && phoneAccountId != null;

    if (!isGlobal && phoneAccountId != null) {
      throw AppError.conflict(
        'Phone number is already registered',
        code: RemoteErrorCode.phoneAlreadyRegistered,
      );
    }

    // Invite gate: personal servers only, and only for genuinely new
    // accounts. Looked up (not consumed) here so a wrong OTP guess below
    // never burns a scarce invite credential.
    Map<String, dynamic>? invite;
    if (!isGlobal) {
      invite = db.getInviteByCodeHash(hashInviteCode(inviteCode));
      if (invite == null ||
          invite['status'] != 'PENDING' ||
          (invite['expires_at'] as int) < now) {
        throw AppError.forbidden('Invalid or expired invite code');
      }
    }

    // OTP gate. Required for every new account and every Global device link:
    // this single SMS code is what authorizes both "create this account" and
    // "attach this device to that account".
    final otpResult = _verifyPhoneOtp(
      phoneHash: phoneHash,
      code: otpCode,
      challengeId: otpChallengeId,
    );
    if (otpResult.error != null) {
      throw AppError.forbidden(
        otpResult.error!,
        code: RemoteErrorCode.invalidOtp,
      );
    }

    if (isPhoneDeviceLink) {
      // Helix Global phone login: this number already owns an account, and a
      // valid SMS OTP proves the person controls that number (and therefore
      // the SIM, i.e. this physical device). Bring the account onto THIS
      // device.
      //
      // The account has a single Ed25519 identity key that signs this
      // account's signed prekeys, and every peer's prekey bundle is verified
      // against the one server-side `identity_public_key`. A freshly linked
      // device holds a new identity key pair, so it can only send/receive
      // messages if the account key rotates to it. That rotation invalidates
      // any previously-linked device's ability to send, so - exactly like the
      // recovery flow in modules/auth/recovery.dart - we revoke those devices
      // and make this device the account's active device. A phone number maps
      // to one SIM/physical device, so this is a takeover-by-the-phone, not a
      // silent second-device attach.
      final linkedAccountId = phoneAccountId;
      // An administrator can block or suspend an account; a valid phone OTP
      // must not be a way around that. Matches the recovery flow's guards.
      final linkedStatus = db.getAccount(linkedAccountId)?['status'] as String?;
      if (linkedStatus == 'BLOCKED') {
        throw AppError.forbidden('This account is blocked');
      }
      for (final device in db.getDevices(linkedAccountId)) {
        final existingDeviceId = device['device_id'] as String;
        if (existingDeviceId != deviceId &&
            device['status'] != 'REVOKED') {
          db.revokeDevice(linkedAccountId, existingDeviceId);
        }
      }
      db.updateAccountIdentityKey(linkedAccountId, identityPublicKey);
      db.registerDevice(
        deviceId,
        linkedAccountId,
        deviceSigningPublicKey,
        deviceAgreementPublicKey,
        deviceName,
      );
      if (otpResult.challengeId != null) {
        db.markOtpConsumed(otpResult.challengeId!, now);
      }
      db.logAudit(
        linkedAccountId,
        deviceId,
        'DEVICE_LINKED_VIA_OTP',
        request.context['client_ip'] as String?,
        null,
      );
      final profile = db.getAccountProfile(linkedAccountId);
      return Response.ok(
        jsonEncode({
          'message': 'Registration successful',
          'account_id': linkedAccountId,
          'device_id': deviceId,
          'existing_account': true,
          if (profile != null) 'display_name': profile['display_name'],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Genuinely new account. Personal servers redeem their invite here,
    // after every other check has passed; Global has no invite to redeem.
    if (invite != null) {
      final redeemed = db.redeemInviteCredential(
        inviteId: invite['invite_id'] as String,
        accountId: accountId,
        now: now,
      );
      if (!redeemed) {
        throw AppError.forbidden('Invite code already used');
      }
    }

    db.createAccount(
      accountId,
      _reservedUsername(accountId),
      identityPublicKey,
      phoneHash: phoneHash,
      phoneLast4: phoneLast4,
      tosAcceptedAt: isGlobal ? now : null,
      tosVersion: isGlobal ? HelixLegalDocuments.termsVersion : null,
    );
    db.upsertAccountProfile(
      accountId: accountId,
      displayName: displayName,
      now: _now(),
    );
    if (otpResult.challengeId != null) {
      db.markOtpConsumed(otpResult.challengeId!, now);
    }
    db.logAudit(
      accountId,
      deviceId,
      'ACCOUNT_REGISTERED',
      request.context['client_ip'] as String?,
      null,
    );

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
        'existing_account': false,
      }),
      headers: {'Content-Type': 'application/json'},
    );
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
