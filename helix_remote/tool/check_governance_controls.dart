/// Keeps governance claims tied to concrete repository evidence.
///
/// §21 of the enterprise readiness audit records "governance documents
/// asserting controls that do not exist in code" as small debt at a *high*
/// interest rate: a document that is confidently wrong is worse than a missing
/// one, because reviewers trust it and skip the check it existed to prompt.
/// Three such documents were found in one pass — `LOG_REDACTION.md` required
/// redaction the client did not perform, `WORKSPACE_LOCKFILE_POLICY.md`
/// described a committed lockfile that was actively gitignored, and
/// `DEPENDENCY_RISK_REGISTER.md` misclassified a direct dependency as
/// transitive.
///
/// This gate is what stops that recurring. Add a row whenever a document makes
/// a durable implementation assertion.
///
/// Paths are relative to `helix_remote/`; `../` reaches repository-wide docs
/// that also govern Helix Remote.
library;

import 'dart:io';

/// A claim that must be evidenced somewhere in the repository.
///
/// [marker] is required to be present in [path] — or, when [absent] is true,
/// required to be *missing* from it. The absent form is what catches a
/// correction being reverted: re-asserting a withdrawn claim is a silent
/// regression that a "must contain" check cannot see.
class GovernanceControl {
  const GovernanceControl(
    this.name,
    this.path,
    this.marker, {
    this.absent = false,
    this.because,
  });

  final String name;
  final String path;
  final String marker;
  final bool absent;

  /// Why the claim matters, printed on failure so whoever trips this gate does
  /// not have to reconstruct the reasoning from the audit.
  final String? because;

  String? evaluate() {
    final file = File(path);
    if (!file.existsSync()) {
      return '$name: $path does not exist';
    }
    final contents = file.readAsStringSync();
    final present = contents.contains(marker);
    if (present == absent) {
      final requirement = absent
          ? '$path must NOT contain "$marker"'
          : '$path must contain "$marker"';
      final reason = because == null ? '' : '\n     ${because!}';
      return '$name: $requirement$reason';
    }
    return null;
  }
}

