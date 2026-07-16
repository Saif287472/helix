part of '../remote_messaging_service.dart';

// In-memory prekey bundle cache entry. Stores all fields EXCEPT one_time_prekey
// because OPKs are consumed server-side on first use and must not be reused.
class _BundleCacheEntry {
  _BundleCacheEntry._({
    required this.accountIdentityKey,
    required this.deviceData,
    required this.fetchedAt,
  });

  factory _BundleCacheEntry.fromResponse(Map<String, dynamic> resp) {
    final deviceData = <String, Map<String, dynamic>>{};
    for (final d in (resp['devices'] as List? ?? [])) {
      final device = d as Map<String, dynamic>;
      final deviceId = device['device_id'] as String? ?? '';
      deviceData[deviceId] = {
        'device_id': deviceId,
        'device_name': device['device_name'],
        'identity_key': device['identity_key'],
        'device_key': device['device_key'],
        'signed_prekey': device['signed_prekey'],
        // one_time_prekey deliberately omitted — must not be reused
      };
    }
    return _BundleCacheEntry._(
      accountIdentityKey: resp['account_identity_key'] as String? ?? '',
      deviceData: deviceData,
      fetchedAt: DateTime.now(),
    );
  }

  final String accountIdentityKey;
  final Map<String, Map<String, dynamic>> deviceData;
  final DateTime fetchedAt;

  static const _ttl = Duration(minutes: 5);

  bool get isExpired => DateTime.now().difference(fetchedAt) > _ttl;

  Map<String, dynamic> toResponseMap() => {
    'account_identity_key': accountIdentityKey,
    'devices': deviceData.values.toList(),
  };
}

// Envelope version for session-reuse messages (X3DH not repeated).
const _kSessionMsgVersion = 2;

