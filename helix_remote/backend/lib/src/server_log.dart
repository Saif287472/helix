import 'dart:collection';
import 'dart:io';

import 'package:helix_remote_backend/src/redacted_logger.dart';

/// Severity tag attached to each captured console line.
enum ServerLogLevel { info, warn, error }

/// Central sink for the server's own console output, so the admin console's
/// Logs screen has something to tail.
///
/// Before this existed, `/api/v1/ops/logs` read `HELIX_REMOTE_LOG_FILE`
/// directly - but nothing in the server ever *wrote* that file. All output
/// went to stdout/stderr (where Docker collects it), so the endpoint always
/// found a missing file and the Logs screen was permanently empty on every
/// deployment, including one that had set HELIX_REMOTE_LOG_FILE exactly as
/// .env.example instructs.
///
/// Everything recorded here is still forwarded to stdout/stderr, so
/// `docker compose logs` keeps working unchanged - this only *adds* an
/// in-process copy (and an optional on-disk one).
class ServerLogSink {
  ServerLogSink({
    this.capacity = 500,
    this.filePath,
    this.maxFileBytes = 5 * 1024 * 1024,
    DateTime Function()? now,
    IOSink? stdoutSink,
    IOSink? stderrSink,
  }) : _now = now ?? DateTime.now,
       _stdout = stdoutSink ?? stdout,
       _stderr = stderrSink ?? stderr;

  /// How many lines the in-memory ring buffer keeps. This is the only
  /// source of logs when no file is configured, so it has to be large
  /// enough to be useful on its own.
  final int capacity;

  /// Optional on-disk copy. Unlike the ring buffer this survives restarts,
  /// which is the whole reason an operator would configure it.
  final String? filePath;

  /// Size at which the log file is rotated to `<path>.1`. Without this a
  /// long-lived server would fill the data volume.
  final int maxFileBytes;

  final DateTime Function() _now;
  final IOSink _stdout;
  final IOSink _stderr;

  final Queue<String> _buffer = Queue<String>();

  /// Set once the file turns out to be unwritable (read-only volume, bad
  /// path, permissions). Reported through [fileError] so the admin console
  /// can explain itself instead of silently showing nothing, and latched so
  /// one bad path doesn't produce a write attempt per log line forever.
  String? _fileError;
  IOSink? _fileSink;
  int _fileBytes = 0;
  bool _fileReady = false;

  String? get fileError => _fileError;

  /// Whether lines are actually reaching [filePath] right now.
  bool get fileActive => _fileReady && _fileError == null;

  void info(String message) => record(message, level: ServerLogLevel.info);

  void warn(String message) => record(message, level: ServerLogLevel.warn);

  void error(String message) => record(message, level: ServerLogLevel.error);

  /// Records [message], forwarding it to the console as well.
  ///
  /// Multi-line input (stack traces, mostly) is split so the buffer stays
  /// strictly line-oriented - the admin console renders one entry per row,
  /// and an embedded newline would otherwise blow out a single row.
  void record(String message, {ServerLogLevel level = ServerLogLevel.info}) {
    final timestamp = _now().toUtc().toIso8601String();
    final tag = level.name.toUpperCase();
    for (final line in redactSecrets(message).split('\n')) {
      // Keep blank lines out of the buffer: the startup banner prints
      // several, and they'd crowd out real content in a capped buffer.
      if (line.trim().isEmpty) continue;
      _append('$timestamp [$tag] $line');
    }
    // The console copy keeps the original formatting, since Docker log
    // collection and a human watching `docker compose logs` both expect
    // the banner to look the way it always has.
    final console = level == ServerLogLevel.error ? _stderr : _stdout;
    try {
      console.writeln(redactSecrets(message));
    } catch (_) {
      // A closed or broken stdout must never take the server down.
    }
  }

  void _append(String line) {
    _buffer.addLast(line);
    while (_buffer.length > capacity) {
      _buffer.removeFirst();
    }
    _writeToFile(line);
  }

  /// The most recent [limit] lines, oldest first.
  List<String> tail(int limit) {
    if (limit <= 0) return const [];
    final lines = _buffer.toList(growable: false);
    if (lines.length <= limit) return lines;
    return lines.sublist(lines.length - limit);
  }

  int get bufferedLineCount => _buffer.length;

  void _writeToFile(String line) {
    final path = filePath;
    if (path == null || path.isEmpty || _fileError != null) return;
    try {
      if (!_fileReady) _openFile(path);
      final sink = _fileSink;
      if (sink == null) return;
      final bytes = line.length + 1;
      if (_fileBytes + bytes > maxFileBytes) {
        _rotate(path);
      }
      _fileSink!.writeln(line);
      _fileBytes += bytes;
    } catch (e) {
      // Latch the failure rather than retrying per line - a read-only
      // volume would otherwise throw on every single log write.
      _fileError = 'Could not write log file at $path: $e';
      _closeFileQuietly();
    }
  }

  void _openFile(String path) {
    final file = File(path);
    final parent = file.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    _fileBytes = file.existsSync() ? file.lengthSync() : 0;
    _fileSink = file.openWrite(mode: FileMode.append);
    _fileReady = true;
  }

  void _rotate(String path) {
    _closeFileQuietly();
    final file = File(path);
    if (file.existsSync()) {
      final previous = File('$path.1');
      if (previous.existsSync()) previous.deleteSync();
      file.renameSync('$path.1');
    }
    _fileBytes = 0;
    _fileSink = File(path).openWrite(mode: FileMode.append);
    _fileReady = true;
  }

  void _closeFileQuietly() {
    try {
      _fileSink?.close();
    } catch (_) {
      // Nothing useful to do - we're already on an error path.
    }
    _fileSink = null;
    _fileReady = false;
  }

  Future<void> dispose() async {
    final sink = _fileSink;
    _fileSink = null;
    _fileReady = false;
    if (sink == null) return;
    try {
      await sink.flush();
      await sink.close();
    } catch (_) {
      // Best effort - shutdown must not fail on a log flush.
    }
  }
}

/// Process-wide sink used by library code that has no route back to the
/// [BackendServer] instance (the WebSocket relay, outbox worker and calls
/// module all log from timers and stream callbacks).
///
/// Null until an entrypoint installs one, so tests and CLI tools that never
/// call [installServerLog] keep writing straight to stderr as before.
ServerLogSink? _activeServerLog;

ServerLogSink? get activeServerLog => _activeServerLog;

void installServerLog(ServerLogSink sink) => _activeServerLog = sink;

/// Only used by tests, to keep a sink from leaking between cases.
void resetServerLogForTesting() => _activeServerLog = null;

/// Logs an error from library code: captured for the admin console when a
/// sink is installed, and written to stderr either way.
void logServerError(String message) {
  final sink = _activeServerLog;
  if (sink != null) {
    sink.error(message);
    return;
  }
  stderr.writeln(message);
}

/// Logs a warning from library code. See [logServerError].
void logServerWarning(String message) {
  final sink = _activeServerLog;
  if (sink != null) {
    sink.warn(message);
    return;
  }
  stderr.writeln(message);
}

/// Logs an informational line from library code. See [logServerError].
void logServerInfo(String message) {
  final sink = _activeServerLog;
  if (sink != null) {
    sink.info(message);
    return;
  }
  stdout.writeln(message);
}
