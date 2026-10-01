/// In-process metrics rendered in the Prometheus text format
/// (`GET /v1/ops/metrics`). Each node exposes its own numbers; a scraper
/// aggregates across nodes. Labels must be low-cardinality (route names,
/// result codes) — never ids.
final class Metrics {
  final Map<String, _Family> _families = {};

  Counter counter(String name, String help) => (_families.putIfAbsent(
    name,
    () => _Family(name, help, 'counter'),
  )).counter;

  Histogram histogram(
    String name,
    String help, {
    List<double> buckets = const [
      0.005,
      0.01,
      0.025,
      0.05,
      0.1,
      0.25,
      0.5,
      1,
      2.5,
      5,
      10,
    ],
  }) => (_families.putIfAbsent(
    name,
    () => _Family(name, help, 'histogram', buckets: buckets),
  )).histogram;

  /// A value read at scrape time.
  void gauge(String name, String help, double Function() read) {
    _families[name] = _Family(name, help, 'gauge', read: read);
  }

  final Map<String, Future<double> Function()> _collected = {};
  final Map<String, double> _lastCollected = {};

  /// A value that needs a query (dead letters, mailbox backlog). Read by
  /// [collect] before each scrape; a failed or slow read keeps the last
  /// value (NaN before the first).
  void collectedGauge(
    String name,
    String help,
    Future<double> Function() read,
  ) {
    _collected[name] = read;
    gauge(name, help, () => _lastCollected[name] ?? double.nan);
  }

  /// Refreshes every [collectedGauge], each within [timeout].
  Future<void> collect({Duration timeout = const Duration(seconds: 3)}) async {
    await Future.wait([
      for (final e in _collected.entries)
        e
            .value()
            .timeout(timeout)
            .then<void>(
              (v) => _lastCollected[e.key] = v,
              onError: (Object _) {},
            ),
    ]);
  }

  String render() {
    final out = StringBuffer();
    for (final family in _families.values) {
      family.render(out);
    }
    return out.toString();
  }
}

String _labels(
  Map<String, String> labels, [
  Map<String, String> extra = const {},
]) {
  final all = {...labels, ...extra};
  if (all.isEmpty) return '';
  final parts = [
    for (final e in all.entries)
      '${e.key}="${e.value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"',
  ];
  return '{${parts.join(',')}}';
}

String _key(Map<String, String> labels) =>
    (labels.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => '${e.key}=${e.value}')
        .join(',');

final class _Family {
  _Family(
    this.name,
    this.help,
    this.type, {
    this.buckets = const [],
    this.read,
  }) {
    counter = Counter._(this);
    histogram = Histogram._(this);
  }

  final String name;
  final String help;
  final String type;
  final List<double> buckets;
  final double Function()? read;
  late final Counter counter;
  late final Histogram histogram;
  final Map<String, (Map<String, String>, double)> _values = {};
  final Map<String, (Map<String, String>, List<int>, double, int)> _histograms =
      {};

  void render(StringBuffer out) {
    out
      ..writeln('# HELP $name $help')
      ..writeln('# TYPE $name $type');
    if (read != null) {
      out.writeln('$name ${read!()}');
      return;
    }
    for (final (labels, value) in _values.values) {
      out.writeln('$name${_labels(labels)} $value');
    }
    for (final (labels, counts, sum, count) in _histograms.values) {
      var cumulative = 0;
      for (var i = 0; i < buckets.length; i++) {
        cumulative += counts[i];
        out.writeln(
          '${name}_bucket${_labels(labels, {'le': '${buckets[i]}'})} $cumulative',
        );
      }
      out
        ..writeln('${name}_bucket${_labels(labels, {'le': '+Inf'})} $count')
        ..writeln('${name}_sum${_labels(labels)} $sum')
        ..writeln('${name}_count${_labels(labels)} $count');
    }
  }
}

final class Counter {
  Counter._(this._family);

  final _Family _family;

  void inc([Map<String, String> labels = const {}, double by = 1]) {
    final key = _key(labels);
    final current = _family._values[key]?.$2 ?? 0;
    _family._values[key] = (labels, current + by);
  }

  double value([Map<String, String> labels = const {}]) =>
      _family._values[_key(labels)]?.$2 ?? 0;
}

final class Histogram {
  Histogram._(this._family);

  final _Family _family;

  void observe(double value, [Map<String, String> labels = const {}]) {
    final key = _key(labels);
    final existing = _family._histograms[key];
    final counts = existing?.$2 ?? List<int>.filled(_family.buckets.length, 0);
    for (var i = 0; i < _family.buckets.length; i++) {
      if (value <= _family.buckets[i]) {
        counts[i]++;
        break;
      }
    }
    _family._histograms[key] = (
      labels,
      counts,
      (existing?.$3 ?? 0) + value,
      (existing?.$4 ?? 0) + 1,
    );
  }
}
