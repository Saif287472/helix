import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as hashing;
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_crypto/helix_remote_crypto.dart';
import 'package:helix_remote_cli/src/cli_secure_storage.dart';
import 'package:helix_remote_cli/src/cli_rest_client.dart';
import 'package:helix_remote_cli/src/cli_message_envelope.dart';
import 'dart:async';

/// Salted HMAC-SHA256 phone hash, mirroring the backend's and mobile app's
/// implementation exactly so a given salt+E.164 number always produces the
/// same phone_hash regardless of which client computed it.
String cliPhoneHash(String saltBase64, String e164Number) {
  final saltBytes = base64.decode(saltBase64);
  final hmac = hashing.Hmac(hashing.sha256, saltBytes);
  return hmac.convert(utf8.encode(e164Number)).toString();
}

class HelixCliClient {
  HelixCliClient({required this.dbFile, required this.keyFile});

  final File dbFile;
  final File keyFile;

  late final HelixRemoteDatabase db;
  late final CliSecureStorage storage;

  bool _initialized = false;

  void initialize() {
    if (_initialized) return;

    // 1. Initialize SQLite Database
    db = HelixRemoteDatabase(dbFile);
    db.initialize();

    // 2. Initialize CliSecureStorage
    storage = CliSecureStorage(keyFile);

    _initialized = true;
  }

  WebSocket? _webSocket;
  StreamSubscription<dynamic>? _wsSubscription;

  void close() {
    if (_initialized) {
      _wsSubscription?.cancel();
      _webSocket?.close();
      db.close();
      _initialized = false;
    }
  }

  /// Bootstraps local client identity (Account Identity Key, Device Keys, and Signed Prekey).
  Future<void> bootstrap({
    required String accountId,
    required String phoneHash,
    required String deviceId,
    required String deviceName,
  }) async {
    initialize();

    final ed25519 = crypto.Ed25519();
    final x25519 = crypto.X25519();

    // 1. Generate Ed25519 Account Identity Key Pair (IK_A)
    final identitySigningKeyPair = await ed25519.newKeyPair();
    final identityKeyPairData = await identitySigningKeyPair.extract();

    // 2. Generate Ed25519 Device Signing Key Pair (IK_D_signing)
    final deviceSigningKeyPair = await ed25519.newKeyPair();
    final devSignKeyPairData = await deviceSigningKeyPair.extract();

    // 3. Generate X25519 Device Identity Key Pair (IK_D)
    final deviceKeyPair = await x25519.newKeyPair();
    final deviceKeyPairData = await deviceKeyPair.extract();

    // 4. Generate X25519 Signed Prekey (SPK)
    final signedPrekeyPair = await x25519.newKeyPair();
    final spkKeyPairData = await signedPrekeyPair.extract();

    // 5. Sign the Signed Prekey with the Account Identity Key (Ed25519)
    final prekeyBytes = Uint8List.fromList(spkKeyPairData.publicKey.bytes);
    final signatureObj = await ed25519.sign(
      prekeyBytes,
      keyPair: identitySigningKeyPair,
    );
    final signatureBytes = Uint8List.fromList(signatureObj.bytes);

    final accountIdentityPub = _toBase64Url(
      identityKeyPairData.publicKey.bytes,
    );
    final devSigningPub = _toBase64Url(devSignKeyPairData.publicKey.bytes);
    final devAgreementPub = _toBase64Url(deviceKeyPairData.publicKey.bytes);
    final spkPub = _toBase64Url(spkKeyPairData.publicKey.bytes);
    final spkSignature = _toBase64Url(signatureBytes);

    // 6. Persist private/public material in file-based Secure Storage
    await storage.writeKey(
      'identity_private',
      base64Encode(identityKeyPairData.bytes),
    );
    await storage.writeKey('identity_public', accountIdentityPub);

    await storage.writeKey(
      'device_signing_private',
      base64Encode(devSignKeyPairData.bytes),
    );
    await storage.writeKey('device_signing_public', devSigningPub);

    await storage.writeKey(
      'device_private',
      base64Encode(deviceKeyPairData.bytes),
    );
    await storage.writeKey('device_public', devAgreementPub);

    await storage.writeKey('spk_private', base64Encode(spkKeyPairData.bytes));
    await storage.writeKey('spk_public', spkPub);
    await storage.writeKey('spk_signature', spkSignature);

    // Save account config helper keys
    await storage.writeKey('account_id', accountId);
    await storage.writeKey('phone_hash', phoneHash);
    await storage.writeKey('device_id', deviceId);

    // 7. Record own identity inside local SQLite database
    final now = DateTime.now();
    db.upsertAccount(
      RemoteAccount(
        accountId: accountId,
        identityPublicKey: accountIdentityPub,
        createdAt: now,
        status: 'Active',
      ),
    );

    db.upsertDevice(
      accountId,
      RemoteDevice(
        deviceId: deviceId,
        deviceName: deviceName,
        deviceSigningPublicKey: devSigningPub,
        deviceAgreementPublicKey: devAgreementPub,
        createdAt: now,
        status: 'Active',
      ),
    );

    db.saveLocalPrekey(
      keyId: 1,
      role: 'signed_prekey',
      deviceId: deviceId,
      publicKey: spkPub,
      privateKeyRef: 'spk_private',
      createdAt: now.millisecondsSinceEpoch,
      rotationState: 'active',
      signature: spkSignature,
    );
  }

