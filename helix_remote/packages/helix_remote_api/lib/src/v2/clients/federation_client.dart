import 'package:helix_remote_api/src/v2/transport/transport.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The `federation` module's one public route. Every other federation route
/// is server-to-server (signed by a server key) and has no client.
final class FederationClient {
  const FederationClient(this._t);

  final HelixTransport _t;

  /// The server's federation identity (`/.well-known/helix-server`).
  Future<ServerIdentityDocument> serverIdentity() =>
      _t.call(Routes.serverIdentity, ServerIdentityDocument.fromJson);
}
