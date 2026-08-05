part of '../auth.dart';

mixin AuthDeviceHandlers on AuthModuleBase {
  static const _deviceLinkTtl = Duration(minutes: 10);

  Future<Response> _listDevicesHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }

    final accountId = auth['account_id'] as String;
    final devices = db.getDevices(accountId);

    return Response.ok(jsonEncode({'devices': devices}));
  }

  Future<Response> _renameDeviceHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }

    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final deviceId = body['device_id'] as String?;
    final deviceName = body['device_name'] as String?;
    if (deviceId == null ||
        deviceName == null ||
        deviceName.trim().isEmpty ||
        deviceName.length > 80) {
      throw AppError.badRequest('Invalid device rename request');
    }
    final accountId = auth['account_id'] as String;
    if (!db.isDeviceActive(accountId, deviceId)) {
      throw AppError.forbidden('Device is inactive');
    }
    db.renameDevice(accountId, deviceId, deviceName.trim());
    db.logAudit(
      accountId,
      auth['device_id'] as String?,
      'DEVICE_RENAMED',
      request.context['client_ip'] as String?,
      null,
    );
    return Response.ok(jsonEncode({'message': 'Device renamed'}));
  }

  Future<Response> _deviceSecurityHistoryHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }
    final deviceId = request.url.queryParameters['device_id'];
    if (deviceId == null || deviceId.isEmpty) {
      throw AppError.badRequest('Missing device_id');
    }
    final accountId = auth['account_id'] as String;
    return Response.ok(
      jsonEncode({'history': db.getDeviceSecurityHistory(accountId, deviceId)}),
    );
  }

  Future<Response> _requestDeviceLinkHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }

    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final newDeviceId = body['device_id'] as String?;
    final newDevicePublicKey = body['device_public_key'] as String?;
    final newDeviceName = body['device_name'] as String?;

    if (newDeviceId == null ||
        newDevicePublicKey == null ||
        newDeviceName == null) {
      throw AppError.badRequest('Missing device link fields');
    }

    final accountId = auth['account_id'] as String;
    final requesterDeviceId = auth['device_id'] as String;
    if (!db.isDeviceActive(accountId, requesterDeviceId)) {
      throw AppError.forbidden('Device is inactive');
    }
    if (db.getDevicesOfDevice(newDeviceId).isNotEmpty) {
      throw AppError.forbidden('Device id is already registered');
    }

    final linkId = _randomToken('link');
    final verificationCode = _humanVerificationCode();
    db.createDeviceLinkRequest(
      linkId: linkId,
      accountId: accountId,
      requestedByDeviceId: requesterDeviceId,
      newDeviceId: newDeviceId,
      newDevicePublicKey: newDevicePublicKey,
      newDeviceName: newDeviceName,
      verificationCodeHash: _hashVerificationCode(verificationCode),
    );
    db.logAudit(
      accountId,
      requesterDeviceId,
      'DEVICE_LINK_REQUESTED',
      request.context['client_ip'] as String?,
      null,
    );

    return Response.ok(
      jsonEncode({
        'link_id': linkId,
        'verification_code': verificationCode,
        'status': 'PENDING',
      }),
    );
  }

  Future<Response> _requestNewDeviceLinkHandler(Request request) async {
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final accountId = body['account_id'] as String?;
    final newDeviceId = body['device_id'] as String?;
    final newDeviceName = body['device_name'] as String?;
    final signingKey = body['device_signing_public_key'] as String?;
    final agreementKey = body['device_agreement_public_key'] as String?;

    if (accountId == null ||
        newDeviceId == null ||
        newDeviceName == null ||
        signingKey == null ||
        agreementKey == null ||
        newDeviceName.trim().isEmpty ||
        newDeviceName.length > 80) {
      throw AppError.badRequest('Missing device link fields');
    }
    if (!_isValidPublicKey(signingKey, crypto.KeyPairType.ed25519) ||
        !_isValidPublicKey(agreementKey, crypto.KeyPairType.x25519) ||
        signingKey == agreementKey) {
      throw AppError.badRequest('Invalid device public keys');
    }
    if (!db.accountExists(accountId)) {
      throw AppError.forbidden('Account not found');
    }
    final trustedDevices = db.getDevices(accountId);
    if (trustedDevices.isEmpty) {
      throw AppError.forbidden('No trusted device can approve this link');
    }
    if (db.getDevicesOfDevice(newDeviceId).isNotEmpty) {
      throw AppError.forbidden('Device id is already registered');
    }

    final linkId = _randomToken('link');
    final verificationCode = _humanVerificationCode();
    final nonce = _randomToken('nonce');
    final now = _now().millisecondsSinceEpoch;
    final expiresAt = _now().add(_deviceLinkTtl).millisecondsSinceEpoch;

    db.createDeviceLinkRequest(
      linkId: linkId,
      accountId: accountId,
      requestedByDeviceId: trustedDevices.first['device_id'] as String,
      newDeviceId: newDeviceId,
      newDevicePublicKey: signingKey,
      newDeviceSigningPublicKey: signingKey,
      newDeviceAgreementPublicKey: agreementKey,
      newDeviceName: newDeviceName.trim(),
      verificationCodeHash: _hashVerificationCode(verificationCode),
      requestNonce: nonce,
      expiresAt: expiresAt,
    );
    db.logAudit(
      accountId,
      newDeviceId,
      'DEVICE_LINK_REQUESTED',
      request.context['client_ip'] as String?,
      null,
    );

    _notifySiblingDevices(
      accountId,
      exceptDeviceId: newDeviceId,
      payload: {
        'type': 'pending_device_link',
        'link_id': linkId,
        'device_id': newDeviceId,
        'device_name': newDeviceName.trim(),
        'expires_at': expiresAt,
        'timestamp': now,
      },
    );

    final qrPayload = _deviceLinkQrPayload(
      linkId: linkId,
      accountId: accountId,
      newDeviceId: newDeviceId,
      verificationCode: verificationCode,
      expiresAt: expiresAt,
    );

    return Response.ok(
      jsonEncode({
        'link_id': linkId,
        'verification_code': verificationCode,
        'expires_at': expiresAt,
        'status': 'PENDING',
        'qr_payload': qrPayload,
      }),
    );
  }

  Future<Response> _verifyDeviceLinkHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }

    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final linkId = body['link_id'] as String?;
    final verificationCode = body['verification_code'] as String?;
    if (linkId == null || verificationCode == null) {
      throw AppError.badRequest('Missing link_id or verification_code');
    }

    final accountId = auth['account_id'] as String;
    final approverDeviceId = auth['device_id'] as String;
    final link = db.getDeviceLinkRequest(linkId);
    if (link == null || link['account_id'] != accountId) {
      throw AppError.forbidden('Device link verification failed');
    }
    final transcript = _approvalTranscript(
      link,
      approvedByDeviceId: approverDeviceId,
      audience: _serverAudience(request),
    );
    final approved = db.approveDeviceLinkRequest(
      linkId: linkId,
      accountId: accountId,
      verificationCodeHash: _hashVerificationCode(verificationCode),
      approvedByDeviceId: approverDeviceId,
      approvalTranscriptHash: _hashTranscript(transcript),
      now: _now().millisecondsSinceEpoch,
    );
    if (!approved) {
      throw AppError.forbidden('Device link verification failed');
    }

    db.logAudit(
      accountId,
      approverDeviceId,
      'DEVICE_LINK_APPROVED',
      request.context['client_ip'] as String?,
      null,
    );
    return Response.ok(
      jsonEncode({
        'status': 'APPROVED',
        'approval_transcript': transcript,
        'approval_transcript_hash': _hashTranscript(transcript),
      }),
    );
  }

  Future<Response> _rejectDeviceLinkHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }

    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final linkId = body['link_id'] as String?;
    final verificationCode = body['verification_code'] as String?;
    if (linkId == null || verificationCode == null) {
      throw AppError.badRequest('Missing link_id or verification_code');
    }

    final accountId = auth['account_id'] as String;
    final rejecterDeviceId = auth['device_id'] as String;
    final rejected = db.rejectDeviceLinkRequest(
      linkId: linkId,
      accountId: accountId,
      verificationCodeHash: _hashVerificationCode(verificationCode),
      rejectedByDeviceId: rejecterDeviceId,
      now: _now().millisecondsSinceEpoch,
    );
    if (!rejected) {
      throw AppError.forbidden('Device link rejection failed');
    }
    db.logAudit(
      accountId,
      rejecterDeviceId,
      'DEVICE_LINK_REJECTED',
      request.context['client_ip'] as String?,
      null,
    );
    return Response.ok(jsonEncode({'status': 'REJECTED'}));
  }

  Future<Response> _completeDeviceLinkHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }

    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final linkId = body['link_id'] as String?;
    if (linkId == null) {
      throw AppError.badRequest('Missing link_id');
    }

    final accountId = auth['account_id'] as String;
    final link = db.getDeviceLinkRequest(linkId);
    if (link == null ||
        link['account_id'] != accountId ||
        link['status'] != 'APPROVED') {
      throw AppError.forbidden('Device link is not approved');
    }

    final newDeviceId = link['new_device_id'] as String;
    db.registerDevice(
      newDeviceId,
      accountId,
      link['new_device_signing_public_key'] as String,
      link['new_device_agreement_public_key'] as String,
      link['new_device_name'] as String,
    );
    if (!db.completeDeviceLinkRequest(
      linkId,
      now: _now().millisecondsSinceEpoch,
    )) {
      throw AppError.forbidden('Device link was already completed');
    }
    db.logAudit(
      accountId,
      auth['device_id'] as String?,
      'DEVICE_LINK_COMPLETED',
      request.context['client_ip'] as String?,
      null,
    );

    _notifySiblingDevices(
      accountId,
      exceptDeviceId: newDeviceId,
      payload: {
        'type': 'device_linked',
        'device_id': newDeviceId,
        'device_name': link['new_device_name'],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    return Response.ok(
      jsonEncode({'status': 'LINKED', 'device_id': newDeviceId}),
    );
  }

  Future<Response> _completeNewDeviceLinkHandler(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final linkId = body['link_id'] as String?;
      final signatureBase64 = body['signature'] as String?;
      if (linkId == null || signatureBase64 == null) {
        throw AppError.badRequest('Missing link_id or signature');
      }

      final link = db.getDeviceLinkRequest(linkId);
      if (link == null ||
          link['status'] != 'APPROVED' ||
          link['approved_by_device_id'] == null) {
        throw AppError.forbidden('Device link is not approved');
      }

      final accountId = link['account_id'] as String;
      final newDeviceId = link['new_device_id'] as String;
      final approvedByDeviceId = link['approved_by_device_id'] as String;
      final expiresAt = link['expires_at'] as int? ?? 0;
      if (expiresAt > 0 && _now().millisecondsSinceEpoch >= expiresAt) {
        throw AppError.forbidden('Device link expired');
      }
      if (!db.isDeviceActive(accountId, approvedByDeviceId) ||
          db.getDevicesOfDevice(newDeviceId).isNotEmpty) {
        throw AppError.forbidden('Device link can no longer be completed');
      }

      final transcript = _approvalTranscript(
        link,
        approvedByDeviceId: approvedByDeviceId,
        audience: _serverAudience(request),
      );
      final transcriptHash = _hashTranscript(transcript);
      if (link['approval_transcript_hash'] != transcriptHash ||
          !await _verifyDeviceLinkSignature(
            transcript: transcript,
            signatureBase64: signatureBase64,
            signingPublicKeyBase64:
                link['new_device_signing_public_key'] as String,
          )) {
        throw AppError.forbidden('Device link signature verification failed');
      }

      db.runInTransaction(() {
        db.registerDevice(
          newDeviceId,
          accountId,
          link['new_device_signing_public_key'] as String,
          link['new_device_agreement_public_key'] as String,
          link['new_device_name'] as String,
        );
        if (!db.completeDeviceLinkRequest(
          linkId,
          now: _now().millisecondsSinceEpoch,
        )) {
          throw StateError('device link already completed');
        }
      });

      db.logAudit(
        accountId,
        newDeviceId,
        'DEVICE_LINK_COMPLETED',
        request.context['client_ip'] as String?,
        null,
      );
      db.logAudit(
        accountId,
        approvedByDeviceId,
        'DEVICE_LINK_COMPLETED',
        request.context['client_ip'] as String?,
        null,
      );

      _notifySiblingDevices(
        accountId,
        exceptDeviceId: newDeviceId,
        payload: {
          'type': 'device_linked',
          'device_id': newDeviceId,
          'device_name': link['new_device_name'],
          'approval_device_id': approvedByDeviceId,
          'timestamp': _now().millisecondsSinceEpoch,
        },
      );

      final session = _issueDeviceSession(accountId, newDeviceId);
      return Response.ok(
        jsonEncode({
          'status': 'LINKED',
          'device_id': newDeviceId,
          'account_id': accountId,
          ...session,
          'message': 'Device linked',
        }),
      );
    } on AppError {
      // The handler body throws these deliberately; without this the
      // StateError branch below would swallow them into a 500.
      rethrow;
    } on StateError {
      // Two devices raced the same link completion - the loser sees the
      // link already consumed.
      throw AppError.forbidden('Device link was already completed');
    }
  }

  Future<Response> _revokeDeviceHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }

    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final deviceToRevoke = body['device_id'] as String?;

    if (deviceToRevoke == null) {
      throw AppError.badRequest('Missing device_id');
    }

    final accountId = auth['account_id'] as String;
    if (!_canRevokeDevice(accountId, deviceToRevoke)) {
      throw AppError.forbidden(
        'Cannot revoke the final active device without recovery',
      );
    }

    db.revokeDevice(accountId, deviceToRevoke);
    db.revokeAllRefreshTokensForDevice(accountId, deviceToRevoke);
    await db.deleteMessagesForDevice(deviceToRevoke);
    db.deletePrekeysForDevice(accountId, deviceToRevoke);
    db.updateDevicePushToken(accountId, deviceToRevoke, '');
    db.expirePendingDeviceLinksForDevice(accountId, deviceToRevoke);
    db.recordDeviceRevocation(
      revocationId: _randomToken('rev'),
      accountId: accountId,
      revokedDeviceId: deviceToRevoke,
      revokedByDeviceId: auth['device_id'] as String?,
      reason: 'USER_REVOKED',
    );
    db.logAudit(
      accountId,
      auth['device_id'] as String?,
      'DEVICE_REVOKED',
      request.context['client_ip'] as String?,
      null,
    );
    _notifySiblingDevices(
      accountId,
      exceptDeviceId: deviceToRevoke,
      payload: {
        'type': 'device_revoked',
        'device_id': deviceToRevoke,
        'reason': 'USER_REVOKED',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    return Response.ok(jsonEncode({'message': 'Device revoked successfully'}));
  }

  Future<Response> _lostDeviceHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }

    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final lostDeviceId = body['device_id'] as String?;
    if (lostDeviceId == null) {
      throw AppError.badRequest('Missing device_id');
    }

    final accountId = auth['account_id'] as String;
    if (!_canRevokeDevice(accountId, lostDeviceId)) {
      throw AppError.forbidden(
        'Cannot revoke the final active device without recovery',
      );
    }
    db.revokeDevice(accountId, lostDeviceId);
    db.revokeAllRefreshTokensForDevice(accountId, lostDeviceId);
    await db.deleteMessagesForDevice(lostDeviceId);
    db.deletePrekeysForDevice(accountId, lostDeviceId);
    db.updateDevicePushToken(accountId, lostDeviceId, '');
    db.expirePendingDeviceLinksForDevice(accountId, lostDeviceId);
    db.recordDeviceRevocation(
      revocationId: _randomToken('rev'),
      accountId: accountId,
      revokedDeviceId: lostDeviceId,
      revokedByDeviceId: auth['device_id'] as String?,
      reason: 'LOST_DEVICE',
    );
    db.logAudit(
      accountId,
      auth['device_id'] as String?,
      'LOST_DEVICE_REPORTED',
      request.context['client_ip'] as String?,
      null,
    );
    _notifySiblingDevices(
      accountId,
      exceptDeviceId: lostDeviceId,
      payload: {
        'type': 'device_revoked',
        'device_id': lostDeviceId,
        'reason': 'LOST_DEVICE',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );

    return Response.ok(
      jsonEncode({'message': 'Lost device revoked', 'device_id': lostDeviceId}),
    );
  }

  bool _canRevokeDevice(String accountId, String deviceId) {
    if (!db.isDeviceActive(accountId, deviceId)) {
      return true;
    }
    return db.activeDeviceCount(accountId) > 1;
  }

  String _randomToken(String prefix) {
    final random = Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    return '${prefix}_${_authBase64UrlEncode(bytes)}';
  }

  String _humanVerificationCode() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10).toString()).join();
  }

  String _hashVerificationCode(String code) {
    return crypto_pkg.sha256.convert(utf8.encode(code)).toString();
  }

  bool _isValidPublicKey(String value, crypto.KeyPairType type) {
    try {
      final bytes = base64Url.decode(base64Url.normalize(value));
      if (bytes.length != 32) return false;
      crypto.SimplePublicKey(bytes, type: type);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _deviceLinkQrPayload({
    required String linkId,
    required String accountId,
    required String newDeviceId,
    required String verificationCode,
    required int expiresAt,
  }) {
    return base64UrlEncode(
      utf8.encode(
        jsonEncode({
          'version': 1,
          'type': 'helix.remote.device-link',
          'link_id': linkId,
          'account_id': accountId,
          'device_id': newDeviceId,
          'verification_code': verificationCode,
          'expires_at': expiresAt,
        }),
      ),
    ).replaceAll('=', '');
  }

  String _approvalTranscript(
    Map<String, dynamic> link, {
    required String approvedByDeviceId,
    required String audience,
  }) {
    final payload = {
      'version': 1,
      'type': 'helix.remote.device-link.approval',
      'account_id': link['account_id'],
      'old_device_id': approvedByDeviceId,
      'new_device_id': link['new_device_id'],
      'new_device_signing_public_key': link['new_device_signing_public_key'],
      'new_device_agreement_public_key':
          link['new_device_agreement_public_key'],
      'new_device_name': link['new_device_name'],
      'nonce': link['request_nonce'],
      'expires_at': link['expires_at'],
      'server_audience': audience,
    };
    return base64UrlEncode(
      utf8.encode(jsonEncode(payload)),
    ).replaceAll('=', '');
  }

  String _hashTranscript(String transcript) =>
      crypto_pkg.sha256.convert(utf8.encode(transcript)).toString();

  Future<bool> _verifyDeviceLinkSignature({
    required String transcript,
    required String signatureBase64,
    required String signingPublicKeyBase64,
  }) async {
    try {
      final publicKey = crypto.SimplePublicKey(
        base64Url.decode(base64Url.normalize(signingPublicKeyBase64)),
        type: crypto.KeyPairType.ed25519,
      );
      final signature = crypto.Signature(
        base64Url.decode(base64Url.normalize(signatureBase64)),
        publicKey: publicKey,
      );
      return _ed25519.verify(utf8.encode(transcript), signature: signature);
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _issueDeviceSession(String accountId, String deviceId) {
    final token = jwt.generateToken({
      'account_id': accountId,
      'device_id': deviceId,
    }, const Duration(hours: 1));
    final refreshToken = jwt.generateToken({
      'account_id': accountId,
      'device_id': deviceId,
      'refresh': true,
      'jti': Random.secure().nextInt(1000000000).toString(),
    }, const Duration(days: 7));
    final expiresAt = _now()
        .add(const Duration(days: 7))
        .millisecondsSinceEpoch;
    db.saveRefreshToken(
      tokenHash: crypto_pkg.sha256
          .convert(utf8.encode(refreshToken))
          .toString(),
      accountId: accountId,
      deviceId: deviceId,
      expiresAt: expiresAt,
    );
    return {
      'token': token,
      'refresh_token': refreshToken,
      'refresh_expires_at': expiresAt,
    };
  }

  Future<Response> _updatePushTokenHandler(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final pushToken = body['push_token'] as String?;
    if (pushToken == null || pushToken.isEmpty || pushToken.length > 256) {
      throw AppError.badRequest('push_token must be 1–256 characters');
    }
    final accountId = auth['account_id'] as String;
    final deviceId = auth['device_id'] as String;
    db.updateDevicePushToken(accountId, deviceId, pushToken);
    return Response.ok(jsonEncode({'status': 'updated'}));
  }
}
