import 'dart:io';

import 'package:test/test.dart';

import '../check_performance_budgets.dart';

void main() {
  // Absolute, so this suite does not care where `dart test` started or what
  // another suite in the same process did to the working directory.
  var root = Directory.current.absolute;
  while (!File('${root.path}/pubspec.lock').existsSync()) {
    final parent = root.parent;
    if (parent.path == root.path) {
      throw StateError('no helix_remote/pubspec.lock above ${root.path}');
    }
    root = parent;
  }
  final remote = '${root.path.replaceAll(r'\', '/')}/';
  bool exists(String relativeToRemote) =>
      File('$remote$relativeToRemote').existsSync() ||
      Directory('$remote$relativeToRemote').existsSync();

  List<String> check(String docText) => performanceBudgetFailures(
    docName: 'PERFORMANCE_BUDGETS.md',
    docText: docText,
    exists: exists,
  );

  /// The metric names the contract promises, so a path test is not also a
  /// metric test.
  final metrics = [
    '# Budgets',
    '| Cold start to usable Home (Remote, Android release) | ≤ 3 000 ms |',
    '| List frame time at 1 000 messages | ≤ 16 ms (p99) |',
    '| Jank frame rate (> 16 ms) at 1 000 messages | ≤ 1 % |',
  ].join('\n');

  test('the committed document runs against the committed repository', () {
    final doc = File('$remote../docs/performance/PERFORMANCE_BUDGETS.md');
    expect(check(doc.readAsStringSync()), isEmpty);
  });

  test('a command that names a test that does not exist fails', () {
    // AUD-18-5: the block told the reader to run
    // `flutter test app/test/phase4_performance_budget_test.dart`, a file that
    // was never in the repository.
    final failures = check(
      '$metrics\n\n```powershell\n'
      'flutter test app/test/phase4_performance_budget_test.dart\n```\n',
    );
    expect(failures, [
      contains('`app/test/phase4_performance_budget_test.dart` does not exist'),
    ]);
  });

  test(
    'a cd target that does not exist fails, and so does the path under it',
    () {
      // The same block also ran `cd backend`, the v1 directory deleted at the
      // Phase X cutover.
      final failures = check(
        '$metrics\n\n```powershell\n'
        'cd backend; dart test test/phase10_scalability_test.dart; cd ..\n'
        '```\n',
      );
      expect(failures, hasLength(2));
      expect(
        failures.first,
        contains('`cd backend` - that directory does not exist'),
      );
      expect(
        failures.last,
        contains(
          '`test/phase10_scalability_test.dart` does not exist (nor under '
          'backend)',
        ),
      );
    },
  );

  test('a path is resolved under the directory the block cd-ed into', () {
    // `dart run tool/load.dart` exists only once the block has run
    // `cd server`, and the checker has to follow that or it fails a real
    // command.
    expect(
      check(
        '$metrics\n\n```powershell\ncd server; dart run tool/load.dart; cd ..\n'
        '```\n',
      ),
      isEmpty,
    );
  });

  test('a withdrawn tool named in prose is a record, not a command', () {
    // The document says plainly which June tools were never built. Only the
    // fenced blocks tell a reader to run something.
    expect(
      check(
        '$metrics\n\nThe `tool/check_asset_sizes.dart` checker was never '
        'written.\n',
      ),
      isEmpty,
    );
  });

  test('a budget name dropped from the table is still reported', () {
    expect(
      check('# Budgets\n\n| List frame time at 1 000 messages | ≤ 16 ms |\n'),
      contains(
        'PERFORMANCE_BUDGETS.md no longer states the budget "Cold start '
        'to usable Home (Remote, Android release)"',
      ),
    );
  });

  test('a comment inside a block is not a command', () {
    expect(
      check(
        '$metrics\n\n```powershell\n'
        '# see app/test/no_such_helper.dart for the fixture\n'
        'flutter test app/test/performance_budget_test.dart\n```\n',
      ),
      isEmpty,
    );
  });
}
