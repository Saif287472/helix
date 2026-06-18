import 'dart:convert';
import 'dart:io';

const _defaultConfigPath = 'docs/architecture/module_boundaries.json';

Future<void> main(List<String> args) async {
  final root = args.isNotEmpty ? Directory(args[0]) : Directory.current;
  final configPath = args.length > 1 ? args[1] : _defaultConfigPath;
  final violations = await checkBoundaries(
    root,
    File(_join(root.path, configPath)),
  );

  if (violations.isEmpty) {
    stdout.writeln('Boundary check passed.');
    return;
  }

  stderr.writeln(
    'Boundary check failed with ${violations.length} violation(s):',
  );
  for (final violation in violations) {
    stderr.writeln(
      '${violation.source}:${violation.line}: ${violation.importUri} -> '
      '${violation.target} (${violation.reason})',
    );
  }
  exitCode = 1;
}

Future<List<BoundaryViolation>> checkBoundaries(
  Directory root,
  File configFile,
) async {
  final config = BoundaryConfig.fromJson(
    jsonDecode(await configFile.readAsString()) as Map<String, Object?>,
  );
  final files = await _dartFiles(root).toList();
  final violations = <BoundaryViolation>[];

  for (final file in files) {
    final source = _relativePath(root, file);
    final content = await file.readAsString();
    final imports = _extractImports(content);

    for (final importRef in imports) {
      final target = _resolveImport(source, importRef.uri);
      if (target == null) {
        continue;
      }

      for (final rule in config.rules) {
        if (!rule.matchesSource(source)) {
          continue;
        }
        if (!rule.matchesImport(target)) {
          continue;
        }
        violations.add(
          BoundaryViolation(
            source: source,
            line: importRef.line,
            importUri: importRef.uri,
            target: target,
            reason: rule.reason,
          ),
        );
      }
    }
  }

  return violations;
}

class BoundaryConfig {
  BoundaryConfig(this.rules);

  factory BoundaryConfig.fromJson(Map<String, Object?> json) {
    final forbidden = json['forbidden'] as List<Object?>? ?? const [];
    return BoundaryConfig(
      forbidden
          .map((item) => BoundaryRule.fromJson(item as Map<String, Object?>))
          .toList(growable: false),
    );
  }

  final List<BoundaryRule> rules;
}

class BoundaryRule {
  BoundaryRule({
    required this.sourcePattern,
    required this.importPatterns,
    required this.reason,
  });

  factory BoundaryRule.fromJson(Map<String, Object?> json) {
    return BoundaryRule(
      sourcePattern: json['source'] as String,
      importPatterns: (json['imports'] as List<Object?>).cast<String>(),
      reason: json['reason'] as String? ?? 'Forbidden dependency',
    );
  }

  final String sourcePattern;
  final List<String> importPatterns;
  final String reason;

  bool matchesSource(String path) => _glob(sourcePattern).hasMatch(path);

  bool matchesImport(String path) {
    return importPatterns.any((pattern) => _glob(pattern).hasMatch(path));
  }
}

class BoundaryViolation {
  BoundaryViolation({
    required this.source,
    required this.line,
    required this.importUri,
    required this.target,
    required this.reason,
  });

  final String source;
  final int line;
  final String importUri;
  final String target;
  final String reason;
}

class _ImportRef {
  _ImportRef(this.uri, this.line);

  final String uri;
  final int line;
}

Stream<File> _dartFiles(Directory root) async* {
  final ignored = {'.dart_tool', '.git', '.idea', 'build', 'coverage'};

  await for (final entity in root.list(recursive: true, followLinks: false)) {
    final relative = _relativeEntityPath(root, entity);
    final segments = relative.split('/');
    if (segments.any(ignored.contains)) {
      continue;
    }
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}

List<_ImportRef> _extractImports(String content) {
  final refs = <_ImportRef>[];
  final statement = RegExp(r"^\s*(import|export)\s+([^;]+);", multiLine: true);
  final uri = RegExp(r'''['"]([^'"]+)['"]''');

  for (final match in statement.allMatches(content)) {
    final prefix = content.substring(0, match.start);
    final line = '\n'.allMatches(prefix).length + 1;
    for (final uriMatch in uri.allMatches(match.group(2)!)) {
      refs.add(_ImportRef(uriMatch.group(1)!, line));
    }
  }

  return refs;
}

String? _resolveImport(String source, String uri) {
  if (uri.startsWith('dart:') || uri.startsWith('package:flutter/')) {
    return null;
  }
  if (uri.startsWith('package:helix/')) {
    return 'lib/${uri.substring('package:helix/'.length)}';
  }
  if (uri.startsWith('package:')) {
    return null;
  }
  if (uri.startsWith('asset:')) {
    return null;
  }

  final sourceDir = source.contains('/')
      ? source.substring(0, source.lastIndexOf('/'))
      : '.';
  return _normalizePath('$sourceDir/$uri');
}

String _relativePath(Directory root, File file) {
  return _relativeEntityPath(root, file);
}

String _relativeEntityPath(Directory root, FileSystemEntity entity) {
  var rootPath = root.absolute.path.replaceAll('\\', '/');
  final entityPath = entity.absolute.path.replaceAll('\\', '/');
  if (!rootPath.endsWith('/')) {
    rootPath = '$rootPath/';
  }
  if (entityPath.startsWith(rootPath)) {
    return entityPath.substring(rootPath.length);
  }
  return entityPath;
}

String _normalizePath(String path) {
  final parts = <String>[];
  for (final part in path.replaceAll('\\', '/').split('/')) {
    if (part.isEmpty || part == '.') {
      continue;
    }
    if (part == '..') {
      if (parts.isNotEmpty) {
        parts.removeLast();
      }
      continue;
    }
    parts.add(part);
  }
  return parts.join('/');
}

String _join(String left, String right) {
  if (right.contains(':') || right.startsWith('/') || right.startsWith(r'\')) {
    return right;
  }
  return '${left.replaceAll('\\', '/')}/$right';
}

RegExp _glob(String pattern) {
  final buffer = StringBuffer('^');
  for (var i = 0; i < pattern.length; i++) {
    final char = pattern[i];
    if (char == '*') {
      final isDouble = i + 1 < pattern.length && pattern[i + 1] == '*';
      if (isDouble) {
        buffer.write('.*');
        i++;
      } else {
        buffer.write('[^/]*');
      }
      continue;
    }
    buffer.write(RegExp.escape(char));
  }
  buffer.write(r'$');
  return RegExp(buffer.toString());
}
