/// The few numbers the dashboard shows, read from the server's Prometheus
/// text (`GET /v1/ops/metrics`, admin audience). Only the families listed in
/// `docs/operations/V2_OPERABILITY.md` are looked at; anything else is
/// ignored, and a family that is missing or `NaN` stays null (never a made
/// up zero).
final class MetricsSummary {
  const MetricsSummary({
    this.requests,
    this.serverErrors,
    this.clientErrors,
    this.websocketsOpen,
    this.websocketConnections,
    this.deadJobs,
    this.mailboxBacklog,
    this.crashReports,
    this.jobsFinished,
  });

  /// Requests this node has answered since it started.
  final int? requests;

  /// Of those, status `5xx` and `4xx`.
  final int? serverErrors;
  final int? clientErrors;

  /// Sockets open on this node now, and opened since start.
  final int? websocketsOpen;
  final int? websocketConnections;

  /// Dead outbox jobs and undelivered envelopes, cluster-wide.
  final int? deadJobs;
  final int? mailboxBacklog;

  final int? crashReports;

  /// Outbox jobs finished, by result (`ok`, `retry`, `dead`).
  final Map<String, int>? jobsFinished;

  /// Share of requests answered with a 5xx, 0 to 1; null before any request.
  double? get serverErrorShare {
    final total = requests;
    final errors = serverErrors;
    if (total == null || total == 0 || errors == null) return null;
    return errors / total;
  }

  static final _line = RegExp(
    r'^([a-zA-Z_:][a-zA-Z0-9_:]*)(?:\{(.*)\})?\s+(\S+)\s*$',
  );
  static final _label = RegExp(r'(\w+)="((?:[^"\\]|\\.)*)"');

  /// Reads Prometheus text format; unknown lines are skipped.
  factory MetricsSummary.parse(String text) {
    double? gauge(Map<String, double> m, String name) => m[name];

    final single = <String, double>{};
    var requests = 0.0;
    var sawRequests = false;
    final byStatus = <String, double>{};
    final jobs = <String, double>{};

    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final match = _line.firstMatch(line);
      if (match == null) continue;
      final name = match.group(1)!;
      final value = double.tryParse(match.group(3)!);
      if (value == null || value.isNaN) continue;
      final labels = {
        for (final l in _label.allMatches(match.group(2) ?? ''))
          l.group(1)!: l.group(2)!,
      };
      switch (name) {
        case 'helix_http_request_seconds_count':
          sawRequests = true;
          requests += value;
          final status = labels['status'];
          if (status != null) {
            byStatus[status] = (byStatus[status] ?? 0) + value;
          }
        case 'helix_jobs_total':
          final result = labels['result'];
          if (result != null) jobs[result] = (jobs[result] ?? 0) + value;
        case 'helix_ws_open' ||
            'helix_ws_connections_total' ||
            'helix_jobs_dead' ||
            'helix_mailbox_backlog' ||
            'helix_client_crash_reports_total':
          single[name] = value;
      }
    }

    int? whole(double? v) => v?.round();
    return MetricsSummary(
      requests: sawRequests ? requests.round() : null,
      serverErrors: sawRequests ? whole(byStatus['5xx'] ?? 0) : null,
      clientErrors: sawRequests ? whole(byStatus['4xx'] ?? 0) : null,
      websocketsOpen: whole(gauge(single, 'helix_ws_open')),
      websocketConnections: whole(gauge(single, 'helix_ws_connections_total')),
      deadJobs: whole(gauge(single, 'helix_jobs_dead')),
      mailboxBacklog: whole(gauge(single, 'helix_mailbox_backlog')),
      crashReports: whole(gauge(single, 'helix_client_crash_reports_total')),
      jobsFinished: jobs.isEmpty
          ? null
          : {for (final e in jobs.entries) e.key: e.value.round()},
    );
  }
}
