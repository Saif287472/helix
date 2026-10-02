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
///   expired messages, and, when due, prekey upkeep and a refresh of the
///   own device list.
///
/// Prekey and device-list refreshes need the network; their failures are
/// swallowed and retried on the next tick.
final class MaintenanceService {
  MaintenanceService(this._ctx, this._keys, this._devices, {this._extraWork});

  final EngineContext _ctx;
  final KeyMaintenance _keys;
  final DeviceService _devices;

  /// Other features' housekeeping (the backup feature's schedule), run at the
  /// end of every pass. Must not throw.
  final Future<void> Function()? _extraWork;

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
  Future<void> runOnce() async {
    try {
      final now = _ctx.now();
      await _ctx.db.messagesDao.removeExpired(now);
      await _ctx.db.inboxDao.purgeExpiredDeferred(now);
      await _ctx.db.inboxDao.pruneProcessed(
        now.subtract(_ctx.config.processedRetention),
      );
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
      final extra = _extraWork;
      if (extra != null) await _guarded(extra);
    } on Object {
      // The database closed under us, or a table is mid-wipe.
      return;
    }
    rescheduleExpiry();
  }

  Future<void> _guarded(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // Offline or signed out: the next tick tries again.
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
        return;
      }
      rescheduleExpiry();
    });
  }
}
