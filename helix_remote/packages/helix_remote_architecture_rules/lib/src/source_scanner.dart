import 'dart:io';

import 'package:path/path.dart' as p;

/// Kind of a Dart directive that refers to another file.
enum DirectiveKind { import, export, part }

/// One `import`, `export` or `part` URI in a Dart file.
///
/// A conditional import yields one [Directive] per URI (the default and each
/// `if (...)` alternative), all with the same [kind] and the [line] where the
/// URI appears.
final class Directive {
  const Directive({required this.kind, required this.uri, required this.line});

  final DirectiveKind kind;
  final String uri;

  /// 1-based line number.
  final int line;

  @override
  String toString() => '${kind.name} $uri (line $line)';
}

/// A scanned Dart file.
final class SourceFile {
  const SourceFile({required this.path, required this.directives});

  /// Path relative to the scanned package root, always with `/` separators
  /// (for example `lib/src/modules/identity/api.dart`).
  final String path;
  final List<Directive> directives;

  /// Resolves [uri] from this file to a package-relative path, if it points
  /// into the package named [packageName]; otherwise returns null.
  ///
  /// `package:<packageName>/x.dart` becomes `lib/x.dart`. A relative URI is
  /// resolved against this file's directory.
  String? resolveInPackage(String uri, {required String packageName}) {
    final prefix = 'package:$packageName/';
    if (uri.startsWith(prefix)) {
      return p.posix.normalize('lib/${uri.substring(prefix.length)}');
    }
    if (uri.contains(':')) return null;
    return p.posix.normalize(p.posix.join(p.posix.dirname(path), uri));
  }
}

/// The package a URI refers to: `x` for `package:x/...`, `dart` for
/// `dart:...`, and null for a relative URI.
String? packageOfUri(String uri) {
  if (uri.startsWith('dart:')) return 'dart';
  if (!uri.startsWith('package:')) return null;
  final slash = uri.indexOf('/');
  if (slash < 0) return uri.substring('package:'.length);
  return uri.substring('package:'.length, slash);
}

final RegExp _directiveStart = RegExp(
  r'''^\s*(import|export|part)\s+['"]([^'"]+)['"]''',
);
final RegExp _conditionalUri = RegExp(
  r'''\bif\s*\([^)]*\)\s*['"]([^'"]+)['"]''',
);

/// Extracts the `import`, `export` and `part` URIs from Dart [source].
///
/// Directives are line-oriented, so a scan is enough: `part of` is skipped,
/// comment lines and block comments are ignored, and conditional URIs that
/// continue on following lines are collected until the terminating `;`.
List<Directive> parseDirectives(String source) {
  final result = <Directive>[];
  final lines = source.split('\n');
  var inBlockComment = false;
  DirectiveKind? continuing;

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (inBlockComment) {
      final end = line.indexOf('*/');
      if (end < 0) continue;
      inBlockComment = false;
      line = line.substring(end + 2);
    }
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('//')) continue;
    if (trimmed.startsWith('/*')) {
      final end = trimmed.indexOf('*/');
      if (end < 0) {
        inBlockComment = true;
        continue;
      }
      line = trimmed.substring(end + 2);
    }

    if (continuing != null) {
      for (final alt in _conditionalUri.allMatches(line)) {
        result.add(
          Directive(kind: continuing, uri: alt.group(1)!, line: i + 1),
        );
      }
      if (line.contains(';')) continuing = null;
      continue;
    }

    final match = _directiveStart.firstMatch(line);
    if (match == null) continue;
    final kind = DirectiveKind.values.byName(match.group(1)!);
    result.add(Directive(kind: kind, uri: match.group(2)!, line: i + 1));
    final rest = line.substring(match.end);
    for (final alt in _conditionalUri.allMatches(rest)) {
      result.add(Directive(kind: kind, uri: alt.group(1)!, line: i + 1));
    }
    if (!rest.contains(';')) continuing = kind;
  }
  return result;
}

/// Scans every `.dart` file under [directories] of the package at [root].
///
/// Missing directories are skipped. Files for which [exclude] returns true
/// (given the package-relative path) are left out. Results are sorted by
/// path so violation reports are stable.
List<SourceFile> scanDartSources(
  String root, {
  List<String> directories = const ['lib', 'bin', 'test'],
  bool Function(String path)? exclude,
}) {
  final files = <SourceFile>[];
  for (final dir in directories) {
    final directory = Directory(p.join(root, dir));
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = p.posix.joinAll(
        p.split(p.relative(entity.path, from: root)),
      );
      if (exclude?.call(relative) ?? false) continue;
      files.add(
        SourceFile(
          path: relative,
          directives: parseDirectives(entity.readAsStringSync()),
        ),
      );
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}
