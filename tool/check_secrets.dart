import 'dart:io';

const _defaultRoots = [
  'lib',
  'test',
  'tool',
  'scripts',
  'docs',
  'pubspec.yaml',
  'analysis_options.yaml',
  '.env.example',
];

final _patterns = <_SecretPattern>[
  _SecretPattern(
    'private key block',
    RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
  ),
  _SecretPattern('AWS access key id', RegExp(r'\bAKIA[0-9A-Z]{16}\b')),
  _SecretPattern('GitHub token', RegExp(r'\bgh[pousr]_[A-Za-z0-9_]{36,}\b')),
  _SecretPattern('Slack token', RegExp(r'\bxox[baprs]-[A-Za-z0-9-]{20,}\b')),
  _SecretPattern(
    'generic assigned secret',
    RegExp(
      r'''\b(api[_-]?key|client[_-]?secret|access[_-]?token|auth[_-]?token|password)\b\s*[:=]\s*['"][^'"]{12,}['"]''',
      caseSensitive: false,
    ),
  ),
];

Future<void> main(List<String> args) async {
  final root = Directory.current;
  final scanRoots = args.isEmpty ? _defaultRoots : args;
  final findings = await scanForSecrets(root, scanRoots);

  if (findings.isEmpty) {
    stdout.writeln('Secret scan passed.');
    return;
  }

  stderr.writeln('Secret scan failed with ${findings.length} finding(s):');
  for (final finding in findings) {
    stderr.writeln('${finding.path}:${finding.line}: ${finding.patternName}');
  }
  exitCode = 1;
}

Future<List<SecretFinding>> scanForSecrets(
  Directory root,
  List<String> scanRoots,
) async {
  final findings = <SecretFinding>[];
  for (final path in scanRoots) {
    final entity =
        FileSystemEntity.typeSync(_join(root.path, path)) ==
            FileSystemEntityType.directory
        ? Directory(_join(root.path, path))
        : File(_join(root.path, path));
    if (!entity.existsSync()) {
      continue;
    }
    if (entity is Directory) {
      await for (final file in _files(root, entity)) {
        findings.addAll(await _scanFile(root, file));
      }
    } else if (entity is File) {
      findings.addAll(await _scanFile(root, entity));
    }
  }
  return findings;
}

class SecretFinding {
  SecretFinding({
    required this.path,
    required this.line,
    required this.patternName,
  });

  final String path;
  final int line;
  final String patternName;
}

class _SecretPattern {
  _SecretPattern(this.name, this.regex);

  final String name;
  final RegExp regex;
}

Stream<File> _files(Directory root, Directory start) async* {
  const ignoredDirectories = {
    '.dart_tool',
    '.git',
    '.idea',
    'build',
    'coverage',
    'android/app/debug',
    'android/app/profile',
    'android/app/release',
  };
  const ignoredExtensions = {'.png', '.jpg', '.jpeg', '.ico', '.db', '.sqlite'};

  await for (final entity in start.list(recursive: true, followLinks: false)) {
    final relative = _relativePath(root, entity);
    if (ignoredDirectories.any(
      (ignored) => relative == ignored || relative.startsWith('$ignored/'),
    )) {
      continue;
    }
    if (entity is File &&
        !ignoredExtensions.any(
          (ext) => entity.path.toLowerCase().endsWith(ext),
        )) {
      yield entity;
    }
  }
}

Future<List<SecretFinding>> _scanFile(Directory root, File file) async {
  final content = await file.readAsString();
  final lines = content.split('\n');
  final findings = <SecretFinding>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (_isAllowedPlaceholder(line)) {
      continue;
    }
    for (final pattern in _patterns) {
      if (pattern.regex.hasMatch(line)) {
        findings.add(
          SecretFinding(
            path: _relativePath(root, file),
            line: i + 1,
            patternName: pattern.name,
          ),
        );
      }
    }
  }
  return findings;
}

bool _isAllowedPlaceholder(String line) {
  final lower = line.toLowerCase();
  return lower.contains('placeholder') ||
      lower.contains('example') ||
      lower.contains('changeme') ||
      lower.contains('dummy') ||
      lower.contains('fake') ||
      lower.contains('your-') ||
      lower.contains('<redacted>');
}

String _relativePath(Directory root, FileSystemEntity entity) {
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

String _join(String left, String right) {
  if (right.contains(':') || right.startsWith('/') || right.startsWith(r'\')) {
    return right;
  }
  return '${left.replaceAll('\\', '/')}/$right';
}
