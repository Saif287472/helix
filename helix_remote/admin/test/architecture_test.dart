import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_architecture_rules/helix_remote_architecture_rules.dart';

/// Import boundaries for the operator console (ARCHITECTURE_V2_PLAN.md §6.1,
/// §8). The console sits on top of the v2 API client and the shared UI
/// package; it does not depend on the server, the engine, the database or any
/// v1 package.
void main() {
  final files = scanDartSources(Directory.current.path);

  test('scans the console sources', () {
    expect(files.map((f) => f.path), contains('lib/main.dart'));
    expect(files.map((f) => f.path), contains('lib/src/app.dart'));
  });

  test('depends only on the protocol, the v2 API client and the UI kit', () {
    final violations = checkAll(files, [
      InternalDependencyRule(
        selfPackage: 'helix_admin',
        allowed: {
          'helix_remote_protocol',
          'helix_remote_api',
          'helix_remote_ui',
        },
      ),
    ]);
    expect(violations, isEmpty, reason: describeViolations(violations));
  });

  test('uses no v1 package and not the v1 API', () {
    final violations = checkAll(files, [
      ForbiddenDirectiveRule(
        name: 'no-v1',
        reason: 'the console runs on the v2 admin API only (Phase AD).',
        forbidden: (uri) =>
            anyPackage(v1RetiredPackages)(uri) ||
            anyPackage({'helix_remote_domain'})(uri) ||
            uri.startsWith('package:helix_remote_api/api'),
      ),
    ]);
    expect(violations, isEmpty, reason: describeViolations(violations));
  });

  test('reaches the v2 client only through its public library', () {
    final violations = checkAll(files, [
      ForbiddenDirectiveRule(
        name: 'public-api-only',
        reason: 'import package:helix_remote_api/v2.dart, not its internals.',
        forbidden: (uri) => uri.startsWith('package:helix_remote_api/src/'),
      ),
    ]);
    expect(violations, isEmpty, reason: describeViolations(violations));
  });

  test('state is plain ChangeNotifiers: no state-management package', () {
    final violations = checkAll(files, [
      ForbiddenDirectiveRule(
        name: 'no-state-package',
        reason:
            'the console keeps ChangeNotifier/setState (plan §6.4 adds '
            'Riverpod to the app, not to the admin console).',
        forbidden: anyPackage({
          'flutter_riverpod',
          'riverpod',
          'provider',
          'flutter_bloc',
          'bloc',
          'get',
          'mobx',
        }),
      ),
    ]);
    expect(violations, isEmpty, reason: describeViolations(violations));
  });

  test('the API facade is built in exactly one place', () {
    // HelixAdminApi is constructed in api/admin_api_factory.dart, so tests
    // swap the transport once and screens never build their own client.
    final constructors = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('HelixAdminApi('))
        .map((f) => f.path.replaceAll(r'\', '/'))
        .toList();
    expect(constructors, ['lib/src/api/admin_api_factory.dart']);
  });
}
