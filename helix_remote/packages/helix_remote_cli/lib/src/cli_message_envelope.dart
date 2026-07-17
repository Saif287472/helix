import 'dart:convert';

class CliMessageEnvelope {
  CliMessageEnvelope({
    required this.isInit,
    required this.ciphertext,
    this.ephemeralKey,
    this.oneTimePrekeyId,
  });

  final bool isInit;
  final String ciphertext; // base64-encoded DoubleRatchet ciphertext bytes
  final String? ephemeralKey; // base64url-encoded Ephemeral Public Key (for X3DH init)
  final int? oneTimePrekeyId;

  Map<String, dynamic> toJson() => {
    'is_init': isInit,
    'ciphertext': ciphertext,
    if (ephemeralKey != null) 'ephemeral_key': ephemeralKey,
    if (oneTimePrekeyId != null) 'one_time_prekey_id': oneTimePrekeyId,
  };

  factory CliMessageEnvelope.fromJson(Map<String, dynamic> json) {
    return CliMessageEnvelope(
      isInit: json['is_init'] as bool? ?? false,
      ciphertext: json['ciphertext'] as String? ?? '',
      ephemeralKey: json['ephemeral_key'] as String?,
      oneTimePrekeyId: json['one_time_prekey_id'] as int?,
    );
  }

  String pack() {
    return base64Url.encode(utf8.encode(jsonEncode(toJson()))).replaceAll('=', '');
  }

  static CliMessageEnvelope unpack(String packed) {
    final decodedJson = utf8.decode(base64Url.decode(base64Url.normalize(packed)));
    return CliMessageEnvelope.fromJson(jsonDecode(decodedJson) as Map<String, dynamic>);
  }
}
