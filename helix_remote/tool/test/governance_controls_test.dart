import 'dart:io';

import 'package:test/test.dart';

import '../check_governance_controls.dart';

/// The register's `Package` tables, written by hand for the parser tests.
String registerText(List<String> rows) =>
    ['| Package | Version |', '|---|---:|', ...rows].join('\n');

/// A `pubspec.lock` body resolving exactly [versions].
String lockText(Map<String, String> versions) => [
  'packages:',
  for (final e in versions.entries) ...[
    '  ${e.key}:',
    '    dependency: transitive',
    '    description:',
    '      name: ${e.key}',
    '      url: "https://pub.dev"',
    '    source: hosted',
    '    version: "${e.value}"',
  ],
].join('\n');

void main() {
  // The checker's default paths are relative to `helix_remote/` and `dart
  // test` starts in `tool/`, and another suite in the same process may move
  // the working directory: walk up once and pass absolute paths everywhere.
  var root = Directory.current.absolute;
  while (!File('${root.path}/pubspec.lock').existsSync()) {
    final parent = root.parent;
    if (parent.path == root.path) {
      throw StateError('no helix_remote/pubspec.lock above ${root.path}');
    }
    root = parent;
  }
  final remote = '${root.path.replaceAll(r'\', '/')}/';
  String at(String relativeToRemote) => '$remote$relativeToRemote';
  final realRegister = at('../docs/dependencies/DEPENDENCY_RISK_REGISTER.md');
  final realPolicy = at('../docs/dependencies/WORKSPACE_LOCKFILE_POLICY.md');
  final realWorkflow = at('../.github/workflows/ci.yml');
  final realLock = at('pubspec.lock');

  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('helix_governance'));
  tearDown(() => temp.deleteSync(recursive: true));
  String write(String name, String text) {
    final file = File('${temp.path}/$name')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    return file.path;
  }

  group('the register parser reads every package row (AUD-18-3)', () {
    test('the committed register parses with no gaps', () {
      final read = registerRows(File(realRegister).readAsLinesSync());
      expect(read.gaps, isEmpty);
      expect(read.rows.length, read.cells);
    });

    test('the rows the old regex skipped are read, not waved past', () {
      // A row like `| `shelf`, `shelf_router`, `http` | `1.4.2` / `1.1.4` /
      // `1.2.x` |` was invisible to the single-name pattern, so the register
      // claimed coverage it did not have.
      final read = registerRows(File(realRegister).readAsLinesSync());
      final names = read.rows.map((r) => r.name).toSet();
      expect(names, containsAll(['shelf_router', 'aws_common', 'drift_dev']));
      expect(
        read.rows.where((r) => r.name == 'http').map((r) => r.version).toSet(),
        {'1.6.0'},
        reason: 'http is documented twice; both rows must agree with the lock',
      );
    });

    test('a multi-package row is checked against the lockfile', () {
      // The audit's own test: this row passes a checker that skips comma
      // rows, and must fail naming `crypto` once it does not.
      final register = write(
        'DEPENDENCY_RISK_REGISTER.md',
        registerText(['| `http`, `crypto` | `1.6.0` / `0.0.0` |']),
      );
      final lock = write(
        'pubspec.lock',
        lockText({'http': '1.6.0', 'crypto': '3.0.7'}),
      );
      expect(
        registerVersionFailures(register: register, lockPath: lock),
        anyElement(
          allOf(contains('says crypto 0.0.0'), contains('resolves 3.0.7')),
        ),
      );
    });

    test('a row whose names and versions do not pair up fails by name', () {
      final register = write(
        'DEPENDENCY_RISK_REGISTER.md',
        registerText(['| `http`, `crypto` | `1.6.0` |']),
      );
      final lock = write(
        'pubspec.lock',
        lockText({'http': '1.6.0', 'crypto': '3.0.7'}),
      );
      final failures = registerVersionFailures(
        register: register,
        lockPath: lock,
      );
      expect(
        failures,
        anyElement(
          contains(
            'line 3: names 2 package(s) (http, crypto) but gives 1 '
            'version(s)',
          ),
        ),
      );
      // And the completeness guard, separately from the gap message, so a
      // future layout cannot reopen the gap quietly.
      expect(
        failures,
        anyElement(
          contains(
            'has 2 package cells but the checker read 0; add the '
            'layout to registerRows()',
          ),
        ),
      );
    });

    test('a package/version table that is not headed `Package` fails', () {
      final register = write(
        'DEPENDENCY_RISK_REGISTER.md',
        [
          '| Dependency | Version |',
          '|---|---:|',
          '| `yaml` | `9.9.9` |',
        ].join('\n'),
      );
      final lock = write('pubspec.lock', lockText({'yaml': '3.1.3'}));
      expect(
        registerVersionFailures(register: register, lockPath: lock),
        anyElement(
          contains(
            'a table headed "Dependency" pairs yaml with versions but '
            'is not a `Package` table',
          ),
        ),
      );
    });

    test('"Held at" ranges are exempt, but a version there is not', () {
      final exempt = registerRows([
        '| Package | Held at | Latest then |',
        '|---|---:|---:|',
        '| `connectivity_plus` | ^6.1.3 | 7.3.1 |',
      ]);
      expect(exempt.rows.single.heldAt, isTrue);
      expect(exempt.gaps, isEmpty);

      final register = write(
        'DEPENDENCY_RISK_REGISTER.md',
        [
          '| Package | Held at |',
          '|---|---:|',
          '| `connectivity_plus` | `7.3.1` |',
        ].join('\n'),
      );
      final lock = write(
        'pubspec.lock',
        lockText({'connectivity_plus': '7.3.1'}),
      );
      expect(
        registerVersionFailures(register: register, lockPath: lock),
        anyElement(contains('carries resolved versions')),
      );
    });

    test('an exemption the register stops naming is stale', () {
      final register = write(
        'DEPENDENCY_RISK_REGISTER.md',
        registerText(['| `http` | `1.6.0` |']),
      );
      final lock = write('pubspec.lock', lockText({'http': '1.6.0'}));
      expect(
        registerVersionFailures(register: register, lockPath: lock),
        anyElement(
          contains(
            'no longer names sqlite3_flutter_libs, so its exemption in '
            'check_governance_controls.dart is stale',
          ),
        ),
      );
    });

    test('the committed register agrees with the committed lockfile', () {
      expect(
        registerVersionFailures(register: realRegister, lockPath: realLock),
        isEmpty,
        reason:
            'a version in the register that the lockfile does not resolve '
            'is the documentation error AUD-18-3 was hiding',
      );
    });
  });

  group('the lockfile policy is checked against the repository (AUD-18-4)', () {
    const pin = 'pinned `flutter-version: 3.44.8`';
    const claims = '# Policy\n\n$pin\n';

    /// A `ci.yml` that does what the policy claims, at the given SDK pin(s).
    String ci({
      List<String> pins = const ['3.44.8'],
      bool enforce = true,
      bool sbom = true,
    }) {
      final steps = <String>[
        if (enforce) '      - run: flutter pub get --enforce-lockfile',
        if (sbom) '      - run: dart run tool/generate_sbom.dart pubspec.lock',
        for (final p in pins) '          flutter-version: $p',
      ];
      return write('ci.yml', '${steps.join('\n')}\n');
    }

    test('the committed policy matches the committed repository', () {
      expect(
        lockfilePolicyFailures(
          policy: realPolicy,
          workflow: realWorkflow,
          committedLockfiles: [realLock, at('../orbit/flutter/pubspec.lock')],
          gitignores: [at('.gitignore'), at('../orbit/flutter/.gitignore')],
        ),
        isEmpty,
      );
    });

    test('a lockfile the policy calls committed must exist', () {
      final missing = lockfilePolicyFailures(
        policy: write('policy.md', claims),
        workflow: ci(),
        committedLockfiles: [realLock, at('no_such_workspace.lock')],
        gitignores: const [],
      );
      expect(
        missing,
        anyElement(
          contains(
            'no_such_workspace.lock is the committed dependency snapshot, '
            'but it does not exist',
          ),
        ),
      );
    });

    test('a .gitignore rule for the lockfile contradicts the policy', () {
      // The workspace's .gitignore carries a comment explaining why the
      // lockfile is committed; a comment is not a rule, and a rule would
      // untrack what the policy guarantees.
      final ignored = lockfilePolicyFailures(
        policy: write('policy.md', claims),
        workflow: ci(),
        committedLockfiles: const [],
        gitignores: [write('gitignore', '# keep it\npubspec.lock\n')],
      );
      expect(
        ignored,
        anyElement(
          contains('ignores pubspec.lock (pubspec.lock), which contradicts'),
        ),
      );
    });

    test('a commented-out lockfile line is not a rule', () {
      expect(
        lockfilePolicyFailures(
          policy: write('policy.md', claims),
          workflow: ci(),
          committedLockfiles: const [],
          gitignores: [write('gitignore', '# pubspec.lock\n')],
        ),
        isEmpty,
      );
    });

    test('CI must run the flag the policy says it runs', () {
      expect(
        lockfilePolicyFailures(
          policy: write('policy.md', claims),
          workflow: ci(enforce: false),
          committedLockfiles: const [],
          gitignores: const [],
        ),
        anyElement(contains('claims CI runs "--enforce-lockfile"')),
      );
    });

    test('deleting the SBOM step fails the policy that promises it', () {
      expect(
        lockfilePolicyFailures(
          policy: write('policy.md', claims),
          workflow: ci(sbom: false),
          committedLockfiles: const [],
          gitignores: const [],
        ),
        anyElement(
          contains('claims CI runs "dart run tool/generate_sbom.dart"'),
        ),
      );
    });

    test('the SDK pin is compared, not just mentioned', () {
      expect(
        lockfilePolicyFailures(
          policy: write('policy.md', claims),
          workflow: ci(pins: const ['3.99.0']),
          committedLockfiles: const [],
          gitignores: const [],
        ),
        anyElement(
          allOf(contains('pinned at 3.44.8'), contains('uses 3.99.0')),
        ),
      );
    });

    test('a policy that drops the pin it used to state is reported', () {
      expect(
        lockfilePolicyFailures(
          policy: write('policy.md', '# Policy\n\nThe SDK is pinned.\n'),
          workflow: ci(),
          committedLockfiles: const [],
          gitignores: const [],
        ),
        anyElement(contains('no longer states the pinned `flutter-version:')),
      );
    });

    test('two different pins in one workflow is not one policy claim', () {
      expect(
        lockfilePolicyFailures(
          policy: write('policy.md', claims),
          workflow: ci(pins: const ['3.44.8', '3.45.0']),
          committedLockfiles: const [],
          gitignores: const [],
        ),
        anyElement(contains('more than one flutter-version')),
      );
    });

    test('the same pin in four jobs is still one pin', () {
      expect(
        lockfilePolicyFailures(
          policy: write('policy.md', claims),
          workflow: ci(pins: const ['3.44.8', '3.44.8', '3.44.8']),
          committedLockfiles: const [],
          gitignores: const [],
        ),
        isEmpty,
      );
    });
  });

  group('a forced CI run verifies the whole tree (AUD-18-2)', () {
    test('the committed workflow admits the bypass everywhere it must', () {
      expect(ciEventCoverageFailures(workflow: realWorkflow), isEmpty);
    });

    test('every verifying job that loses the bypass is named', () {
      // Reading the real file rather than a fixture: the invariant is about
      // this workflow, and a fixture would pass while the file regressed.
      final lines = File(realWorkflow).readAsLinesSync();
      final stripped = lines
          .where((l) => !l.contains("outputs.forced == 'true' ||"))
          .toList();
      expect(stripped.length, lessThan(lines.length));
      final failures = ciEventCoverageFailures(
        workflow: write('ci.yml', stripped.join('\n')),
      );
      for (final job in [
        'verify-windows',
        'verify-linux',
        'performance-budgets',
        'supply-chain',
      ]) {
        expect(failures, anyElement(contains("job '$job'")));
      }
      expect(
        failures.where((f) => f.contains('job ')),
        hasLength(4),
        reason:
            'the echo job still excludes the bypass, so only the four '
            'verifying jobs are reported',
      );
    });

    test('a job that checks the tree out must admit the bypass', () {
      expect(
        ciEventCoverageFailures(
          workflow: write(
            'ci.yml',
            [
              'jobs:',
              '  changes:',
              '    outputs:',
              '      forced: \${{ steps.forced.outputs.forced }}',
              '    steps:',
              '      - id: forced',
              "        run: test \"\$EVENT_NAME\" = \"schedule\" || test \"\$EVENT_NAME\" = \"workflow_dispatch\"",
              '  verify-linux:',
              '    needs: changes',
              "    if: needs.changes.outputs.remote == 'true'",
              '    steps:',
              '      - uses: actions/checkout@v4',
            ].join('\n'),
          ),
        ),
        anyElement(contains("job 'verify-linux'")),
      );
    });

    test('the echo job may not run on a forced run', () {
      final workflow = [
        'jobs:',
        '  changes:',
        '    outputs:',
        '      forced: \${{ steps.forced.outputs.forced }}',
        '    steps:',
        '      - id: forced',
        "        run: test \"\$EVENT_NAME\" = \"schedule\" || test \"\$EVENT_NAME\" = \"workflow_dispatch\"",
        '  no-source-changes:',
        '    needs: changes',
        "    if: needs.changes.outputs.remote != 'true'",
        '    steps:',
        '      - run: echo nothing changed',
      ].join('\n');
      expect(
        ciEventCoverageFailures(workflow: write('ci.yml', workflow)),
        anyElement(contains("job 'no-source-changes'")),
      );
      expect(
        ciEventCoverageFailures(
          workflow: write(
            'ci.yml',
            workflow.replaceFirst(
              "    if: needs.changes.outputs.remote != 'true'",
              "    if: >-\n"
                  "      needs.changes.outputs.forced != 'true' &&\n"
                  "      needs.changes.outputs.remote != 'true'",
            ),
          ),
        ),
        isEmpty,
      );
    });

    test('a workflow the reader cannot see is a failure, not a pass', () {
      expect(
        ciEventCoverageFailures(
          workflow: write('ci.yml', 'jobs:\n  other:\n    runs-on: ubuntu\n'),
        ),
        anyElement(contains('the AUD-18-2 guard cannot see this workflow')),
      );
    });

    test('the bypass covers both events that have no diff', () {
      final workflow = File(realWorkflow).readAsStringSync();
      final step = workflow.substring(workflow.indexOf('id: forced'));
      for (final event in ['schedule', 'workflow_dispatch']) {
        final dropped = step.replaceFirst('= "$event"', '= "nothing"');
        final edited = workflow.replaceFirst(step, dropped);
        expect(
          ciEventCoverageFailures(workflow: write('ci.yml', edited)),
          anyElement(contains('does not compare `$event`')),
          reason: 'a forced run of the dropped event verifies nothing',
        );
      }
    });
  });
}
