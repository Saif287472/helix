import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as crypto;

class DoubleRatchetHeader {
  DoubleRatchetHeader({
    required this.dhPublicBytes,
    required this.pn,
    required this.n,
  });

  final Uint8List dhPublicBytes;
  final int pn;
  final int n;

  Map<String, dynamic> toJson() => {
        'dh': base64Encode(dhPublicBytes),
        'pn': pn,
        'n': n,
      };

  factory DoubleRatchetHeader.fromJson(Map<String, dynamic> json) {
    return DoubleRatchetHeader(
      dhPublicBytes: base64Decode(json['dh'] as String),
      pn: json['pn'] as int,
      n: json['n'] as int,
    );
  }
}

class DoubleRatchetSession {
  crypto.SimpleKeyPair? dHk; // our current local DH keypair
  crypto.SimplePublicKey? dHp; // peer's current DH public key
  crypto.SecretKey rk; // Root Key
  crypto.SecretKey? ckSend; // Sending Chain Key
  crypto.SecretKey? ckRecv; // Receiving Chain Key
  int ns = 0; // sending sequence number
  int nr = 0; // receiving sequence number
  int pn = 0; // PN: previous sending chain length

  final Map<String, crypto.SecretKey> skippedMessageKeys = {};

  final crypto.AesGcm aesGcm = crypto.AesGcm.with256bits();
  final crypto.Hkdf hkdf = crypto.Hkdf(
    hmac: crypto.Hmac(crypto.Sha256()),
    outputLength: 32,
  );

  // Compatible constructor for existing tests
  DoubleRatchetSession({
    required crypto.SecretKey rootKey,
    required crypto.SecretKey sendingChainKey,
    required crypto.SecretKey receivingChainKey,
    this.dHk,
    this.dHp,
    this.ns = 0,
    this.nr = 0,
    this.pn = 0,
  })  : rk = rootKey,
        ckSend = sendingChainKey,
        ckRecv = receivingChainKey;

  DoubleRatchetSession._({
    this.dHk,
    this.dHp,
    required this.rk,
    this.ckSend,
    this.ckRecv,
    this.ns = 0,
    this.nr = 0,
    this.pn = 0,
    Map<String, crypto.SecretKey>? skippedKeys,
  }) {
    if (skippedKeys != null) {
      skippedMessageKeys.addAll(skippedKeys);
    }
  }

  // Alice (initiator) initialization
  static Future<DoubleRatchetSession> initiate({
    required crypto.SecretKey sharedKey,
    required crypto.SimplePublicKey peerPublicKey,
  }) async {
    final x25519 = crypto.X25519();
    final localKeyPair = await x25519.newKeyPair();

    // DH = ECDH(localKeyPair, peerPublicKey)
    final dh = await x25519.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: peerPublicKey,
    );

    final hkdfRK = crypto.Hkdf(
      hmac: crypto.Hmac(crypto.Sha256()),
      outputLength: 64, // 32 bytes Root Key, 32 bytes Sending Chain Key
    );
    final derived = await hkdfRK.deriveKey(
      secretKey: dh,
      nonce: await sharedKey.extractBytes(),
      info: 'helix-double-ratchet-rk'.codeUnits,
    );
    final derivedBytes = await derived.extractBytes();
    final newRk = crypto.SecretKey(derivedBytes.sublist(0, 32));
    final newCkSend = crypto.SecretKey(derivedBytes.sublist(32, 64));

