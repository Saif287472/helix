import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart' as crypto;

class RemoteTransferOffer {
  const RemoteTransferOffer({
    required this.transferId,
    required this.sourceDeviceId,
    required this.nonce,
    required this.publicKey,
  });

  final String transferId;
  final String sourceDeviceId;
  final String nonce;
  final String publicKey;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'type': 'helix.remote.transfer.offer',
    'transfer_id': transferId,
    'source_device_id': sourceDeviceId,
    'nonce': nonce,
    'public_key': publicKey,
  };

  factory RemoteTransferOffer.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 || json['type'] != 'helix.remote.transfer.offer') {
      throw const FormatException('Unsupported transfer offer');
    }
    return RemoteTransferOffer(
      transferId: json['transfer_id'] as String,
      sourceDeviceId: json['source_device_id'] as String,
      nonce: json['nonce'] as String,
      publicKey: json['public_key'] as String,
    );
  }

  String toQrPayload() => base64Url.encode(utf8.encode(jsonEncode(toJson())));
}

class RemoteTransferAnswer {
  const RemoteTransferAnswer({
    required this.transferId,
    required this.destinationDeviceId,
    required this.publicKey,
    required this.confirmationCode,
  });

  final String transferId;
  final String destinationDeviceId;
  final String publicKey;
  final String confirmationCode;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'type': 'helix.remote.transfer.answer',
    'transfer_id': transferId,
    'destination_device_id': destinationDeviceId,
    'public_key': publicKey,
    'confirmation_code': confirmationCode,
  };

  factory RemoteTransferAnswer.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 ||
        json['type'] != 'helix.remote.transfer.answer') {
      throw const FormatException('Unsupported transfer answer');
    }
    return RemoteTransferAnswer(
      transferId: json['transfer_id'] as String,
      destinationDeviceId: json['destination_device_id'] as String,
      publicKey: json['public_key'] as String,
      confirmationCode: json['confirmation_code'] as String,
    );
  }
}

class RemoteTransferOfferState {
  const RemoteTransferOfferState({required this.offer, required this.keyPair});

  final RemoteTransferOffer offer;
  final crypto.SimpleKeyPair keyPair;
}

class RemoteTransferAnswerState {
  const RemoteTransferAnswerState({required this.answer, required this.key});

  final RemoteTransferAnswer answer;
  final crypto.SecretKey key;
}

class RemoteTransferHandshake {
  RemoteTransferHandshake({crypto.X25519? x25519})
    : _x25519 = x25519 ?? crypto.X25519();

  final crypto.X25519 _x25519;

  Future<RemoteTransferOfferState> createOffer({
    required String sourceDeviceId,
  }) async {
    final keyPair = await _x25519.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final offer = RemoteTransferOffer(
      transferId: _randomToken('transfer'),
      sourceDeviceId: sourceDeviceId,
      nonce: _randomToken('nonce'),
      publicKey: _b64(publicKey.bytes),
    );
    return RemoteTransferOfferState(offer: offer, keyPair: keyPair);
  }

  Future<RemoteTransferAnswerState> acceptOffer({
    required RemoteTransferOffer offer,
    required String destinationDeviceId,
  }) async {
    final keyPair = await _x25519.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final shared = await _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: crypto.SimplePublicKey(
        base64Url.decode(base64Url.normalize(offer.publicKey)),
        type: crypto.KeyPairType.x25519,
      ),
    );
    final confirmationCode = await _confirmationCode(shared, offer.transferId);
    return RemoteTransferAnswerState(
      answer: RemoteTransferAnswer(
        transferId: offer.transferId,
        destinationDeviceId: destinationDeviceId,
        publicKey: _b64(publicKey.bytes),
        confirmationCode: confirmationCode,
      ),
      key: shared,
    );
  }

  Future<crypto.SecretKey> completeOffer({
    required RemoteTransferOfferState state,
    required RemoteTransferAnswer answer,
  }) async {
    if (answer.transferId != state.offer.transferId) {
      throw const FormatException('Transfer answer does not match offer');
    }
    final shared = await _x25519.sharedSecretKey(
      keyPair: state.keyPair,
      remotePublicKey: crypto.SimplePublicKey(
        base64Url.decode(base64Url.normalize(answer.publicKey)),
        type: crypto.KeyPairType.x25519,
      ),
    );
    final expected = await _confirmationCode(shared, state.offer.transferId);
    if (answer.confirmationCode != expected) {
      throw const FormatException('Transfer confirmation mismatch');
    }
    return shared;
  }

  Future<String> _confirmationCode(
    crypto.SecretKey key,
    String transferId,
  ) async {
    final bytes = await key.extractBytes();
    final mac = await crypto.Hmac(
      crypto.Sha256(),
    ).calculateMac(utf8.encode(transferId), secretKey: crypto.SecretKey(bytes));
    final value = mac.bytes
        .take(4)
        .fold<int>(0, (acc, byte) => (acc << 8) | byte);
    return (value % 1000000).toString().padLeft(6, '0');
  }

  String _randomToken(String prefix) {
    final random = Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    return '${prefix}_${_b64(bytes)}';
  }

  String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
}
