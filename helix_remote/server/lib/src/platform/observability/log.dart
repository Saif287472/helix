import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

enum LogLevel { debug, info, warn, error }

/// Structured JSON logging with redaction (AGENTS.md: never log passwords,
/// tokens, keys, message content, codes or full phone numbers).
///
/// Redaction is by field name *and* by value shape, so a secret passed under
/// an innocent name is still masked when it looks like a token, a key, a URL
/// with credentials or a phone number. Events are short snake_case names;
/// details go in fields.
final class Log {
  Log({this.minLevel = LogLevel.info, LogSink? sink, this._ringSize = 500})
    : _root = null,
      _context = const {},
      _sink = sink ?? const StdoutSink();

  Log._child(Log root, this._context)
    : _root = root,
      minLevel = root.minLevel,
      _sink = root._sink,
      _ringSize = 0;

  final LogLevel minLevel;
  final Log? _root;
  final Map<String, Object?> _context;
  final LogSink _sink;
  final int _ringSize;
  final Queue<String> _ring = Queue();
  final StreamController<String> _lines = StreamController.broadcast();

  /// A logger that adds [fields] to every line (module, request id).
  Log child(Map<String, Object?> fields) =>
      Log._child(_root ?? this, {..._context, ...fields});

  void debug(String event, [Map<String, Object?> fields = const {}]) =>
      write(LogLevel.debug, event, fields);

  void info(String event, [Map<String, Object?> fields = const {}]) =>
      write(LogLevel.info, event, fields);

  void warn(String event, [Map<String, Object?> fields = const {}]) =>
      write(LogLevel.warn, event, fields);

  void error(String event, [Map<String, Object?> fields = const {}]) =>
      write(LogLevel.error, event, fields);

  void write(LogLevel level, String event, Map<String, Object?> fields) {
    final root = _root ?? this;
    root._emit(level, event, {..._context, ...fields});
  }

  void _emit(LogLevel level, String event, Map<String, Object?> fields) {
    if (level.index < minLevel.index) return;
    final line = jsonEncode({
      'ts': DateTime.now().toUtc().toIso8601String(),
      'level': level.name,
      'event': event,
      ...redactFields(fields),
    });
    _sink.write(line);
    if (_lines.hasListener) _lines.add(line);
    _ring.addLast(line);
    while (_ring.length > _ringSize) {
      _ring.removeFirst();
    }
  }

  /// Every line from now on (already redacted), for the admin log stream.
  Stream<String> get lines => (_root ?? this)._lines.stream;

  /// The most recent lines (already redacted), for the admin log view.
  List<String> recent([int limit = 100]) {
    final all = (_root ?? this)._ring.toList();
    return all.sublist(all.length > limit ? all.length - limit : 0);
  }
}

abstract interface class LogSink {
  void write(String line);
}

final class StdoutSink implements LogSink {
  const StdoutSink();

  @override
  void write(String line) => stdout.writeln(line);
}

/// Appends lines to a file (`HELIX_LOG_FILE`) and rotates it daily: the
/// first line of a new UTC day renames the file to `<name>-YYYY-MM-DD<ext>`
/// (the day it holds) and starts a new one, and rotated files older than
/// [keepDays] are deleted (review H-05; copy-and-truncate tools cannot work
/// on Windows, where an open file cannot be renamed). A file left from an
/// earlier day is rotated at open. Opening fails early (a
/// [FileSystemException]) if the file cannot be written.
///
/// Lines are buffered and written by one asynchronous flush
/// ([flushInterval] apart, or sooner once [flushBeforeBytes] have piled up),
/// because a synchronous write per line puts the disk on the request path:
/// every request already costs one line, and a flood or a reconnect storm
/// then costs one blocking write each (AUD-1a-5). The buffer only ever holds
/// whole lines and a rotation happens between two flushes, so a rotation
/// still cannot split a line.
///
/// A day that grows past [maxBytesPerDay] rotates early, to the next numbered
/// file of the same day: retention by day alone bounds nothing for a day that
/// never ends, and 5k requests a second is ~86 MB of access lines an hour.
/// At each rotation the oldest file of the day is deleted until the day is back
/// inside the bound, so a flooded day costs about [maxBytesPerDay] plus the
/// file being written, not everything the flood wrote, and the whole log costs
/// about `keepDays * maxBytesPerDay`.
///
/// A failed write, rotation or flush never reaches the caller (stdout still
/// has the line, and the next flush tries again).
final class FileSink implements LogSink {
  FileSink._(
    this.path,
    this.keepDays,
    this.maxBytesPerDay,
    this._now,
    this._file,
    this._day,
    this._dayBytes,
  );

  /// `HELIX_LOG_MAX_BYTES_PER_DAY`: the size one day's log file may reach
  /// before it rotates early.
  static const defaultMaxBytesPerDay = 256 * 1024 * 1024;

  /// How long a line may wait in the buffer before it is written.
  static const flushInterval = Duration(milliseconds: 200);

  /// The buffer size that triggers a flush without waiting for the timer.
  static const flushBeforeBytes = 64 * 1024;