const controls = <GovernanceControl>[
  // --- Platform and product decisions -------------------------------------
  GovernanceControl(
    'iOS support decision',
    'docs/adr/023-ios-support-decision.md',
    'does not currently ship an iOS target',
  ),
  GovernanceControl(
    'server architecture decision',
    'docs/adr/025-postgres-stateless-server.md',
    'PostgreSQL',
    because:
        'ADR-025 replaced the SQLite server (ADR-022 is historical); the '
        'handoff and the verify scripts assume Postgres.',
  ),
  GovernanceControl(
    'release obfuscation',
    'scripts/remote_release_gate.ps1',
    '--obfuscate',
  ),

  // --- HIGH-3: backup refusal ---------------------------------------------
  GovernanceControl(
    'Android backup refusal',
    'app/android/app/src/main/AndroidManifest.xml',
    'android:allowBackup="false"',
    because:
        'HIGH-3 — the app-private directory holds the SQLCipher database '
        'and the diagnostic log; the platform default is allowBackup=true.',
  ),

  // --- Transport security --------------------------------------------------
  GovernanceControl(
    'Android release config forbids cleartext traffic',
    'app/android/app/src/main/res/xml/helix_remote_network_security.xml',
    'base-config cleartextTrafficPermitted="false"',
  ),
  GovernanceControl(
    'Android release config carries no pin that Dart would ignore',
    'app/android/app/src/main/res/xml/helix_remote_network_security.xml',
    '<pin-set',
    absent: true,
    because:
        'network_security_config only governs the platform HTTP stack. The '
        'app\'s traffic is Dart\'s, so a pin here protects nothing and only '
        'looks like protection. Pinning lives in tls_pinning.dart.',
  ),
  GovernanceControl(
    'TLS pinning is off unless a build defines pins',
    'app/lib/core/platform/tls_pinning.dart',
    'enforce: !debug && pins.isNotEmpty',
    because:
        'no pin is built in (a stale one locks every release build out of '
        'Orbit Home); HELIX_GLOBAL_PINS turns pinning on at build time.',
  ),

  // --- Screenshots are allowed (product rule, 2026-09-30) ------------------
  GovernanceControl(
    'no screen-capture blocking on Android',
    'app/android/app/src/main/kotlin/com/helix/remote/MainActivity.kt',
    'FLAG_SECURE',
    absent: true,
    because:
        'people need to screenshot chats; capture blocking was removed on '
        '2026-09-30 and must not come back (AGENTS.md, product rules).',
  ),
  GovernanceControl(
    'no screen-capture blocking on Windows (handler is not built)',
    'app/windows/runner/CMakeLists.txt',
    'screen_security.cpp',
    absent: true,
    because:
        'the Windows display-affinity handler was removed with Android\'s.',
  ),
  GovernanceControl(
    'no screen-capture blocking on Windows (no display affinity)',
    'app/windows/runner/flutter_window.cpp',
    'SetWindowDisplayAffinity',
    absent: true,
    because: 'screenshots are allowed everywhere.',
  ),
  GovernanceControl(
    'a test keeps screenshots allowed',
    'app/test/product_rules_test.dart',
    'screenshots are allowed everywhere',
  ),

  // --- LOW-1: release shrinking ----------------------------------------------
  GovernanceControl(
    'release builds are minified',
    'app/android/app/build.gradle.kts',
    'isMinifyEnabled = true',
    because:
        'LOW-1 — shipping without R8 leaves debug metadata in the artifact. '
        'The v1 regression test for it was deleted with v1.',
  ),
  GovernanceControl(
    'release builds shrink resources',
    'app/android/app/build.gradle.kts',
    'isShrinkResources = true',
  ),

  // --- Logs and problem reports: no secrets, no content ---------------------
  GovernanceControl(
    'server logs are redacted at the write boundary',
    'server/lib/src/platform/observability/log.dart',
    'redactFields',
    because:
        'AGENTS.md: never log passwords, tokens, keys, message content, '
        'codes or full phone numbers. Redaction must stay where every call '
        'site goes through it.',
  ),
  GovernanceControl(
    'a test proves the log redaction',
    'server/test/platform/infra_test.dart',
    'redact',
  ),
  GovernanceControl(
    'the request id reaches the request log line',
    'server/lib/src/platform/http/pipeline.dart',
    "'request_id': requestId",
    because:
        'a request that cannot be found in the log by its id cannot be '
        'correlated with a client report.',
  ),

  // --- HIGH-4 / MED-9: dependency governance -------------------------------
  // HIGH-4's claim - the workspace commits its lockfiles and CI resolves with
  // `--enforce-lockfile` - is checked against the repository, not against this
  // policy's own text, by `lockfilePolicyFailures()` below (AUD-18-4). A
  // `contains` control on the policy was self-referential: it passed while the
  // guarantee it named had no owner.
  GovernanceControl(
    'file_picker is recorded as a direct dependency',
    '../docs/dependencies/DEPENDENCY_RISK_REGISTER.md',
    'not directly declared by Helix',
    absent: true,
    because:
        'MED-9 — file_picker IS directly declared in app/pubspec.yaml. '
        'The claim came from reading direct-vs-transitive off a workspace '
        'root lockfile, which classifies from the root package. Do not '
        'reinstate it.',
  ),
  GovernanceControl(
    'the file_picker prerelease exception is retired',
    'docs/adr/024-file-picker-prerelease-exception.md',
    'Retired (2026-10-14',
    because:
        'G-01 — the app resolves stable file_picker 13.1.0; the exception '
        'must not quietly come back.',
  ),
  GovernanceControl(
    'file_picker is still declared where the register says it is',
    'app/pubspec.yaml',
    'file_picker:',
    because: 'if this moves, the risk register entry needs to move with it.',
  ),
  GovernanceControl(
    'stale drift generated code fails CI',
    '../.github/workflows/ci.yml',
    'dart run tool/codegen.dart --check',
    because:
        'the risk register accepts drift_dev and build_runner on the '
        'condition that committed generated code can never silently diverge '
        'from the schema (ADR-027).',
  ),
  GovernanceControl(
    'the local database keeps the SQLCipher at-rest tests',
    'packages/helix_remote_db/test/encryption_test.dart',
    'P2-01 encrypted database rejects a wrong key',
    because:
        'the register carries the P2-01 wrong-key and no-plaintext tests '
        'over to helix_remote_db; the at-rest promise depends on them.',
  ),

  // --- MED-4: problem reports (the anomaly log) ----------------------------
  // The owner decided on 2026-10-21 that every build sends problem reports,
  // with no opt-in (PRIVACY_CLAIM_MATRIX). What must hold instead: they are
  // wired, they are masked on the device, and they go to the app's own
  // server and nowhere else.
  GovernanceControl(
    'the anomaly log is wired to the zone handlers',
    'app/lib/main.dart',
    'AnomalyLog.crash',
    because:
        'MED-4: the consent and event types once existed with no caller, '
        'so nothing was ever reported. The wiring is the control.',
  ),
  GovernanceControl(
    'refused requests reach the anomaly log',
    'app/lib/core/engine/helix_runtime.dart',
    'AnomalyLog.request(failure',
  ),
  GovernanceControl(
    'problem reports are masked on the device',
    'app/lib/core/diagnostics/anomaly_log.dart',
    'static String mask(String text)',
    because:
        'AGENTS.md: never send tokens, keys or full phone numbers. The '
        'server redacts again, but the device must not rely on it.',
  ),
  GovernanceControl(
    'a test proves the masking',
    'app/test/diagnostics/anomaly_log_test.dart',
    'are masked in every build',
  ),
  GovernanceControl(
    'the problem-report sink is self-hosted',
    'server/lib/src/modules/ops/module.dart',
    'Routes.anomalies',
    because:
        'MED-4 asked for a self-hosted sink specifically. A vendor SDK '
        'in the client would satisfy the letter and not the intent.',
  ),
];

