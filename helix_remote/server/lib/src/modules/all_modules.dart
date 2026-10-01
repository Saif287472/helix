import 'package:helix_remote_server/src/modules/backup/module.dart';
import 'package:helix_remote_server/src/modules/calls/module.dart';
import 'package:helix_remote_server/src/modules/groups/module.dart';
import 'package:helix_remote_server/src/modules/identity/module.dart';
import 'package:helix_remote_server/src/modules/identity/sms.dart';
import 'package:helix_remote_server/src/modules/keys/module.dart';
import 'package:helix_remote_server/src/modules/media/module.dart';
import 'package:helix_remote_server/src/modules/messaging/module.dart';
import 'package:helix_remote_server/src/modules/ops/module.dart';
import 'package:helix_remote_server/src/modules/people/module.dart';
import 'package:helix_remote_server/src/modules/realtime/module.dart';
import 'package:helix_remote_server/src/server.dart';

/// The production module list, in construction order: a module may receive
/// the facades of modules listed before it. Grows phase by phase.
///
/// [sms] replaces the configured SMS provider (tests).
List<ModuleFactory> allModules({SmsProvider? sms}) {
  late IdentityModule identity;
  late KeysModule keys;
  late MessagingModule messaging;
  late MediaModule media;
  late PeopleModule people;
  return [
    OpsModule.new,
    (c) => identity = IdentityModule(c, sms: sms),
    (c) => keys = KeysModule(c, identity: identity.api),
    (c) =>
        messaging = MessagingModule(c, identity: identity.api, keys: keys.api),
    (c) => RealtimeModule(c, messaging: messaging.api),
    (c) => people = PeopleModule(
      c,
      identity: identity.api,
      messaging: messaging.api,
    ),
    (c) => media = MediaModule(c, identity: identity.api),
    (c) => BackupModule(c, identity: identity.api, media: media.api),
    (c) => GroupsModule(
      c,
      identity: identity.api,
      messaging: messaging.api,
      people: people.api,
    ),
    (c) => CallsModule(c, identity: identity.api, messaging: messaging.api),
  ];
}
