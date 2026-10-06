import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Pumps [child] under the Helix light theme in a [width] x [height] logical
/// surface (phone-sized by default), optionally with a text scale and an
/// RTL locale.
Future<void> pumpHelix(
  WidgetTester tester,
  Widget child, {
  double width = 400,
  double height = 800,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
  bool scaffold = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: HelixThemes.light(),
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          // Skeleton and typing animations repeat forever; tests settle.
          disableAnimations: true,
        ),
        child: Directionality(textDirection: direction, child: app!),
      ),
      home: scaffold ? Scaffold(body: child) : child,
    ),
  );
}

/// Every `IconButton(` / `IconButton.filled(` (and tonal/outlined) in [source], with its
/// 1-based line, whose argument list carries no `tooltip:`.
List<int> unlabelledIconButtonLines(String source) {
  final lines = <int>[];
  for (final match in RegExp(
    r'IconButton(?:\.(?:filled|filledTonal|outlined))?\(',
  ).allMatches(source)) {
    var index = match.end;
    var depth = 1;
    while (index < source.length && depth > 0) {
      final char = source[index];
      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
      }
      index++;
    }
    if (!source.substring(match.end, index).contains('tooltip:')) {
      lines.add('\n'.allMatches(source.substring(0, match.start)).length + 1);
    }
  }
  return lines;
}
