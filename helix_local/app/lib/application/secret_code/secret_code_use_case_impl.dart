import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/models.dart';

const _kTypeChallenge = 0x10;
const _kTypeResponse = 0x11;

class _RateLimiter {
  static const _maxPerSecond = 3;
  final _timestamps = <DateTime>[];

  bool tryConsume() {
    final now = DateTime.now();
    _timestamps.removeWhere(
      (t) => now.difference(t) >= const Duration(seconds: 1),
    );
    if (_timestamps.length >= _maxPerSecond) return false;
    _timestamps.add(now);
    return true;
  }
}

class SecretCodeUseCaseImpl implements SecretCodeUseCase {
  final _rateLimiter = _RateLimiter();
  final _rng = Random.secure();

  static final Uint8List _lookupSalt = Uint8List.fromList(
    utf8.encode('HelixCodeV1!'),
  );

  SecretCodeUseCaseImpl();

  @override
  bool isChallengePacket(Uint8List packet) =>
      packet.isNotEmpty && packet[0] == _kTypeChallenge;

  @override
  Future<String> deriveVerifier(String code) async {
    final lookupKey = await _deriveLookupKey(code);
    return 'v2:${_hex(lookupKey)}';
  }

  @override
  Future<void> broadcastSearch(
    String enteredCode,
    RawDatagramSocket socket,
    List<String> broadcastAddresses,
  ) async {
    final challenge = _randomBytes(kChallengeBytes);
    final salt = _randomBytes(kSaltBytes);

    final lookupKey = await _deriveLookupKey(enteredCode);
    final hashBytes = await _argon2id(_hex(lookupKey), salt);
    final proof = Uint8List(kChallengeBytes);
    for (var i = 0; i < kChallengeBytes; i++) {
      proof[i] = hashBytes[i] ^ challenge[i];
    }

    final packet = _buildChallengePacket(challenge, salt, proof);
    if (packet.length > kUdpCodeLookupMaxSize) return;

    for (final addr in broadcastAddresses) {
      try {
        socket.send(packet, InternetAddress(addr), kUdpDiscoveryPort);
      } catch (_) {
        // Skip unreachable broadcast addresses silently
      }
    }
  }

  @override
  Future<bool> handleChallenge(
    Uint8List packet,
    String storedVerifier,
    RawDatagramSocket replySocket,
    InternetAddress requesterAddr,
    int requesterPort,
    String sessionId,
    String displayName,
    String deviceSuffix,
    int tcpPort,
  ) async {
    if (!_rateLimiter.tryConsume()) return false;

    final parsed = _parseChallengePacket(packet);
    if (parsed == null) return false;

    final challenge = parsed.$1;
    final salt = parsed.$2;
    final proof = parsed.$3;

    // expected = proof XOR challenge = Argon2id(code, salt)
    final expectedHash = Uint8List(kChallengeBytes);
    for (var i = 0; i < kChallengeBytes; i++) {
      expectedHash[i] = proof[i] ^ challenge[i];
    }

    final storedHashHex = _lookupKeyHexFromVerifier(storedVerifier);
    if (storedHashHex == null) return false;

    final derivedHash = await _argon2id(storedHashHex, salt);

    int diff = 0;
    for (var i = 0; i < kChallengeBytes; i++) {
      diff |= derivedHash[i] ^ expectedHash[i];
    }
    if (diff != 0) return false;

    final response = _buildResponsePacket(
      challenge: challenge,
      sessionId: sessionId,
      displayName: displayName,
      deviceSuffix: deviceSuffix,
      tcpPort: tcpPort,
    );
    if (response.length > kUdpCodeLookupMaxSize) return false;

    try {
      replySocket.send(response, requesterAddr, requesterPort);
    } catch (_) {
      return false;
    }
    return true;
  }

  @override
  Future<Peer?> waitForResponse(
    RawDatagramSocket socket,
    Duration timeout,
  ) async {
    final peers = await waitForResponses(socket, timeout);
    return peers.isEmpty ? null : peers.first;
  }

