import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Which kind of engine is asking to own the database.
enum LeaseRole {
  /// The app's own engine: sockets, timers, the whole thing.
  foreground,

  /// The FCM background isolate's one-shot engine.
  headless,
}

/// Another engine already owns this database.
///
/// For a foreground engine that means a second window (Windows has no single
/// instance guard); for the push isolate it means the app is running and will
/// fetch the mailbox itself. Neither is a failure of the data, so the router
/// shows it as such and never offers the destructive reset.
final class EngineAlreadyRunning implements Exception {
  const EngineAlreadyRunning({required this.byRole});

  /// What holds the lease.
  final LeaseRole byRole;

  @override
  String toString() => 'another Helix engine owns this database';
}

/// A cross-isolate, cross-process claim on the database, kept in a small file
/// next to it.
///
/// **Why.** The app's engine and the FCM background isolate are two engines
/// that open the same SQLCipher file in the same process; Windows can start a
/// second process. SQLite serialises their writes, but nothing makes two
/// engines take turns over *inbound processing*: both could read the same
/// mailbox entry and both advance the same double-ratchet state. The first
/// engine to own the lease is the only one that syncs.
///
/// **Why a file and not `RandomAccessFile.lock`.** On Android and Linux Dart's
/// file locks are per-process (`fcntl`), so they do not separate two isolates
/// of the same process - the very pair that matters. A lease with a heartbeat
/// works the same for isolates and processes, and a crash cannot wedge it: it
/// is taken over once the heartbeat is [staleAfter] old.
///
/// **What it is not.** A best-effort advisory claim, not a mutex: the check
/// and the write are not atomic, so two engines started within the same few
/// milliseconds can both win. [acquire] re-reads after [settle] to make that
/// rare, and the cost of the rare case is the situation before this existed.
///
/// Rules:
/// - a headless engine never waits and never takes over a live lease: it
///   throws [EngineAlreadyRunning] and the push handler returns;
/// - a foreground engine waits up to [waitForHeadless] for a running headless
///   one (it is short-lived), then takes the lease over;
/// - a foreground engine refuses to share with another foreground engine in a
///   **different process** (a second Windows window), and replaces one in its
///   own process (a server switch, where the old runtime is closing).
final class EngineLease {
  EngineLease._(this._file, this._owner, this._role);

  /// A lease whose heartbeat is older than this is dead.
  static const staleAfter = Duration(seconds: 20);

  /// How often a held lease says it is alive.
  static const beat = Duration(seconds: 5);

  final File _file;
  final String _owner;
  final LeaseRole _role;
  Timer? _heartbeat;
  bool _released = false;

  /// Takes the lease kept in [file], or throws [EngineAlreadyRunning].
  static Future<EngineLease> acquire(
    File file, {
    required LeaseRole role,
    DateTime Function() now = DateTime.now,
    Duration waitForHeadless = const Duration(seconds: 10),
    Duration poll = const Duration(milliseconds: 250),
    Duration settle = const Duration(milliseconds: 40),
    int? processId,
  }) async {
    final pidNow = processId ?? pid;
    final owner = _newOwner();
    final deadline = now().add(waitForHeadless);

    while (true) {
      final held = _read(file, now());
      if (held == null) break;
      if (role == LeaseRole.headless) {
        throw EngineAlreadyRunning(byRole: held.role);
      }
      if (held.role == LeaseRole.foreground && held.pid != pidNow) {
        throw const EngineAlreadyRunning(byRole: LeaseRole.foreground);
      }
      if (held.role == LeaseRole.foreground) break; // our own process: replace
      // A headless engine in the middle of its pass: let it finish.
      if (!now().isBefore(deadline)) break;
      await Future<void>.delayed(poll);
    }

    _write(file, owner, role, pidNow, now());
    if (settle > Duration.zero) await Future<void>.delayed(settle);
    final after = _read(file, now());
    if (after != null && after.owner != owner) {
      // Somebody wrote in the same instant and won.
      throw EngineAlreadyRunning(byRole: after.role);
    }

    final lease = EngineLease._(file, owner, role);
    lease._heartbeat = Timer.periodic(beat, (_) {
      if (lease._released) return;
      _write(file, owner, role, pidNow, now());
    });
    return lease;
  }

  /// Gives the lease back, if it is still ours.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    _heartbeat?.cancel();
    try {
      final held = _read(_file, DateTime.now(), ignoreStale: true);
      if (held != null && held.owner == _owner && _file.existsSync()) {
        _file.deleteSync();
      }
    } on Object {
      // A stale file expires by itself.
    }
  }

  /// This lease's role, for diagnostics.
  LeaseRole get role => _role;

  static String _newOwner() {
    final random = Random.secure();
    return base64Url.encode([for (var i = 0; i < 12; i++) random.nextInt(256)]);
  }

  static void _write(
    File file,
    String owner,
    LeaseRole role,
    int pid,
    DateTime at,
  ) {
    try {
      file.writeAsStringSync(
        jsonEncode({
          'owner': owner,
          'role': role.name,
          'pid': pid,
          'at': at.millisecondsSinceEpoch,
        }),
        flush: true,
      );
    } on Object {
      // An unwritable lease file means no claim can be recorded; carrying on
      // is what the app did before leases existed.
    }
  }

  static _Held? _read(File file, DateTime now, {bool ignoreStale = false}) {
    try {
      if (!file.existsSync()) return null;
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map) return null;
      final at = json['at'];
      final owner = json['owner'];
      final role = json['role'];
      final pid = json['pid'];
      if (at is! int || owner is! String || role is! String || pid is! int) {
        return null;
      }
      final age = now.difference(DateTime.fromMillisecondsSinceEpoch(at));
      // A heartbeat from the future (a clock set back) is not trusted either.
      if (!ignoreStale && (age > staleAfter || age < -staleAfter)) return null;
      return _Held(
        owner,
        role == LeaseRole.headless.name
            ? LeaseRole.headless
            : LeaseRole.foreground,
        pid,
      );
    } on Object {
      return null;
    }
  }
}

final class _Held {
  const _Held(this.owner, this.role, this.pid);

  final String owner;
  final LeaseRole role;
  final int pid;
}