mixin RemoteMessageCrypto on RemoteMessagingServiceBase {
  // Prekey bundle cache: keyed by recipient accountId.
  // Populated after the first fresh fetch; subsequent sends within the TTL
  // skip the network round-trip and use cached SPK data (no OPK reuse).
  final _bundleCache = <String, _BundleCacheEntry>{};

  // Deduplicates concurrent in-flight fetches for the same accountId so that
  // a burst of messages to the same recipient causes only one HTTP request.
  final _bundleFetchInFlight = <String, Future<Map<String, dynamic>>>{};

  // Directional X3DH session ID: unique per (conversationId, sender, recipient).
  // Both sides store under the same formula; the receiver reads 'sid' from the
  // v=2 envelope to look up the correct session without re-deriving the key.
  static String _sessionKey(
    String conversationId,
    String senderDeviceId,
    String recipientDeviceId,
  ) => 'helix:x3dh:v1:$conversationId:$senderDeviceId:$recipientDeviceId';

  // Derives a per-message AES-256 key from the session root key using
  // HKDF-SHA256. Counter + messageId are mixed in so each message gets a
  // unique key even across parallel sends.
  Future<crypto.SecretKey> _deriveMessageKey(
    List<int> rootKeyBytes,
    int counter,
    String sessionId,
    String messageId,
  ) {
    final counterBytes = (ByteData(
      4,
    )..setUint32(0, counter & 0xFFFFFFFF, Endian.big)).buffer.asUint8List();
    return crypto.Hkdf(
      hmac: crypto.Hmac(crypto.Sha256()),
      outputLength: 32,
    ).deriveKey(
      secretKey: crypto.SecretKey(rootKeyBytes),
      nonce: List.filled(32, 0),
      info: [
        ...utf8.encode('helix-msg-v2|$sessionId|$messageId|'),
        ...counterBytes,
      ],
    );
  }

  Future<Map<String, dynamic>> _fetchOrCacheBundle(String accountId) async {
    final cached = _bundleCache[accountId];
    if (cached != null && !cached.isExpired) {
      return cached.toResponseMap();
    }

    final inflight = _bundleFetchInFlight[accountId];
    if (inflight != null) {
      // Another call is already fetching — wait for it, then return the cached
      // (no-OPK) version so only the initiating caller consumes the OPK.
      await inflight;
      final entry = _bundleCache[accountId];
      return entry?.toResponseMap() ?? {};
    }

    final fetch = restClient.getPreKeyBundle(accountId: accountId);
    _bundleFetchInFlight[accountId] = fetch;
    try {
      final response = await fetch;
      _bundleCache[accountId] = _BundleCacheEntry.fromResponse(response);
      return response; // first caller gets OPK for stronger forward secrecy
    } catch (e) {
      AppLogger.instance.error(
        'MessageCrypto',
        'prekey bundle fetch failed for account=$accountId: '
            '${e.runtimeType}: $e',
      );
      rethrow;
    } finally {
      _bundleFetchInFlight.remove(accountId);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> _buildX3dhEnvelopes({
    required String conversationId,
    required String messageId,
    required String plaintext,
    required List<String> recipientDeviceIds,
    required String senderAccountId,
    required String senderDeviceId,
  }) async {
    final envelopes = <Map<String, dynamic>>[];
    final x3dh = X3dhSessionInitiator();
    final x25519 = crypto.X25519();

    final devicePriv = _devicePrivateKey;
    final devicePub = _devicePublicKey;
    if (devicePriv == null || devicePub == null) {
      throw const SecureSessionUnavailableException(
        'local device agreement key is unavailable',
      );
    }

    // Fetch (or serve from cache) prekey bundles for all unique member accounts.
    // Concurrent messages to the same recipient share one HTTP request via
    // _bundleFetchInFlight; subsequent messages within the TTL skip the fetch
    // entirely.
    final allMembers = conversationMemberIds(conversationId);
    final otherMembers = allMembers
        .where((m) => m != senderAccountId)
        .toSet()
        .toList();

    final bundleFutures = otherMembers.map((m) => _fetchOrCacheBundle(m));
    final bundleResults = await Future.wait(bundleFutures, eagerError: false);

    // Build device_id → bundle and device_id → accountId maps; persist
    // discovered peer devices so future sends do not require pre-seeded metadata.
    final deviceBundleMap = <String, Map<String, dynamic>>{};
    final deviceToAccount = <String, String>{};
    for (var i = 0; i < bundleResults.length; i++) {
      final accountId = otherMembers[i];
      final result = bundleResults[i];
      final devices = result['devices'] as List<dynamic>? ?? [];
      final firstDevice = devices.isEmpty
          ? null
          : devices.first as Map<String, dynamic>;
      db.upsertAccount(
        RemoteAccount(
          accountId: accountId,
          username: accountId,
          identityPublicKey:
              result['account_identity_key'] as String? ??
              firstDevice?['identity_key'] as String? ??
              '',
          createdAt: _clock(),
        ),
      );
      for (final device in devices) {
        final d = device as Map<String, dynamic>;
        final deviceId = d['device_id'] as String;
        deviceBundleMap[deviceId] = d;
        deviceToAccount[deviceId] = accountId;
        db.upsertDevice(
          accountId,
          RemoteDevice(
            deviceId: deviceId,
            deviceName: d['device_name'] as String? ?? deviceId,
            deviceSigningPublicKey: d['identity_key'] as String? ?? '',
            deviceAgreementPublicKey: d['device_key'] as String? ?? '',
            createdAt: _clock(),
          ),
        );
      }
    }

    final targetDeviceIds = recipientDeviceIds.isEmpty
        ? deviceBundleMap.keys.toList()
        : recipientDeviceIds;
    if (otherMembers.isNotEmpty && targetDeviceIds.isEmpty) {
      throw const SecureSessionUnavailableException(
        'no active recipient devices found',
      );
    }

    // Reconstruct Alice's identity key pair from stored bytes.
    final aliceIdentityKey = crypto.SimpleKeyPairData(
      devicePriv,
      publicKey: crypto.SimplePublicKey(
        devicePub,
        type: crypto.KeyPairType.x25519,
      ),
      type: crypto.KeyPairType.x25519,
    );

    for (final recipientDeviceId in targetDeviceIds) {
      final bundle = deviceBundleMap[recipientDeviceId];
      if (bundle == null) {
        throw SecureSessionUnavailableException(
          'missing prekey bundle for $recipientDeviceId',
        );
      }

      final sessionId = _sessionKey(
        conversationId,
        senderDeviceId,
        recipientDeviceId,
      );
      final trace = MessageLatencyRegistry.instance.findSend(messageId);
      final existingSession = db.getCryptoSession(sessionId);

      String packedEnvelope;

      if (existingSession != null) {
        // Session exists: skip X3DH entirely and derive a per-message key.
        trace?.mark('session_cache_hit');
        try {
          packedEnvelope = await _encryptWithSession(
            session: existingSession,
            sessionId: sessionId,
            messageId: messageId,
            conversationId: conversationId,
            senderDeviceId: senderDeviceId,
            recipientDeviceId: recipientDeviceId,
            peerAccountId: deviceToAccount[recipientDeviceId],
            plaintext: plaintext,
          );
        } on SecureSessionUnavailableException {
          rethrow;
        } catch (e) {
          // Any unexpected crypto failure (e.g. native "Empty key" from a
          // corrupt session) is converted to a recoverable exception so
          // sendText marks the message SECURE_SESSION_UNAVAILABLE rather than
          // crashing. The corrupt session was already removed inside
          // _encryptWithSession; the next send will re-run full X3DH.
          throw SecureSessionUnavailableException(
            'session encrypt failed for $recipientDeviceId: $e',
          );
        }
      } else {
        // No session: run full X3DH, then persist the master key for reuse.
        trace?.mark('session_cache_miss');

        final ephemeralKey = await x25519.newKeyPair();
        final ephemeralPubKey = await ephemeralKey.extractPublicKey();

        final bobIdentityPubKey = crypto.SimplePublicKey(
          _b64d(bundle['device_key'] as String),
          type: crypto.KeyPairType.x25519,
        );
        final bobSigningPubKey = crypto.SimplePublicKey(
          _b64d(bundle['identity_key'] as String),
          type: crypto.KeyPairType.ed25519,
        );
        final spk = bundle['signed_prekey'] as Map<String, dynamic>;
        final bobSignedPrekey = crypto.SimplePublicKey(
          _b64d(spk['public_key'] as String),
          type: crypto.KeyPairType.x25519,
        );
        final bobSig = Uint8List.fromList(_b64d(spk['signature'] as String));

        crypto.SimplePublicKey? bobOpk;
        int? usedOpkId;
        final otk = bundle['one_time_prekey'] as Map<String, dynamic>?;
        if (otk != null) {
          bobOpk = crypto.SimplePublicKey(
            _b64d(otk['public_key'] as String),
            type: crypto.KeyPairType.x25519,
          );
          usedOpkId = otk['key_id'] as int;
        }

        crypto.SecretKey masterSecret;
        try {
          masterSecret = await x3dh.initiateSession(
            aliceIdentityKey: aliceIdentityKey,
            aliceEphemeralKey: ephemeralKey,
            bobIdentityPublicKey: bobIdentityPubKey,
            bobIdentitySigningPublicKey: bobSigningPubKey,
            bobSignedPrekey: bobSignedPrekey,
            bobSignedPrekeySignature: bobSig,
            bobOneTimePrekey: bobOpk,
            protocolVersion: '1',
            conversationId: conversationId,
            senderDeviceId: senderDeviceId,
            recipientDeviceId: recipientDeviceId,
          );
        } catch (_) {
          throw SecureSessionUnavailableException(
            'signed prekey verification failed for $recipientDeviceId',
          );
        }

        final masterKeyBytes = await masterSecret.extractBytes();
        if (masterKeyBytes.isEmpty) {
          // X3DH produced an unusable shared secret — do not persist this
          // session so future sends retry full X3DH with a fresh bundle.
          throw const SecureSessionUnavailableException(
            'X3DH derived empty shared secret',
          );
        }
        final aes = crypto.AesGcm.with256bits();
        final aad = _messageAad(
          messageId: messageId,
          conversationId: conversationId,
          senderDeviceId: senderDeviceId,
          recipientDeviceId: recipientDeviceId,
          protocolVersion: 1,
          contentType: RemoteCapability.contentEnvelopeV1,
          counter: 0,
        );
        final nonce = Uint8List.fromList(
          List<int>.generate(12, (_) => math.Random.secure().nextInt(256)),
        );
        final encrypted = await aes.encrypt(
          utf8.encode(plaintext),
          secretKey: crypto.SecretKey(masterKeyBytes),
          nonce: nonce,
          aad: aad,
        );

        final ciphertextBytes = BytesBuilder()
          ..add(nonce)
          ..add(encrypted.cipherText)
          ..add(encrypted.mac.bytes);
        final innerCiphertext = base64Url.encode(ciphertextBytes.toBytes());

        final aliceIdentityPubKey = await aliceIdentityKey.extractPublicKey();
        final x3dhHeader = <String, dynamic>{
          'protocol_version': 1,
          'identity_key': base64Url.encode(aliceIdentityPubKey.bytes),
          'ephemeral_key': base64Url.encode(ephemeralPubKey.bytes),
          'used_signed_prekey_id': spk['key_id'],
          'used_one_time_prekey_id': usedOpkId,
          'aad': {
            'message_id': messageId,
            'conversation_id': conversationId,
            'sender_device_id': senderDeviceId,
            'recipient_device_id': recipientDeviceId,
            'content_type': RemoteCapability.contentEnvelopeV1,
            'counter': 0,
          },
        };

        // P4-03: Pack ciphertext + X3DH header into a single opaque blob.
        packedEnvelope = base64Url.encode(
          utf8.encode(
            jsonEncode({'v': 1, 'ct': innerCiphertext, 'h': x3dhHeader}),
          ),
        );

        // Persist the derived master key so subsequent messages skip X3DH.
        // counter=0 is consumed by this v=1 message; next send starts at 1.
        final now = DateTime.now().millisecondsSinceEpoch;
        db.upsertCryptoSession(
          sessionId: sessionId,
          conversationId: conversationId,
          peerAccountId: deviceToAccount[recipientDeviceId],
          peerDeviceId: recipientDeviceId,
          role: 'sender',
          protocolVersion: 1,
          rootKey: base64Url.encode(masterKeyBytes),
          sendingChainKey: '',
          receivingChainKey: '',
          sendCount: 1,
          receiveCount: 0,
          createdAt: now,
          updatedAt: now,
        );
      }

      envelopes.add({
        'recipient_device_id': recipientDeviceId,
        'ciphertext': packedEnvelope,
      });
    }

    return envelopes;
  }

  // Encrypts [plaintext] using an existing persisted session, atomically
  // increments the send counter before any async operation, and returns
  // a v=2 packed envelope. Counter is read-then-written synchronously so
  // rapid parallel sends each get a unique counter slot.
  Future<String> _encryptWithSession({
    required Map<String, dynamic> session,
    required String sessionId,
    required String messageId,
    required String conversationId,
    required String senderDeviceId,
    required String recipientDeviceId,
    required String? peerAccountId,
    required String plaintext,
  }) async {
    final rootKeyB64 = session['root_key'] as String;
    final counter = session['send_count'] as int;

    final rootKeyBytes = _b64d(rootKeyB64);
    if (rootKeyBytes.isEmpty) {
      // Corrupt session: the stored root key decoded to zero bytes.
      // Delete it so the next sendText triggers a fresh X3DH exchange.
      db.deleteCryptoSession(sessionId);
      throw SecureSessionUnavailableException(
        'corrupt session (empty root key) for $recipientDeviceId — session cleared',
      );
    }

    // Synchronous counter increment — no await between read and write.
    final now = DateTime.now().millisecondsSinceEpoch;
    db.upsertCryptoSession(
      sessionId: sessionId,
      conversationId: conversationId,
      peerAccountId: peerAccountId,
      peerDeviceId: recipientDeviceId,
      role: session['role'] as String? ?? 'sender',
      protocolVersion: session['protocol_version'] as int? ?? 1,
      rootKey: rootKeyB64,
      sendingChainKey: session['sending_chain_key'] as String? ?? '',
      receivingChainKey: session['receiving_chain_key'] as String? ?? '',
      sendCount: counter + 1,
      receiveCount: session['receive_count'] as int? ?? 0,
      createdAt: session['created_at'] as int? ?? now,
      updatedAt: now,
    );

    final msgKey = await _deriveMessageKey(
      rootKeyBytes,
      counter,
      sessionId,
      messageId,
    );

    final nonce = Uint8List.fromList(
      List<int>.generate(12, (_) => math.Random.secure().nextInt(256)),
    );
    final aad = _messageAad(
      messageId: messageId,
      conversationId: conversationId,
      senderDeviceId: senderDeviceId,
      recipientDeviceId: recipientDeviceId,
      protocolVersion: _kSessionMsgVersion,
      contentType: RemoteCapability.contentEnvelopeV1,
      counter: counter,
    );
    final encrypted = await crypto.AesGcm.with256bits().encrypt(
      utf8.encode(plaintext),
      secretKey: msgKey,
      nonce: nonce,
      aad: aad,
    );

    final ctBytes = BytesBuilder()
      ..add(nonce)
      ..add(encrypted.cipherText)
      ..add(encrypted.mac.bytes);

    return base64Url.encode(
      utf8.encode(
        jsonEncode({
          'v': _kSessionMsgVersion,
          'sid': sessionId,
          'mc': counter,
          'ct': base64Url.encode(ctBytes.toBytes()),
          'aad': {
            'message_id': messageId,
            'conversation_id': conversationId,
            'sender_device_id': senderDeviceId,
            'recipient_device_id': recipientDeviceId,
            'content_type': RemoteCapability.contentEnvelopeV1,
            'counter': counter,
          },
        }),
      ),
    );
  }

  List<int> _messageAad({
    required String messageId,
    required String conversationId,
    required String senderDeviceId,
    required String recipientDeviceId,
    required int protocolVersion,
    required String contentType,
    required int counter,
  }) {
    return utf8.encode(
      jsonEncode({
        'domain': 'helix.remote.message.v1',
        'message_id': messageId,
        'conversation_id': conversationId,
        'sender_device_id': senderDeviceId,
        'recipient_device_id': recipientDeviceId,
        'protocol_version': protocolVersion,
        'content_type': contentType,
        'counter': counter,
      }),
    );
  }

  // Decodes base64url strings that may be missing `=` padding.
  Uint8List _b64d(String s) => base64Url.decode(base64Url.normalize(s));

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
        // Not a packed envelope JSON — fall through to local protector.
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
    final sessionId = _sessionKey(convId, senderDeviceId, recipientDeviceId);
    final now = DateTime.now().millisecondsSinceEpoch;
    db.upsertCryptoSession(
      sessionId: sessionId,
      conversationId: convId,
      peerDeviceId: senderDeviceId,
      role: 'receiver',
      protocolVersion: 1,
      rootKey: base64Url.encode(masterKeyBytes),
      sendingChainKey: '',
      receivingChainKey: '',
      sendCount: 0,
      receiveCount: (aadMap['counter'] as int? ?? 0) + 1,
      createdAt: now,
      updatedAt: now,
    );

    return utf8.decode(decrypted);
  }

  // Decrypts a v=2 session-reuse envelope. Looks up the session by 'sid' and
  // re-derives the per-message key from the root key using HKDF. X3DH does
  // not repeat. Throws [StateError] if no matching session is found — this
  // indicates the v=1 establishing message was never processed, which cannot
  // happen under normal sequential delivery.
  Future<String> _decryptSessionEnvelope(Map<String, dynamic> envelope) async {
    final sessionId = envelope['sid'] as String;
    final counter = envelope['mc'] as int;
    final innerCiphertext = envelope['ct'] as String;
    final aadMap = envelope['aad'] as Map<String, dynamic>? ?? {};

    final session = db.getCryptoSession(sessionId);
    if (session == null) {
      throw StateError('No persisted session for id=$sessionId');
    }

    final rootKeyBytes = _b64d(session['root_key'] as String);
    final messageId = aadMap['message_id'] as String? ?? '';
    final msgKey = await _deriveMessageKey(
      rootKeyBytes,
      counter,
      sessionId,
      messageId,
    );

    final rawCt = _b64d(innerCiphertext);
    final nonce = rawCt.sublist(0, 12);
    final mac = rawCt.sublist(rawCt.length - 16);
    final body = rawCt.sublist(12, rawCt.length - 16);

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

    final decrypted = await crypto.AesGcm.with256bits().decrypt(
      crypto.SecretBox(body, nonce: nonce, mac: crypto.Mac(mac)),
      secretKey: msgKey,
      aad: aad,
    );

    // Update receive counter so skipped-message detection can work later.
    final now = DateTime.now().millisecondsSinceEpoch;
    db.upsertCryptoSession(
      sessionId: sessionId,
      conversationId: aadMap['conversation_id'] as String? ?? '',
      peerDeviceId: session['peer_device_id'] as String?,
      peerAccountId: session['peer_account_id'] as String?,
      role: session['role'] as String? ?? 'receiver',
      protocolVersion: session['protocol_version'] as int? ?? 1,
      rootKey: session['root_key'] as String,
      sendingChainKey: session['sending_chain_key'] as String? ?? '',
      receivingChainKey: session['receiving_chain_key'] as String? ?? '',
      sendCount: session['send_count'] as int? ?? 0,
      receiveCount: counter + 1,
      createdAt: session['created_at'] as int? ?? now,
      updatedAt: now,
    );

    return utf8.decode(decrypted);
  }
}
