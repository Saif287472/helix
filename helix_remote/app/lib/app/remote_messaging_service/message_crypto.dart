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
        // one_time_prekey deliberately omitted â€” must not be reused
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
      // Another call is already fetching â€” wait for it, then return the cached
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

    // Build device_id â†’ bundle and device_id â†’ accountId maps; persist
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
          // X3DH produced an unusable shared secret â€” do not persist this
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
        'corrupt session (empty root key) for $recipientDeviceId â€” session cleared',
      );
    }

    // Synchronous counter increment â€” no await between read and write.
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


}
