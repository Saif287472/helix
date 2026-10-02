import 'dart:async';

import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/transfers/blob_store.dart';
import 'package:helix_remote_engine/src/transfers/transfer_config.dart';
import 'package:helix_remote_engine/src/transfers/transfer_files.dart';

/// Keeps the file store honest: **a file lives exactly as long as something
/// points at it.**
///
/// When a message goes (delete for me, delete for everyone, a disappearing
/// timer, a view-once message after it was seen) its attachment rows go with
/// it by cascade, and the files they named become unreferenced. The
/// janitor deletes them: it compares what the store holds with what the
/// attachment rows and the live transfer jobs refer to, and removes the rest.
/// Working this out from the database, instead of hooking every place a
/// message can disappear, means no path (groups, backup restore, a crash
/// halfway through a delete) can leave a file behind.
///
/// It runs when the attachment count drops, on a timer, at start, and on
/// demand ([sweep]). A file younger than `sweepGrace` is never taken for
/// leftover, so one being written while a sweep runs is safe.
final class MediaJanitor {
  MediaJanitor(this._ctx, this._blobs, this._config, {this.beforeSweep});

  final EngineContext _ctx;
  final BlobStore _blobs;
  final TransferConfig _config;

  /// Runs before each sweep (the engine drops what has become pointless:
  /// queued sends of deleted messages, view-once media that was seen).
  final Future<void> Function()? beforeSweep;

  StreamSubscription<int>? _counts;
  Timer? _timer;
  Timer? _debounce;
  bool _active = false;
  bool _sweeping = false;
  int? _lastCount;

  void start() {
    if (_active) return;
    _active = true;
    _counts = _ctx.db.messagesDao.watchAttachmentCount().listen((count) {
      final previous = _lastCount;
      _lastCount = count;
      if (previous != null && count < previous) _soon();
    });
    _timer = Timer.periodic(_config.sweepInterval, (_) => _soon());
    _soon();
  }

  Future<void> stop() async {
    _active = false;
    _timer?.cancel();
    _debounce?.cancel();
    _timer = _debounce = null;
    await _counts?.cancel();
    _counts = null;
    _lastCount = null;
  }

  void _soon() {
    if (!_active) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      unawaited(sweep());
    });
  }

  /// Deletes the leftover files. Returns how many.
  Future<int> sweep() async {
    if (_sweeping) return 0;
    _sweeping = true;
    try {
      await beforeSweep?.call();
      final db = _ctx.db;
      final kept = <String>{...await db.messagesDao.attachmentPaths()};
      for (final job in await db.transfersDao.live()) {
        kept.addAll(await TransferFiles.allFor(_blobs, job.id));
        final path = job.localPath;
        if (path != null) kept.add(path);
      }
      final cutoff = _ctx.now().subtract(_config.sweepGrace);
      var removed = 0;
      for (final area in BlobArea.values) {
        for (final file in await _blobs.list(area)) {
          if (kept.contains(file.path) || file.modifiedAt.isAfter(cutoff)) {
            continue;
          }
          await _blobs.delete(file.path);
          removed++;
        }
      }
      return removed;
    } on Object {
      // The database closed under us (sign-out, wipe).
      return 0;
    } finally {
      _sweeping = false;
    }
  }
}