/// Every `.dart` path the regression matrix names must exist, so the matrix
/// cannot come to describe tests that were renamed or deleted. Paths in the
/// matrix are relative to `helix_remote/`.
List<String> regressionMatrixFailures() {
  const matrix = 'docs/security/REGRESSION_TEST_MATRIX.md';
  final file = File(matrix);
  if (!file.existsSync()) return ['$matrix does not exist'];
  final paths = RegExp(
    r'`([A-Za-z0-9_./-]+\.dart)`',
  ).allMatches(file.readAsStringSync()).map((m) => m.group(1)!).toSet();
  return [
    if (paths.isEmpty) '$matrix names no test files',
    for (final path in paths)
      if (!File(path).existsSync()) '$matrix names $path, which does not exist',
  ];
}

/// Packages the register names that are not in Helix Remote's lockfile, with
/// the reason. Anything else the register names must be in it.
const _notInRemoteLock = {
  // Resolved by Helix Local's workspace, which has its own lockfile.
  'sqlite3_flutter_libs',
};

/// `pubspec.lock` entries as `name -> resolved version`.
Map<String, String> lockVersions(String lockText) {
  final resolved = <String, String>{};
  for (final m in RegExp(
    r'^  ([a-z0-9_]+):\r?\n(?:    .*\r?\n)*?    version: "([^"]+)"',
    multiLine: true,
  ).allMatches(lockText)) {
    resolved[m.group(1)!] = m.group(2)!;
  }
  return resolved;
}

/// The cells of a markdown table row (the outer pipes dropped).
List<String> _rowCells(String line) {
  final cells = line.split('|');
  if (cells.length > 1) {
    if (cells.first.trim().isEmpty) cells.removeAt(0);
    if (cells.last.trim().isEmpty) cells.removeLast();
  }
  return cells.map((c) => c.trim()).toList();
}

/// Whether [line] is the `|---|---:|` rule under a table header.
bool _isTableRule(String line) {
  final cells = _rowCells(line);
  return cells.isNotEmpty &&
      cells.every((c) => RegExp(r'^:?-{2,}:?$').hasMatch(c));
}

final _ticked = RegExp('`([^`]+)`');

/// A `Package` cell names pub.dev packages: lower-case, digits and underscores.
final _looksLikePackageName = RegExp(r'^[a-z][a-z0-9_]*$');

