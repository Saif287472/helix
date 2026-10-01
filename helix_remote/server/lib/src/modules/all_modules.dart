import 'package:helix_remote_server/src/modules/identity/module.dart';
import 'package:helix_remote_server/src/modules/identity/sms.dart';
import 'package:helix_remote_server/src/modules/keys/module.dart';
import 'package:helix_remote_server/src/modules/ops/module.dart';
import 'package:helix_remote_server/src/server.dart';

/// The production module list, in construction order: a module may receive
/// the facades of modules listed before it. Grows phase by phase.
///
/// [sms] replaces the configured SMS provider (tests).
List<ModuleFactory> allModules({SmsProvider? sms}) {
  late IdentityModule identity;
  return [
    OpsModule.new,
    (c) => identity = IdentityModule(c, sms: sms),
    (c) => KeysModule(c, identity: identity.api),
  ];
}
