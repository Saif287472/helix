import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_architecture_rules/helix_remote_architecture_rules.dart';

/// The app's half of the v2 guardrails (plan §8.1, ADR-029).
///
/// Two rules the shared package cannot express, because they are about this
/// app's own shape:
///
/// 1. **Presentation imports nothing below it.** A file in
///    `features/*/presentation/` may import its own `application/`, `shared/`,
///    `orbit_ui` and `helix_remote_domain` - and nothing
///    else. The engine, database, crypto and API are reached through a
///    notifier, so a widget cannot end up coupled to a ratchet, a row or a
///    socket.
/// 2. **No v1 package.** `helix_remote_storage`, `_sync`, `_groups` and
///    `helix_remote_backend` are deleted at cutover.
void main() {
  final files = scanDartSources(Directory.current.path);

  test('the app imports no v1 package', () {
    final violations = checkAll(files, [
      ForbiddenDirectiveRule(
        name: 'no-v1-packages',
        reason:
            'v1 packages are retired at cutover; the v2 app must not depend on '
            'them (ADR-029).',
        forbidden: anyPackage(v1RetiredPackages),
      ),
    ]);
    expect(violations, isEmpty, reason: describeViolations(violations));
  });

  test('presentation imports only its own application, shared and ui', () {
    final violations = checkAll(files, [
      ForbiddenDirectiveRule(
        name: 'presentation-imports',
        reason:
            'presentation draws what application/ gives it. Put the work in a '
            'Riverpod Notifier or StreamProvider and pass plain values down '
            '(plan §6.4).',
        forbidden: (uri) => _forbiddenInPresentation(uri),
        appliesTo: (path) => path.contains('/presentation/'),
      ),
    ]);
    expect(violations, isEmpty, reason: describeViolations(violations));
  });

  test('no database or HTTP leaks outside the packages that own them', () {
    // `helix_remote_db` is allowed to open the database, because it owns it;
    // every other layer reaches it through the engine.
    final violations = checkAll(files, [
      ForbiddenDirectiveRule(
        name: 'no-sqlite-outside-db',
        reason:
            'SQL access belongs to helix_remote_db; use the engine, which owns '
            'the schema and its migrations.',
        forbidden: (uri) =>
            uri.startsWith('package:sqlite3/') ||
            uri.startsWith('package:drift/'),
        appliesTo: (path) => !path.startsWith('test/'),
      ),
      ForbiddenDirectiveRule(
        name: 'no-http-outside-api',
        reason:
            'HTTP and WebSockets belong to helix_remote_api, which owns token '
            'refresh, retries and the realtime policy.',
        forbidden: (uri) =>
            uri == 'package:http/http.dart' ||
            uri == 'package:http/io_client.dart' ||
            uri.startsWith('package:web_socket_channel/'),
        appliesTo: (path) => !path.startsWith('test/'),
      ),
    ]);
    expect(violations, isEmpty, reason: describeViolations(violations));
  });

  test('no feature or screen holds a print or debugPrint', () {
    // A stray print in a messenger is a leftover, and the risk is that it
    // carries a message, a key or a number. Only the two places that *have* to
    // say something are exempt, and both may report an exception's type only -
    // which is asserted separately below.
    final offenders = <String>[];
    for (final file in files.where((f) => f.path.startsWith('lib/'))) {
      if (_isExemptFromLogging(file.path)) continue;
      final source = File(file.path).readAsStringSync();
      for (final match in RegExp(
        r'\b(print|debugPrint|developer\.log)\s*\(',
      ).allMatches(source)) {
        offenders.add('${file.path}:${match.group(0)}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Remove it. If something must be reported, raise it as an engine '
          'event the UI can show rather than writing it out.',
    );
  });

  test('the two logging sites report an exception type and nothing else', () {
    // `core/push/push_background.dart` runs in an isolate that has no UI, and
    // `main.dart` holds the zone handler; both must say *that* something
    // failed without saying what was in it. Any interpolation that is not
    // `.runtimeType` is a leak waiting to happen.
    for (final path in const [
      'lib/main.dart',
      'lib/core/push/push_background.dart',
    ]) {
      final source = File(path).readAsStringSync();
      for (final match in RegExp(
        r'\b(print|debugPrint)\(\s*([^;]*?)\);',
        dotAll: true,
      ).allMatches(source)) {
        final argument = match.group(2)!;
        // Strip the interpolated parts; what is left must be plain text.
        final literals = argument.replaceAll(
          RegExp(r'\$\{[^}]*\}', dotAll: true),
          '',
        );
        for (final interpolation in RegExp(
          r'\$\{([^}]*)\}',
          dotAll: true,
        ).allMatches(argument)) {
          expect(
            interpolation.group(1)!.trim(),
            endsWith('.runtimeType'),
            reason:
                '$path interpolates ${interpolation.group(1)} into a log line; '
                'only an exception type may be reported',
          );
        }
        expect(
          literals,
          isNot(matches(RegExp(r'\$'))),
          reason: '$path builds a log line dynamically',
        );
      }
    }
  });

  test('a feature never imports another feature', () {
    // Two features sharing a provider's lifetime would make the dependency
    // graph a mesh and let one screen's state decide another's. A widget both
    // need belongs in `shared/`, which the presentation rule already permits.
    // `core/` is exempt: it is the wiring, and the router is exactly where a
    // feature's entry screen belongs.
    final offenders = <String>[];
    for (final file in files) {
      final own = _featureOf(file.path);
      if (own == null) continue;
      for (final directive in file.directives) {
        final target = _featureOf(directive.uri);
        if (target != null && target != own) {
          offenders.add('${file.path} -> ${directive.uri}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Features do not know about each other. Put anything both need in '
          'shared/, or read it from a provider in core/.',
    );
  });

  test('a gateway that streams from the engine is keyed on the account', () {
    // Several accounts are signed in on one phone and one is on screen. A
    // gateway that resolves that account's runtime *inside its methods*
    // (`ref.read(runtimeProvider…)`) keeps every stream it opened on the
    // engine it first read, so one account's profile, settings, devices or
    // backup went on showing while another's chats were open. Its provider
    // must therefore watch the account on screen - `activeAccountProvider`,
    // or `runtimeProvider` where watching that is safe: a new account is a new
    // gateway, and its streams start again on the right database.
    //
    // The check is per file, which is enough for the seam it guards: a file
    // that opens engine streams and reads the runtime lazily must key them on
    // the account. See the rule in MODULE.md.
    final offenders = <String>[];
    for (final file in files.where((f) => f.path.startsWith('lib/'))) {
      if (_rebindsItsOwnStreams.contains(file.path)) continue;
      final source = File(file.path).readAsStringSync();
      final opensStreams = RegExp(r'Stream<|async\*').hasMatch(source);
      final lazyRuntime = RegExp(r'read\(\s*runtimeProvider').hasMatch(source);
      final keyedOnAccount = RegExp(
        r'(watch|listen)[<(]*[^;]*(activeAccountProvider|runtimeProvider)',
      ).hasMatch(source);
      if (opensStreams && lazyRuntime && !keyedOnAccount) {
        offenders.add(file.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'These files open a stream off a lazily-read runtime. Give their '
          'provider `ref.watch(activeAccountProvider)`, so an account switch '
          'reopens the stream on the account now on screen.',
    );
  });
}

/// The two files allowed to log, and only an exception's type from each.
bool _isExemptFromLogging(String path) =>
    path == 'lib/main.dart' || path == 'lib/core/push/push_background.dart';

/// Files that read the runtime lazily and hold streams, and re-bind those
/// streams to the account now on screen in their own way: they listen to a
/// provider that is itself keyed on the runtime (`callsPortProvider`) and
/// cancel and reopen the subscription on every change. Adding a file here
/// needs that sentence in the file, not only the path.
const _rebindsItsOwnStreams = {
  'lib/features/calls/application/call_effects.dart',
};

/// `lib/features/<name>/…` -> `<name>`; anything else -> null.
String? _featureOf(String path) {
  const prefix = 'lib/features/';
  if (!path.startsWith(prefix)) return null;
  final rest = path.substring(prefix.length);
  final slash = rest.indexOf('/');
  return slash < 0 ? null : rest.substring(0, slash);
}

/// What a file in a `presentation/` directory may not import.
///
/// Allowed: `dart:` and Flutter, this feature's own `application/` and its own
/// `presentation/` siblings, `shared/`, and the two leaf packages
/// (`orbit_ui`'s components and `helix_remote_domain`'s value types).
/// Everything else - the engine, the database, the crypto, the API, `core/` -
/// is reached through a provider, never imported by a widget.
bool _forbiddenInPresentation(String uri) {
  if (uri.startsWith('dart:') || uri.startsWith('package:flutter/')) {
    return false;
  }
  if (uri.startsWith('package:helix_remote/shared/')) return false;
  // A feature's own files, application and presentation alike. Whether one
  // feature may reach into *another* is a separate question, answered by the
  // "a feature never imports another feature" test above; this rule is only
  // about staying off the layers below.
  if (uri.startsWith('package:helix_remote/features/')) return false;
  // The two leaf packages: components and value types, no I/O.
  const allowed = {'package:orbit_ui/', 'package:helix_remote_domain/'};
  if (allowed.any(uri.startsWith)) return false;
  // Everything else in this app - engine, database, crypto, api, core - is
  // reached through a provider, not imported by a widget.
  return uri.startsWith('package:helix_remote');
}
