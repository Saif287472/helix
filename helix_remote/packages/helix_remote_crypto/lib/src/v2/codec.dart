import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_crypto/src/v2/errors.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Local state serialisation. Crypto state (sessions, sender keys, prekeys)
/// is plain JSON with base64url bytes, so `helix_remote_db` can store it as
/// an opaque blob inside SQLCipher. Each record carries a `v` field; a
/// record with an unknown version fails to load instead of being misread.

Uint8List encodeStateJson(JsonMap json) => utf8.encode(jsonEncode(json));

JsonReader decodeStateJson(List<int> bytes, {required String what}) {
  try {
    return JsonReader.decode(utf8.decode(bytes));
  } on FormatException {
    throw MalformedCryptoInputException('$what is not valid state JSON');
  }
}

/// Runs [decode], turning protocol format errors into crypto ones.
T readState<T>(String what, T Function() decode) {
  try {
    return decode();
  } on ProtocolFormatException catch (e) {
    throw MalformedCryptoInputException('$what: ${e.message}');
  } on ArgumentError catch (e) {
    throw MalformedCryptoInputException('$what: ${e.message}');
  }
}

void requireVersion(JsonReader json, int version, String what) {
  final v = json.integer('v');
  if (v != version) {
    throw MalformedCryptoInputException('unsupported $what version $v');
  }
}
