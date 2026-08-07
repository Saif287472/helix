// Phase 8.6 — "one test per finding in this document".
//
// Most findings already have a purpose-built suite; this file covers the ones
// that had none, and checks that the matrix which claims to index them all is
// not describing tests that do not exist.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LOW-1 the release build is minified and shrunk', () {
    // Dart AOT limits the exposure, but Kotlin/Java and resources ship in the
    // clear without this. The .gitignore already anticipated symbol files
    // (app.*.symbols, app.*.map.json), so the intent predated the switch.
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(gradle, contains('isMinifyEnabled = true'));
    expect(gradle, contains('isShrinkResources = true'));
    expect(
      File('android/app/proguard-rules.pro').existsSync(),
      isTrue,
      reason: 'minification without keep rules strips reflective entry points',
    );
  });

  test('LOW-3 the invite code never travels in a query string', () {
    // An invite code is a bearer credential. In a query string it reaches the
    // reverse proxy's access log, and reaches this client's own diagnostic log
    // through RemoteRestException.uri — which is HIGH-1's export path.
    final client = File('lib/app/remote_rest_client.dart').readAsStringSync();

    expect(
      RegExp(r"queryParameters:\s*\{[^}]*'invite_code'").hasMatch(client),
      isFalse,
      reason: 'invite_code must be a POST body field, not a query parameter',
    );
    expect(
      RegExp(
        r"invite/lookup'[\s\S]{0,400}?body:\s*\{'invite_code'",
      ).hasMatch(client),
      isTrue,
      reason: 'the invite lookup must send its code in the body',
    );
  });

  test('MED-1 the conversation applies deltas instead of refetching', () {
    // The screen used to set visibleLimit = _messages.length and re-run
    // messageHistory on every inbound change, re-reading and re-decrypting the
    // whole loaded window — quadratic under a burst, on the hottest screen.
    final viewModel = File(
      'lib/presentation/conversation/conversation_view_model.dart',
    ).readAsStringSync();

    expect(
      viewModel,
      contains('RemoteSyncChange'),
      reason: 'the view model listens for changes rather than polling',
    );
    expect(
      RegExp(r'visibleLimit\s*=\s*_messages\.length').hasMatch(viewModel),
      isFalse,
      reason: 're-reading the whole loaded window per change is MED-1',
    );
  });

  test('the regression matrix does not name tests that do not exist', () {
    // A matrix is a control document, and §21's finding is that control
    // documents drift. Every backtick-quoted path in it that looks like a test
    // file must resolve.
    final matrix = File(
      '../docs/security/REGRESSION_TEST_MATRIX.md',
    ).readAsStringSync();

    final referenced = RegExp(
      r'`([^`]+_test\.dart)`',
    ).allMatches(matrix).map((match) => match.group(1)!).toSet();

    expect(
      referenced,
      isNotEmpty,
      reason: 'the matrix must actually reference test files',
    );

    final missing = referenced
        .where((path) => !File('../$path').existsSync())
        .toList();

    expect(
      missing,
      isEmpty,
      reason: 'the matrix claims these protect a finding, and they are gone',
    );
  });
}
