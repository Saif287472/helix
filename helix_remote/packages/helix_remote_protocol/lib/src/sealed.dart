import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/src/json.dart';

/// Wire forms of encrypted payloads (CRYPTO_V2.md §8). These are the bytes
/// inside `Envelope.payload`; the server stores and forwards them without
/// parsing. Encoding is UTF-8 JSON; a binary codec can replace it later
/// behind [SealedPayload.encode]/[SealedPayload.decode].
sealed class SealedPayload {
  const SealedPayload();

  /// Wire format version of sealed payloads.
  static const version = 2;

  JsonMap toJson();

  Uint8List encode() => utf8.encode(jsonEncode(toJson()));

  static SealedPayload decode(List<int> bytes) {
    final JsonReader json;
    try {
      json = JsonReader.decode(utf8.decode(bytes));
    } on FormatException {
      throw ProtocolFormatException('sealed payload is not UTF-8 JSON');
    }
    final v = json.integer('v');
    if (v != version) {
      throw ProtocolFormatException('unsupported sealed payload version $v');
    }
    return switch (json.string('t')) {
      'prekey' => PrekeyMessage.fromJson(json),
      'ratchet' => RatchetMessage.fromJson(json),
      'sender_key' => SenderKeyMessage.fromJson(json),
      _ => throw ProtocolFormatException('unknown sealed payload type'),
    };
  }
}

/// Double Ratchet header (CRYPTO_V2.md §5).
final class RatchetHeader {
  const RatchetHeader({
    required this.ratchetKey,
    required this.previousCount,
    required this.count,
  });

  /// Sender's current ratchet public key (X25519, 32 bytes).
  final Uint8List ratchetKey;

  /// `pn`: messages in the sender's previous sending chain.
  final int previousCount;

  /// `n`: index of this message in the current sending chain.
  final int count;

  JsonMap toJson() => {
    'dh': encodeBytes(ratchetKey),
    'pn': previousCount,
    'n': count,
  };

  factory RatchetHeader.fromJson(JsonReader json) => RatchetHeader(
    ratchetKey: json.bytes('dh'),
    previousCount: json.intIn('pn', 0, _maxU32),
    count: json.intIn('n', 0, _maxU32),
  );

  /// Bytes authenticated as part of the AEAD associated data.
  Uint8List toAuthenticatedBytes() {
    final label = ascii.encode('helix.v2.hdr');
    final out = BytesBuilder(copy: false)
      ..add(label)
      ..add(ratchetKey)
      ..add(_u32(previousCount))
      ..add(_u32(count));
    return out.toBytes();
  }
}

/// The counters and ids of the sealed layouts are 32-bit on the wire.
const _maxU32 = 4294967295;

Uint8List _u32(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value);

/// First message of a new pairwise session: X3DH parameters plus the first
/// ratchet message.
final class PrekeyMessage extends SealedPayload {
  const PrekeyMessage({
    required this.senderIdentityKey,
    required this.ephemeralKey,
    required this.signedPrekeyId,
    required this.header,
    required this.ciphertext,
    this.oneTimePrekeyId,
  });

  /// Sender device's DIK public key.
  final Uint8List senderIdentityKey;
  final Uint8List ephemeralKey;
  final int signedPrekeyId;
  final int? oneTimePrekeyId;
  final RatchetHeader header;
  final Uint8List ciphertext;

  @override
  JsonMap toJson() => compact({
    'v': SealedPayload.version,
    't': 'prekey',
    'dik': encodeBytes(senderIdentityKey),
    'ek': encodeBytes(ephemeralKey),
    'spk': signedPrekeyId,
    'opk': oneTimePrekeyId,
    'h': header.toJson(),
    'ct': encodeBytes(ciphertext),
  });

  factory PrekeyMessage.fromJson(JsonReader json) => PrekeyMessage(
    senderIdentityKey: json.bytes('dik'),
    ephemeralKey: json.bytes('ek'),
    signedPrekeyId: json.intIn('spk', 0, _maxU32),
    oneTimePrekeyId: json.optIntIn('opk', 0, _maxU32),
    header: RatchetHeader.fromJson(json.object('h')),
    ciphertext: json.bytes('ct'),
  );
}

/// A message in an established pairwise session.
final class RatchetMessage extends SealedPayload {
  const RatchetMessage({required this.header, required this.ciphertext});

  final RatchetHeader header;
  final Uint8List ciphertext;

  @override
  JsonMap toJson() => {
    'v': SealedPayload.version,
    't': 'ratchet',
    'h': header.toJson(),
    'ct': encodeBytes(ciphertext),
  };

  factory RatchetMessage.fromJson(JsonReader json) => RatchetMessage(
    header: RatchetHeader.fromJson(json.object('h')),
    ciphertext: json.bytes('ct'),
  );
}

/// A group message encrypted with the sender's sender key (CRYPTO_V2.md §7).
final class SenderKeyMessage extends SealedPayload {
  const SenderKeyMessage({
    required this.distributionId,
    required this.iteration,
    required this.ciphertext,
    required this.signature,
  });

  final String distributionId;
  final int iteration;
  final Uint8List ciphertext;

  /// Ed25519 signature by the sender key's signing key.
  final Uint8List signature;

  @override
  JsonMap toJson() => {
    'v': SealedPayload.version,
    't': 'sender_key',
    'dist': distributionId,
    'it': iteration,
    'ct': encodeBytes(ciphertext),
    'sig': encodeBytes(signature),
  };

  factory SenderKeyMessage.fromJson(JsonReader json) => SenderKeyMessage(
    distributionId: json.nonEmpty('dist'),
    iteration: json.intIn('it', 0, _maxU32),
    ciphertext: json.bytes('ct'),
    signature: json.bytes('sig'),
  );
}
