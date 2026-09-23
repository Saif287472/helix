part of '../remote_messaging_service.dart';

mixin RemoteMessageDecryption
    on RemoteMessagingServiceBase, RemoteMessageCrypto {
  /// Decrypts a message ciphertext, routing to the correct handler based on
  /// the envelope version field:
  ///   v=1  X3DH packed envelope (initial message from a peer device)
  ///   v=2  session-reuse envelope (subsequent messages, X3DH skipped)
  ///   (none) local AES-GCM ciphertext (own-device history)
  @override
  Future<String> _decryptMessage({
    required String conversationId,
    required String messageId,
    required String ciphertext,
  }) async {
    if (_prekeyResolver != null && _devicePrivateKey != null) {
      Map<String, dynamic>? envelope;
      try {
        final jsonBytes = _b64d(ciphertext);
        envelope = jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
      } catch (_) {
        // Not a packed envelope JSON â€” fall through to local protector.
      }
      if (envelope != null) {
        final version = envelope['v'];
        if (version == 1 &&
            envelope.containsKey('ct') &&
            envelope.containsKey('h')) {
          return _decryptX3dhEnvelope(envelope);
        }
        if (version == _kSessionMsgVersion &&
            envelope.containsKey('ct') &&
            envelope.containsKey('sid')) {
          return _decryptSessionEnvelope(envelope);
        }
      }
    }
    return protector.decryptText(
      conversationId: conversationId,
      messageId: messageId,
      ciphertext: ciphertext,
    );
  }

  Future<String> _decryptX3dhEnvelope(Map<String, dynamic> envelope) async {
    final innerCiphertext = envelope['ct'] as String;
    final header = envelope['h'] as Map<String, dynamic>;

    final senderIdentityPubKey = crypto.SimplePublicKey(
      _b64d(header['identity_key'] as String),
      type: crypto.KeyPairType.x25519,
    );
    final senderEphemeralPubKey = crypto.SimplePublicKey(
      _b64d(header['ephemeral_key'] as String),
      type: crypto.KeyPairType.x25519,
    );
    final usedOpkId = header['used_one_time_prekey_id'] as int?;
    final usedSpkId = header['used_signed_prekey_id'] as int?;
    final aadMap = header['aad'] as Map<String, dynamic>;
    final senderDeviceId = aadMap['sender_device_id'] as String? ?? '';
    final recipientDeviceId = aadMap['recipient_device_id'] as String? ?? '';
    final convId = aadMap['conversation_id'] as String? ?? '';

    // Receiver's device agreement key (identity key for X3DH).
    final bobIdentityKey = crypto.SimpleKeyPairData(
      _devicePrivateKey!,
      publicKey: crypto.SimplePublicKey(
        _devicePublicKey!,
        type: crypto.KeyPairType.x25519,
      ),
      type: crypto.KeyPairType.x25519,
    );

    // Look up the signed prekey that was used.
    final deviceId = _requireDeviceId();
    final spkRows = db.getLocalPrekeys(
      deviceId: deviceId,
      role: 'signed_prekey',
    );
    final spkRow = usedSpkId != null
        ? (spkRows.firstWhere(
            (r) => r['key_id'] == usedSpkId,
            orElse: () => spkRows.isNotEmpty ? spkRows.last : {},
          ))
        : (spkRows.isNotEmpty ? spkRows.last : <String, dynamic>{});
    if (spkRow.isEmpty) {
      throw StateError('No signed prekey found for decryption');
    }
    final spkPrivBytes = await _prekeyResolver!(
      spkRow['private_key_ref'] as String,
    );
    final bobSpk = crypto.SimpleKeyPairData(
      spkPrivBytes,
      publicKey: crypto.SimplePublicKey(
        _b64d(spkRow['public_key'] as String),
        type: crypto.KeyPairType.x25519,
      ),
      type: crypto.KeyPairType.x25519,
    );

    // Look up the one-time prekey if one was used.
    crypto.SimpleKeyPair? bobOpk;
    if (usedOpkId != null) {
      final otkRows = db.getLocalPrekeys(
        deviceId: deviceId,
        role: 'one_time_prekey',
      );
      final otkRow = otkRows.where((r) => r['key_id'] == usedOpkId).firstOrNull;
      if (otkRow != null) {
        final otkPrivBytes = await _prekeyResolver(
          otkRow['private_key_ref'] as String,
        );
        bobOpk = crypto.SimpleKeyPairData(
          otkPrivBytes,
          publicKey: crypto.SimplePublicKey(
            _b64d(otkRow['public_key'] as String),
            type: crypto.KeyPairType.x25519,
          ),
          type: crypto.KeyPairType.x25519,
        );
      }
    }

    // Derive the shared master secret using X3DH receive.
    final x3dh = X3dhSessionInitiator();
    final masterSecret = await x3dh.receiveSession(
      bobIdentityKey: bobIdentityKey,
      bobSignedPrekey: bobSpk,
      bobOneTimePrekey: bobOpk,
      aliceIdentityPublicKey: senderIdentityPubKey,
      aliceEphemeralPublicKey: senderEphemeralPubKey,
      protocolVersion: (aadMap['protocol_version'] ?? 1).toString(),
      conversationId: convId,
      senderDeviceId: senderDeviceId,
      recipientDeviceId: recipientDeviceId,
    );

    final masterKeyBytes = await masterSecret.extractBytes();

    // Decrypt inner ciphertext: nonce(12) || ciphertext || mac(16).
    final rawCt = _b64d(innerCiphertext);
    final nonce = rawCt.sublist(0, 12);
    final mac = rawCt.sublist(rawCt.length - 16);
    final body = rawCt.sublist(12, rawCt.length - 16);

    final aad = _messageAad(
      messageId: aadMap['message_id'] as String? ?? '',
      conversationId: convId,
      senderDeviceId: senderDeviceId,
      recipientDeviceId: recipientDeviceId,
      protocolVersion: aadMap['protocol_version'] as int? ?? 1,
      contentType:
          aadMap['content_type'] as String? ??
          RemoteCapability.contentEnvelopeV1,
      counter: aadMap['counter'] as int? ?? 0,
    );

    final decrypted = await crypto.AesGcm.with256bits().decrypt(
      crypto.SecretBox(body, nonce: nonce, mac: crypto.Mac(mac)),
      secretKey: crypto.SecretKey(masterKeyBytes),
      aad: aad,
    );

    // Persist the receiver-side session so incoming v=2 messages from this
    // sender can be decrypted without repeating X3DH.
    final sessionId = RemoteMessageCrypto._sessionKey(
      convId,
      senderDeviceId,
      recipientDeviceId,
    );
    final hkdf = crypto.Hkdf(
      hmac: crypto.Hmac(crypto.Sha256()),
      outputLength: 32,
    );
    final sendKey = await hkdf.deriveKey(
      secretKey: crypto.SecretKey(masterKeyBytes),
      nonce: const [2],
      info: utf8.encode('helix-chain-recv'),
    );
    final recvKey = await hkdf.deriveKey(
      secretKey: crypto.SecretKey(masterKeyBytes),
      nonce: const [1],
      info: utf8.encode('helix-chain-send'),
    );
    final sendKeyB64 = base64Url.encode(await sendKey.extractBytes());
    final recvKeyB64 = base64Url.encode(await recvKey.extractBytes());

    final now = DateTime.now().millisecondsSinceEpoch;
    db.upsertCryptoSession(
      sessionId: sessionId,
      conversationId: convId,
      peerDeviceId: senderDeviceId,
      role: 'receiver',
      protocolVersion: 1,
      rootKey: base64Url.encode(masterKeyBytes),
      sendingChainKey: sendKeyB64,
      receivingChainKey: recvKeyB64,
      sendCount: 0,
      receiveCount: (aadMap['counter'] as int? ?? 0) + 1,
      createdAt: now,
      updatedAt: now,
    );

    return utf8.decode(decrypted);
  }

  // Decrypts a v=2 session-reuse envelope. Consumes or steps the receiving chain
  // in DoubleRatchetSession, supporting out-of-order delivery via skipped keys,
  // and falls back to root key derivation for legacy sessions.
  Future<String> _decryptSessionEnvelope(Map<String, dynamic> envelope) async {
    final sessionId = envelope['sid'] as String;
    final counter = envelope['mc'] as int;
    final innerCiphertext = envelope['ct'] as String;
    final aadMap = envelope['aad'] as Map<String, dynamic>? ?? {};

    final session = db.getCryptoSession(sessionId);
    if (session == null) {
      throw StateError('No persisted session for id=$sessionId');
    }

    final rawCt = _b64d(innerCiphertext);
    final nonce = rawCt.sublist(0, 12);
    final mac = rawCt.sublist(rawCt.length - 16);
    final body = rawCt.sublist(12, rawCt.length - 16);
    final messageId = aadMap['message_id'] as String? ?? '';

    final aad = _messageAad(
      messageId: messageId,
      conversationId: aadMap['conversation_id'] as String? ?? '',
      senderDeviceId: aadMap['sender_device_id'] as String? ?? '',
      recipientDeviceId: aadMap['recipient_device_id'] as String? ?? '',
      protocolVersion: _kSessionMsgVersion,
      contentType:
          aadMap['content_type'] as String? ??
          RemoteCapability.contentEnvelopeV1,
      counter: counter,
    );

    final ratchetSession = await DoubleRatchetSession.fromStoredSession(session);
    List<int>? decrypted;
    try {
      final msgKey = await ratchetSession.ratchetReceivingChain(counter);
      decrypted = await crypto.AesGcm.with256bits().decrypt(
        crypto.SecretBox(body, nonce: nonce, mac: crypto.Mac(mac)),
        secretKey: msgKey,
        aad: aad,
      );
    } catch (_) {
      // Fallback for legacy static sessions: derive key from rootKey via old method
      final rootKeyBytes = _b64d(session['root_key'] as String);
      final legacyKey = await _deriveMessageKey(
        rootKeyBytes,
        counter,
        sessionId,
        messageId,
      );
      decrypted = await crypto.AesGcm.with256bits().decrypt(
        crypto.SecretBox(body, nonce: nonce, mac: crypto.Mac(mac)),
        secretKey: legacyKey,
        aad: aad,
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final recvKeyBytes = ratchetSession.ckRecv != null
        ? await ratchetSession.ckRecv!.extractBytes()
        : <int>[];
    final sendKeyBytes = ratchetSession.ckSend != null
        ? await ratchetSession.ckSend!.extractBytes()
        : <int>[];

    db.upsertCryptoSession(
      sessionId: sessionId,
      conversationId: aadMap['conversation_id'] as String? ?? '',
      peerDeviceId: session['peer_device_id'] as String?,
      peerAccountId: session['peer_account_id'] as String?,
      role: session['role'] as String? ?? 'receiver',
      protocolVersion: _kSessionMsgVersion,
      rootKey: session['root_key'] as String,
      sendingChainKey: sendKeyBytes.isNotEmpty
          ? base64Url.encode(sendKeyBytes)
          : session['sending_chain_key'] as String? ?? '',
      receivingChainKey: recvKeyBytes.isNotEmpty
          ? base64Url.encode(recvKeyBytes)
          : session['receiving_chain_key'] as String? ?? '',
      sendCount: session['send_count'] as int? ?? 0,
      receiveCount: ratchetSession.nr > (session['receive_count'] as int? ?? 0)
          ? ratchetSession.nr
          : (session['receive_count'] as int? ?? 0),
      previousChainLength: ratchetSession.pn,
      skippedKeysJson: await ratchetSession.exportSkippedKeysJson(),
      createdAt: session['created_at'] as int? ?? now,
      updatedAt: now,
    );

    return utf8.decode(decrypted);
  }
}
