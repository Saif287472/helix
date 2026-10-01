import 'dart:io';

import 'package:helix_remote_architecture_rules/helix_remote_architecture_rules.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('parseDirectives', () {
    test('reads import, export and part, but not part of', () {
      final directives = parseDirectives('''
library;

import 'dart:async';
import "package:a/a.dart" show A;
export 'package:b/b.dart';
part 'src/c.dart';
part of 'd.dart';
''');
      expect(directives.map((d) => '${d.kind.name} ${d.uri} ${d.line}'), [
        'import dart:async 3',
        'import package:a/a.dart 4',
        'export package:b/b.dart 5',
        'part src/c.dart 6',
      ]);
    });

    test('skips line comments and block comments', () {
      final directives = parseDirectives('''
// import 'package:hidden/one.dart';
/*
import 'package:hidden/two.dart';
*/
/* one-line */ import 'package:seen/seen.dart';
import 'package:kept/kept.dart';
''');
      expect(directives.map((d) => d.uri), [
        'package:seen/seen.dart',
        'package:kept/kept.dart',
      ]);
    });

    test('collects conditional URIs on the same and following lines', () {
      final directives = parseDirectives('''
import 'stub.dart' if (dart.library.io) 'io.dart';
export 'a.dart'
    if (dart.library.js_interop) 'web.dart'
    if (dart.library.io) 'native.dart';
import 'after.dart';
''');
      expect(directives.map((d) => '${d.kind.name} ${d.uri} ${d.line}'), [
        'import stub.dart 1',
        'import io.dart 1',
        'export a.dart 2',
        'export web.dart 3',
        'export native.dart 4',
        'import after.dart 5',
      ]);
    });
  });

  group('packageOfUri', () {
    test('names the package, dart for SDK libraries, null for relative', () {
      expect(packageOfUri('package:foo/src/x.dart'), 'foo');
      expect(packageOfUri('dart:io'), 'dart');
      expect(packageOfUri('src/x.dart'), isNull);
      expect(packageOfUri('../x.dart'), isNull);
    });
  });

  group('SourceFile.resolveInPackage', () {
    const file = SourceFile(
      path: 'lib/src/modules/identity/http/routes.dart',
      directives: [],
    );

    test('maps own package URIs to lib/', () {
      expect(
        file.resolveInPackage(
          'package:srv/src/modules/keys/api.dart',
          packageName: 'srv',
        ),
        'lib/src/modules/keys/api.dart',
      );
    });

    test('resolves relative URIs against the file directory', () {
      expect(
        file.resolveInPackage('../../keys/data/repo.dart', packageName: 'srv'),
        'lib/src/modules/keys/data/repo.dart',
      );
    });

    test('returns null for other packages and SDK libraries', () {
      expect(
        file.resolveInPackage('package:other/x.dart', packageName: 'srv'),
        isNull,
      );
      expect(file.resolveInPackage('dart:io', packageName: 'srv'), isNull);
    });
  });

  group('scanDartSources', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('arch_scan_');
      void write(String path, String content) {
        File(p.join(root.path, path))
          ..createSync(recursive: true)
          ..writeAsStringSync(content);
      }

      write('lib/b.dart', "import 'package:x/x.dart';\n");
      write('lib/src/a.dart', "import 'dart:io';\n");
      write('test/a_test.dart', "import 'package:test/test.dart';\n");
      write('tool/ignored.dart', "import 'package:y/y.dart';\n");
      write('lib/notes.txt', "import 'package:z/z.dart';\n");
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('finds .dart files in lib, bin and test, sorted, with / paths', () {
      final files = scanDartSources(root.path);
      expect(files.map((f) => f.path), [
        'lib/b.dart',
        'lib/src/a.dart',
        'test/a_test.dart',
      ]);
      expect(files.first.directives.single.uri, 'package:x/x.dart');
    });

    test('honours exclude', () {
      final files = scanDartSources(
        root.path,
        exclude: (path) => path.startsWith('test/'),
      );
      expect(files.map((f) => f.path), ['lib/b.dart', 'lib/src/a.dart']);
    });
  });
}
