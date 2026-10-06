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

  /// Reports for the operator console, newest first.
  Future<Page<AdminReport>> reports(
    SqlSession db, {
    required PageRequest page,
    ReportStatus? status,
  });

  /// Marks an open report resolved or dismissed; false if it is not open.
  Future<bool> resolveReport(SqlSession db, String reportId, ReportStatus to);

  Future<int> openReportsAbout(SqlSession db, String accountId);
}
