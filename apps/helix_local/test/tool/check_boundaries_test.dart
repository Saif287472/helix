import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../../tool/check_boundaries.dart';

void main() {
  test('valid imports pass', () async {
    final project = await _project({
      'lib/core/constants.dart': 'const appName = "Helix";',
      'lib/services/chat.dart':
          "import 'package:helix_local_domain/core/constants.dart';\n"
          'final name = appName;\n',
      'docs/architecture/module_boundaries.json': _config(),
    });
    addTearDown(() => project.delete(recursive: true));

    final violations = await checkBoundaries(
      project,
      File('${project.path}/docs/architecture/module_boundaries.json'),
    );

    expect(violations, isEmpty);
  });

  test('forbidden package imports fail', () async {
    final project = await _project({
      'lib/core/constants.dart':
          "import 'package:helix/services/chat.dart';\n",
      'lib/services/chat.dart': 'class ChatService {}\n',
      'docs/architecture/module_boundaries.json': _config(),
    });
    addTearDown(() => project.delete(recursive: true));

    final violations = await checkBoundaries(
      project,
      File('${project.path}/docs/architecture/module_boundaries.json'),
    );

    expect(violations, hasLength(1));
    expect(violations.single.source, 'lib/core/constants.dart');
    expect(violations.single.target, 'lib/services/chat.dart');
  });

  test('re-exports and relative imports are checked', () async {
    final project = await _project({
      'lib/domain/models.dart': "export '../ui/app_theme.dart';\n",
      'lib/ui/app_theme.dart': 'class AppTheme {}\n',
      'docs/architecture/module_boundaries.json': _config(),
    });
    addTearDown(() => project.delete(recursive: true));

    final violations = await checkBoundaries(
      project,
      File('${project.path}/docs/architecture/module_boundaries.json'),
    );

    expect(violations, hasLength(1));
    expect(violations.single.target, 'lib/ui/app_theme.dart');
  });

  test('part files and conditional imports are handled', () async {
    final project = await _project({
      'lib/services/socket.dart':
          "import 'stub.dart' if (dart.library.io) '../ui/app_theme.dart';\n",
      'lib/services/stub.dart': 'class Stub {}\n',
      'lib/ui/app_theme.dart': 'class AppTheme {}\n',
      'lib/domain/model_part.dart': 'part of models;\nclass ModelPart {}\n',
      'docs/architecture/module_boundaries.json': _config(),
    });
    addTearDown(() => project.delete(recursive: true));

    final violations = await checkBoundaries(
      project,
      File('${project.path}/docs/architecture/module_boundaries.json'),
    );

    expect(violations, hasLength(1));
    expect(violations.single.target, 'lib/ui/app_theme.dart');
  });
}

Future<Directory> _project(Map<String, String> files) async {
  final root = await Directory.systemTemp.createTemp('boundary_test_');
  for (final entry in files.entries) {
    final file = File('${root.path}/${entry.key}');
    await file.parent.create(recursive: true);
    await file.writeAsString(entry.value);
  }
  return root;
}

String _config() {
  return jsonEncode({
    'forbidden': [
      {
        'source': 'lib/core/**',
        'imports': ['lib/services/**', 'lib/ui/**'],
        'reason': 'core is inward',
      },
      {
        'source': 'lib/domain/**',
        'imports': ['lib/ui/**'],
        'reason': 'domain is inward',
      },
      {
        'source': 'lib/services/**',
        'imports': ['lib/ui/**'],
        'reason': 'services cannot import UI',
      },
    ],
  });
}
