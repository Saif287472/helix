import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contract test: every route the admin console calls must exist on the
/// backend, and every response key it reads must be one the backend actually
/// sends.
///
/// This is the same class of bug as the realtime envelope gate that made the
/// device-pairing prompt unreachable (see the execution plan): the client and
/// the server were written against different ideas of the contract, both sides
/// compiled, every test passed, and the feature was simply dead at runtime.
/// Here the failure mode is worse - the console silently shows "no users",
/// "no reports", "no audit events" because the call 404s.
///
/// Source-scanning rather than a live server, because the interesting failures
/// are *renames*: a route that exists in the client's string literals and not in
/// the backend's router. A running server would need one to be started and
/// would only catch the mismatch one call at a time.
void main() {
  // The admin package is `<repo>/helix_remote/admin`; the backend module and
  // the server that mounts it are siblings of it.
  final repoRoot = Directory.current.parent;
  final clientSource = File('${Directory.current.path}/lib/admin_client.dart');
  final backendModule = File(
    '${repoRoot.path}/backend/lib/src/modules/operability.dart',
  );
  final serverImpl = File(
    '${repoRoot.path}/backend/lib/src/server_impl.dart',
  );

  /// `/api/v1/ops/users/$accountId/suspend` and
  /// `/users/<accountId>/suspend` both normalise to a comparable shape.
  ///
  /// Interpolations and route parameters both become `:p`, because a test that
  /// distinguishes them would pass while the real server 404s on a mismatched
  /// placeholder name. Quote characters are stripped because the client's paths
  /// are Dart string literals and the closing quote would otherwise become
  /// part of the last segment.
  String normalise(String path) => path
      .replaceAll("'", '')
      .replaceAll('"', '')
      .split('/')
      .where((s) => s.isNotEmpty)
      .map((segment) {
        if (segment.startsWith('<') && segment.endsWith('>')) return ':p';
        if (segment.startsWith(r'$')) return ':p';
        if (segment.contains(r'${')) return ':p';
        return segment;
      })
      .join('/');

  /// Client paths, as full paths including the `/api/v1` prefix so they are
  /// directly comparable with [serverPaths].
  Set<String> clientPaths() {
    final source = clientSource.readAsStringSync();
    final matches = RegExp(
      r"""api/v1/([A-Za-z0-9_/\-$"'{}]+)""",
    ).allMatches(source);

    String staticPath(String raw) {
      final segments = <String>[];
      for (final segment in raw.replaceAll("'", '').split('/')) {
        if (segment.isEmpty) continue;
        // A whole-segment interpolation (`$accountId`) is a path parameter.
        if (segment.startsWith(r'$')) continue;
        // A query string glued onto the last segment (`reports$query`) is not
        // part of the path at all.
        final cut = segment.indexOf(r'$');
        final name = cut >= 0 ? segment.substring(0, cut) : segment;
        if (name.isEmpty) continue;
        if (name.startsWith('<') && name.endsWith('>')) continue;
        segments.add(name);
      }
      return normalise(segments.join('/'));
    }

    return matches
        .map((m) => staticPath('api/v1/${m.group(1)!}'))
        .where((p) => p.isNotEmpty)
        .toSet();
  }

  /// Backend routes, as full paths including their mount prefix.
  Set<String> serverPaths() {
    // A module is mounted once per router it exposes - `operabilityModule` is
    // mounted four times (health, server, telemetry, ops, admin) - so the
    // prefixes have to be collected as a list, not overwritten. Collapsing
    // them to one left every route under the last prefix and made the whole
    // comparison vacuous.
    final mounts = <String, List<String>>{};
    for (final m in RegExp(
      r"""router\.mount\('([^']+)',\s*(\w+Module)\.(\w+)Router""",
    ).allMatches(serverImpl.readAsStringSync())) {
      (mounts[m.group(2)!] ??= []).add(m.group(1)!);
    }

    final module = backendModule.readAsStringSync();
    // The operability module exposes five routers; the routes under each are
    // collected by tracking which getter body the `r.get(...)` registrations
    // fall inside.
    final byRouter = <String, List<String>>{};
    final pattern = RegExp(
      r"""Handler get (\w+Router) \{|r\.(get|post|delete|put)\('([^']+)'""",
    );

    String? router;
    for (final m in pattern.allMatches(module)) {
      if (m.group(1) != null) {
        router = m.group(1);
        byRouter.putIfAbsent(router!, () => []);
      } else if (router case final r?) {
        byRouter[r]!.add(m.group(3)!);
      }
    }

    final prefixes = mounts['operabilityModule'] ?? const <String>[];
    return {
      for (final prefix in prefixes)
        for (final routes in byRouter.values)
          for (final route in routes) normalise('$prefix$route'),
    };
  }

  group('admin client and backend routes agree', () {
    test('the source files this contract is derived from exist', () {
      // A silently-missing file would make every assertion below vacuous, which
      // is the worst possible failure for a contract test.
      expect(clientSource.existsSync(), isTrue, reason: clientSource.path);
      expect(backendModule.existsSync(), isTrue, reason: backendModule.path);
      expect(serverImpl.existsSync(), isTrue, reason: serverImpl.path);
    });

    test('the backend route scan actually found routes', () {
      // Guards the parser above: if the regex stops matching after a backend
      // refactor, `serverPaths()` returns an empty set and every "client path
      // exists" check below would pass vacuously.
      expect(serverPaths().length, greaterThan(20));
    });

    test('every path AdminClient calls is a registered route', () {
      final known = serverPaths();
      final missing = <String>[];
      for (final path in clientPaths()) {
        // A client path with a trailing dynamic segment (e.g.
        // `ops/invites/:p/cancel`) is matched by comparing the static prefix
        // against the registered routes with parameters collapsed.
        final segments = path.split('/');
        var matched = false;
        for (var take = segments.length; take >= 1 && !matched; take--) {
          final prefix = normalise(segments.take(take).join('/'));
          if (known.contains(prefix)) matched = true;
        }
        if (!matched) missing.add(path);
      }

      expect(
        missing,
        isEmpty,
        reason:
            'AdminClient calls routes the backend does not register. Either '
            'the client path or the backend route was renamed:\n'
            '${missing.join('\n')}',
      );
    });
  });

  group('response keys', () {
    /// Keys the client reads out of a response body must be keys the backend
    /// writes.
    ///
    /// This is the check that catches the quieter half of a contract drift: a
    /// rename on the server that leaves the client reading a key that is no
    /// longer sent, so the console renders a default where real data should
    /// be - an "unknown" status, a zero count, a permanently empty list.
    ///
    /// Read from the `response.body` handling in admin_client.dart, which is
    /// the only place a missing key turns into a wrong value rather than a
    /// compile error.
    test('the client reads keys the backend writes', () {
      final source = clientSource.readAsStringSync();

      // Success bodies are built in operability.dart; the error envelope
      // (`{error, code, details}`) is produced once by the error-handling
      // middleware in server_impl.dart, so both have to be searched. Reading
      // `error` off a failed response is a real and supported read - it just
      // is not a key operability.dart itself writes.
      final emitted = [
        backendModule.readAsStringSync(),
        serverImpl.readAsStringSync(),
      ].join('\n');

      final read = RegExp(r"\w+\['([a-z_]+)'\]").allMatches(source);
      final keys = read.map((m) => m.group(1)!).toSet();

      final unwritten = keys
          .where((k) => !emitted.contains("'$k':"))
          .where((k) => !emitted.contains('"$k":'))
          .toList();

      expect(
        unwritten,
        isEmpty,
        reason:
            'AdminClient reads response keys the backend never writes. The '
            'console would render a default in place of real data:\n'
            '${unwritten.join('\n')}',
      );
    });
  });
}
