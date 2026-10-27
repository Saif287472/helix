import 'dart:async';

import 'package:helix_remote_engine/src/account/device_service.dart';
import 'package:helix_remote_engine/src/account/key_maintenance.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/settings_keys.dart';

/// Timers and housekeeping while the engine runs:
///
/// - **Disappearing messages** ([rescheduleExpiry]): one timer set for the
///   next `expires_at`, so a message disappears when its time is up, not on
///   the next poll.
/// - **Housekeeping** (every `maintenanceInterval`, and [runOnce]): expired
///   deferred actions, processed-envelope ids past the replay window,
///   expired messages, live locations whose time is up (their place is
///   taken out), and, when due, prekey upkeep and a refresh of the
///   own device list. Whatever the other features pass in `_extraWork` runs at
///   the end of the same pass, each on its own guard.
///
/// Prekey and device-list refreshes need the network; their failures are
/// swallowed and retried on the next tick.
final class MaintenanceService {
  MaintenanceService(
    this._ctx,
    this._keys,
    this._devices, {
    this._extraWork = const [],
  });

  final EngineContext _ctx;
  final KeyMaintenance _keys;
  final DeviceService _devices;

  /// Other features' housekeeping (the backup schedule, the group key duties),
  /// run at the end of every pass. Each is guarded separately: one that throws
  /// must not stop the others.
  final List<Future<void> Function()> _extraWork;

  Timer? _tick;
  Timer? _expiry;
  bool _active = false;

  void start() {
    if (_active) return;
    _active = true;
    _tick = Timer.periodic(
      _ctx.config.maintenanceInterval,
      (_) => unawaited(runOnce()),
    );
    unawaited(runOnce());
    rescheduleExpiry();
  }

  Future<void> stop() async {
    _active = false;
    _tick?.cancel();
    _expiry?.cancel();
    _tick = _expiry = null;
  }

  /// One pass of everything. Safe to call at any time.
  ///
  /// Every duty is guarded on its own and the expiry timer is re-armed in a
  /// `finally`: one sweep that throws - the database closed under us, a table
  /// mid-wipe - must not stop the duties after it, or end the disappearing
  /// message timers for the rest of this engine's life (AUD-10-1).
  Future<void> runOnce() async {
    try {
      final now = _ctx.now();
      await _guarded(() => _ctx.db.messagesDao.removeExpired(now));
      await _guarded(() => _ctx.db.messagesDao.endLiveLocations(now));
      await _guarded(() => _ctx.db.inboxDao.purgeExpiredDeferred(now));
      await _guarded(
        () => _ctx.db.inboxDao.pruneProcessed(
          now.subtract(_ctx.config.processedRetention),
        ),
      );
      await _guarded(() => _refreshKeysAndDevices(now));
      for (final extra in _extraWork) {
        await _guarded(extra);
      }
    } finally {
      rescheduleExpiry();
    }
  }

  Future<void> _refreshKeysAndDevices(DateTime now) async {
    final last = await _ctx.db.settingsDao.get(EngineState.lastPrekeyCheck);
    final due =
        now.millisecondsSinceEpoch - last >=
        _ctx.config.prekeyCheckInterval.inMilliseconds;
    if (due) await _guarded(_keys.run);
    final refreshed = await _ctx.db.settingsDao.get(
      EngineState.lastOwnDevicesRefresh,
    );
    if (now.millisecondsSinceEpoch - refreshed >=
        _ctx.config.prekeyCheckInterval.inMilliseconds) {
      await _guarded(_devices.refresh);
    }
  }

  Future<void> _guarded(Future<Object?> Function() action) async {
    try {
      await action();
    } on Object {
      // Offline or signed out, or this duty's own failure: the next tick tries
      // again, and the duties after it in this pass still run.
    }
  }

  /// Re-arms the expiry timer for the next disappearing message. Call after
  /// anything that sets an `expires_at`.
  void rescheduleExpiry() {
    if (!_active) return;
    unawaited(_arm());
  }

  Future<void> _arm() async {
    _expiry?.cancel();
    final DateTime? next;
    try {
      next = await _ctx.db.messagesDao.nextExpiryAt();
    } on Object {
      return;
    }
    if (next == null || !_active) return;
    var wait = next.difference(_ctx.now());
    if (wait < Duration.zero) wait = Duration.zero;
    if (wait > const Duration(hours: 1)) wait = const Duration(hours: 1);
    _expiry = Timer(wait + const Duration(milliseconds: 50), () async {
      try {
        await _ctx.db.messagesDao.removeExpired(_ctx.now());
      } on Object {
        // The rows are still due, so re-arming now would fire again in 50 ms
        // and spin on a sweep that keeps failing. The next tick re-arms
        // through `runOnce`.
        return;
      }
      rescheduleExpiry();
    });
  }
}
