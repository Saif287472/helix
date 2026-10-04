import 'package:helix_remote_engine/helix_remote_engine.dart'
    show BackupException, BackupFailure, BackupRemote;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show FullBackup, HistoryBackup;

/// The history backup's server calls, with one rule added: an **upload** only
/// goes out when [mayUpload] says so.
///
/// The engine has one switch for the automatic backup and no idea what a
/// metered connection is, so "do not back up over mobile data" is enforced
/// here, at the single place the backup leaves the phone. A refused upload is
/// recorded by the engine as a failed attempt and tried again after its retry
/// interval, which is exactly "wait for Wi-Fi". Downloads (a restore, the
/// merge that precedes an upload) are never blocked, and neither is the manual
/// full backup: somebody who asked for it has decided.
final class PolicyBackupRemote implements BackupRemote {
  PolicyBackupRemote(this._inner, {required this.mayUpload});

  final BackupRemote _inner;
  final Future<bool> Function() mayUpload;

  @override
  Future<HistoryBackup?> history() => _inner.history();

  @override
  Future<void> putHistory(HistoryBackup backup) async {
    if (!await mayUpload()) {
      throw const BackupException(BackupFailure.notAllowed, 'metered network');
    }
    return _inner.putHistory(backup);
  }

  @override
  Future<void> deleteHistory() => _inner.deleteHistory();

  @override
  Future<FullBackup?> full() => _inner.full();

  @override
  Future<void> putFull(FullBackup backup) => _inner.putFull(backup);

  @override
  Future<void> deleteFull() => _inner.deleteFull();
}