/// A version cell is a number with at least one dot, optionally with a caret,
/// tilde or comparator in front of it.
final _looksLikeVersion = RegExp(r'^[\^~]?\d+(\.\d+)+');

List<String> _names(String cell) =>
    _ticked.allMatches(cell).map((m) => m.group(1)!).toList();

/// Every `Package` table of the dependency register, as `(header, rows)` with
/// the 1-based line each row starts on.
List<({List<String> header, List<({int line, List<String> cells})> rows})>
_packageTables(List<String> lines) {
  final tables =
      <({List<String> header, List<({int line, List<String> cells})> rows})>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (!line.trimLeft().startsWith('|') ||
        i + 1 >= lines.length ||
        !_isTableRule(lines[i + 1])) {
      continue;
    }
    final header = _rowCells(line);
    final rows = <({int line, List<String> cells})>[];
    var next = i + 2;
    while (next < lines.length && lines[next].trimLeft().startsWith('|')) {
      rows.add((line: next + 1, cells: _rowCells(lines[next])));
      next++;
    }
    tables.add((header: header, rows: rows));
    i = next - 1;
  }
  return tables;
}

/// One package a `Package` table row names, with the version the same row
/// gives it. [heldAt] is the register's one explicit exemption: the "Held at"
/// column holds a range (`^18.0.0`), not a resolution, so it cannot be
/// compared with the lockfile - but the package must still be in it.
typedef RegisterRow = ({String name, String? version, bool heldAt});

/// Every package row of every `Package` table in the register, plus the rows
/// the checker cannot read at all.
///
/// A row may name several packages in one cell (`` `shelf`, `shelf_router` ``
/// or `` `a` + `b` ``) and pair them with the same number of versions
/// (`` `1.4.2` / `1.1.4` ``), and a version cell may carry a note outside its
/// backticks (`` `4.10.1` (already resolved transitively) ``). A row whose
/// counts do not line up is a gap, never a silent skip: AUD-18-3 found nine
/// rows skipped while the register claimed "any table".
({List<RegisterRow> rows, List<String> gaps, int cells}) registerRows(
  List<String> lines, {
  String register = 'DEPENDENCY_RISK_REGISTER.md',
}) {
  final rows = <RegisterRow>[];
  final gaps = <String>[];
  var cells = 0;
  for (final table in _packageTables(lines)) {
    if (table.header.isEmpty) continue;
    final isPackageTable = table.header.first.toLowerCase() == 'package';
    if (!isPackageTable) {
      // A table the checker does not read is how AUD-18-3 stayed hidden: the
      // register claimed "any table" while rows in a differently headed table
      // were skipped. Name one rather than silently not checking it.
      for (final row in table.rows) {
        if (row.cells.length < 2) continue;
        final packages = _names(
          row.cells[0],
        ).where((n) => _looksLikePackageName.hasMatch(n)).toList();
        final versions = _names(
          row.cells[1],
        ).where((v) => _looksLikeVersion.hasMatch(v)).toList();
        if (packages.isEmpty || versions.isEmpty) continue;
        gaps.add(
          '$register line ${row.line}: a table headed '
          '"${table.header[0]}" pairs ${packages.join(', ')} with versions but '
          'is not a `Package` table, so registerRows() does not check it',
        );
      }
      continue;
    }
    final holdsRanges =
        table.header.length > 1 &&
        table.header[1].toLowerCase().startsWith('held at');
    for (final row in table.rows) {
      if (row.cells.isEmpty) continue;
      final names = _names(row.cells.first);
      final versions = row.cells.length > 1 ? _names(row.cells[1]) : const [];
      cells += names.length;
      if (names.isEmpty) {
        gaps.add(
          '$register line ${row.line}: a row of a Package table names no '
          '`package`, so nothing here can be checked',
        );
        continue;
      }
      if (holdsRanges) {
        if (versions.isNotEmpty) {
          gaps.add(
            '$register line ${row.line}: a "Held at" row carries resolved '
            'versions (${versions.join(', ')}); only ranges are exempt',
          );
          continue;
        }
        rows.addAll([
          for (final name in names) (name: name, version: null, heldAt: true),
        ]);
        continue;
      }
      if (versions.length != names.length) {
        gaps.add(
          '$register line ${row.line}: names ${names.length} package(s) '
          '(${names.join(', ')}) but gives ${versions.length} version(s) - '
          r'a Package table row needs one `version` per `package`, or it is '
          'checked only partly',
        );
        continue;
      }
      for (var i = 0; i < names.length; i++) {
        rows.add((name: names[i], version: versions[i], heldAt: false));
      }
    }
  }
  return (rows: rows, gaps: gaps, cells: cells);
}

