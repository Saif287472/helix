part of '../composition_root.dart';

const _historyBackupLastKey = 'history_backup.last_at';
const _historyRestorePendingKey = 'history_backup.restore_pending';

/// The automatic, encrypted, text-only chat history backup.
///
/// Every device of the account backs up about once a day, merging with what
/// is already stored so no device overwrites another's history. A device
/// that signs in with the password restores it before the app opens.
mixin RemoteCompositionHistoryBackup on RemoteCompositionRootBase {
  static const backupInterval = Duration(hours: 24);

  Future<({List<int> key, String identityPublicKey})?> _historyKey() async {
    final store = _keyValue;
    if (store == null) return null;
    final private = await store.read('identity_private_key');
    final public = await store.read('identity_public_key');
    if (private == null || public == null) return null;
    return (
      key: await HistoryBackupCodec.deriveKey(_base64UrlDecode(private)),
      identityPublicKey: public,
    );
  }

  /// When this device last uploaded the history backup, if ever.
  Future<DateTime?> lastHistoryBackupAt() async {
    final raw = await _keyValue?.read(_historyBackupLastKey);
    final ms = raw == null ? null : int.tryParse(raw);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Merges this device's text history into the stored backup and uploads
  /// it. Throws on failure so "Back up now" can say so.
  Future<void> backUpHistoryNow() async {
    final rest = _requireReady(_restClient, 'restClient');
    final ms = _requireReady(_messagingService, 'messagingService');
    final key = await _historyKey();
    if (key == null) throw StateError('This device has no account key');

    Map<String, dynamic>? remote;
    final existing = await rest.downloadHistoryBackup();
    if (existing != null) {
      try {
        remote = await HistoryBackupCodec.decrypt(
          key: key.key,
          identityPublicKey: key.identityPublicKey,
          blob: existing,
        );
      } catch (_) {
        // Made under an older identity; nothing in it can be kept.
        remote = null;
      }
    }
    final merged = HistoryBackupCodec.merge(
      remote,
      await ms.exportTextHistory(),
    );
    await rest.uploadHistoryBackup(
      await HistoryBackupCodec.encrypt(
        key: key.key,
        identityPublicKey: key.identityPublicKey,
        snapshot: merged,
      ),
    );
    await _keyValue?.write(
      _historyBackupLastKey,
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  /// Restores the stored backup into this device. Never throws: a failure
  /// is remembered and retried when the app next starts.
  @override
  Future<int> restoreHistoryBackup() async {
    final store = _keyValue;
    try {
      final rest = _requireReady(_restClient, 'restClient');
      final ms = _requireReady(_messagingService, 'messagingService');
      final key = await _historyKey();
      if (key == null) return 0;
      final blob = await rest.downloadHistoryBackup();
      var restored = 0;
      if (blob != null) {
        final snapshot = await HistoryBackupCodec.decrypt(
          key: key.key,
          identityPublicKey: key.identityPublicKey,
          blob: blob,
        );
        restored = await ms.importTextHistory(snapshot);
      }
      await store?.delete(_historyRestorePendingKey);
      AppLogger.instance.info('HISTORY', 'restored $restored message(s)');
      return restored;
    } catch (e) {
      await store?.write(_historyRestorePendingKey, '1');
      AppLogger.instance.warn('HISTORY', 'restore failed: ${e.runtimeType}');
      return 0;
    }
  }

  /// Runs at every app start: finishes an interrupted restore, then backs
  /// up if the last backup is a day old. Best-effort throughout.
  @override
  Future<void> _historyBackupOnStart() async {
    try {
      if (await _keyValue?.read(_historyRestorePendingKey) == '1') {
        await restoreHistoryBackup();
      }
      final last = await lastHistoryBackupAt();
      if (last != null && DateTime.now().difference(last) < backupInterval) {
        return;
      }
      await backUpHistoryNow();
    } catch (e) {
      AppLogger.instance.warn('HISTORY', 'backup failed: ${e.runtimeType}');
    }
  }
}
