import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

part 'database/accounts_devices_repository.dart';
part 'database/admin_pairing_repository.dart';
part 'database/attachments_repository.dart';
part 'database/audit_tokens_repository.dart';
part 'database/backups_outbox_repository.dart';
part 'database/calls_repository.dart';
part 'database/contacts_repository.dart';
part 'database/group_calls_repository.dart';
part 'database/group_federation_repository.dart';
part 'database/groups_repository.dart';
part 'database/messaging_repository.dart';
part 'database/federation_repository.dart';
part 'database/invites_repository.dart';
part 'database/migrations.dart';
part 'database/operational_repository.dart';
part 'database/phone_otp_repository.dart';
part 'database/server_config_repository.dart';

class BackendDatabase {
  final Database _db;
  int _transactionDepth = 0;

  BackendDatabase(this._db) {
    _initializeSchema();
  }

  void close() {
    _db.close();
  }

  /// Builds a consistent envelope map for realtime delivery.
  /// All modules must use this method to ensure clients receive uniform
  /// RemoteRealtimeEnvelope-compatible payloads.
  static Map<String, dynamic> buildEnvelope({
    required String eventId,
    required String type,
    required Map<String, dynamic> payload,
    required int timestamp,
    int schemaVersion = 1,
    int? serverSequence,
  }) {
    return {
      'event_id': eventId,
      'schema_version': schemaVersion,
      'timestamp': timestamp,
      'type': type,
      'payload': payload,
      'server_sequence': serverSequence,
    };
  }
}
