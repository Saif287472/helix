import 'package:helix_remote_backend/src/database.dart';

abstract interface class BackendTransactionRunner {
  T run<T>(T Function() operation);
}

abstract interface class AccountRepository {
  void createAccount(String accountId, String username, String publicKey);
  bool accountExists(String accountId);
}

abstract interface class MessageRepository {
  int saveMessage({
    required String messageId,
    required String conversationId,
    required String senderAccountId,
    required String senderDeviceId,
    required String recipientDeviceId,
    required String ciphertext,
  });

  Map<String, dynamic>? getMessage(String messageId);
}

abstract interface class OperationalRetentionRepository {
  Map<String, int> purgeOperationalRecords({
    required int completedOutboxOlderThan,
    required int auditOlderThan,
    required int tombstonesOlderThan,
  });
}

class SqliteBackendRepositories
    implements
        BackendTransactionRunner,
        AccountRepository,
        MessageRepository,
        OperationalRetentionRepository {
  SqliteBackendRepositories(this.db);

  final BackendDatabase db;

  @override
  T run<T>(T Function() operation) => db.runInTransaction(operation);

  @override
  void createAccount(String accountId, String username, String publicKey) {
    db.createAccount(accountId, username, publicKey);
  }

  @override
  bool accountExists(String accountId) => db.accountExists(accountId);

  @override
  int saveMessage({
    required String messageId,
    required String conversationId,
    required String senderAccountId,
    required String senderDeviceId,
    required String recipientDeviceId,
    required String ciphertext,
  }) {
    return db.saveMessage(
      messageId: messageId,
      conversationId: conversationId,
      senderAccountId: senderAccountId,
      senderDeviceId: senderDeviceId,
      recipientDeviceId: recipientDeviceId,
      ciphertext: ciphertext,
    );
  }

  @override
  Map<String, dynamic>? getMessage(String messageId) =>
      db.getMessage(messageId);

  @override
  Map<String, int> purgeOperationalRecords({
    required int completedOutboxOlderThan,
    required int auditOlderThan,
    required int tombstonesOlderThan,
  }) {
    return db.purgeOperationalRecords(
      completedOutboxOlderThan: completedOutboxOlderThan,
      auditOlderThan: auditOlderThan,
      tombstonesOlderThan: tombstonesOlderThan,
    );
  }
}
