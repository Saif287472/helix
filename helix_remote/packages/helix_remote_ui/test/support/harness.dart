// The scanner `package_rules_test.dart` runs over this package's sources,
// with its own test. The widget harness that came with it left with the
// widgets (Part B step 4).
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
