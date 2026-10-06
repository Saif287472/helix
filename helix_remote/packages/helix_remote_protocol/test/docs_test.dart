import 'dart:io';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

/// REST_V2.md must document every catalog route, and only catalog routes.
void main() {
  final doc = File('../../docs/protocol/v2/REST_V2.md').readAsStringSync();

  test('every route is documented', () {
    final missing = [
      for (final route in Routes.all)
        if (!doc.contains('`$route`')) route.toString(),
    ];
    expect(missing, isEmpty, reason: 'add these to REST_V2.md');
  });

  test('the doc names no route the catalog lacks', () {
    final documented = RegExp(
      r'`(GET|POST|PUT|PATCH|DELETE|HEAD) (/[^`\s]*)`',
    ).allMatches(doc).map((m) => '${m.group(1)} ${m.group(2)}');
    final known = {for (final r in Routes.all) r.toString()};
    expect(documented.where((r) => !known.contains(r)).toList(), isEmpty);
  });
}
