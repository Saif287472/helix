// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inbox_dao.dart';

// ignore_for_file: type=lint
mixin _$InboxDaoMixin on DatabaseAccessor<HelixDb> {
  $InboxCursorTable get inboxCursor => attachedDatabase.inboxCursor;
  $ProcessedEnvelopesTable get processedEnvelopes =>
      attachedDatabase.processedEnvelopes;
  $DeferredActionsTable get deferredActions => attachedDatabase.deferredActions;
  InboxDaoManager get managers => InboxDaoManager(this);
}

class InboxDaoManager {
  final _$InboxDaoMixin _db;
  InboxDaoManager(this._db);
  $$InboxCursorTableTableManager get inboxCursor =>
      $$InboxCursorTableTableManager(_db.attachedDatabase, _db.inboxCursor);
  $$ProcessedEnvelopesTableTableManager get processedEnvelopes =>
      $$ProcessedEnvelopesTableTableManager(
        _db.attachedDatabase,
        _db.processedEnvelopes,
      );
  $$DeferredActionsTableTableManager get deferredActions =>
      $$DeferredActionsTableTableManager(
        _db.attachedDatabase,
        _db.deferredActions,
      );
}
