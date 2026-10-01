/// Helix Remote v2 wire contract (ADR-028; docs/protocol/v2/).
///
/// Pure Dart, no Flutter. Shared by the v2 server, the client engine, the
/// admin console and the CLI, so the two ends of every message are compiled
/// from the same definitions.
library;

export 'src/content/bodies.dart';
export 'src/content/content_message.dart';
export 'src/content/media_pointer.dart';
export 'src/envelope.dart';
export 'src/errors.dart';
export 'src/headers.dart';
export 'src/ids.dart';
export 'src/json.dart';
export 'src/legal.dart';
export 'src/modules/admin.dart';
export 'src/modules/backup.dart';
export 'src/modules/calls.dart';
export 'src/modules/groups.dart';
export 'src/modules/identity.dart';
export 'src/modules/keys.dart';
export 'src/modules/media.dart';
export 'src/modules/messaging.dart';
export 'src/modules/ops.dart';
export 'src/modules/people.dart';
export 'src/paging.dart';
export 'src/realtime.dart';
export 'src/routes.dart';
export 'src/sealed.dart';
