import 'dart:io';

void main() {
  final budgetFile = File('../docs/performance/PERFORMANCE_BUDGETS.md');
  if (!budgetFile.existsSync()) {
    stderr.writeln('Missing PERFORMANCE_BUDGETS.md');
    exitCode = 1;
    return;
  }
  final budget = budgetFile.readAsStringSync();
  const requiredMetrics = [
    'Cold start to usable Home (Remote, Android release)',
    'List frame time at 1 000 messages',
    'Jank frame rate (> 16 ms) at 1 000 messages',
  ];
  final missing = requiredMetrics.where((metric) => !budget.contains(metric));
  if (missing.isNotEmpty) {
    stderr.writeln(
      'Performance budget contract is incomplete: ${missing.join(', ')}',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln('Performance budget contract verified.');
}
