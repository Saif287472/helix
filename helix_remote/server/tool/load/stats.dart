import 'dart:typed_data';

/// Latency samples in microseconds. Workers fill one per metric and ship
/// the raw values to the coordinator, which merges and summarises them.
final class Samples {
  Samples();

  Samples.of(Iterable<int> values) {
    _values.addAll(values);
  }

  final List<int> _values = [];

  int get count => _values.length;

  void add(int micros) => _values.add(micros);

  void addAll(Samples other) => _values.addAll(other._values);

  /// For sending between isolates.
  Int64List toWire() => Int64List.fromList(_values);

  static Samples fromWire(Object? wire) =>
      Samples.of(wire == null ? const <int>[] : wire as List<int>);

  Summary summarize() => Summary.of(_values);
}

/// Percentiles (nearest rank) of a set of samples, in milliseconds.
final class Summary {
  const Summary._(
    this.count,
    this.p50,
    this.p95,
    this.p99,
    this.max,
    this.mean,
  );

  factory Summary.of(List<int> micros) {
    if (micros.isEmpty) return const Summary._(0, 0, 0, 0, 0, 0);
    final sorted = Int64List.fromList(micros)..sort();
    double at(double q) {
      final rank = (q * sorted.length).ceil().clamp(1, sorted.length);
      return sorted[rank - 1] / 1000;
    }

    var sum = 0;
    for (final v in sorted) {
      sum += v;
    }
    return Summary._(
      sorted.length,
      at(0.50),
      at(0.95),
      at(0.99),
      sorted.last / 1000,
      sum / sorted.length / 1000,
    );
  }

  final int count;
  final double p50;
  final double p95;
  final double p99;
  final double max;
  final double mean;

  Map<String, Object?> toJson() => {
    'count': count,
    'p50_ms': _round(p50),
    'p95_ms': _round(p95),
    'p99_ms': _round(p99),
    'max_ms': _round(max),
    'mean_ms': _round(mean),
  };
}

double _round(double v) => (v * 100).roundToDouble() / 100;

/// Counts by key (error codes, close codes).
final class Counts {
  final Map<String, int> values = {};

  void add(String key, [int by = 1]) =>
      values.update(key, (v) => v + by, ifAbsent: () => by);

  void addAll(Map<Object?, Object?> other) {
    for (final e in other.entries) {
      add(e.key! as String, e.value! as int);
    }
  }

  int get total => values.values.fold(0, (a, b) => a + b);

  Map<String, int> sorted() => Map.fromEntries(
    values.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
  );
}

/// A fixed-width table of [rows] (label, summary).
String latencyTable(List<(String, Summary)> rows) {
  const header = ['', 'count', 'p50 ms', 'p95 ms', 'p99 ms', 'max ms'];
  final cells = [
    header,
    for (final (label, s) in rows)
      [
        label,
        '${s.count}',
        s.p50.toStringAsFixed(1),
        s.p95.toStringAsFixed(1),
        s.p99.toStringAsFixed(1),
        s.max.toStringAsFixed(1),
      ],
  ];
  final widths = [
    for (var c = 0; c < header.length; c++)
      cells.map((r) => r[c].length).reduce((a, b) => a > b ? a : b),
  ];
  final out = StringBuffer();
  for (final row in cells) {
    for (var c = 0; c < row.length; c++) {
      out.write(
        c == 0 ? row[c].padRight(widths[c]) : row[c].padLeft(widths[c] + 2),
      );
    }
    out.writeln();
  }
  return out.toString();
}
