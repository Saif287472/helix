/// Helix Remote v2 clients (ARCHITECTURE_V2_PLAN.md §6.1, ADR-027): typed
/// REST clients, one per server module, and the realtime WebSocket client,
/// built from the `helix_remote_protocol` route catalog and DTOs.
///
/// Pure Dart. The v1 API (`package:helix_remote_api/api.dart`) is separate
/// and is retired when the app moves to v2 (Phase A1).
library;

export 'package:helix_remote_api/src/v2/clients/admin_client.dart';
export 'package:helix_remote_api/src/v2/clients/backup_client.dart';
export 'package:helix_remote_api/src/v2/clients/calls_client.dart';
export 'package:helix_remote_api/src/v2/clients/compliance_client.dart';
export 'package:helix_remote_api/src/v2/clients/federation_client.dart';
export 'package:helix_remote_api/src/v2/clients/groups_client.dart';
export 'package:helix_remote_api/src/v2/clients/identity_client.dart';
export 'package:helix_remote_api/src/v2/clients/keys_client.dart';
export 'package:helix_remote_api/src/v2/clients/media_client.dart';
export 'package:helix_remote_api/src/v2/clients/messaging_client.dart';
export 'package:helix_remote_api/src/v2/clients/ops_client.dart';
export 'package:helix_remote_api/src/v2/clients/people_client.dart';
export 'package:helix_remote_api/src/v2/helix_api.dart';
export 'package:helix_remote_api/src/v2/realtime/realtime_client.dart';
export 'package:helix_remote_api/src/v2/realtime/socket.dart';
export 'package:helix_remote_api/src/v2/transport/auth.dart';
export 'package:helix_remote_api/src/v2/transport/errors.dart';
export 'package:helix_remote_api/src/v2/transport/retry.dart';
export 'package:helix_remote_api/src/v2/transport/transport.dart';