/// The register's claim (`tool/check_governance_controls.dart` fails when a
/// version in it differs from the lockfile) applied to *every* table, with the
/// "Held at" ranges exempted explicitly rather than accidentally.
List<String> registerVersionFailures({
  String register = '../docs/dependencies/DEPENDENCY_RISK_REGISTER.md',
  String lockPath = 'pubspec.lock',
}) {
  final regFile = File(register);
  final lockFile = File(lockPath);
  if (!regFile.existsSync()) return ['$register does not exist'];
  if (!lockFile.existsSync()) return ['$lockPath does not exist'];
  final resolved = lockVersions(lockFile.readAsStringSync());
  final read = registerRows(regFile.readAsLinesSync(), register: register);
  final failures = <String>[...read.gaps];
  final named = <String>{};
  var compared = 0;
  for (final row in read.rows) {
    named.add(row.name);
    if (row.heldAt) continue;
    compared++;
    final version = row.version!;
    if (_notInRemoteLock.contains(row.name)) continue;
    final locked = resolved[row.name];
    if (locked == null) {
      failures.add(
        '$register lists ${row.name}, which $lockPath does not resolve',
      );
    } else if (locked != version) {
      failures.add(
        '$register says ${row.name} $version; $lockPath resolves $locked',
      );
    }
  }
  // The completeness guard: a package cell the parser did not hand back is a
  // row that looks like prose and checks nothing. Counted separately from
  // `failures` so a new table layout cannot reopen AUD-18-3 quietly.
  if (read.rows.length != read.cells) {
    failures.add(
      '$register has ${read.cells} package cells but the checker read '
      '${read.rows.length}; add the layout to registerRows()',
    );
  }
  for (final exempt in _notInRemoteLock) {
    if (!named.contains(exempt)) {
      failures.add(
        '$register no longer names $exempt, so its exemption in '
        'check_governance_controls.dart is stale - drop it',
      );
    }
  }
  if (compared == 0) failures.add('$register has no package rows to check');
  return failures;
}

/// The lockfile policy's factual claims, checked against the repository
/// rather than against the policy's own text (AUD-18-4). A `contains` control
/// on the policy is self-referential: it passes while the claim it names is
/// unowned.
List<String> lockfilePolicyFailures({
  String policy = '../docs/dependencies/WORKSPACE_LOCKFILE_POLICY.md',
  String workflow = '../.github/workflows/ci.yml',
  List<String> committedLockfiles = const [
    'pubspec.lock',
    '../orbit/flutter/pubspec.lock',
  ],
  List<String> gitignores = const ['.gitignore', '../orbit/flutter/.gitignore'],
}) {
  final failures = <String>[];
  final policyFile = File(policy);
  final workflowFile = File(workflow);
  if (!policyFile.existsSync()) return ['$policy does not exist'];
  if (!workflowFile.existsSync()) return ['$workflow does not exist'];
  final policyText = policyFile.readAsStringSync();
  final workflowText = workflowFile.readAsStringSync();

  for (final lock in committedLockfiles) {
    if (!File(lock).existsSync()) {
      failures.add(
        '$policy says $lock is the committed dependency snapshot, but it '
        'does not exist',
      );
    }
  }
  for (final marker in const [
    '--enforce-lockfile',
    'dart run tool/generate_sbom.dart',
  ]) {
    if (!workflowText.contains(marker)) {
      failures.add(
        '$policy claims CI runs "$marker", but $workflow does not contain it',
      );
    }
  }
  // A rule, not a comment: the workspace's .gitignore explains in a comment
  // why the lockfile is committed, and must never also ignore it.
  for (final gitignore in gitignores) {
    final file = File(gitignore);
    if (!file.existsSync()) continue;
    for (final line in file.readAsLinesSync()) {
      final text = line.trim();
      if (text.startsWith('#') || text.isEmpty) continue;
      if (text.contains('pubspec.lock')) {
        failures.add(
          '$gitignore ignores pubspec.lock ($text), which contradicts '
          '$policy: a lockfile it calls committed cannot be untracked',
        );
      }
    }
  }
  final pin = RegExp(r'flutter-version: ([0-9.]+)');
  final policyPin = pin.firstMatch(policyText)?.group(1);
  final ciPins = pin.allMatches(workflowText).map((m) => m.group(1)!).toSet();
  if (policyPin == null) {
    failures.add(
      '$policy no longer states the pinned `flutter-version:`, so the pin in '
      '$workflow cannot be compared with it',
    );
  } else if (ciPins.isEmpty) {
    failures.add('$workflow pins no flutter-version the policy can describe');
  } else if (ciPins.length > 1) {
    failures.add(
      '$workflow pins more than one flutter-version (${ciPins.join(', ')}); '
      '$policy names one ($policyPin)',
    );
  } else if (ciPins.single != policyPin) {
    failures.add(
      '$policy says the SDK is pinned at $policyPin; $workflow uses '
      '${ciPins.single}',
    );
  }
  return failures;
}

