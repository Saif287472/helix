import 'dart:async';

import 'package:helix_admin/src/api/error_text.dart';
import 'package:helix_admin/src/features/common/feature_controller.dart';
import 'package:helix_admin/src/features/dashboard/metrics_summary.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The server's state: configuration, feature flags, health and the metrics
/// summary. The dashboard shows it and flips the switches; Settings renames
/// the server and purges. The shell keeps one for the whole session so the
/// title and the Invites tab follow the server's own answers.
final class ServerController extends FeatureController {
  ServerController(super.ctx);

  AdminConfig? _config;
  Map<String, bool> _flags = const {};
  ReadyResponse? _ready;
  MetricsSummary? _metrics;
  int? _latencyMs;

  bool _loading = false;
  String? _error;
  String? _flagsNote;
  String? _healthNote;
  String? _metricsNote;
  final Set<String> _busy = {};

  AdminConfig? get config => _config;

  /// Feature flags by name, in the server's order.
  Map<String, bool> get flags => _flags;

  /// Null when the health check could not be asked; see [healthNote].
  ReadyResponse? get ready => _ready;
  MetricsSummary? get metrics => _metrics;

  /// How long the last readiness check took to answer, in milliseconds; null
  /// before the first answer or when the server could not be reached.
  int? get latencyMs => _latencyMs;

  /// The server could not be asked at all (no readiness answer and no
  /// configuration).
  bool get offline => _ready == null && _config == null && _error != null;

  bool get loading => _loading;

  /// The configuration could not be loaded (and none was loaded before).
  String? get error => _error;

  String? get flagsNote => _flagsNote;
  String? get healthNote => _healthNote;
  String? get metricsNote => _metricsNote;

  /// Whether an action named [key] (`maintenance`, `federation`,
  /// `flag:<name>`, `name`, `purge`) is running.
  bool isBusy(String key) => _busy.contains(key);

  /// Helix Global signs people up by phone number; invite codes only matter
  /// on servers that register by invite.
  bool get usesInvites {
    final mode = _config?.registration;
    return mode == null || mode != RegistrationMode.phone;
  }

  /// Reloads everything. The four reads are independent: one failing leaves
  /// a note instead of hiding the rest.
  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    Object? configError;
    await Future.wait([
      _read(() async => _config = await ctx.api.admin.config(), (e) {
        configError = e;
      }),
      _read(
        () async => _flags = (await ctx.api.admin.featureFlags()).flags,
        (e) => _flagsNote = describeAdminError(e, now: ctx.now),
        clear: () => _flagsNote = null,
      ),
      _read(
        () async {
          final clock = Stopwatch()..start();
          _ready = await ctx.api.ops.ready();
          _latencyMs = clock.elapsedMilliseconds;
        },
        (e) {
          _ready = null;
          _latencyMs = null;
          _healthNote = describeAdminError(e, now: ctx.now);
        },
        clear: () => _healthNote = null,
      ),
      _read(
        () async =>
            _metrics = MetricsSummary.parse(await ctx.api.admin.metrics()),
        (e) {
          _metrics = null;
          _metricsNote = describeAdminError(e, now: ctx.now);
        },
        clear: () => _metricsNote = null,
      ),
    ]);
    if (isDisposed) return;
    final e = configError;
    _error = e == null ? null : describeAdminError(e, now: ctx.now);
    if (e != null && _config != null) {
      // Keep showing the last good configuration, with the problem as a note.
      _healthNote ??= _error;
      _error = null;
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _read(
    Future<void> Function() load,
    void Function(Object error) fail, {
    void Function()? clear,
  }) async {
    try {
      await load();
      clear?.call();
    } on Object catch (e) {
      ctx.report(e);
      fail(e);
    }
  }

  /// Applies [patch] and takes the server's answer as the new configuration.
  Future<String?> _patch(String key, AdminConfigPatch patch) async {
    if (!_busy.add(key)) return null;
    notifyListeners();
    final problem = await attempt(() async {
      _config = await ctx.api.admin.updateConfig(patch);
    });
    _busy.remove(key);
    notifyListeners();
    return problem;
  }

  /// Returns a problem to show, or null.
  Future<String?> setMaintenance(bool on) =>
      _patch('maintenance', AdminConfigPatch(maintenance: on));

  Future<String?> setFederation(bool on) =>
      _patch('federation', AdminConfigPatch(federationEnabled: on));

  /// [name] is trimmed; empty or too long names are refused here.
  Future<String?> rename(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return Future.value('The server needs a name.');
    }
    if (trimmed.length > AdminConfigPatch.maxServerNameLength) {
      return Future.value(
        'The name can have at most '
        '${AdminConfigPatch.maxServerNameLength} characters.',
      );
    }
    return _patch('name', AdminConfigPatch(serverName: trimmed));
  }

  Future<String?> setFlag(String name, bool enabled) async {
    final key = 'flag:$name';
    if (!_busy.add(key)) return null;
    notifyListeners();
    final problem = await attempt(() async {
      await ctx.api.admin.setFeatureFlag(name, enabled: enabled);
      _flags = {..._flags, name: enabled};
    });
    _busy.remove(key);
    notifyListeners();
    return problem;
  }

  /// Purges dead jobs and expired identity rows; the counts by kind, or the
  /// problem.
  Future<({PurgeResult? result, String? problem})> purge() async {
    if (!_busy.add('purge')) return (result: null, problem: null);
    notifyListeners();
    PurgeResult? result;
    final problem = await attempt(() async {
      result = await ctx.api.admin.purge();
    });
    _busy.remove('purge');
    notifyListeners();
    if (problem == null) {
      // The dead-job gauge changed; refresh quietly.
      unawaited(refresh());
    }
    return (result: result, problem: problem);
  }
}
