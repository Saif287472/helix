import 'dart:collection';
import 'dart:convert';
import 'dart:io';

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
    _ring.addLast(line);
    while (_ring.length > _ringSize) {
      _ring.removeFirst();
    }
  }

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