/// One job of the CI workflow: its name, the `if:` that gates it (line
/// continuations folded into one string), whether it checks the repository out
/// — that is, verifies the tree rather than describing what it did not do —
/// and the jobs it waits for.
typedef CiJob = ({
  String name,
  String gate,
  bool verifies,
  List<String> needs,
  String body,
});

/// The jobs of [text], read from the shape `.github/workflows/ci.yml` is
/// written in: two-space job names under `jobs:`, four-space keys, six-space
/// steps. Deliberately not a YAML parser; a workflow restructured out of this
/// shape makes [ciEventCoverageFailures] report that it read no gated jobs
/// rather than pass quietly.
List<CiJob> ciJobs(String text) {
  final lines = text.split('\n');
  final jobs = <CiJob>[];
  var inJobs = false;
  var name = '';
  var body = <String>[];
  var gate = <String>[];
  var needs = <String>[];
  var verifying = false;
  var insideIf = false;
  void flush() {
    if (name.isEmpty) return;
    jobs.add((
      name: name,
      gate: gate.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
      verifies: verifying,
      needs: needs,
      body: body.join('\n'),
    ));
    name = '';
    body = [];
    gate = [];
    needs = [];
    verifying = false;
  }

  for (final raw in lines) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    if (line == 'jobs:') {
      inJobs = true;
      continue;
    }
    if (!inJobs) continue;
    if (line.trimLeft().isEmpty || line.startsWith('  #') || line.isEmpty) {
      if (name.isNotEmpty) body.add(line);
      continue;
    }
    if (!line.startsWith(' ')) {
      // Back to a top-level key: the job list is over.
      flush();
      inJobs = false;
      continue;
    }
    final jobName = RegExp(r'^  ([A-Za-z0-9_-]+):\s*$').firstMatch(line);
    if (jobName != null) {
      flush();
      name = jobName.group(1)!;
      insideIf = false;
      continue;
    }
    if (name.isEmpty) continue;
    body.add(line);
    final indent = line.length - line.trimLeft().length;
    if (indent == 4) {
      insideIf = false;
      final inlineIf = RegExp(r'^    if:\s*(\S.*)$').firstMatch(line);
      if (RegExp(r'^    if:\s*[>|]-?\s*$').hasMatch(line)) {
        insideIf = true;
      } else if (inlineIf != null) {
        gate.add(inlineIf.group(1)!);
      } else if (RegExp(r'^    needs:\s*(\S.*)$').hasMatch(line)) {
        needs.add(line.substring(line.indexOf(':') + 1).trim());
      } else if (line == '    needs:') {
        // List form; the items follow at indent 6.
      }
    } else if (insideIf && indent > 4) {
      gate.add(line.trim());
    }
    if (indent > 4 && !insideIf) {
      needs.addAll(
        RegExp(
          r'^ +- +([A-Za-z0-9_-]+)\s*$',
        ).allMatches(line).map((m) => m.group(1)!),
      );
    }
    if (line.contains('uses: actions/checkout@')) verifying = true;
  }
  flush();
  return jobs;
}