  static FileSink open(
    String path, {
    int keepDays = 14,
    int maxBytesPerDay = defaultMaxBytesPerDay,
    DateTime Function()? now,
  }) {
    final clock = now ?? () => DateTime.now().toUtc();
    final file = File(path);
    final today = _dayOf(clock());
    var bytes = 0;
    if (file.existsSync() && file.lengthSync() > 0) {
      final day = _dayOf(file.lastModifiedSync().toUtc());
      if (day != today) {
        _rotate(path, day);
        bytes = 0;
      } else {
        bytes = file.lengthSync();
      }
    }
    // Fails now, not on the first write, if the path is unusable.
    final sink = FileSink._(
      path,
      keepDays,
      maxBytesPerDay <= 0 ? _noSizeBound : maxBytesPerDay,
      clock,
      file.openSync(mode: FileMode.append),
      today,
      bytes,
    );
    sink._prune();
    return sink;
  }

  /// `HELIX_LOG_MAX_BYTES_PER_DAY=0`: no size bound, only the daily one.
  static const _noSizeBound = 1 << 62;

  final String path;
  final int keepDays;

  /// The size one day's file may reach before it rotates early; [open] maps
  /// `0` to "no bound".
  final int maxBytesPerDay;
  final DateTime Function() _now;
  RandomAccessFile _file;
  String _day;

  /// Bytes in the file for [_day], so the cap survives a restart.
  int _dayBytes;

  bool _closed = false;
  final List<String> _buffer = [];
  int _bufferBytes = 0;

  /// The UTC day of the lines in [_buffer] while it holds any, so a batch is
  /// filed under the day it was written on even when its flush runs after
  /// midnight. Null exactly while the buffer is empty.
  String? _bufferDay;

  Timer? _timer;

  /// Whole encoded batches waiting for the disk, each stamped with the UTC day
  /// its lines were written on - so a line is filed under its own day even if
  /// the flush that carries it runs after midnight.
  final List<(String, List<int>)> _queued = [];

  /// How many batches may wait. Past it the oldest goes: the disk being
  /// slower than the requests must not turn the log into a memory leak, which
  /// is half of what this sink is here to avoid (AUD-1a-5). Stdout still has
  /// every line.
  static const maxQueuedBatches = 32;

  /// Chained so flushes cannot interleave: one rotation is between two whole
  /// batches, never inside one.
  Future<void> _flushed = Future<void>.value();

  static String _dayOf(DateTime t) =>
      t.toUtc().toIso8601String().substring(0, 10);

  /// `helix.log` holding 2026-10-14 becomes `helix-2026-10-14.log`.
  static String rotatedName(String path, String day) =>
      '${p.withoutExtension(path)}-$day${p.extension(path)}';

  static void _rotate(String path, String day) {
    var target = rotatedName(path, day);
    // Rotated twice for one day (a restart): number the later ones.
    for (var n = 1; File(target).existsSync(); n++) {
      target = '${p.withoutExtension(path)}-$day.$n${p.extension(path)}';
    }
    File(path).renameSync(target);
  }

  @override
  void write(String line) {
    if (_closed) return;
    // A line that starts a new day, or that would take this day past its
    // bound, is cut out of the buffer first: what is already in it belongs to
    // the day and the file it was written under.
    final day = _dayOf(_now());
    if (_bufferDay != null &&
        (_bufferDay != day ||
            _dayBytes + _bufferBytes + line.length + 1 > maxBytesPerDay)) {
      _cut();
    }
    _bufferDay ??= day;
    _buffer.add(line);
    _bufferBytes += line.length + 1;
    if (_bufferBytes >= flushBeforeBytes) {
      _cut();
    } else {
      _timer ??= Timer(flushInterval, _cut);
    }
  }

  /// Move the buffered lines into a batch. Synchronous, so the lines a write
  /// decided about are the lines that batch carries, and the day the batch is
  /// stamped with is the day they were written on - not the day the flush
  /// happens to run on, which after midnight is a different one.
  void _cut() {
    _timer?.cancel();
    _timer = null;
    if (_buffer.isEmpty) return;
    _queued.add((_bufferDay!, utf8.encode('${_buffer.join('\n')}\n')));
    _bufferDay = null;
    _buffer.clear();
    _bufferBytes = 0;
    while (_queued.length > maxQueuedBatches) {
      _queued.removeAt(0);
    }
    _flushed = _flushed.then((_) => _drain());
  }

  Future<void> _drain() async {
    while (_queued.isNotEmpty && !_closed) {
      final (day, data) = _queued.removeAt(0);
      try {
        await _rollFor(day, data.length);
        await _file.writeFrom(data);
        _dayBytes += data.length;
      } on FileSystemException {
        // A full or closed file loses these lines, not the requests that made
        // them; stdout still has them and the next flush tries again.
      }
    }
  }

