import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

/// The people module's facade (ADR-026).
abstract interface class PeopleApi {
  /// Recipients (of [recipients]) who blocked [sender].
  Future<Set<String>> blockedBy(
    SqlSession db,
    String sender,
    Iterable<String> recipients,
  );

  /// Whether [target]'s `group_add` audience lets [adder] add them to a
  /// group directly.
  Future<bool> mayAddToGroup(
    SqlSession db, {
    required String adder,
    required String target,
  });

  Future<PrivacySettings> privacy(SqlSession db, String accountId);
}
