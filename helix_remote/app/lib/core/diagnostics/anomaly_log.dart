import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/platform/app_info.dart';
import 'package:helix_remote_api/v2.dart'
    show
        ApiException,
        NetworkException,
        RequestCancelledException,
        RequestFailure,
        SignedOutException;
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show NotSignedInException;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show Anomaly, AnomalyReport, Routes;

/// The app's anomaly log: what went wrong on this device, sent to the server
/// in batches, where the operator sees each entry as a `client_anomaly` line
/// in the server's log (`server/tool/anomalies.dart` shows them).
///
/// Four kinds: `crash` (an uncaught error), `failure` (an action that failed
/// with something other than a refused request or being offline), `request`
/// (a request the server refused: its route template, status, code and
/// request id) and `state` (something that should not happen).
///
/// Every build sends it, with no opt-in (the owner's decision, 2026-10-21).
/// A debug build sends whole messages and stacks; a release build trims the
/// message and keeps only the app's own stack frames. Every build masks
/// phone numbers, e-mail addresses, tokens and key-shaped text, and nothing
/// here is ever given message content: callers pass errors, not data.
///
/// Entries wait in memory (at most [maxQueued]; the oldest go first, and how
/// many a burst pushed out is reported once something is sent) until the
/// device has a session, so errors from before sign-in are sent after it.
/// An entry belongs to the server that was open when it was seen, and only
/// that server is sent it: what went wrong in a session on one operator's
/// server never reaches another's. What was seen before any session exists is
/// given to the first server that has one ([install]'s `server`). Entries for
/// a server that is not open wait their turn.
/// The same anomaly again within [repeatWindow] only counts up.
abstract final class AnomalyLog {
  static const maxQueued = 200;
  static const flushEvery = Duration(seconds: 20);
  static const repeatWindow = Duration(minutes: 1);

  /// Full detail, as a debug build sends it.
  static bool fullDetail = kDebugMode;
  static DateTime Function() now = DateTime.now;

  static final List<_Entry> _queue = [];
  static Future<void> Function(AnomalyReport report)? _send;
  static Timer? _timer;

  /// Whether [_timer] is the short one a crash asks for.
  static bool _timerSoon = false;

  /// How long a crash may wait before it is sent.
  static const soonAfter = Duration(seconds: 2);
  static bool _sending = false;
  static String? Function()? _serverOf;

  /// The server a batch is being sent to, for as long as [flush] is sending
  /// it: the sender checks that the session it uses is that server's.
  static String? flushingServer;
  static int _dropped = 0;

  /// What is waiting to be sent, oldest first.
  static List<Anomaly> get queued => [for (final e in _queue) e.toAnomaly()];

  /// Whether the log has a way out. A short-lived isolate checks this before
  /// giving the log its own route, so it never takes the place of the sender
  /// the running app installed.
  static bool get hasSender => _send != null;

  /// An uncaught error.
  static void crash(Object error, StackTrace? stack) => record(
    'crash',
    error.runtimeType.toString(),
    message: '$error',
    stack: stack,
    soon: true,
  );

  /// An error the framework caught. A layout overflow has no stack, so the
  /// widget it blames (a debug build names its file and line) and what the
  /// framework was doing are what say where it happened.
  static void flutterError(FlutterErrorDetails details) {
    final during = details.context?.toDescription() ?? '';
    final widget = culpritOf(details.toString());
    record(
      'crash',
      details.exception.runtimeType.toString(),
      message: '${details.exception}',
      stack: details.stack,
      fields: {if (during.isNotEmpty) 'during': during, 'widget': ?widget},
      soon: true,
    );
  }

  static final _culprit = RegExp(
    r'The relevant error-causing widget was:?\s+(\S+)\s+\S*?([\w.-]+\.dart):(\d+)',
  );

  /// The widget a framework error report blames, as `Type file.dart:line`
  /// (the file's name only: a whole path would be masked as a token).
  @visibleForTesting
  static String? culpritOf(String report) {
    final m = _culprit.firstMatch(report);
    return m == null ? null : '${m[1]} ${m[2]}:${m[3]}';
  }

  /// An action that failed. Refused requests (reported by the API's
  /// observer), being offline, being signed out and a cancel are expected
  /// and skipped.
  static void failure(Object error, {StackTrace? stack}) {
    if (error is ApiException ||
        error is NetworkException ||
        error is SignedOutException ||
        error is NotSignedInException ||
        error is RequestCancelledException) {
      return;
    }
    record(
      'failure',
      error.runtimeType.toString(),
      message: '$error',
      stack: stack ?? StackTrace.current,
    );
  }

