import 'dart:typed_data';

import 'package:helix_remote_api/src/v2/transport/transport.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The `compliance` module: data export and self-deletion. Both work while
/// the account is suspended.
final class ComplianceClient {
  const ComplianceClient(this._t);

  final HelixTransport _t;

  /// Everything the server holds about the account (metadata only).
  Future<AccountExport> export() => _t.call(
    Routes.exportData,
    AccountExport.fromJson,
    maxResponseBytes: 32 * 1024 * 1024,
  );

  /// Deletes the account on this server. Not reversible. The server wants
  /// proof that the caller owns the account, not only a session: give the
  /// [currentAuthKey] of an account with a password, a fresh
  /// [verificationToken] for its number, or (for an account with neither)
  /// a [deviceProof]. See `DeleteAccountRequest`.
  Future<void> deleteAccount({
    Uint8List? currentAuthKey,
    String? verificationToken,
    DeviceKeyProof? deviceProof,
  }) => _t.empty(
    Routes.deleteAccount,
    json: DeleteAccountRequest(
      currentAuthKey: currentAuthKey,
      verificationToken: verificationToken,
      deviceProof: deviceProof,
    ).toJson(),
  );
}
