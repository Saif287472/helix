import 'dart:io';

import 'package:helix_remote_architecture_rules/helix_remote_architecture_rules.dart';
import 'package:test/test.dart';

SourceFile _file(String path, List<String> uris) => SourceFile(
  path: path,
  directives: [
    for (var i = 0; i < uris.length; i++)
      Directive(kind: DirectiveKind.import, uri: uris[i], line: i + 1),
  ],
);

void main() {
  group('ForbiddenDirectiveRule', () {
    final rule = ForbiddenDirectiveRule(
      name: 'no-sqlite',
      reason: 'use the Db interface',
      forbidden: anyPackage({'sqlite3'}),
      appliesTo: (path) => path.startsWith('lib/'),
    );

    test('reports forbidden URIs in files it applies to', () {
      final violations = rule.check([
        _file('lib/a.dart', ['dart:io', 'package:sqlite3/sqlite3.dart']),
        _file('test/a_test.dart', ['package:sqlite3/sqlite3.dart']),
      ]).toList();
      expect(violations, hasLength(1));
      expect(violations.single.file, 'lib/a.dart');
      expect(violations.single.line, 2);
      expect(violations.single.message, 'use the Db interface');
    });
  });

  group('InternalDependencyRule', () {
    final rule = InternalDependencyRule(
      selfPackage: 'helix_remote_api',
      allowed: {'helix_remote_protocol'},
    );

    test(
      'allows itself, dart:, third-party, relative and allowed packages',
      () {
        final violations = rule.check([
          _file('lib/a.dart', [
            'dart:async',
            'package:helix_remote_api/src/b.dart',
            'package:http/http.dart',
            'src/c.dart',
            'package:helix_remote_protocol/protocol.dart',
          ]),
        ]);
        expect(violations, isEmpty);
      },
    );

    test('allows test-only packages from test/ but not from lib/', () {
      const uri =
          'package:helix_remote_architecture_rules/helix_remote_architecture_rules.dart';
      final violations = rule.check([
        _file('test/architecture_test.dart', [uri]),
        _file('lib/a.dart', [uri]),
      ]).toList();
      expect(violations.map((v) => v.file), ['lib/a.dart']);
    });

    test('rejects internal packages that are not allowed', () {
      final violations = rule.check([
        _file('lib/a.dart', ['package:helix_remote_db/db.dart']),
      ]).toList();
      expect(violations.single.uri, 'package:helix_remote_db/db.dart');
      expect(violations.single.message, contains('helix_remote_protocol'));
    });
  });

  group('ModuleBoundaryRule', () {
    final rule = ModuleBoundaryRule(packageName: 'srv');

    test(
      'allows own-module files, other modules\' api.dart and non-modules',
      () {
        final violations = rule.check([
          _file('lib/src/modules/identity/application/sign_in.dart', [
            'package:srv/src/modules/identity/data/accounts.dart',
            'package:srv/src/modules/keys/api.dart',
            'package:srv/src/platform/db/db.dart',
            '../../keys/api.dart',
          ]),
          _file('lib/src/server.dart', [
            'package:srv/src/modules/keys/data/prekeys.dart',
          ]),
        ]);
        expect(violations, isEmpty);
      },
    );

    test('rejects reaching into another module', () {
      final violations = rule.check([
        _file('lib/src/modules/identity/application/sign_in.dart', [
          'package:srv/src/modules/keys/data/prekeys.dart',
          '../../keys/domain/prekey.dart',
        ]),
      ]).toList();
      expect(violations.map((v) => v.line), [1, 2]);
      expect(
        violations.first.message,
        contains('lib/src/modules/keys/api.dart'),
      );
    });
  });

  group('v2PackageRules', () {
    test('rejects v1 packages and wrong-direction dependencies', () {
      final violations = checkAll([
        _file('lib/a.dart', [
          'package:helix_remote_storage/helix_remote_storage.dart',
          'package:helix_remote_engine/engine.dart',
          'package:helix_remote_protocol/protocol.dart',
        ]),
      ], v2PackageRules('helix_remote_db'));
      expect(violations.map((v) => v.rule).toSet(), {
        'dependency-direction:helix_remote_db',
        'no-v1-packages',
      });
      expect(
        violations.map((v) => v.uri),
        isNot(contains('package:helix_remote_protocol/protocol.dart')),
      );
    });

    test('refuses packages that are not declared v2 layers', () {
      expect(() => v2PackageRules('helix_remote_sync'), throwsArgumentError);
    });

    test('the declared layers only reference declared packages', () {
      for (final entry in v2PackageDependencies.entries) {
        expect(
          v2PackageDependencies.keys,
          containsAll(entry.value),
          reason: '${entry.key} depends on an undeclared package',
        );
        expect(entry.value, isNot(contains(entry.key)));
        expect(v1RetiredPackages.intersection(entry.value), isEmpty);
      }
    });
  });

  test('describeViolations lists every violation', () {
    const violation = Violation(
      rule: 'r',
      file: 'lib/a.dart',
      line: 3,
      uri: 'package:x/x.dart',
      message: 'm',
    );
    expect(describeViolations(const []), 'No architecture violations.');
    expect(
      describeViolations(const [violation]),
      contains('[r] lib/a.dart:3 -> package:x/x.dart: m'),
    );
  });

  test('this package imports no Helix Remote package', () {
    final files = scanDartSources(Directory.current.path);
    expect(files, isNotEmpty);
    final violations = checkAll(files, [
      InternalDependencyRule(
        selfPackage: 'helix_remote_architecture_rules',
        allowed: const {},
      ),
    ]);
    expect(violations, isEmpty, reason: describeViolations(violations));
  });
}
