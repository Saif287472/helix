import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

/// Encodes [value], sends it through real JSON text, decodes it, and checks
/// the re-encoded form is identical. Returns the decoded value.
T expectRoundTrip<T>(
  T value,
  JsonMap Function(T value) encode,
  T Function(JsonReader json) decode,
) {
  final first = encode(value);
  final text = jsonEncode(first);
  final decoded = decode(JsonReader.decode(text));
  expect(jsonEncode(encode(decoded)), text, reason: 'round trip changed $T');
  return decoded;
}

Uint8List bytes(int length, [int seed = 1]) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) (seed + i * 7) % 256]);

final DateTime t0 = DateTime.utc(2026, 10, 1, 12);

const accountA = '0192a4f0-0000-7000-8000-00000000000a';
const accountB = '0192a4f0-0000-7000-8000-00000000000b';
const deviceA1 = '0192a4f0-0000-7000-8000-0000000000a1';
const deviceB1 = '0192a4f0-0000-7000-8000-0000000000b1';
const groupG = '0192a4f0-0000-7000-8000-00000000000c';
const messageM = '0192a4f0-0000-7000-8000-00000000000d';
