// tool/check_asset_sizes.dart
//
// P10-02 — Asset size audit and enforcement.
//
// Usage:
//   dart run tool/check_asset_sizes.dart
//   dart run tool/check_asset_sizes.dart --fail-on-budget-exceeded
//
// Checks all bundled assets in both apps and reports sizes against the budgets
// defined in docs/performance/PERFORMANCE_BUDGETS.md.

import 'dart:io';

const _budgets = {
  'apps/helix_local/assets': _Budget(
    totalBytes: 10 * 1024 * 1024,
    label: 'Local total asset bundle',
  ),
  'apps/helix_remote/assets': _Budget(
    totalBytes: 5 * 1024 * 1024,
    label: 'Remote total asset bundle',
  ),
};

const _perFileBudgets = {
  '.mp3': _Budget(
    totalBytes: 5 * 1024 * 1024,
    label: 'Individual MP3 ringtone/notification sound',
  ),
  '.png': _Budget(totalBytes: 2 * 1024 * 1024, label: 'Individual PNG image'),
  '.jpg': _Budget(totalBytes: 1 * 1024 * 1024, label: 'Individual JPEG image'),
};

// Approximate APK size contribution: assets contribute ~1:1 (no compression for
// already-compressed audio). Total Local audio bundle must not exceed budget.
const _soundsDirBudget = _Budget(
  totalBytes: 8 * 1024 * 1024,
  label: 'Local sounds/ directory',
);

class _Budget {
  final int totalBytes;
  final String label;
  const _Budget({required this.totalBytes, required this.label});
}

void main(List<String> args) {
  final failOnExceeded = args.contains('--fail-on-budget-exceeded');

  final repoRoot = _findRepoRoot();
  if (repoRoot == null) {
    stderr.writeln(
      'ERROR: Could not find repository root (no pubspec.yaml at root).',
    );
    exit(1);
  }

  final violations = <String>[];
  final report = StringBuffer();

  report.writeln('Helix Asset Size Report — ${DateTime.now().toLocal()}');
  report.writeln('Repository root: $repoRoot');
  report.writeln('');

  // Check per-directory budgets.
  for (final entry in _budgets.entries) {
    final dir = Directory('$repoRoot/${entry.key}');
    if (!dir.existsSync()) {
      report.writeln('  [SKIP] ${entry.key} — directory not found');
      continue;
    }
    _auditDirectory(dir, repoRoot, report, entry.value, violations);
    report.writeln('');
  }

  // Check Local sounds/ directory specifically.
  final soundsDir = Directory('$repoRoot/apps/helix_local/assets/sounds');
  if (soundsDir.existsSync()) {
    _auditDirectory(soundsDir, repoRoot, report, _soundsDirBudget, violations);
    report.writeln('');
  }

  // Per-file type checks across all asset directories.
  report.writeln('Per-file budget checks:');
  for (final app in ['apps/helix_local/assets', 'apps/helix_remote/assets']) {
    final dir = Directory('$repoRoot/$app');
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final ext = _extension(entity.path).toLowerCase();
      final budget = _perFileBudgets[ext];
      if (budget == null) continue;
      final size = entity.lengthSync();
      final relPath = entity.path.replaceFirst('$repoRoot/', '');
      final sizeStr = _formatBytes(size);
      final budgetStr = _formatBytes(budget.totalBytes);
      if (size > budget.totalBytes) {
        violations.add(
          '$relPath: $sizeStr > budget $budgetStr (${budget.label})',
        );
        report.writeln('  [FAIL] $relPath: $sizeStr > $budgetStr');
      } else {
        report.writeln('  [OK  ] $relPath: $sizeStr / $budgetStr');
      }
    }
  }
  report.writeln('');

  // Recommendations for large assets.
  _emitRecommendations(repoRoot, report);

  stdout.write(report.toString());

  if (violations.isNotEmpty) {
    stdout.writeln('BUDGET VIOLATIONS (${violations.length}):');
    for (final v in violations) {
      stdout.writeln('  $v');
    }
    if (failOnExceeded) {
      exit(1);
    }
  } else {
    stdout.writeln('All asset budgets satisfied.');
  }
}

int _auditDirectory(
  Directory dir,
  String repoRoot,
  StringBuffer report,
  _Budget budget,
  List<String> violations,
) {
  final relPath = dir.path.replaceFirst('$repoRoot/', '');
  report.writeln('Directory: $relPath');

  int total = 0;
  final files = dir.listSync(recursive: true).whereType<File>().toList()
    ..sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));

  for (final file in files) {
    final size = file.lengthSync();
    total += size;
    final fileRel = file.path.replaceFirst('$repoRoot/', '');
    report.writeln('  ${_formatBytes(size).padLeft(10)}  $fileRel');
  }

  final totalStr = _formatBytes(total);
  final budgetStr = _formatBytes(budget.totalBytes);
  final pct = total * 100 ~/ budget.totalBytes;

  if (total > budget.totalBytes) {
    violations.add(
      '$relPath: $totalStr > budget $budgetStr ($pct%) — ${budget.label}',
    );
    report.writeln(
      '  TOTAL: $totalStr / $budgetStr ($pct%) [FAIL] ${budget.label}',
    );
  } else {
    report.writeln(
      '  TOTAL: $totalStr / $budgetStr ($pct%) [OK  ] ${budget.label}',
    );
  }
  return total;
}

void _emitRecommendations(String repoRoot, StringBuffer report) {
  report.writeln('Recommendations:');

  final soundsDir = Directory('$repoRoot/apps/helix_local/assets/sounds');
  if (soundsDir.existsSync()) {
    final mp3s = soundsDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => _extension(f.path).toLowerCase() == '.mp3')
        .toList();
    final totalMp3 = mp3s.fold<int>(0, (s, f) => s + f.lengthSync());
    if (totalMp3 > 2 * 1024 * 1024) {
      report.writeln(
        '  [ACTION] ${mp3s.length} MP3 files total ${_formatBytes(totalMp3)}.'
        ' Consider encoding at 64 kbps mono (≤ 100 KB per 15 s clip).'
        ' Use `ffmpeg -i input.mp3 -b:a 64k -ac 1 output.mp3`.',
      );
    }
  }

  final logo = File('$repoRoot/apps/helix_local/assets/logo.png');
  if (logo.existsSync() && logo.lengthSync() > 200 * 1024) {
    report.writeln(
      '  [ACTION] logo.png is ${_formatBytes(logo.lengthSync())}.'
      ' Compress with `pngquant --quality=65-80 logo.png`.',
    );
  }

  report.writeln(
    '  [INFO ] Product policy decision required before lazy-downloading optional'
    ' sound packs — consult privacy/network data-collection policy.',
  );
  report.writeln('');
}

String? _findRepoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/apps').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
  return null;
}

String _extension(String path) {
  final dot = path.lastIndexOf('.');
  if (dot == -1) return '';
  return path.substring(dot);
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  } else if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}
