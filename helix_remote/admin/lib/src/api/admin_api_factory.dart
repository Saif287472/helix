import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The console's version, sent as `x-helix-client`.
const adminClientName = 'admin/2.0.0';

/// Builds the one API facade the console talks through. Every screen gets
/// its `HelixAdminApi` from the session (`AdminSessionController.api`), and
/// the session builds it only here, so tests swap the transport in one
/// place.
typedef AdminApiFactory =
    HelixAdminApi Function(Uri baseUrl, {AdminSession? session});

/// The real client. The live log stream uses the `dart:io` socket where
/// there is one. A browser cannot set the `Authorization` header on a
/// WebSocket, so on the web the stream fails with an `UnsupportedError`
/// and the log viewer polls `GET /v1/admin/logs` instead.
HelixAdminApi createAdminApi(Uri baseUrl, {AdminSession? session}) =>
    HelixAdminApi(
      baseUrl: baseUrl,
      session: session,
      clientName: adminClientName,
    );
