import 'dart:io';

/// The process environment, with `KEY=VALUE` lines from [path] (default
/// `.env` in the working directory) filling gaps. Real environment
/// variables win. Lines starting with `#` and blank lines are ignored;
/// values may be wrapped in single or double quotes.
Map<String, String> loadEnvironment({String path = '.env'}) {
  final merged = <String, String>{};
  final file = File(path);
  if (file.existsSync()) {
    for (final raw in file.readAsLinesSync()) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      var value = line.substring(eq + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      merged[line.substring(0, eq).trim()] = value;
    }
  }
  merged.addAll(Platform.environment);
  return merged;
}
