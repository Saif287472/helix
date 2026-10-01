/// Helix Remote v2 server.
///
/// Built phase by phase to `docs/architecture/ARCHITECTURE_V2_PLAN.md`. Until
/// the cutover (Phase X) the live server is the v1 `backend/` package.
library;

export 'src/modules/all_modules.dart';
export 'src/platform/config/server_config.dart';
export 'src/platform/observability/log.dart';
export 'src/platform/platform.dart';
export 'src/server.dart';
