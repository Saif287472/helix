import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:sqlite3/sqlite3.dart';
import 'package:helix_remote_domain/models.dart';

part 'database/accounts_contacts_repository.dart';
part 'database/attachments_repository.dart';
part 'database/backups_repository.dart';
part 'database/conversations_repository.dart';
part 'database/crypto_repository.dart';
part 'database/group_calls_repository.dart';
part 'database/groups_repository.dart';
part 'database/lifecycle.dart';
part 'database/messages_repository.dart';
part 'database/collaboration_repository.dart';
part 'database/media_repository.dart';
part 'database/migrations.dart';
part 'database/personalization_repository.dart';
part 'database/privacy_repository.dart';
part 'database/productivity_repository.dart';
part 'database/runtime_repository.dart';
part 'database/sync_outbox_repository.dart';
part 'database/tombstones_calls_repository.dart';

enum RemoteDatabaseMigrationFault {
  afterPlaintextBackupRename,
  afterEncryptedSwapRename,
}

class RemoteDatabaseEncryptionException implements Exception {
  RemoteDatabaseEncryptionException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() {
    final suffix = cause == null ? '' : ' Cause: $cause';
    return 'RemoteDatabaseEncryptionException: $message$suffix';
  }
}

class RemoteDatabaseMigrationException implements Exception {
  RemoteDatabaseMigrationException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() {
    final suffix = cause == null ? '' : ' Cause: $cause';
    return 'RemoteDatabaseMigrationException: $message$suffix';
  }
}

abstract class HelixRemoteDatabaseBase {
  File get file;
  String? get password;
  RemoteDatabaseMigrationFault? get migrationFault;
  Database get _db;

  void deleteMessage(String messageId);
  void saveTombstone(String itemId, String type);
  List<RemoteContact> getContacts();
  List<RemoteConversation> getConversations();
  Map<String, dynamic>? getAttachment(String attachmentId);
  void saveAttachment({
    required String attachmentId,
    required String filename,
    required int sizeBytes,
    required String encryptedKey,
    String? localPath,
    String? importedSourcePath,
    String? encryptedCachePath,
    String? downloadedCiphertextPath,
    String? exportedPlaintextPath,
    required String status,
  });
  List<String> cleanupExpiredMessages(int nowMs);
  void enqueueOperation(
    String opId,
    String type,
    String payload, {
    String idempotencyKey = '',
  });
  List<Map<String, dynamic>> getTombstones();
}

class HelixRemoteDatabase extends HelixRemoteDatabaseBase
    with
        RemoteDatabaseLifecycle,
        RemoteDatabaseMigrations,
        RemoteAccountsContactsRepository,
        RemoteConversationsRepository,
        RemoteMessagesRepository,
        RemoteCollaborationRepository,
        RemoteMediaRepository,
        RemotePersonalizationRepository,
        RemotePrivacyRepository,
        RemoteProductivityRepository,
        RemoteRuntimeRepository,
        RemoteCryptoRepository,
        RemoteAttachmentsRepository,
        RemoteSyncOutboxRepository,
        RemoteTombstonesCallsRepository,
        RemoteGroupCallsRepository,
        RemoteGroupsRepository,
        RemoteBackupsRepository {
  @override
  final File file;
  @override
  final String? password;
  @override
  final RemoteDatabaseMigrationFault? migrationFault;
  @override
  late final Database _db;

  HelixRemoteDatabase(this.file, {this.password, this.migrationFault});

  void initialize() {
    Database? opened;
    try {
      opened = _openDatabase();
      _db = opened;
      _configureDatabase(_db);
      _onCreate();
      _applyMigrations();
      _assertIntegrityOk(_db);
    } catch (_) {
      opened?.close();
      rethrow;
    }
  }
}