  @override
  Future<List<Peer>> waitForResponses(
    RawDatagramSocket socket,
    Duration timeout,
  ) async {
    final completer = Completer<Peer?>();
    final results = <String, Peer>{};

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(null);
    });

    StreamSubscription<RawSocketEvent>? sub;
    sub = socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        try {
          final peer = _parseResponsePacket(
            datagram.data,
            datagram.address.address,
          );
          if (peer != null) {
            results[peer.sessionId] = peer;
          }
        } catch (_) {}
      },
      onError: (_) {},
      cancelOnError: false,
    );

    await completer.future;
    timer.cancel();
    await sub.cancel();
    return results.values.toList(growable: false);
  }

  @override
  Future<List<Peer>> search(
    String enteredCode, {
    Duration? timeout,
    List<String>? broadcastAddresses,
  }) async {
    final t = timeout ?? kCodeSearchTimeout;
    final addrs = broadcastAddresses ?? const ['255.255.255.255'];
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.readEventsEnabled = true;
      await broadcastSearch(enteredCode, socket, addrs);
      return await waitForResponses(socket, t);
    } finally {
      socket?.close();
    }
  }

  // ── Private packet builders / parsers ──────────────────────────────────────

  Uint8List _buildChallengePacket(
    Uint8List challenge,
    Uint8List salt,
    Uint8List proof,
  ) {
    final buf = Uint8List(1 + kChallengeBytes + kSaltBytes + kChallengeBytes);
    var offset = 0;
    buf[offset++] = _kTypeChallenge;
    buf.setRange(offset, offset + kChallengeBytes, challenge);
    offset += kChallengeBytes;
    buf.setRange(offset, offset + kSaltBytes, salt);
    offset += kSaltBytes;
    buf.setRange(offset, offset + kChallengeBytes, proof);
    return buf;
  }

  (Uint8List, Uint8List, Uint8List)? _parseChallengePacket(Uint8List data) {
    final minLen = 1 + kChallengeBytes + kSaltBytes + kChallengeBytes;
    if (data.length < minLen) return null;
    if (data[0] != _kTypeChallenge) return null;
    var offset = 1;
    final challenge = Uint8List.fromList(
      data.sublist(offset, offset + kChallengeBytes),
    );
    offset += kChallengeBytes;
    final salt = Uint8List.fromList(data.sublist(offset, offset + kSaltBytes));
    offset += kSaltBytes;
    final proof = Uint8List.fromList(
      data.sublist(offset, offset + kChallengeBytes),
    );
    return (challenge, salt, proof);
  }

  Uint8List _buildResponsePacket({
    required Uint8List challenge,
    required String sessionId,
    required String displayName,
    required String deviceSuffix,
    required int tcpPort,
  }) {
    final sidBytes = utf8.encode(sessionId);
    final nameBytes = utf8.encode(displayName);
    final sfxBytes = utf8.encode(deviceSuffix);

    final totalLen =
        1 +
        kChallengeBytes +
        2 +
        1 +
        sidBytes.length +
        1 +
        nameBytes.length +
        1 +
        sfxBytes.length;

    final buf = Uint8List(totalLen);
    var offset = 0;

    buf[offset++] = _kTypeResponse;
    buf.setRange(offset, offset + kChallengeBytes, challenge);
    offset += kChallengeBytes;
    buf[offset++] = (tcpPort >> 8) & 0xFF;
    buf[offset++] = tcpPort & 0xFF;

    buf[offset++] = sidBytes.length & 0xFF;
    buf.setRange(offset, offset + sidBytes.length, sidBytes);
    offset += sidBytes.length;

    buf[offset++] = nameBytes.length & 0xFF;
    buf.setRange(offset, offset + nameBytes.length, nameBytes);
    offset += nameBytes.length;

    buf[offset++] = sfxBytes.length & 0xFF;
    buf.setRange(offset, offset + sfxBytes.length, sfxBytes);

    return buf;
  }

  Peer? _parseResponsePacket(Uint8List data, String senderIp) {
    final minLen = 1 + kChallengeBytes + 2 + 3;
    if (data.length < minLen) return null;
    if (data[0] != _kTypeResponse) return null;

    var offset = 1 + kChallengeBytes;
    final port = (data[offset] << 8) | data[offset + 1];
    offset += 2;

    if (offset >= data.length) return null;
    final sidLen = data[offset++];
    if (offset + sidLen > data.length) return null;
    final sessionId = utf8.decode(data.sublist(offset, offset + sidLen));
    offset += sidLen;

    if (offset >= data.length) return null;
    final nameLen = data[offset++];
    if (offset + nameLen > data.length) return null;
    final displayName = utf8.decode(data.sublist(offset, offset + nameLen));
    offset += nameLen;

    if (offset >= data.length) return null;
    final sfxLen = data[offset++];
    if (offset + sfxLen > data.length) return null;
    final deviceSuffix = utf8.decode(data.sublist(offset, offset + sfxLen));

    if (sessionId.isEmpty) return null;

    return Peer(
      sessionId: sessionId,
      displayName: displayName,
      deviceSuffix: deviceSuffix,
      host: senderIp,
      port: port,
      source: PeerSource.secretCode,
      seenAt: DateTime.now(),
      protocolMajor: kProtocolMajor,
      protocolMinor: kProtocolMinor,
    );
  }

  // ── Crypto Helpers ─────────────────────────────────────────────────────────

  static Future<Uint8List> _deriveLookupKey(String code) =>
      _argon2id(code, _lookupSalt);

  static String? _lookupKeyHexFromVerifier(String verifier) {
    if (verifier.startsWith('v2:')) {
      final hex = verifier.substring(3);
      return RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex) ? hex.toLowerCase() : null;
    }
    final parts = verifier.split(':');
    if (parts.length == 2) {
      return parts[1].toLowerCase();
    }
    return null;
  }

  static Future<Uint8List> _argon2id(String password, Uint8List salt) async {
    final argon2 = cryptography.Argon2id(
      memory: kArgon2Memory,
      parallelism: kArgon2Parallelism,
      iterations: kArgon2Time,
      hashLength: kArgon2HashLength,
    );
    final key = await argon2.deriveKey(
      secretKey: cryptography.SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Uint8List _randomBytes(int count) =>
      Uint8List.fromList(List<int>.generate(count, (_) => _rng.nextInt(256)));
}