  /// A request the server refused (the API transport's observer). The
  /// anomaly route itself is never reported, so a failing send cannot
  /// report itself.
  static void request(RequestFailure f) {
    if (f.route == Routes.anomalies) return;
    record(
      'request',
      '${f.route.method.name.toUpperCase()} ${f.route.path}',
      message: f.code,
      fields: {'status': '${f.status}', 'request_id': f.requestId},
    );
  }

  /// Something that should not happen.
  static void state(
    String where,
    String message, {
    Map<String, String> fields = const {},
  }) => record('state', where, message: message, fields: fields);

  /// Adds one entry. Never throws and never waits.
  static void record(
    String kind,
    String where, {
    String message = '',
    StackTrace? stack,
    Map<String, String> fields = const {},
    bool soon = false,
  }) {
    try {
      final at = now();
      final text = _message(message);
      final server = _serverOf?.call();
      for (final e in _queue.reversed) {
        if (at.difference(e.lastAt) > repeatWindow) break;
        if (e.kind == kind &&
            e.where == where &&
            e.message == text &&
            e.server == server) {
          e.count++;
          e.lastAt = at;
          _schedule(soon: soon);
          return;
        }
      }
      _queue.add(
        _Entry(
          at: at,
          kind: kind,
          where: mask(where),
          message: text,
          stack: stack == null ? '' : _stack(stack),
          fields: {for (final f in fields.entries) f.key: mask(f.value)},
          server: server,
        ),
      );
      while (_queue.length > maxQueued) {
        _queue.removeAt(0);
        _dropped++;
      }
      _schedule(soon: soon);
    } on Object {
      // The log must never be the thing that breaks.
    }
  }

  /// Sends what is queued, a batch at a time. Entries that could not be sent
  /// stay for the next try.
  static Future<void> flush() async {
    final send = _send;
    if (send == null || _sending || _queue.isEmpty) return;
    String? server;
    if (_serverOf != null) {
      server = _serverOf!();
      // No session, so no server to tell: everything waits.
      if (server == null) return;
      // What was seen before there was a session belongs to the first server
      // that has one.
      for (final e in _queue) {
        e.server ??= server;
      }
    }
    _sending = true;
    try {
      while (true) {
        final batch = [
          for (final e in _queue)
            if (_serverOf == null || e.server == server) e,
        ].take(AnomalyReport.maxEntries).toList();
        if (batch.isEmpty) break;
        flushingServer = server;
        await send(
          AnomalyReport(
            appVersion: kAppVersion,
            platform: defaultTargetPlatform.name,
            debug: fullDetail,
            entries: [for (final e in batch) e.toAnomaly()],
          ),
        );
        _queue.removeWhere(batch.contains);
        _noteDropped();
      }
    } on Object {
      // Offline or signed out: kept for the next try.
    } finally {
      flushingServer = null;
      _sending = false;
    }
  }

  /// A burst that overflowed the queue lost its oldest entries; once
  /// something has gone out, say how many, from the front of what is left.
  static void _noteDropped() {
    final dropped = _dropped;
    if (dropped == 0) return;
    _dropped = 0;
    _queue.insert(
      0,
      _Entry(
        at: now(),
        kind: 'state',
        where: 'diagnostics.queue',
        message: 'entries dropped',
        stack: '',
        server: _serverOf?.call(),
        fields: {'dropped': '$dropped'},
      ),
    );
  }

  /// A crash brings the next send forward to [soonAfter] from the first one,
  /// and never pushes it back: a crash that recurs faster than that (a widget
  /// that throws in every frame) used to restart the wait on each repeat and
  /// so postponed its own report for as long as it went on (AUD-14h-1).
  static void _schedule({bool soon = false}) {
    if (_send == null) return;
    if (soon) {
      if (_timer != null && _timerSoon) return;
      _timer?.cancel();
      _timerSoon = true;
      _timer = Timer(soonAfter, _tick);
      return;
    }
    if (_timer != null) return;
    _timerSoon = false;
    _timer = Timer(flushEvery, _tick);
  }

  static void _tick() {
    _timer = null;
    _timerSoon = false;
    unawaited(
      flush().whenComplete(() {
        if (_queue.isNotEmpty) _schedule();
      }),
    );
  }

  static String _message(String message) {
    final masked = mask(message);
    final max = fullDetail ? Anomaly.maxMessageLength : 300;
    return masked.length > max ? '${masked.substring(0, max)}…' : masked;
  }

