import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Account ids as one server sees them. The home server stores its own
/// accounts bare and others as `uuid@domain`; a client or server on
/// [viewer] sees its own accounts bare, this server's qualified with
/// [home], and third servers' unchanged.
final class Frame {
  const Frame.local(this.home) : viewer = null;

  const Frame.of(String this.home, String this.viewer);

  /// This server's domain (null without federation).
  final String? home;

  /// The domain whose frame this is; null for this server's own clients.
  final String? viewer;

  bool get isLocal => viewer == null;

  /// A stored id as the viewer writes it.
  String view(String stored) {
    final viewer = this.viewer;
    if (viewer == null) return stored;
    final address = AccountAddress.tryParse(stored)!;
    if (address.domain == null) return '${address.id}@$home';
    if (address.domain == viewer) return address.id;
    return address.toString();
  }

  /// The stored form of an id the viewer wrote; null if malformed or if it
  /// names another server while this one does not federate.
  String? stored(String input) {
    final address = AccountAddress.tryParse(input);
    if (address == null) return null;
    final viewer = this.viewer;
    if (viewer == null) {
      final home = this.home;
      if (home == null) return address.isRemote ? null : address.id;
      return address.relativeTo(home).toString();
    }
    if (address.domain == null) return '${address.id}@$viewer';
    if (address.domain == home) return address.id;
    return address.toString();
  }

  /// The domain of a stored id (null for this server's accounts).
  static String? domainOf(String stored) =>
      AccountAddress.tryParse(stored)?.domain;

  static bool isLocalId(String stored) => !stored.contains('@');
}
