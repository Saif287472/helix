// lib/services/app_logger.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persistent anomaly logger. Survives app restarts; accumulates entries across
/// sessions. Call [init] once on startup, then [error] / [warn] anywhere.
/// Call [clearLogs] after exporting to start fresh.
class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  File? _logFile;
  File? _counterFile;
  int _sessionNumber = 0;

  static const int _maxLines = 5000;
  static const int _maxAgeDays = 7;

  Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/helix_anomaly_log.txt');
      _counterFile = File('${dir.path}/helix_session_counter.txt');

      int counter = 0;
      if (await _counterFile!.exists()) {
        final raw = (await _counterFile!.readAsString()).trim();
        counter = int.tryParse(raw) ?? 0;
      }
      _sessionNumber = counter + 1;
      await _counterFile!.writeAsString('$_sessionNumber');

      await _purge();
      await _append('--- SESSION $_sessionNumber | ${_fmt(DateTime.now())} ---');
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
      String level, String tag, String message, StackTrace? stack) async {
    debugPrint('[Helix $level] [$tag] $message');
    final flat = message.replaceAll('\r\n', ' | ').replaceAll('\n', ' | ').trim();
    final stackPart =
        stack != null ? ' | STACK: ${_flattenStack(stack)}' : '';
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
    try {
      await _logFile!.writeAsString('$line\n', mode: FileMode.append);
    } catch (_) {}
  }

  Future<void> _purge() async {
    if (_logFile == null || !await _logFile!.exists()) return;
    try {
      final lines = await _logFile!.readAsLines();
      final cutoff = DateTime.now().subtract(const Duration(days: _maxAgeDays));

      final kept = lines.where((line) {
        if (line.startsWith('---')) return true;
        final m = RegExp(r'^\[(\d{4}-\d{2}-\d{2})').firstMatch(line);
        if (m == null) return true;
        final date = DateTime.tryParse(m.group(1)!);
        if (date == null) return true;
        return !date.isBefore(cutoff);
      }).toList();

      final trimmed =
          kept.length > _maxLines ? kept.sublist(kept.length - _maxLines) : kept;

      if (trimmed.length != lines.length) {
        await _logFile!.writeAsString('${trimmed.join('\n')}\n');
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
      if (_logFile != null && await _logFile!.exists()) {
        await _logFile!.delete();
      }
      await _append('--- LOG CLEARED | SESSION $_sessionNumber | ${_fmt(DateTime.now())} ---');
    } catch (_) {}
  }
}
