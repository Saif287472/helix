import 'package:helix_remote_api/src/v2/transport/transport.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The `compliance` module: data export and self-deletion. Both work while
/// the account is suspended.
final class ComplianceClient {
  const ComplianceClient(this._t);

  final HelixTransport _t;

  /// Everything the server holds about the account (metadata only).
  Future<AccountExport> export() =>
      _t.call(Routes.exportData, AccountExport.fromJson);

  /// Deletes the account on this server. Not reversible.
  Future<void> deleteAccount() => _t.empty(
    Routes.deleteAccount,
    json: const DeleteAccountRequest().toJson(),
  );
}
