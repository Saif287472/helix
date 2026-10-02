import 'dart:async';
import 'dart:convert';

import 'package:helix_admin/src/api/error_text.dart';
import 'package:helix_admin/src/features/common/feature_controller.dart';

/// One server log line. The server writes JSON objects (`ts`, `level`,
/// `event`, fields) and redacts them before they leave the process; a line
/// that is not JSON is kept as text.
final class LogEntry {
  const LogEntry(this.raw, {this.level});

  final String raw;

  /// `info`, `warn` or `error` when the line says so.
  final String? level;

  factory LogEntry.parse(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) {
        final level = json['level'];
        return LogEntry(raw, level: level is String ? level : null);
      }
    } on FormatException {
      // Plain text.
    }
    return LogEntry(raw);
  }

  bool get isError => level == 'error';
  bool get isWarning => level == 'warn' || level == 'warning';
}

/// How new lines reach the screen.
enum LogFeed {
  /// The tail was fetched once; nothing arrives by itself.
  paused,

  /// A WebSocket pushes new lines.
  live,

  /// The socket is not available (a browser, or it dropped): the tail is
  /// fetched again every few seconds.
  polling,
}

/// The server's recent log lines, optionally followed live. The lines are
/// already redacted by the server; this controller keeps at most [maxLines]
/// in memory and never writes them anywhere.
final class LogsController extends FeatureController {
  LogsController(
    super.ctx, {
    this.pollInterval = const Duration(seconds: 3),
    this.maxLines = 1000,
    this.tail = 200,
  });

  final Duration pollInterval;
  final int maxLines;
  final int tail;

  List<LogEntry> _lines = const [];
  String _filter = '';
  bool _loading = false;
  String? _error;
  String? _feedNote;
  LogFeed _feed = LogFeed.paused;

  StreamSubscription<String>? _sub;
  Timer? _poll;
  bool _polling = false;

  List<LogEntry> get lines => _lines;
  String get filter => _filter;
  bool get loading => _loading;

  /// The tail could not be fetched.
  String? get error => _error;

  /// Why the live feed fell back to polling.
  String? get feedNote => _feedNote;
  LogFeed get feed => _feed;

  /// The lines matching [filter] (case-insensitive), oldest first.
  List<LogEntry> get shown {
    final needle = _filter.trim().toLowerCase();
    if (needle.isEmpty) return _lines;
    return [
      for (final l in _lines)
        if (l.raw.toLowerCase().contains(needle)) l,
    ];
  }

  void setFilter(String value) {
    _filter = value;
    notifyListeners();
  }

  /// Fetches the recent tail, replacing what is shown.
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final recent = await ctx.api.admin.logs(limit: tail);
      if (isDisposed) return;
      _lines = [for (final l in recent.lines) LogEntry.parse(l)];
    } on Object catch (e) {
      if (isDisposed) return;
      ctx.report(e);
      _error = describeAdminError(e, now: ctx.now);
    }
    _loading = false;
    notifyListeners();
  }

  /// Follows the log live; off stops following (the lines stay).
  Future<void> setLive(bool on) async {
    _stop();
    _feedNote = null;
    if (!on) {
      _feed = LogFeed.paused;
      notifyListeners();
      return;
    }
    _feed = LogFeed.live;
    notifyListeners();
    _sub = ctx.api.admin.logStream().listen(
      _append,
      onError: (Object e) {
        ctx.report(e);
        _fallBack(describeAdminError(e, now: ctx.now));
      },
      onDone: () => _fallBack('The live connection closed.'),
      cancelOnError: true,
    );
  }

  void _append(String line) {
    final next = [..._lines, LogEntry.parse(line)];
    _lines = next.length > maxLines
        ? next.sublist(next.length - maxLines)
        : next;
    notifyListeners();
  }

  void _fallBack(String why) {
    if (isDisposed || _feed != LogFeed.live) return;
    _sub = null;
    _feed = LogFeed.polling;
    _feedNote = '$why Reloading every ${pollInterval.inSeconds} seconds.';
    _poll = Timer.periodic(pollInterval, (_) => _pollOnce());
    notifyListeners();
    unawaited(_pollOnce());
  }

  Future<void> _pollOnce() async {
    if (_polling || isDisposed) return;
    _polling = true;
    try {
      final recent = await ctx.api.admin.logs(limit: tail);
      if (!isDisposed && _feed == LogFeed.polling) {
        _lines = [for (final l in recent.lines) LogEntry.parse(l)];
        notifyListeners();
      }
    } on Object catch (e) {
      ctx.report(e);
    } finally {
      _polling = false;
    }
  }

  /// Stops the socket and the polling. Closing the socket is left to finish
  /// by itself: the switch must not wait for the network.
  void _stop() {
    _poll?.cancel();
    _poll = null;
    final sub = _sub;
    _sub = null;
    unawaited(sub?.cancel());
  }

  @override
  void dispose() {
    _poll?.cancel();
    unawaited(_sub?.cancel());
    super.dispose();
  }
}
