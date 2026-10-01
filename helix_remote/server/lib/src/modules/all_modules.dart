import 'package:helix_remote_server/src/modules/ops/module.dart';
import 'package:helix_remote_server/src/server.dart';

/// The production module list, in construction order (a module may receive
/// the facades of modules listed before it). Grows phase by phase.
List<ModuleFactory> allModules() => [OpsModule.new];
