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
/// [FileSystemException]) if the file cannot be written. Writes are
/// synchronous, so a rotation never splits a line; a failed write or
/// rotation never reaches the caller (stdout still has the line).
final class FileSink implements LogSink {
  FileSink._(this.path, this.keepDays, this._now, this._file, this._day);

  static FileSink open(
    String path, {
    int keepDays = 14,
    DateTime Function()? now,
  }) {
    final clock = now ?? () => DateTime.now().toUtc();
    final file = File(path);
    final today = _dayOf(clock());
    if (file.existsSync() && file.lengthSync() > 0) {
      final day = _dayOf(file.lastModifiedSync().toUtc());
      if (day != today) _rotate(path, day);
    }
    // Fails now, not on the first write, if the path is unusable.
    final sink = FileSink._(
      path,
      keepDays,
      clock,
      file.openSync(mode: FileMode.append),
      today,
    );
    sink._prune();
    return sink;
  }

  final String path;
  final int keepDays;
  final DateTime Function() _now;
  RandomAccessFile _file;
  String _day;
  bool _closed = false;

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
    final today = _dayOf(_now());
    if (today != _day) {
      try {
        _file.closeSync();
        _rotate(path, _day);
      } on FileSystemException {
        // Keep writing to the one file; the next day tries again.
      }
      _day = today;
      try {
        _file = File(path).openSync(mode: FileMode.append);
      } on FileSystemException {
        _closed = true;
        return;
      }
      _prune();
    }
    try {
      _file.writeStringSync('$line\n');
    } on FileSystemException {
      // A full disk loses the file copy of the line, not the request.
    }
  }

  /// Deletes rotated files of this log older than [keepDays].
  void _prune() {
    final dir = Directory(p.dirname(path));
    final stem = RegExp.escape(p.basenameWithoutExtension(path));
    final ext = RegExp.escape(p.extension(path));
    final rotated = RegExp('^$stem-(\\d{4}-\\d{2}-\\d{2})(\\.\\d+)?$ext\$');
    final oldest = _dayOf(_now().subtract(Duration(days: keepDays)));
    try {
      for (final entry in dir.listSync()) {
        if (entry is! File) continue;
        final m = rotated.firstMatch(p.basename(entry.path));
        if (m != null && m.group(1)!.compareTo(oldest) < 0) entry.deleteSync();
      }
    } on FileSystemException {
      // Tried again at the next rotation.
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _file.closeSync();
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