  /// Registers client identity with a remote backend server and bootstraps local storage.
  ///
  /// `phoneNumber` must already be in E.164 form (e.g. `+15551234567`);
  /// `otpCode` comes from a prior `restClient.requestPhoneOtp()` call and
  /// `inviteCode` from an admin-issued or Helix-Global auto-issued invite.
  Future<void> register({
    required CliRestClient restClient,
    required String accountId,
    required String phoneNumber,
    required String displayName,
    required String otpCode,
    required String inviteCode,
    required String deviceId,
    required String deviceName,
  }) async {
    final saltResult = await restClient.fetchDiscoverySalt();
    final phoneHash = _phoneHash(saltResult['salt'] as String, phoneNumber);

    // Generate all keys and populate local state
    await bootstrap(
      accountId: accountId,
      phoneHash: phoneHash,
      deviceId: deviceId,
      deviceName: deviceName,
    );

    // Load keys to compute registration signatures
    final privIdentity = await storage.readKey('identity_private');
    final pubIdentity = await storage.readKey('identity_public');
    final privDevSigning = await storage.readKey('device_signing_private');
    final pubDevSigning = await storage.readKey('device_signing_public');
    final pubDevAgreement = await storage.readKey('device_public');

    final ed25519 = crypto.Ed25519();
    final accountKeyPair = crypto.SimpleKeyPairData(
      _decodeB64(privIdentity!),
      publicKey: crypto.SimplePublicKey(
        _decodeB64(pubIdentity!),
        type: crypto.KeyPairType.ed25519,
      ),
      type: crypto.KeyPairType.ed25519,
    );
    final deviceSigningKeyPair = crypto.SimpleKeyPairData(
      _decodeB64(privDevSigning!),
      publicKey: crypto.SimplePublicKey(
        _decodeB64(pubDevSigning!),
        type: crypto.KeyPairType.ed25519,
      ),
      type: crypto.KeyPairType.ed25519,
    );

    // Compute Registration Signatures
    final transcript = [
      'helix.remote.registration.v3',
      accountId,
      phoneHash,
      pubIdentity,
      deviceId,
      pubDevSigning,
      pubDevAgreement,
      deviceName,
    ].join('\n');

    final accountRegSigObj = await ed25519.sign(
      utf8.encode(transcript),
      keyPair: accountKeyPair,
    );
    final deviceRegSigObj = await ed25519.sign(
      utf8.encode(transcript),
      keyPair: deviceSigningKeyPair,
    );

    final accountRegSig = _toBase64Url(accountRegSigObj.bytes);
    final deviceRegSig = _toBase64Url(deviceRegSigObj.bytes);

    // Call REST register endpoint
    await restClient.registerAccount(
      accountId: accountId,
      phoneHash: phoneHash,
      otpCode: otpCode,
      inviteCode: inviteCode,
      displayName: displayName,
      accountIdentityPublicKey: pubIdentity,
      deviceId: deviceId,
      deviceSigningPublicKey: pubDevSigning,
      deviceAgreementPublicKey: pubDevAgreement!,
      accountRegistrationSignature: accountRegSig,
      deviceRegistrationSignature: deviceRegSig,
      deviceName: deviceName,
    );
  }

