import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:helix_remote/services/log_redaction.dart';
import 'package:path_provider/path_provider.dart';

/// Persistent anomaly logger. Survives app restarts; accumulates entries across
/// sessions. Call [init] once on startup, then [error] / [warn] / [info]
/// anywhere. Call [clearLogs] after exporting to start fresh.
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  File? _logFile;
  File? _counterFile;
  Future<void> _writeChain = Future<void>.value();
  final List<String> _pendingLines = [];
  Future<void>? _scheduledFlush;
  int _sessionNumber = 0;
  String _namespace = 'helix_remote';

  static const int _maxLines = 5000;
  static const int _maxAgeDays = 7;

  Future<void> init(String namespace) async {
    _namespace = namespace;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/${namespace}_anomaly_log.txt');
      _counterFile = File('${dir.path}/${namespace}_session_counter.txt');

      int counter = 0;
      if (await _counterFile!.exists()) {
        final raw = (await _counterFile!.readAsString()).trim();
        counter = int.tryParse(raw) ?? 0;
      }
      _sessionNumber = counter + 1;
      await _counterFile!.writeAsString('$_sessionNumber');

      await _purge();
      await _append(
        '--- SESSION $_sessionNumber | ${_fmt(DateTime.now())} ---',
      );
    } catch (e) {
      debugPrint('[AppLogger] init failed: $e');
    }
  }

  Future<void> error(String tag, String message, [StackTrace? stack]) =>
      _write('ERROR', tag, message, stack);
  Future<void> warn(String tag, String message, [StackTrace? stack]) =>
      _write('WARN', tag, message, stack);
  Future<void> info(String tag, String message) =>
      _write('INFO', tag, message, null);

  Future<void> _write(
    String level,
    String tag,
    String message,
    StackTrace? stack,
  ) async {
    // Redact before anything else, so the console mirror cannot leak what the
    // file redacts - `flutter logs` and a connected IDE both see debugPrint.
    final safe = truncateForLog(redactLogLine(message));
    debugPrint('[$_namespace $level] [$tag] $safe');
    final flat = safe
        .replaceAll('\r\n', ' | ')
        .replaceAll('\r', ' | ')
        .replaceAll('\n', ' | ')
        .trim();
    final stackPart = stack != null
        ? ' | STACK: ${redactLogLine(_flattenStack(stack))}'
        : '';
    final entry =
        '[${_fmt(DateTime.now())}] [S$_sessionNumber] [$level] [$tag] $flat$stackPart';
    await _append(entry);
  }

  String _fmt(DateTime dt) {
    String p(int n) => n.toString().padLeft(2, '0');
    String ms(int n) => n.toString().padLeft(3, '0');
    return '${dt.year}-${p(dt.month)}-${p(dt.day)} '
        '${p(dt.hour)}:${p(dt.minute)}:${p(dt.second)}.${ms(dt.millisecond)}';
  }

  String _flattenStack(StackTrace stack) {
    return stack
        .toString()
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(5)
        .join(' >> ');
  }

  Future<void> _append(String line) async {
    if (_logFile == null) return;
    // Last line of defence. [_write] has already redacted, and redaction is
    // idempotent, so this costs a second pass to guarantee that anything
    // reaching the file - including a future direct caller of [_append] - has
    // been through it.
    final sanitized = redactLogLine(
      line,
    ).replaceAll('\r\n', ' | ').replaceAll('\r', ' | ').replaceAll('\n', ' | ');
    _pendingLines.add(sanitized);
    await _scheduleFlush();
  }

  /// Coalesces bursts into a single append, without weakening the ordering
  /// guarantee callers get from awaiting their log method.
  Future<void> _scheduleFlush() {
    return _scheduledFlush ??= Future<void>.delayed(
      const Duration(milliseconds: 16),
    ).then((_) async {
      try {
        while (_pendingLines.isNotEmpty) {
          final batch = List<String>.from(_pendingLines);
          _pendingLines.clear();
          _writeChain = _writeChain.then((_) async {
            try {
              await _logFile!.writeAsString(
                '${batch.join('\n')}\n',
                mode: FileMode.append,
              );
            } catch (_) {}
          });
          await _writeChain;
        }
      } finally {
        _scheduledFlush = null;
        if (_pendingLines.isNotEmpty) {
          unawaited(_scheduleFlush());
        }
      }
    });
  }

  Future<void> _purge() async {
    if (_logFile == null || !await _logFile!.exists()) return;
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: _maxAgeDays));
      final kept = ListQueue<String>();
      var lineCount = 0;
      await for (final line in _logFile!
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        lineCount++;
        if (line.startsWith('---')) {
          kept.addLast(line);
        } else {
          final m = RegExp(r'^\[(\d{4}-\d{2}-\d{2})').firstMatch(line);
          if (m == null) {
            kept.addLast(line);
          } else {
            final date = DateTime.tryParse(m.group(1)!);
            if (date == null || !date.isBefore(cutoff)) {
              kept.addLast(line);
            }
          }
        }
        if (kept.length > _maxLines) kept.removeFirst();
      }

      if (kept.length != lineCount) {
        await _logFile!.writeAsString('${kept.join('\n')}\n');
      }
    } catch (_) {}
  }

  /// Returns the log file if it exists and has content, otherwise null.
  Future<File?> getLogFile() async {
    if (_logFile == null) return null;
    try {
      if (!await _logFile!.exists()) return null;
      return (await _logFile!.length()) > 0 ? _logFile : null;
    } catch (_) {
      return null;
    }
  }

  /// Deletes the log file and writes a fresh session marker.
  Future<void> clearLogs() async {
    try {
      await _scheduledFlush;
      await _writeChain;
      if (_logFile != null && await _logFile!.exists()) {
        await _logFile!.delete();
      }
      await _append(
        '--- LOG CLEARED | SESSION $_sessionNumber | ${_fmt(DateTime.now())} ---',
      );
    } catch (_) {}
  }
}
