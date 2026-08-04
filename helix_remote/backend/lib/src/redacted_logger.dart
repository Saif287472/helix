import 'dart:convert';

enum LogSeverity { debug, info, warning, error }

final class RedactedLogRecord {
  const RedactedLogRecord({
    required this.severity,
    required this.message,
    required this.fields,
    required this.timestamp,
    this.correlationId,
  });

  final LogSeverity severity;
  final String message;
  final Map<String, Object?> fields;
  final DateTime timestamp;
  final String? correlationId;

  String toJsonLine() {
    return jsonEncode({
      'severity': severity.name,
      'message': message,
      'timestamp': timestamp.toUtc().toIso8601String(),
      if (correlationId != null) 'correlation_id': correlationId,
      'fields': fields,
    });
  }
}

final class RedactedLogger {
  RedactedLogger({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final List<RedactedLogRecord> _records = [];

  List<RedactedLogRecord> get records => List.unmodifiable(_records);

  RedactedLogRecord log(
    LogSeverity severity,
    String message, {
    Map<String, Object?> fields = const {},
    String? correlationId,
  }) {
    final record = RedactedLogRecord(
      severity: severity,
      message: _redactText(message),
      fields: _redactMap(fields),
      timestamp: _now(),
      correlationId: correlationId,
    );
    _records.add(record);
    return record;
  }

  Map<String, Object?> _redactMap(Map<String, Object?> input) {
    return {
      for (final entry in input.entries)
        entry.key: _sensitiveKey(entry.key)
            ? 'redacted'
            : _redactValue(entry.value),
    };
  }

  Object? _redactValue(Object? value) {
    if (value is Map<String, Object?>) return _redactMap(value);
    if (value is Iterable) return value.map(_redactValue).toList();
    if (value is String) return _redactText(value);
    return value;
  }

  String _redactText(String value) => redactSecrets(value);

  bool _sensitiveKey(String key) {
    final lower = key.toLowerCase();
    return const {
      'token',
      'authorization',
      'password',
      'secret',
      'key',
      'ciphertext',
      'plaintext',
      'message_text',
      'body',
      'content',
      'filename',
      'backup_key',
      'passphrase',
      'recovery_phrase',
    }.any(lower.contains);
  }
}

/// Strips bearer tokens and JWTs out of free-form text.
///
/// Shared with [ServerLogSink] so that console output captured for the admin
/// console's Logs screen gets the same treatment as structured log records -
/// those lines are served over the admin API and written to disk, so a
/// stray `Authorization:` header echoed into an error message must not
/// survive into either.
String redactSecrets(String value) {
  var redacted = value;
  for (final pattern in _secretPatterns) {
    redacted = redacted.replaceAll(pattern, '[redacted]');
  }
  return redacted;
}

final _secretPatterns = <RegExp>[
  RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+'),
  RegExp(r'eyJ[A-Za-z0-9._~+/=-]+'),
];
