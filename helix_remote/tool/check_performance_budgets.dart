/// Checks the performance-budget document against the repository.
///
/// Two rules, both from AUD-18-5: the metric names the budget contract promises
/// are still in the file, and every command the file tells a reader to run
/// names paths that exist. A doc that says "no performance-sensitive change is
/// accepted without before/after evidence against these budgets" while its
/// runnable block points at files that were never written produces no evidence
/// at all - and the reader cannot tell.
///
/// Paths are relative to `helix_remote/`; `../` reaches repository-wide docs.
library;

import 'dart:io';

const _requiredMetrics = [
  'Cold start to usable Home (Remote, Android release)',
  'List frame time at 1 000 messages',
  'Jank frame rate (> 16 ms) at 1 000 messages',
];

final _dartPath = RegExp(r'[\w./-]+\.dart');

/// The failures of [docText] as the budget document, with commands resolved
/// against [workspace] (the directory the blocks say to run from) and the
/// `cd` targets inside them.
///
/// Only fenced blocks are read: the document also names withdrawn tools in
/// prose, and a withdrawn name in a sentence is a record, not a command.
List<String> performanceBudgetFailures({
  required String docName,
  required String docText,
  required bool Function(String relativeToWorkspace) exists,
}) {
  final failures = <String>[];
  for (final metric in _requiredMetrics) {
    if (!docText.contains(metric)) {
      failures.add('$docName no longer states the budget "$metric"');
    }
  }

  var cwd = '';
  var inFence = false;
  final lines = docText.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trimRight();
    if (line.trimLeft().startsWith('```')) {
      inFence = !inFence;
      cwd = '';
      continue;
    }
    if (!inFence) continue;
    // `cd server; dart run tool/load.dart; cd ..` is one line: each statement
    // is read in order, with the directory the ones before it left.
    for (final part in line.split(';')) {
      final statement = part.trim();
      if (statement.isEmpty || statement.startsWith('#')) continue;
      if (statement.startsWith('cd ')) {
        final target = statement.substring(3).trim();
        if (target.isEmpty || target == '.') continue;
        if (target == '..') {
          cwd = cwd.contains('/') ? cwd.substring(0, cwd.lastIndexOf('/')) : '';
          continue;
        }
        cwd = cwd.isEmpty ? target : '$cwd/$target';
        if (!exists(cwd)) {
          failures.add(
            '$docName line ${i + 1}: `cd $cwd` - that directory does not '
            'exist, so the commands under it cannot be run',
          );
        }
        continue;
      }
      for (final match in _dartPath.allMatches(statement)) {
        final path = match[0]!;
        final attempts = [if (cwd.isEmpty) path else '$cwd/$path', path];
        if (attempts.any(exists)) continue;
        failures.add(
          '$docName line ${i + 1}: `$path` does not exist'
          '${cwd.isEmpty ? '' : ' (nor under $cwd)'}, so the command that '
          'names it cannot be run',
        );
      }
    }
  }
  return failures;
}

void main() {
  const docPath = '../docs/performance/PERFORMANCE_BUDGETS.md';
  final budgetFile = File(docPath);
  if (!budgetFile.existsSync()) {
    stderr.writeln('Missing $docPath');
    exitCode = 1;
    return;
  }
  final failures = performanceBudgetFailures(
    docName: docPath,
    docText: budgetFile.readAsStringSync(),
    exists: (relative) =>
        File(relative).existsSync() || Directory(relative).existsSync(),
  );
  if (failures.isNotEmpty) {
    stderr.writeln('Performance budget contract is incomplete:');
    for (final failure in failures) {
      stderr.writeln(' - $failure');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('Performance budget contract verified.');
}