    return DoubleRatchetSession._(
      dHk: localKeyPair,
      dHp: peerPublicKey,
      rk: newRk,
      ckSend: newCkSend,
    );
  }

  // Bob (receiver) initialization
  static Future<DoubleRatchetSession> receive({
    required crypto.SecretKey sharedKey,
    required crypto.SimpleKeyPair localKeyPair,
  }) async {
    return DoubleRatchetSession._(
      dHk: localKeyPair,
      rk: sharedKey,
    );
  }

  /// Encrypt a payload.
  /// Ratchets the sending chain forward and returns the serialized combined envelope.
  Future<Uint8List> encrypt(Uint8List plaintext) async {
    if (ckSend == null) {
      throw StateError('Cannot encrypt: sending chain key is null');
    }

    final derived = await _ratchetSymmetric(
      ckSend!,
      'sending-message-key',
    );
    ckSend = derived.nextChainKey;

    final mkBytes = await derived.messageKey.extractBytes();
    final nonce = aesGcm.newNonce();

    final box = await aesGcm.encrypt(
      plaintext,
      secretKey: crypto.SecretKey(mkBytes),
      nonce: nonce,
    );

    if (dHk == null) {
      // Legacy symmetric-only mode: return raw ciphertext bytes
      return Uint8List.fromList(box.concatenation());
    }

    // Full asymmetric mode: prepend serialized header
    final localPublic = await dHk!.extractPublicKey();
    final header = DoubleRatchetHeader(
      dhPublicBytes: Uint8List.fromList(localPublic.bytes),
      pn: pn,
      n: ns,
    );
    ns++;

    final headerJson = jsonEncode(header.toJson());
    final headerBytes = utf8.encode(headerJson);
    final builder = BytesBuilder();
    final lengthData = ByteData(4)..setUint32(0, headerBytes.length, Endian.big);

    builder.add(lengthData.buffer.asUint8List());
    builder.add(headerBytes);
    builder.add(box.concatenation());

    return Uint8List.fromList(builder.toBytes());
  }

  /// Decrypt a ciphertext combined envelope.
  /// Decryption happens in temporary memory first to preserve state on auth failure.
  Future<Uint8List> decrypt(Uint8List combinedBytes) async {
    // If local keys are null, fall back to simple symmetric-only decryption (old tests compatibility)
    if (dHk == null) {
      final derived = await _ratchetSymmetric(
        receivingChainKey!,
        'sending-message-key',
      );
      final candidateNextChainKey = derived.nextChainKey;
      final mkBytes = await derived.messageKey.extractBytes();

      final box = crypto.SecretBox.fromConcatenation(
        combinedBytes,
        nonceLength: 12,
        macLength: 16,
      );

      final plaintext = await aesGcm.decrypt(
        box,
        secretKey: crypto.SecretKey(mkBytes),
      );

      receivingChainKey = candidateNextChainKey;
      return Uint8List.fromList(plaintext);
    }

    // Parse Envelope
    final byteData = ByteData.sublistView(combinedBytes, 0, 4);
    final headerLength = byteData.getUint32(0, Endian.big);
    final headerBytes = combinedBytes.sublist(4, 4 + headerLength);
    final ciphertext = combinedBytes.sublist(4 + headerLength);

    final headerJson = utf8.decode(headerBytes);
    final header = DoubleRatchetHeader.fromJson(jsonDecode(headerJson) as Map<String, dynamic>);

    final peerPublicKey = crypto.SimplePublicKey(
      header.dhPublicBytes,
      type: crypto.KeyPairType.x25519,
    );

    // Step 2: Try skipped keys first
    final skippedKey = _skippedKey(header.dhPublicBytes, header.n);
    if (skippedMessageKeys.containsKey(skippedKey)) {
      final mk = skippedMessageKeys[skippedKey]!;
      final box = crypto.SecretBox.fromConcatenation(
        ciphertext,
        nonceLength: 12,
        macLength: 16,
      );
      final plaintext = await aesGcm.decrypt(box, secretKey: mk);
      skippedMessageKeys.remove(skippedKey);
      return Uint8List.fromList(plaintext);
    }

    // Step 3: DH Ratchet check
    final isNewDh = dHp == null || !_compareKeys(dHp!, peerPublicKey);

    // Clone state variables for defect-1 safety
    var candidateDhk = dHk;
    var candidateDhp = dHp;
    var candidateRk = rk;
    var candidateCkSend = ckSend;
    var candidateCkRecv = ckRecv;
    var candidateNs = ns;
    var candidateNr = nr;
    var candidatePn = pn;
    final candidateSkippedKeys = Map<String, crypto.SecretKey>.from(skippedMessageKeys);

    if (isNewDh) {
      final ratchetResult = await _dhRatchetStep(
        peerPublicKey: peerPublicKey,
        currentDhk: candidateDhk!,
        currentRk: candidateRk,
        currentPn: candidatePn,
        currentNs: candidateNs,
        currentNr: candidateNr,
        currentCkRecv: candidateCkRecv,
        skippedKeys: candidateSkippedKeys,
        headerPn: header.pn,
      );
      candidateDhk = ratchetResult.newDhk;
      candidateDhp = ratchetResult.newDhp;
      candidateRk = ratchetResult.newRk;
      candidateCkSend = ratchetResult.newCkSend;
      candidateCkRecv = ratchetResult.newCkRecv;
      candidateNs = ratchetResult.newNs;
      candidateNr = ratchetResult.newNr;
      candidatePn = ratchetResult.newPn;
    }

    // Skip keys in current receiving chain up to header sequence number
    final skipResult = await _skipMessageKeysStep(
      until: header.n,
      currentNr: candidateNr,
      currentCkRecv: candidateCkRecv,
      currentDhp: candidateDhp ?? peerPublicKey,
      skippedKeys: candidateSkippedKeys,
    );
    candidateCkRecv = skipResult.ckRecv;
    candidateNr = skipResult.nr;

    // Derive message key
    final derived = await _ratchetSymmetric(candidateCkRecv!, 'sending-message-key');
    final candidateNextCkRecv = derived.nextChainKey;
    final mk = derived.messageKey;

    final box = crypto.SecretBox.fromConcatenation(
      ciphertext,
      nonceLength: 12,
      macLength: 16,
    );

    // Decrypt using derived message key
    final plaintext = await aesGcm.decrypt(box, secretKey: mk);

    // Decryption succeeded! Commit candidate state modifications.
    dHk = candidateDhk;
    dHp = candidateDhp ?? peerPublicKey;
    rk = candidateRk;
    ckSend = candidateCkSend;
    ckRecv = candidateNextCkRecv;
    ns = candidateNs;
    nr = candidateNr + 1;
    pn = candidatePn;
    skippedMessageKeys.clear();
    skippedMessageKeys.addAll(candidateSkippedKeys);

    return Uint8List.fromList(plaintext);
  }

  // Symmetric ratchet derived from current codebase
  Future<_RatchetStepResult> _ratchetSymmetric(
    crypto.SecretKey chainKey,
    String info,
  ) async {
    final mk = await hkdf.deriveKey(
      secretKey: chainKey,
      nonce: List.filled(32, 0),
      info: '$info-mk'.codeUnits,
    );
    final nextCk = await hkdf.deriveKey(
      secretKey: chainKey,
      nonce: List.filled(32, 0),
      info: '$info-next-ck'.codeUnits,
    );
    return _RatchetStepResult(messageKey: mk, nextChainKey: nextCk);
  }

  // Compatibility getters/setters for old tests
  crypto.SecretKey? get rootKey => rk;
  crypto.SecretKey get sendingChainKey => ckSend!;
  set sendingChainKey(crypto.SecretKey val) => ckSend = val;
  crypto.SecretKey get receivingChainKey => ckRecv!;
  set receivingChainKey(crypto.SecretKey val) => ckRecv = val;

  static bool _compareKeys(crypto.SimplePublicKey k1, crypto.SimplePublicKey k2) {
    if (k1.bytes.length != k2.bytes.length) return false;
    for (var i = 0; i < k1.bytes.length; i++) {
      if (k1.bytes[i] != k2.bytes[i]) return false;
    }
    return true;
  }

  static String _skippedKey(Uint8List dhPublicBytes, int n) {
    return '${base64Encode(dhPublicBytes)}:$n';
  }

  static Future<({crypto.SecretKey? ckRecv, int nr})> _skipMessageKeysStep({
    required int until,
    required int currentNr,
    required crypto.SecretKey? currentCkRecv,
    required crypto.SimplePublicKey currentDhp,
    required Map<String, crypto.SecretKey> skippedKeys,
  }) async {
    var nr = currentNr;
    var ckRecv = currentCkRecv;

    if (ckRecv == null) return (ckRecv: null, nr: nr);

    if (nr + 1000 < until) {
      throw StateError('Too many skipped messages: gap is too large');
    }

    final hkdfHelper = crypto.Hkdf(
      hmac: crypto.Hmac(crypto.Sha256()),
      outputLength: 32,
    );

    while (nr < until) {
      // Ratchet receiving chain forward to skip keys
      final mk = await hkdfHelper.deriveKey(
        secretKey: ckRecv!,
        nonce: List.filled(32, 0),
        info: 'sending-message-key-mk'.codeUnits,
      );
      final nextCk = await hkdfHelper.deriveKey(
        secretKey: ckRecv,
        nonce: List.filled(32, 0),
        info: 'sending-message-key-next-ck'.codeUnits,
      );

      final skippedKey = _skippedKey(Uint8List.fromList(currentDhp.bytes), nr);
      skippedKeys[skippedKey] = mk;
      ckRecv = nextCk;
      nr++;

      // Maintain max skipped keys limit (1000)
      if (skippedKeys.length > 1000) {
        final oldestKey = skippedKeys.keys.first;
        skippedKeys.remove(oldestKey);
      }
    }
    return (ckRecv: ckRecv, nr: nr);
  }

  static Future<_DhRatchetResult> _dhRatchetStep({
    required crypto.SimplePublicKey peerPublicKey,
    required crypto.SimpleKeyPair currentDhk,
    required crypto.SecretKey currentRk,
    required int currentPn,
    required int currentNs,
    required int currentNr,
    required crypto.SecretKey? currentCkRecv,
    required Map<String, crypto.SecretKey> skippedKeys,
    required int headerPn,
  }) async {
    final x25519 = crypto.X25519();
    final nextPn = currentNs;
    final nextNs = 0;
    final nextNr = 0;
    final nextDhp = peerPublicKey;

    // Skip any remaining keys in current receiving chain before updating keys
    final skipRes = await _skipMessageKeysStep(
      until: headerPn,
      currentNr: currentNr,
      currentCkRecv: currentCkRecv,
      currentDhp: nextDhp,
      skippedKeys: skippedKeys,
    );

    // Root derivation 1 (Receiving Chain Key)
    final dh1 = await x25519.sharedSecretKey(
      keyPair: currentDhk,
      remotePublicKey: nextDhp,
    );

    final hkdfRK = crypto.Hkdf(
      hmac: crypto.Hmac(crypto.Sha256()),
      outputLength: 64,
    );
    final derived1 = await hkdfRK.deriveKey(
      secretKey: dh1,
      nonce: await currentRk.extractBytes(),
      info: 'helix-double-ratchet-rk'.codeUnits,
    );
    final derived1Bytes = await derived1.extractBytes();
    final nextRkStage1 = crypto.SecretKey(derived1Bytes.sublist(0, 32));
    final nextCkRecv = crypto.SecretKey(derived1Bytes.sublist(32, 64));

    // Generate new local keypair for the next sending chain
    final nextDhk = await x25519.newKeyPair();

    // Root derivation 2 (Sending Chain Key)
    final dh2 = await x25519.sharedSecretKey(
      keyPair: nextDhk,
      remotePublicKey: nextDhp,
    );
    final derived2 = await hkdfRK.deriveKey(
      secretKey: dh2,
      nonce: await nextRkStage1.extractBytes(),
      info: 'helix-double-ratchet-rk'.codeUnits,
    );
    final derived2Bytes = await derived2.extractBytes();
    final nextRk = crypto.SecretKey(derived2Bytes.sublist(0, 32));
    final nextCkSend = crypto.SecretKey(derived2Bytes.sublist(32, 64));

    return _DhRatchetResult(
      newDhk: nextDhk,
      newDhp: nextDhp,
      newRk: nextRk,
      newCkSend: nextCkSend,
      newCkRecv: nextCkRecv,
      newNs: nextNs,
      newNr: nextNr,
      newPn: nextPn,
    );
  }
}

class _RatchetStepResult {
  const _RatchetStepResult({
    required this.messageKey,
    required this.nextChainKey,
  });
  final crypto.SecretKey messageKey;
  final crypto.SecretKey nextChainKey;
}

class _DhRatchetResult {
  const _DhRatchetResult({
    required this.newDhk,
    required this.newDhp,
    required this.newRk,
    required this.newCkSend,
    required this.newCkRecv,
    required this.newNs,
    required this.newNr,
    required this.newPn,
  });
  final crypto.SimpleKeyPair newDhk;
  final crypto.SimplePublicKey newDhp;
  final crypto.SecretKey newRk;
  final crypto.SecretKey newCkSend;
  final crypto.SecretKey newCkRecv;
  final int newNs;
  final int newNr;
  final int newPn;
}