  String _toBase64Url(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _phoneHash(String saltBase64, String e164Number) =>
      cliPhoneHash(saltBase64, e164Number);

  List<int> _decodeB64(String value) {
    try {
      return base64Url.decode(base64Url.normalize(value));
    } catch (_) {
      return base64.decode(value);
    }
  }

  // ---------------------------------------------------------------------------
  // Contact Registry Operations
  // ---------------------------------------------------------------------------

  void addContact(String peerAccountId, String nickname) {
    initialize();
    db.upsertContact(
      RemoteContact(
        peerAccountId: peerAccountId,
        nickname: nickname,
        status: 'active',
      ),
    );
  }

  List<RemoteContact> listContacts() {
    initialize();
    return db.getContacts();
  }

  // ---------------------------------------------------------------------------
  // Session Persistence Operations
  // ---------------------------------------------------------------------------

  Future<void> saveSession(
    String sessionId,
    String conversationId,
    DoubleRatchetSession session, {
    String? peerAccountId,
    String? peerDeviceId,
  }) async {
    initialize();

    final rootKeyBytes = await session.rk.extractBytes();
    final ckSendBytes = session.ckSend != null
        ? await session.ckSend!.extractBytes()
        : null;
    final ckRecvBytes = session.ckRecv != null
        ? await session.ckRecv!.extractBytes()
        : null;

    final Map<String, String> skippedKeysBase64 = {};
    for (final entry in session.skippedMessageKeys.entries) {
      final keyBytes = await entry.value.extractBytes();
      skippedKeysBase64[entry.key] = base64Encode(keyBytes);
    }
    final skippedKeysJson = jsonEncode(skippedKeysBase64);

    final now = DateTime.now().millisecondsSinceEpoch;

    db.upsertCryptoSession(
      sessionId: sessionId,
      conversationId: conversationId,
      role: 'direct',
      protocolVersion: 1,
      rootKey: base64Encode(rootKeyBytes),
      sendingChainKey: ckSendBytes != null ? base64Encode(ckSendBytes) : '',
      receivingChainKey: ckRecvBytes != null ? base64Encode(ckRecvBytes) : '',
      sendCount: session.ns,
      receiveCount: session.nr,
      previousChainLength: session.pn,
      skippedKeysJson: skippedKeysJson,
      createdAt: now,
      updatedAt: now,
      peerAccountId: peerAccountId,
      peerDeviceId: peerDeviceId,
    );

    // Save DH keys if set
    if (session.dHk != null) {
      final dhkData = await session.dHk!.extract();
      await storage.writeKey(
        'session_dhk_private_$sessionId',
        base64Encode(dhkData.bytes),
      );
      await storage.writeKey(
        'session_dhk_public_$sessionId',
        base64Encode(dhkData.publicKey.bytes),
      );
    }
    if (session.dHp != null) {
      await storage.writeKey(
        'session_dhp_public_$sessionId',
        base64Encode(session.dHp!.bytes),
      );
    }
  }

  Future<DoubleRatchetSession?> loadSession(String sessionId) async {
    initialize();

    final sessionMap = db.getCryptoSession(sessionId);
    if (sessionMap == null) return null;

    final rootKey = crypto.SecretKey(
      _decodeB64(sessionMap['root_key'] as String),
    );
    final sendKeyRaw = sessionMap['sending_chain_key'] as String;
    final recvKeyRaw = sessionMap['receiving_chain_key'] as String;

    final sendKey = sendKeyRaw.isNotEmpty
        ? crypto.SecretKey(_decodeB64(sendKeyRaw))
        : null;
    final recvKey = recvKeyRaw.isNotEmpty
        ? crypto.SecretKey(_decodeB64(recvKeyRaw))
        : null;

    final skippedKeysJson = sessionMap['skipped_keys_json'] as String? ?? '[]';
    final Map<String, dynamic> skippedKeysDecoded =
        skippedKeysJson.startsWith('{')
        ? jsonDecode(skippedKeysJson) as Map<String, dynamic>
        : {};

    final Map<String, crypto.SecretKey> skippedKeys = {};
    for (final entry in skippedKeysDecoded.entries) {
      skippedKeys[entry.key] = crypto.SecretKey(
        _decodeB64(entry.value as String),
      );
    }

    // Load DH keys if set
    crypto.SimpleKeyPair? dHk;
    final dhkPrivateStr = await storage.readKey(
      'session_dhk_private_$sessionId',
    );
    final dhkPublicStr = await storage.readKey('session_dhk_public_$sessionId');
    if (dhkPrivateStr != null && dhkPublicStr != null) {
      dHk = crypto.SimpleKeyPairData(
        _decodeB64(dhkPrivateStr),
        publicKey: crypto.SimplePublicKey(
          _decodeB64(dhkPublicStr),
          type: crypto.KeyPairType.x25519,
        ),
        type: crypto.KeyPairType.x25519,
      );
    }

    crypto.SimplePublicKey? dHp;
    final dhpPublicStr = await storage.readKey('session_dhp_public_$sessionId');
    if (dhpPublicStr != null) {
      dHp = crypto.SimplePublicKey(
        _decodeB64(dhpPublicStr),
        type: crypto.KeyPairType.x25519,
      );
    }

    return DoubleRatchetSession(
      rootKey: rootKey,
      sendingChainKey: sendKey ?? crypto.SecretKey([]), // Fallback
      receivingChainKey: recvKey ?? crypto.SecretKey([]),
      dHk: dHk,
      dHp: dHp,
      ns: sessionMap['send_count'] as int? ?? 0,
      nr: sessionMap['receive_count'] as int? ?? 0,
      pn: sessionMap['previous_chain_length'] as int? ?? 0,
    )..skippedMessageKeys.addAll(skippedKeys);
  }

  // ---------------------------------------------------------------------------
  // Prekeys & X3DH Operations
  // ---------------------------------------------------------------------------

  Future<void> publishPrekeys({
    required CliRestClient restClient,
    int oneTimePrekeysCount = 20,
  }) async {
    initialize();

    final deviceId = await storage.readKey('device_id');
    final spkPublic = await storage.readKey('spk_public');
    final spkSignature = await storage.readKey('spk_signature');
    if (deviceId == null || spkPublic == null || spkSignature == null) {
      throw StateError('Client not bootstrapped');
    }

    final x25519 = crypto.X25519();
    final List<Map<String, dynamic>> oneTimePrekeys = [];

    for (var i = 0; i < oneTimePrekeysCount; i++) {
      final kp = await x25519.newKeyPair();
      final kpData = await kp.extract();

      final keyId = i + 1; // 1-indexed key ID
      oneTimePrekeys.add({
        'key_id': keyId,
        'public_key': base64Encode(kpData.publicKey.bytes),
      });

      // Save locally
      db.saveLocalPrekey(
        keyId: keyId,
        role: 'one_time_prekey',
        deviceId: deviceId,
        publicKey: base64Encode(kpData.publicKey.bytes),
        privateKeyRef: 'otk_private_$keyId',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        rotationState: 'active',
      );
      await storage.writeKey('otk_private_$keyId', base64Encode(kpData.bytes));
    }

    // Publish to backend
    await restClient.uploadPreKeys(
      signedPrekeyId: 1,
      signedPrekey: spkPublic,
      signedPrekeySignature: spkSignature,
      oneTimePrekeys: oneTimePrekeys,
    );
  }

  Future<void> login({required CliRestClient restClient}) async {
    final accountId = await storage.readKey('account_id');
    final deviceId = await storage.readKey('device_id');
    if (accountId == null || deviceId == null) {
      throw StateError('Client not bootstrapped');
    }

    final challengeRes = await restClient.getChallenge(
      accountId: accountId,
      deviceId: deviceId,
    );
    final challenge = challengeRes['challenge'] as String;

    // Load local device signing key
    final privStr = await storage.readKey('device_signing_private');
    final pubStr = await storage.readKey('device_signing_public');
    if (privStr == null || pubStr == null) {
      throw StateError('Device signing keypair not found in storage');
    }
    final ed25519 = crypto.Ed25519();
    final identityKeyPair = crypto.SimpleKeyPairData(
      _decodeB64(privStr),
      publicKey: crypto.SimplePublicKey(
        _decodeB64(pubStr),
        type: crypto.KeyPairType.ed25519,
      ),
      type: crypto.KeyPairType.ed25519,
    );

    // Sign challenge
    final signatureObj = await ed25519.sign(
      utf8.encode(challenge),
      keyPair: identityKeyPair,
    );
    final signature = _toBase64Url(signatureObj.bytes);

    // Login
    await restClient.loginDevice(
      accountId: accountId,
      deviceId: deviceId,
      signature: signature,
    );
  }

  Future<DoubleRatchetSession> initiateSessionWithPeer({
    required CliRestClient restClient,
    required String peerAccountId,
    required String conversationId,
  }) async {
    initialize();

    // 1. Get peer's prekey bundle
    final bundle = await restClient.getPreKeyBundle(accountId: peerAccountId);
    final devices = bundle['devices'] as List;
    if (devices.isEmpty) {
      throw StateError('No active devices found for peer: $peerAccountId');
    }

    final device = devices[0] as Map<String, dynamic>;
    final peerDeviceId = device['device_id'] as String;

    // Parse keys from bundle
    final bobIdentitySigningPublic = crypto.SimplePublicKey(
      _decodeB64(device['identity_key'] as String),
      type: crypto.KeyPairType.ed25519,
    );
    final bobIdentityPublic = crypto.SimplePublicKey(
      _decodeB64(device['device_key'] as String),
      type: crypto.KeyPairType.x25519,
    );
    final signedPrekey = device['signed_prekey'] as Map<String, dynamic>;
    final bobSignedPrekey = crypto.SimplePublicKey(
      _decodeB64(signedPrekey['public_key'] as String),
      type: crypto.KeyPairType.x25519,
    );
    final bobSignedPrekeySignature = _decodeB64(
      signedPrekey['signature'] as String,
    );

    crypto.SimplePublicKey? bobOneTimePrekey;
    final oneTimePrekey = device['one_time_prekey'] as Map<String, dynamic>?;
    if (oneTimePrekey != null) {
      bobOneTimePrekey = crypto.SimplePublicKey(
        _decodeB64(oneTimePrekey['public_key'] as String),
        type: crypto.KeyPairType.x25519,
      );
    }

    // 2. Load Alice's device keypair (IK_D_Alice)
    final aliceDevPrivate = await storage.readKey('device_private');
    final aliceDevPublic = await storage.readKey('device_public');
    if (aliceDevPrivate == null || aliceDevPublic == null) {
      throw StateError('Client identity keys not found');
    }

    final aliceIdentityKeyPair = crypto.SimpleKeyPairData(
      _decodeB64(aliceDevPrivate),
      publicKey: crypto.SimplePublicKey(
        _decodeB64(aliceDevPublic),
        type: crypto.KeyPairType.x25519,
      ),
      type: crypto.KeyPairType.x25519,
    );

    // 3. Generate Ephemeral Key (EK_Alice)
    final x25519 = crypto.X25519();
    final aliceEphemeralKey = await x25519.newKeyPair();

    // 4. Perform X3DH Key Agreement
    final initiator = X3dhSessionInitiator();
    final sharedSecret = await initiator.initiateSession(
      aliceIdentityKey: aliceIdentityKeyPair,
      aliceEphemeralKey: aliceEphemeralKey,
      bobIdentityPublicKey: bobIdentityPublic,
      bobIdentitySigningPublicKey: bobIdentitySigningPublic,
      bobSignedPrekey: bobSignedPrekey,
      bobSignedPrekeySignature: Uint8List.fromList(bobSignedPrekeySignature),
      bobOneTimePrekey: bobOneTimePrekey,
    );

    // 5. Initialize Double Ratchet Session
    final session = await DoubleRatchetSession.initiate(
      sharedKey: sharedSecret,
      peerPublicKey: bobIdentityPublic,
    );

    // 6. Save Session locally
    final sessionId = 'direct:$conversationId:$peerAccountId:$peerDeviceId';
    await saveSession(
      sessionId,
      conversationId,
      session,
      peerAccountId: peerAccountId,
      peerDeviceId: peerDeviceId,
    );

    // Save extra session metadata for Bob to consume
    final epPublic = await aliceEphemeralKey.extractPublicKey();
    await storage.writeKey(
      'session_init_ephemeral_$sessionId',
      base64Encode(epPublic.bytes),
    );
    if (oneTimePrekey != null) {
      await storage.writeKey(
        'session_init_otk_id_$sessionId',
        '${oneTimePrekey['key_id']}',
      );
    }

    return session;
  }

  Future<DoubleRatchetSession> receiveSessionFromPeer({
    required String peerAccountId,
    required String peerDeviceId,
    required String conversationId,
    required String aliceEphemeralPublicBase64,
    int? bobOneTimePrekeyId,
  }) async {
    initialize();

    // 1. Load Bob's device identity keys (IK_D_Bob)
    final bobIdPrivate = await storage.readKey('device_private');
    final bobIdPublic = await storage.readKey('device_public');
    if (bobIdPrivate == null || bobIdPublic == null) {
      throw StateError('Bob device identity keys not found');
    }
    final bobIdentityKeyPair = crypto.SimpleKeyPairData(
      _decodeB64(bobIdPrivate),
      publicKey: crypto.SimplePublicKey(
        _decodeB64(bobIdPublic),
        type: crypto.KeyPairType.x25519,
      ),
      type: crypto.KeyPairType.x25519,
    );

    // Load consumed Signed Prekey (SPK_Bob)
    final bobSpkPrivate = await storage.readKey('spk_private');
    final bobSpkPublic = await storage.readKey('spk_public');
    if (bobSpkPrivate == null || bobSpkPublic == null) {
      throw StateError('Bob SPK keys not found');
    }
    final bobSignedPrekeyKeyPair = crypto.SimpleKeyPairData(
      _decodeB64(bobSpkPrivate),
      publicKey: crypto.SimplePublicKey(
        _decodeB64(bobSpkPublic),
        type: crypto.KeyPairType.x25519,
      ),
      type: crypto.KeyPairType.x25519,
    );

    // Load consumed One-Time Prekey (OPK_Bob) if any
    crypto.SimpleKeyPair? bobOneTimePrekeyKeyPair;
    if (bobOneTimePrekeyId != null) {
      final otkPrivate = await storage.readKey(
        'otk_private_$bobOneTimePrekeyId',
      );
      if (otkPrivate != null) {
        final x25519 = crypto.X25519();
        final privateKeyBytes = _decodeB64(otkPrivate);
        bobOneTimePrekeyKeyPair = await x25519.newKeyPairFromSeed(
          privateKeyBytes,
        );
      }
    }

    // 2. Fetch Alice's Device Key (IK_D_Alice)
    final devices = db.getDevices(peerAccountId);
    final aliceDevice = devices.firstWhere((d) => d.deviceId == peerDeviceId);
    final aliceIdentityPublic = crypto.SimplePublicKey(
      _decodeB64(aliceDevice.deviceAgreementPublicKey),
      type: crypto.KeyPairType.x25519,
    );

    final aliceEphemeralPublicKey = crypto.SimplePublicKey(
      _decodeB64(aliceEphemeralPublicBase64),
      type: crypto.KeyPairType.x25519,
    );

    // 3. Compute X3DH Shared Secret
    final initiator = X3dhSessionInitiator();
    final sharedSecret = await initiator.receiveSession(
      bobIdentityKey: bobIdentityKeyPair,
      bobSignedPrekey: bobSignedPrekeyKeyPair,
      bobOneTimePrekey: bobOneTimePrekeyKeyPair,
      aliceIdentityPublicKey: aliceIdentityPublic,
      aliceEphemeralPublicKey: aliceEphemeralPublicKey,
    );

    // 4. Initialize Bob's Double Ratchet Session
    final session = await DoubleRatchetSession.receive(
      sharedKey: sharedSecret,
      localKeyPair: bobIdentityKeyPair,
    );

    // 5. Save Bob's Session locally
    final sessionId = 'direct:$conversationId:$peerAccountId:$peerDeviceId';
    await saveSession(
      sessionId,
      conversationId,
      session,
      peerAccountId: peerAccountId,
      peerDeviceId: peerDeviceId,
    );

    return session;
  }

  // ---------------------------------------------------------------------------
  // Outbox & WebSocket Exchange Operations
  // ---------------------------------------------------------------------------

  void enqueueSendMessage({
    required String messageId,
    required String conversationId,
    required String peerAccountId,
    required String plaintext,
  }) {
    initialize();
    final payload = {
      'message_id': messageId,
      'conversation_id': conversationId,
      'peer_account_id': peerAccountId,
      'plaintext': plaintext,
    };
    db.enqueueOperation(
      'op_$messageId',
      'SEND_MESSAGE',
      jsonEncode(payload),
      idempotencyKey: 'idem_$messageId',
    );
  }

  Future<void> processOutbox(CliRestClient restClient) async {
    initialize();
    final pending = db.getPendingOperations();
    for (final op in pending) {
      if (op['type'] != 'SEND_MESSAGE') continue;

      final opId = op['op_id'] as String;
      final retries = op['retries'] as int;
      final payload =
          jsonDecode(op['payload'] as String) as Map<String, dynamic>;

      final messageId = payload['message_id'] as String;
      final conversationId = payload['conversation_id'] as String;
      final peerAccountId = payload['peer_account_id'] as String;
      final plaintext = payload['plaintext'] as String;

      try {
        // 1. Resolve or establish E2EE session with the peer
        final bundle = await restClient.getPreKeyBundle(
          accountId: peerAccountId,
        );
        final devices = (bundle['devices'] as List)
            .cast<Map<String, dynamic>>();
        if (devices.isEmpty) {
          throw StateError('No active devices for peer: $peerAccountId');
        }

        final envelopes = <Map<String, dynamic>>[];
        String? finalPackedEnvelope;

        for (final device in devices) {
          final peerDeviceId = device['device_id'] as String;
          final sessionId =
              'direct:$conversationId:$peerAccountId:$peerDeviceId';

          DoubleRatchetSession session;
          final existingSession = await loadSession(sessionId);

          String packedEnvelope;

          if (existingSession != null) {
            session = existingSession;
            final doubleRatchetCt = await session.encrypt(
              Uint8List.fromList(plaintext.codeUnits),
            );
            final envelope = CliMessageEnvelope(
              isInit: false,
              ciphertext: base64Encode(doubleRatchetCt),
            );
            packedEnvelope = envelope.pack();

            await saveSession(
              sessionId,
              conversationId,
              session,
              peerAccountId: peerAccountId,
              peerDeviceId: peerDeviceId,
            );
          } else {
            // Initiate new session
            session = await initiateSessionWithPeer(
              restClient: restClient,
              peerAccountId: peerAccountId,
              conversationId: conversationId,
            );

            final doubleRatchetCt = await session.encrypt(
              Uint8List.fromList(plaintext.codeUnits),
            );

            final epKey = await storage.readKey(
              'session_init_ephemeral_$sessionId',
            );
            final otkId = await storage.readKey(
              'session_init_otk_id_$sessionId',
            );

            final envelope = CliMessageEnvelope(
              isInit: true,
              ciphertext: base64Encode(doubleRatchetCt),
              ephemeralKey: epKey,
              oneTimePrekeyId: otkId != null ? int.parse(otkId) : null,
            );
            packedEnvelope = envelope.pack();

            // Clear the initiation metadata
            await storage.deleteKey('session_init_ephemeral_$sessionId');
            await storage.deleteKey('session_init_otk_id_$sessionId');

            // Save the session again to commit the Advanced counter
            await saveSession(
              sessionId,
              conversationId,
              session,
              peerAccountId: peerAccountId,
              peerDeviceId: peerDeviceId,
            );
          }

          envelopes.add({
            'recipient_device_id': peerDeviceId,
            'ciphertext': packedEnvelope,
          });
          finalPackedEnvelope = packedEnvelope;
        }

        // 2. Upload envelopes to the backend message registry
        await restClient.sendMessage(
          messageId: messageId,
          conversationId: conversationId,
          envelopes: envelopes,
        );

        // 3. Mark pending operation as completed and save to local SQLite
        db.updateOperationStatus(opId, 'COMPLETED', retries);

        // Retrieve account ID and device ID from storage
        final accountId = await storage.readKey('account_id');
        final deviceId = await storage.readKey('device_id');

        db.saveMessage(
          RemoteMessage(
            messageId: messageId,
            conversationId: conversationId,
            senderAccountId: accountId ?? '',
            senderDeviceId: deviceId ?? '',
            ciphertext: finalPackedEnvelope ?? '',
          ),
          0, // sequence placeholder, updated on sync
          DateTime.now().millisecondsSinceEpoch,
          'SENT',
        );
      } catch (e) {
        db.updateOperationStatus(opId, 'FAILED', retries + 1);
        final backoff = Duration(seconds: (retries + 1) * 2);
        db.scheduleNextOperationAttempt(
          opId,
          DateTime.now().add(backoff).millisecondsSinceEpoch,
        );
        rethrow;
      }
    }
  }

  Future<void> connectWebSocket({
    required CliRestClient restClient,
    void Function(String messageId, String plaintext)? onMessageReceived,
  }) async {
    initialize();

    // Determine cursor ('since' parameter)
    final cursor = 0;

    // Build WS URL
    final wsUrl = restClient.baseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    final uri = Uri.parse('$wsUrl/api/v1/ws?since=$cursor');

    // Connect
    _webSocket = await WebSocket.connect(
      uri.toString(),
      headers: {'Authorization': 'Bearer ${restClient.accessToken}'},
    );

    _wsSubscription = _webSocket!.listen(
      (data) async {
        try {
          final payload = jsonDecode(data as String) as Map<String, dynamic>;
          final eventType = payload['type'] as String?;
          if (eventType == 'chat_message') {
            final msgMap = payload['payload'] as Map<String, dynamic>;
            final messageId = msgMap['message_id'] as String;
            final conversationId = msgMap['conversation_id'] as String;
            final senderAccountId = msgMap['sender_account_id'] as String;
            final senderDeviceId = msgMap['sender_device_id'] as String;
            final packedCiphertext = msgMap['ciphertext'] as String;
            final serverSeq = payload['server_sequence'] as int;
            final timestamp = payload['timestamp'] as int;

            // Unpack the envelope
            final envelope = CliMessageEnvelope.unpack(packedCiphertext);
            final doubleRatchetCt = _decodeB64(envelope.ciphertext);

            final sessionId =
                'direct:$conversationId:$senderAccountId:$senderDeviceId';
            DoubleRatchetSession session;

            if (envelope.isInit) {
              // 1. Process X3DH reception
              session = await receiveSessionFromPeer(
                peerAccountId: senderAccountId,
                peerDeviceId: senderDeviceId,
                conversationId: conversationId,
                aliceEphemeralPublicBase64: envelope.ephemeralKey!,
                bobOneTimePrekeyId: envelope.oneTimePrekeyId,
              );
            } else {
              // 2. Load existing session
              final existing = await loadSession(sessionId);
              if (existing == null) {
                throw StateError(
                  'E2EE session not found for message: $messageId',
                );
              }
              session = existing;
            }

            // 3. Decrypt ciphertext using Double Ratchet
            final plaintextBytes = await session.decrypt(
              Uint8List.fromList(doubleRatchetCt),
            );
            final plaintext = String.fromCharCodes(plaintextBytes);

            // 4. Save session updates (counters/ratchet keys/skipped keys)
            await saveSession(
              sessionId,
              conversationId,
              session,
              peerAccountId: senderAccountId,
              peerDeviceId: senderDeviceId,
            );

            // 5. Save received message locally
            db.saveMessage(
              RemoteMessage(
                messageId: messageId,
                conversationId: conversationId,
                senderAccountId: senderAccountId,
                senderDeviceId: senderDeviceId,
                ciphertext: packedCiphertext,
              ),
              serverSeq,
              timestamp,
              'RECEIVED',
            );

            // 6. Send cursor acknowledgment back to server
            _webSocket?.add(
              jsonEncode({
                'type': 'ack',
                'conversation_id': conversationId,
                'sequence': serverSeq,
              }),
            );

            // 7. Invoke client callback
            onMessageReceived?.call(messageId, plaintext);
          }
        } catch (e) {
          stderr.writeln('Error processing WS incoming message: $e');
        }
      },
      onDone: () => _wsSubscription = null,
      onError: (err) => stderr.writeln('WS stream error: $err'),
    );
  }
}