  /// Move the file aside when the day changed or when it would pass
  /// [maxBytesPerDay] with this batch, and start the next one.
  Future<void> _rollFor(String day, int incoming) async {
    // A file holding nothing for its day is not worth rotating: a bound
    // smaller than one batch would otherwise rename and reopen on every line.
    if (day == _day &&
        (_dayBytes == 0 || _dayBytes + incoming <= maxBytesPerDay)) {
      return;
    }
    final sameDay = day == _day;
    try {
      await _file.close();
    } on FileSystemException {
      // Nothing to close cleanly; the rename and the reopen below still
      // replace the handle.
    }
    try {
      _rotate(path, _day);
    } on FileSystemException {
      // Keep writing to the one file; the next rotation tries again.
    }
    // A day that hit its bound continues in a second numbered file of the
    // same day; only a day change moves to a new day.
    _day = sameDay ? _day : day;
    _dayBytes = 0;
    try {
      _file = await File(path).open(mode: FileMode.append);
    } on FileSystemException {
      _closed = true;
      return;
    }
    _prune();
  }

  /// Deletes rotated files of this log older than [keepDays], and the oldest
  /// of today's own files once the day has passed [maxBytesPerDay]: the cap
  /// bounds the disk a flooded day can take, which is what it is for.
  void _prune() {
    final dir = Directory(p.dirname(path));
    final stem = RegExp.escape(p.basenameWithoutExtension(path));
    final ext = RegExp.escape(p.extension(path));
    final rotated = RegExp('^$stem-(\\d{4}-\\d{2}-\\d{2})(\\.\\d+)?$ext\$');
    final oldest = _dayOf(_now().subtract(Duration(days: keepDays)));
    final today = _dayOf(_now());
    try {
      final ofToday = <(int, File)>[];
      for (final entry in dir.listSync()) {
        if (entry is! File) continue;
        final m = rotated.firstMatch(p.basename(entry.path));
        if (m == null) continue;
        final day = m.group(1)!;
        if (day.compareTo(oldest) < 0) {
          entry.deleteSync();
        } else if (day == today) {
          ofToday.add((int.parse(m.group(2)?.substring(1) ?? '0'), entry));
        }
      }
      ofToday.sort((a, b) => a.$1.compareTo(b.$1));
      var kept = _dayBytes;
      for (final (_, file) in ofToday.reversed) {
        kept += file.lengthSync();
      }
      for (final (_, file) in ofToday) {
        if (kept <= maxBytesPerDay) break;
        final size = file.lengthSync();
        file.deleteSync();
        kept -= size;
      }
    } on FileSystemException {
      // Tried again at the next rotation.
    }
  }

  /// Write everything buffered, then close.
  Future<void> close() async {
    if (_closed) return;
    _cut();
    await _flushed;
    if (_closed) return;
    _closed = true;
    try {
      await _file.close();
    } on FileSystemException {
      // The last rotation closed it and could not reopen; nothing left to do.
    }
  }
}

/// Writes every line to each of [sinks] (stdout and a file).
final class TeeSink implements LogSink {
  const TeeSink(this.sinks);

  final List<LogSink> sinks;

  @override
  void write(String line) {
    for (final sink in sinks) {
      sink.write(line);
    }
  }
}

/// Collects lines in memory (tests).
final class MemorySink implements LogSink {
  final List<String> lines = [];

  @override
  void write(String line) => lines.add(line);
}

const _redacted = '[redacted]';

final RegExp _secretName = RegExp(
  r'(passw|secret|token|authorization|cookie|signature|private|auth_key|'
  r'api_key|otp|phone|ciphertext|payload|credential|invite|recovery|'
  r'verification|database_url|dsn)',
  caseSensitive: false,
);

final RegExp _jwt = RegExp(
  r'^[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+$',
);
final RegExp _phone = RegExp(r'\+?\d[\d\s-]{8,}\d');
final RegExp _longOpaque = RegExp(r'^[A-Za-z0-9+/_=-]{40,}$');
final RegExp _bearer = RegExp(r'bearer\s+\S+', caseSensitive: false);
final RegExp _urlUserInfo = RegExp(r'://[^/@\s]+@');

/// Redacts a field map for logging. Field names ending in `_id` are kept
/// (account and device ids are not secret); anything secret-named or
/// secret-shaped is masked.
Map<String, Object?> redactFields(Map<String, Object?> fields) => {
  for (final e in fields.entries) e.key: _redactValue(e.key, e.value),
};

Object? _redactValue(String key, Object? value) {
  final lower = key.toLowerCase();
  final isId = lower == 'id' || lower.endsWith('_id');
  if (!isId && _secretName.hasMatch(lower)) {
    return value == null ? null : _redacted;
  }
  return switch (value) {
    final String s => redactString(s),
    final Map<String, Object?> m => redactFields(m),
    final List<Object?> l => [for (final v in l) _redactValue(key, v)],
    _ => value,
  };
}

/// Masks token-, key-, credential- and phone-shaped parts of free text.
String redactString(String value) {
  if (_jwt.hasMatch(value) || _longOpaque.hasMatch(value)) return _redacted;
  return value
      .replaceAll(_bearer, 'Bearer $_redacted')
      .replaceAll(_urlUserInfo, '://$_redacted@')
      .replaceAllMapped(_phone, (m) {
        final digits = m.group(0)!.replaceAll(RegExp(r'\D'), '');
        return digits.length >= 10
            ? '[phone…${digits.substring(digits.length - 2)}]'
            : m.group(0)!;
      });
}
