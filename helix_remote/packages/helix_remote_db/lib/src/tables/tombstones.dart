import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/values.dart';

/// What this device deleted, so a merge cannot bring it back (AUD-12q-1).
///
/// A local removal — "delete for me", a cleared chat, a deleted chat — deletes
/// rows and leaves no trace that they were ever here. Another device of the
/// same account still has them, and its backup still carries them, so the next
/// merge puts them back: the version-conflict catch-up inside an ordinary
/// nightly backup, or the restore button. An incoming message comes back unread.
///
/// A row here is this device's own choice, not the account's: it is never
/// exported, and `wipeAll` drops it with everything else, so a new device
/// recovering the history is not told what an older one deleted. It is not
/// aged out either — a backup can be of any date, so a cut by age could
/// resurrect what the person removed.
@DataClassName('DeleteTombstoneRow')
class DeleteTombstones extends Table {
  TextColumn get kind => textEnum<TombstoneKind>()();

  /// The message's wire id, or the conversation's id.
  TextColumn get targetId => text()();

  /// The message's author, so a tombstone names one person's message and not
  /// another's that happens to share its id. Empty for a conversation.
  TextColumn get authorId => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {kind, targetId, authorId};
}