/// AUD-18-2: `dorny/paths-filter` describes a *diff*, so a `schedule` or
/// `workflow_dispatch` run gets the filters of the tip commit only. Without a
/// bypass those runs - the ones whose whole purpose is to re-verify an
/// unchanged tree - consist of the "no changes" echo and report green having
/// verified nothing, including the only unattended vulnerability scan. The
/// bypass is the `changes.forced` output; this asserts every job that reads
/// the filters has ORed it in, and the echo job has excluded it.
List<String> ciEventCoverageFailures({
  String workflow = '../.github/workflows/ci.yml',
}) {
  final file = File(workflow);
  if (!file.existsSync()) return ['$workflow does not exist'];
  final text = file.readAsStringSync();
  final jobs = ciJobs(text);
  final gated = jobs.where((j) => j.needs.contains('changes')).toList();
  if (gated.isEmpty) {
    return [
      '$workflow was read as ${jobs.length} job(s) and none waits on the '
          '`changes` filter; the AUD-18-2 guard cannot see this workflow - fix '
          'ciJobs() before trusting it',
    ];
  }
  final failures = <String>[];
  final changes = jobs.where((j) => j.name == 'changes').toList();
  if (changes.length != 1) {
    failures.add(
      '$workflow must have exactly one `changes` job for the verify jobs to '
      'wait on (found ${changes.length})',
    );
  } else {
    final body = changes.single.body;
    if (!body.contains('steps.forced.outputs.forced')) {
      failures.add(
        "$workflow's `changes` job publishes no `forced` output, so a "
        'scheduled or dispatched run has nothing to bypass the path filters '
        'with (AUD-18-2)',
      );
    }
    if (!body.contains('id: forced')) {
      failures.add(
        "$workflow's `forced` output is not produced by a step with "
        '`id: forced`',
      );
    }
    for (final event in const ['schedule', 'workflow_dispatch']) {
      // The event name as a compared string literal, not as prose: the step
      // above it is a comment that says "a scheduled or dispatched run".
      if (!RegExp('''['"]$event['"]''').hasMatch(body)) {
        failures.add(
          "$workflow's `forced` step does not compare `$event` by name, so "
          'that event still runs only the filters of the tip commit',
        );
      }
    }
  }
  for (final job in gated) {
    if (job.name == 'changes') continue;
    final admits = job.gate.contains("""forced == 'true'""");
    final excludes = job.gate.contains("""forced != 'true'""");
    if (job.verifies) {
      if (!admits) {
        failures.add(
          "$workflow job '${job.name}' checks the tree out but its `if:` "
          "never admits needs.changes.outputs.forced == 'true': a scheduled "
          'or dispatched run skips it and reports green anyway (AUD-18-2)',
        );
      }
    } else if (!excludes) {
      failures.add(
        "$workflow job '${job.name}' does not check the tree out, so its "
        "`if:` must exclude the bypass "
        "(needs.changes.outputs.forced != 'true'): on a scheduled or "
        'dispatched run it must either verify something or stay silent, not '
        'report that the tree needed nothing (AUD-18-2). If this job does '
        "verify, OR forced == 'true' into its `if:` instead.",
      );
    }
  }
  return failures;
}

void main() {
  final missing = <String>[];
  for (final control in controls) {
    final failure = control.evaluate();
    if (failure != null) missing.add(failure);
  }
  missing.addAll(regressionMatrixFailures());
  missing.addAll(registerVersionFailures());
  missing.addAll(lockfilePolicyFailures());
  missing.addAll(ciEventCoverageFailures());

  if (missing.isNotEmpty) {
    stderr.writeln('Governance control verification failed:');
    for (final failure in missing) {
      stderr.writeln(' - $failure');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Governance control verification passed (${controls.length} controls).',
  );
}
