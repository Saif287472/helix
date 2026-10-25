import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_crypto/src/v2/errors.dart';
import 'package:helix_remote_crypto/src/v2/primitives.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Local state serialisation. Crypto state (sessions, sender keys, prekeys)
/// is plain JSON with base64url bytes, so `helix_remote_db` can store it as
/// an opaque blob inside SQLCipher. Each record carries a `v` field; a
/// record with an unknown version fails to load instead of being misread.
///
/// A failure here is [CorruptStateException]: the bytes are this device's own
/// record, so the engine drops and rebuilds it (AUD-9-1). Peer-supplied bytes
/// go through [readWire] instead, where a failure is
/// [MalformedCryptoInputException].

Uint8List encodeStateJson(JsonMap json) => utf8.encode(jsonEncode(json));

JsonReader decodeStateJson(List<int> bytes, {required String what}) {
  try {
    return JsonReader.decode(utf8.decode(bytes));
  } on FormatException {
    throw CorruptStateException('$what is not valid state JSON');
  }
}

/// Runs [decode] over local state, turning format errors into
/// [CorruptStateException].
T readState<T>(String what, T Function() decode) {
  try {
    return decode();
  } on ProtocolFormatException catch (e) {
    throw CorruptStateException('$what: ${e.message}');
  } on ArgumentError catch (e) {
    throw CorruptStateException('$what: ${e.message}');
  }
}

/// [readState] for untrusted bytes (a provisioning message, a backup envelope
/// fetched from the server): the same failures mean malformed input, not a
/// record this device owns.
T readWire<T>(String what, T Function() decode) {
  try {
    return decode();
  } on CorruptStateException catch (e) {
    throw MalformedCryptoInputException(e.message);
  } on ProtocolFormatException catch (e) {
    throw MalformedCryptoInputException('$what: ${e.message}');
  } on ArgumentError catch (e) {
    throw MalformedCryptoInputException('$what: ${e.message}');
  }
}

void requireVersion(JsonReader json, int version, String what) {
  final v = json.integer('v');
  if (v != version) {
    throw CorruptStateException('unsupported $what version $v');
  }
}

/// A fixed-width key read from local state. State the crypto layer wrote has
/// 32-byte keys; any other length is a damaged record, not a peer's choice
/// (AUD-9-1).
Uint8List stateKey(JsonReader json, String field, {required String what}) =>
    checkedStateKey(json.bytes(field), what);

/// The optional form of [stateKey].
Uint8List? optStateKey(JsonReader json, String field, {required String what}) {
  final bytes = json.optBytes(field);
  return bytes == null ? null : checkedStateKey(bytes, what);
}

/// [stateKey] for bytes already decoded (a list of keys, a key pair).
Uint8List checkedStateKey(Uint8List bytes, String what) {
  if (bytes.length != 32) {
    throw CorruptStateException('$what must be 32 bytes');
  }
  return bytes;
}

/// A counter read from local state: `u32`, as the wire and the crypto rules
/// define them. A negative or oversized value would otherwise reach `u32()`
/// or a loop bound and fail far from the damaged record.
int stateCounter(JsonReader json, String field, {required String what}) {
  final value = json.integer(field);
  if (!isU32(value)) {
    throw CorruptStateException('$what is out of range');
  }
  return value;
}
