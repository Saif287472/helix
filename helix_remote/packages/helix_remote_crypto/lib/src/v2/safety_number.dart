import 'dart:typed_data';

import 'package:helix_remote_crypto/src/v2/identity.dart';
import 'package:helix_remote_crypto/src/v2/primitives.dart';

/// Safety numbers per pair of accounts (CRYPTO_V2.md §10):
///
/// ```
/// h_0     = SHA-512(u16(0) ‖ AIK_pub ‖ account_id(16))
/// h_(i+1) = SHA-512(h_i ‖ AIK_pub)            for i = 0 … 5,199
/// digits  = first 30 bytes of h_5200 -> six 5-byte chunks
///           -> each as u40 mod 100000, zero-padded to 5 digits
/// number  = digits of the lower account id first, then the other (60)
/// ```
///
/// Device additions do not change it; an AIK change does.
final class SafetyNumber {
  SafetyNumber._(this.digits, this._fingerprints);

  static const iterations = 5200;
  static const qrVersion = 1;

  /// Computes the number for two accounts. Both sides get the same digits.
  factory SafetyNumber.compute({
    required String localAccount,
    required List<int> localIdentityKey,
    required String remoteAccount,
    required List<int> remoteIdentityKey,
  }) {
    requireLength(localIdentityKey, 32, 'AIK');
    requireLength(remoteIdentityKey, 32, 'AIK');
    final local = (
      id: accountIdBytes(localAccount),
      address: localAccount,
      key: localIdentityKey,
    );
    final remote = (
      id: accountIdBytes(remoteAccount),
      address: remoteAccount,
      key: remoteIdentityKey,
    );
    var order = compareBytes(local.id, remote.id);
    if (order == 0) order = local.address.compareTo(remote.address);
    final (first, second) = order <= 0 ? (local, remote) : (remote, local);
    final f1 = fingerprint(first.key, first.id);
    final f2 = fingerprint(second.key, second.id);
    return SafetyNumber._(
      '${_digits(f1)}${_digits(f2)}',
      concatBytes([f1, f2]),
    );
  }

  /// 60 digits.
  final String digits;
  final Uint8List _fingerprints;

  /// Twelve groups of five digits, for display.
  List<String> get groups => [
    for (var i = 0; i < 60; i += 5) digits.substring(i, i + 5),
  ];

  /// QR payload: `"HXSN" ‖ u8(1) ‖ fingerprint(lower) ‖ fingerprint(other)`
  /// (30 bytes each). Both devices show the same payload.
  Uint8List get qrPayload =>
      concatBytes([label('HXSN'), u8(qrVersion), _fingerprints]);

  /// Whether a scanned QR payload matches this number (both halves).
  bool matchesQr(List<int> scanned) => bytesEqual(scanned, qrPayload);

  /// The 30-byte fingerprint of one account.
  static Uint8List fingerprint(List<int> identityKey, List<int> accountId) {
    requireLength(accountId, 16, 'account id');
    var h = sha512(concatBytes([u16(0), identityKey, accountId]));
    for (var i = 0; i < iterations; i++) {
      h = sha512(concatBytes([h, identityKey]));
    }
    return Uint8List.fromList(h.sublist(0, 30));
  }

  static String _digits(Uint8List fingerprint) {
    final out = StringBuffer();
    for (var chunk = 0; chunk < 6; chunk++) {
      var value = 0;
      for (var i = 0; i < 5; i++) {
        value = value * 256 + fingerprint[chunk * 5 + i];
      }
      out.write((value % 100000).toString().padLeft(5, '0'));
    }
    return out.toString();
  }

  @override
  String toString() => 'SafetyNumber(${groups.join(' ')})';
}
