import 'package:helix_remote_api/src/v2/clients/admin_client.dart';
import 'package:helix_remote_api/src/v2/clients/backup_client.dart';
import 'package:helix_remote_api/src/v2/clients/calls_client.dart';
import 'package:helix_remote_api/src/v2/clients/compliance_client.dart';
import 'package:helix_remote_api/src/v2/clients/federation_client.dart';
import 'package:helix_remote_api/src/v2/clients/groups_client.dart';
import 'package:helix_remote_api/src/v2/clients/identity_client.dart';
import 'package:helix_remote_api/src/v2/clients/keys_client.dart';
import 'package:helix_remote_api/src/v2/clients/media_client.dart';
import 'package:helix_remote_api/src/v2/clients/messaging_client.dart';
import 'package:helix_remote_api/src/v2/clients/ops_client.dart';
import 'package:helix_remote_api/src/v2/clients/people_client.dart';
import 'package:helix_remote_api/src/v2/realtime/realtime_client.dart';
import 'package:helix_remote_api/src/v2/realtime/socket.dart';
import 'package:helix_remote_api/src/v2/transport/auth.dart';
import 'package:helix_remote_api/src/v2/transport/retry.dart';
import 'package:helix_remote_api/src/v2/transport/transport.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:http/http.dart' as http;

/// Everything a device (app, CLI, background isolate) needs to talk to one
/// v2 server: one client per server module on a shared transport, with the
/// device session in [auth] and a lazily created [realtime] connection.
final class HelixApi {
  HelixApi._(this.transport, this.auth, this._sockets);

  /// [sessions] holds the device session; [reauthenticate] is the engine's
  /// device-key sign-in, tried once when the refresh token is refused.
  factory HelixApi({
    required Uri baseUrl,
    required SessionStore sessions,
    http.Client? httpClient,
    RealtimeSocketFactory sockets = defaultSocketFactory,
    String? clientName,
    RetryPolicy retry = const RetryPolicy(),
    Duration timeout = const Duration(seconds: 30),
    Future<Session?> Function(IdentityClient identity)? reauthenticate,
  }) {
    late final HelixTransport transport;
    final auth = DeviceSessionAuth(
      store: sessions,
      refresher: (token) => IdentityClient(transport).refresh(token),
    );
    transport = HelixTransport(
      baseUrl: baseUrl,
      client: httpClient,
      auth: auth,
      clientName: clientName,
      retry: retry,
      timeout: timeout,
    );
    if (reauthenticate != null) {
      auth.reauthenticate = () => reauthenticate(IdentityClient(transport));
    }
    return HelixApi._(transport, auth, sockets);
  }

  final HelixTransport transport;
  final DeviceSessionAuth auth;
  final RealtimeSocketFactory _sockets;

  late final IdentityClient identity = IdentityClient(transport);
  late final KeysClient keys = KeysClient(transport);
  late final MessagingClient messaging = MessagingClient(transport);
  late final PeopleClient people = PeopleClient(transport);
  late final GroupsClient groups = GroupsClient(transport);
  late final CallsClient calls = CallsClient(transport);
  late final MediaClient media = MediaClient(transport);
  late final BackupClient backup = BackupClient(transport);
  late final OpsClient ops = OpsClient(transport);
  late final ComplianceClient compliance = ComplianceClient(transport);
  late final FederationClient federation = FederationClient(transport);

  RealtimeClient? _realtime;

  /// The device's WebSocket connection (not started until `start`).
  RealtimeClient get realtime => _realtime ??= RealtimeClient(
    baseUrl: transport.baseUrl,
    auth: auth,
    connect: _sockets,
    clientName: transport.clientName,
  );

  Future<void> close() async {
    await _realtime?.dispose();
    await auth.close();
    transport.close();
  }
}

/// The operator console's view of a server: the admin client on an
/// admin-audience transport, plus the public ops and federation routes.
final class HelixAdminApi {
  HelixAdminApi._(this.transport, this.admin);

  factory HelixAdminApi({
    required Uri baseUrl,
    http.Client? httpClient,
    RealtimeSocketFactory sockets = defaultSocketFactory,
    String? clientName,
    AdminSession? session,
    RetryPolicy retry = const RetryPolicy(),
    Duration timeout = const Duration(seconds: 30),
  }) {
    final transport = HelixTransport(
      baseUrl: baseUrl,
      client: httpClient,
      auth: AdminTokenAuth(session: session),
      clientName: clientName,
      retry: retry,
      timeout: timeout,
    );
    return HelixAdminApi._(transport, AdminClient(transport, sockets: sockets));
  }

  final HelixTransport transport;
  final AdminClient admin;

  late final OpsClient ops = OpsClient(transport);
  late final FederationClient federation = FederationClient(transport);

  AdminTokenAuth get auth => admin.auth;

  Future<void> close() async {
    await auth.close();
    transport.close();
  }
}
