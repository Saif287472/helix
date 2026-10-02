import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/src/features/dashboard/metrics_summary.dart';

const _sample = '''
# HELP helix_http_request_seconds Request latency.
# TYPE helix_http_request_seconds histogram
helix_http_request_seconds_bucket{route="/v1/server",status="2xx",le="0.005"} 3
helix_http_request_seconds_bucket{route="/v1/server",status="2xx",le="+Inf"} 8
helix_http_request_seconds_sum{route="/v1/server",status="2xx"} 0.4
helix_http_request_seconds_count{route="/v1/server",status="2xx"} 8
helix_http_request_seconds_count{route="/v1/ws",status="2xx"} 2
helix_http_request_seconds_count{route="/v1/send",status="4xx"} 4
helix_http_request_seconds_count{route="/v1/send",status="5xx"} 1
# TYPE helix_jobs_total counter
helix_jobs_total{kind="relay",result="ok"} 7.0
helix_jobs_total{kind="relay",result="dead"} 2.0
helix_jobs_total{kind="push",result="ok"} 3.0
# TYPE helix_ws_open gauge
helix_ws_open 5.0
helix_ws_connections_total 40.0
helix_jobs_dead 2.0
helix_mailbox_backlog 120.0
helix_http_body_bytes_in_flight 0.0
helix_client_crash_reports_total 6.0
''';

void main() {
  test('reads the families the dashboard shows', () {
    final m = MetricsSummary.parse(_sample);

    expect(m.requests, 15);
    expect(m.serverErrors, 1);
    expect(m.clientErrors, 4);
    expect(m.serverErrorShare, closeTo(1 / 15, 1e-9));
    expect(m.websocketsOpen, 5);
    expect(m.websocketConnections, 40);
    expect(m.deadJobs, 2);
    expect(m.mailboxBacklog, 120);
    expect(m.crashReports, 6);
    expect(m.jobsFinished, {'ok': 10, 'dead': 2});
  });

  test('a missing family is null, never an invented zero', () {
    final m = MetricsSummary.parse('helix_ws_open 1\n');

    expect(m.websocketsOpen, 1);
    expect(m.requests, isNull);
    expect(m.serverErrors, isNull);
    expect(m.serverErrorShare, isNull);
    expect(m.deadJobs, isNull);
    expect(m.mailboxBacklog, isNull);
    expect(m.jobsFinished, isNull);
  });

  test('NaN (a gauge not read yet) is treated as missing', () {
    final m = MetricsSummary.parse('helix_jobs_dead NaN\nhelix_ws_open 2\n');

    expect(m.deadJobs, isNull);
    expect(m.websocketsOpen, 2);
  });

  test('no requests yet gives no error share', () {
    final m = MetricsSummary.parse(
      'helix_http_request_seconds_count{route="/x",status="2xx"} 0\n',
    );

    expect(m.requests, 0);
    expect(m.serverErrors, 0);
    expect(m.serverErrorShare, isNull);
  });

  test('ignores comments, blank lines, junk and unknown families', () {
    final m = MetricsSummary.parse(
      '\n# only a comment\nthis is not metrics\nsome_other_total 9\n',
    );

    expect(m.requests, isNull);
    expect(m.websocketsOpen, isNull);
  });

  test('empty text is an empty summary', () {
    final m = MetricsSummary.parse('');

    expect(m.requests, isNull);
    expect(m.deadJobs, isNull);
  });
}
