import 'dart:async';
import 'dart:convert';

import 'package:helix_remote_server/src/platform/db/db.dart';

/// Cross-node notifications (ADR-025): small, best-effort hints such as
/// "device X has mail" or "device Y was revoked". Anything that must not be
/// lost goes through the outbox instead; a missed hint only delays work
/// until the next poll or reconnect.
abstract interface class EventBus {
  /// Delivers [message] to every subscriber of [topic] on every node,
  /// including this one.
  Future<void> publish(String topic, Map<String, Object?> message);

  Stream<Map<String, Object?>> subscribe(String topic);

  /// Completes once this node receives messages published from now on.
  Future<void> get ready;

  Future<void> close();
}

/// Single-process bus (tests, single-node dev runs).
final class InMemoryEventBus implements EventBus {
  final Map<String, StreamController<Map<String, Object?>>> _topics = {};

  StreamController<Map<String, Object?>> _topic(String name) =>
      _topics.putIfAbsent(name, StreamController.broadcast);

  @override
  Future<void> publish(String topic, Map<String, Object?> message) async {
    _topic(topic).add(message);
  }

  @override
  Stream<Map<String, Object?>> subscribe(String topic) => _topic(topic).stream;

  @override
  Future<void> get ready async {}

  @override
  Future<void> close() async {
    for (final c in _topics.values) {
      await c.close();
    }
  }
}

/// Bus over Postgres `LISTEN/NOTIFY`: one channel per deployment (the schema
/// prefix keeps test runs apart), JSON payloads `{"t": topic, "m": message}`.
/// Payloads are limited to [maxPayloadBytes] (Postgres allows 8,000).
final class PostgresEventBus implements EventBus {
  PostgresEventBus(this._db, {String prefix = ''})
    : _channel = '${prefix}helix_bus';

  static const maxPayloadBytes = 7900;

  final Db _db;
  final String _channel;
  final Map<String, StreamController<Map<String, Object?>>> _topics = {};
  StreamSubscription<String>? _subscription;
  Future<void>? _listening;

  @override
  Future<void> get ready => _listening ??= _db.listen(_channel).then((stream) {
    _subscription = stream.listen(_deliver);
  });

  void _deliver(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      final topic = decoded['t']! as String;
      final message = (decoded['m']! as Map).cast<String, Object?>();
      _topics[topic]?.add(message);
    } on Object {
      // A malformed notification is dropped; the bus carries only hints.
    }
  }

  @override
  Future<void> publish(String topic, Map<String, Object?> message) async {
    final payload = jsonEncode({'t': topic, 'm': message});
    if (utf8.encode(payload).length > maxPayloadBytes) {
      throw ArgumentError(
        'bus message on "$topic" is too large; use the outbox',
      );
    }
    await _db.notify(_channel, payload);
  }

  @override
  Stream<Map<String, Object?>> subscribe(String topic) {
    final controller = _topics.putIfAbsent(topic, StreamController.broadcast);
    unawaited(ready);
    return controller.stream;
  }

  @override
  Future<void> close() async {
    try {
      await _listening;
    } on Object {
      // Closing anyway.
    }
    await _subscription?.cancel();
    for (final c in _topics.values) {
      await c.close();
    }
  }
}