  /// A debug build keeps the whole stack; a release build keeps the app's
  /// own frames (Helix and Orbit packages), at most 12.
  static String _stack(StackTrace stack) {
    final lines = stack.toString().split('\n').where((l) => l.isNotEmpty);
    final kept = fullDetail
        ? lines.take(60)
        : lines
              .where(
                (l) =>
                    l.contains('package:helix_remote') ||
                    l.contains('package:orbit_ui'),
              )
              .take(12);
    final text = mask(kept.join('\n'));
    return text.length > Anomaly.maxStackLength
        ? text.substring(0, Anomaly.maxStackLength)
        : text;
  }

  static final _jwt = RegExp(
    r'[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{6,}',
  );
  static final _opaque = RegExp(r'[A-Za-z0-9+/_=-]{32,}');
  static final _bearer = RegExp(r'bearer\s+\S+', caseSensitive: false);
  static final _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');
  static final _phone = RegExp(r'\+?\d[\d\s-]{7,}\d');

  /// Masks token-, key-, e-mail- and phone-shaped text (a phone keeps its
  /// last two digits).
  static String mask(String text) => text
      .replaceAll(_bearer, 'Bearer [redacted]')
      .replaceAll(_jwt, '[token]')
      .replaceAll(_opaque, '[redacted]')
      .replaceAll(_email, '[email]')
      .replaceAllMapped(_phone, (m) {
        final digits = m.group(0)!.replaceAll(RegExp(r'\D'), '');
        return digits.length >= 9
            ? '[phone…${digits.substring(digits.length - 2)}]'
            : m.group(0)!;
      });

  /// Gives the log its way out, and takes it away again when passed null.
  ///
  /// The app does this once at start ([anomalyLogInstallProvider]) and a
  /// one-pass isolate for as long as it lives ([hasSender] says whether
  /// anyone already has). What was recorded before a sender exists waits for
  /// the next [flush].
  ///
  /// [server] names the server the sender talks to now (null while there is no
  /// session); with it, every entry is tagged with the server it was seen under
  /// and sent only there. Without it the log is not split by server.
  static void install(
    Future<void> Function(AnomalyReport report)? send, {
    String? Function()? server,
  }) {
    _send = send;
    _serverOf = send == null ? null : server;
    _timer?.cancel();
    _timer = null;
    _timerSoon = false;
    if (send != null && _queue.isNotEmpty) _schedule();
  }

  /// What the log calls a server: scheme, host and port, so two spellings of
  /// one address are one server and a path never matters.
  static String serverKey(Uri url) =>
      '${url.scheme.toLowerCase()}://${url.host.toLowerCase()}:${url.port}';

  @visibleForTesting
  static void resetForTest() {
    _queue.clear();
    _send = null;
    _timer?.cancel();
    _timer = null;
    _timerSoon = false;
    _sending = false;
    _serverOf = null;
    flushingServer = null;
    _dropped = 0;
    fullDetail = kDebugMode;
    now = DateTime.now;
  }
}

final class _Entry {
  _Entry({
    required this.at,
    required this.kind,
    required this.where,
    required this.message,
    required this.stack,
    required this.fields,
    this.server,
  }) : lastAt = at;

  final DateTime at;
  final String kind;
  final String where;
  final String message;
  final String stack;
  final Map<String, String> fields;

  /// The server this was seen under; null before there was a session.
  String? server;
  DateTime lastAt;
  int count = 1;

  Anomaly toAnomaly() => Anomaly(
    at: at,
    kind: kind,
    where: where,
    message: message,
    stack: stack,
    fields: {...fields, if (count > 1) 'repeats': '$count'},
  );
}

/// Connects [AnomalyLog] to this device's server. Read once when the app
/// starts; what was recorded before then is sent once a session exists.
///
/// What was seen under one server is sent to that server only, whichever
/// account is open when the send happens (an account of another operator's
/// server never receives it); [AnomalyLog] keeps the entries of a server that
/// is not open until it is.
final anomalyLogInstallProvider = Provider<void>((ref) {
  String? openServer() {
    final runtime = ref.read(runtimeProvider).value;
    return runtime == null ? null : AnomalyLog.serverKey(runtime.serverUrl);
  }

  AnomalyLog.install((report) async {
    final runtime = await ref.read(runtimeProvider.future);
    // An account switch between choosing the batch and sending it must not
    // carry it to the other server.
    if (AnomalyLog.serverKey(runtime.serverUrl) != AnomalyLog.flushingServer) {
      throw StateError('the open server changed');
    }
    await runtime.api.ops.anomalies(report);
  }, server: openServer);
  ref.onDispose(() => AnomalyLog.install(null));
});
