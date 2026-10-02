import 'package:helix_remote_api/src/v2/transport/errors.dart';
import 'package:helix_remote_api/src/v2/transport/transport.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The `backup` module: the automatic, AIK-keyed history backup and the
/// user-secret full backup. Both are opaque to the server.
final class BackupClient {
  const BackupClient(this._t);

  final HelixTransport _t;

  /// `version` must increase (`version_conflict` otherwise).
  Future<void> putHistory(HistoryBackup backup) =>
      _t.empty(Routes.putHistoryBackup, json: backup.toJson());

  /// Null when there is none.
  Future<HistoryBackup?> history() =>
      _orNull(_t.call(Routes.getHistoryBackup, HistoryBackup.fromJson));

  Future<void> deleteHistory() => _t.empty(Routes.deleteHistoryBackup);

  Future<void> putFull(FullBackup backup) =>
      _t.empty(Routes.putFullBackup, json: backup.toJson());

  /// Null when there is none.
  Future<FullBackup?> full() =>
      _orNull(_t.call(Routes.getFullBackup, FullBackup.fromJson));

  Future<void> deleteFull() => _t.empty(Routes.deleteFullBackup);

  static Future<T?> _orNull<T>(Future<T> request) async {
    try {
      return await request;
    } on ApiException catch (e) {
      if (e.code == ErrorCode.notFound) return null;
      rethrow;
    }
  }
}
