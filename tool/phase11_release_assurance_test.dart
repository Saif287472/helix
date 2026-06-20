import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory root;

  setUpAll(() {
    root = _findRepoRoot();
  });

  test('Phase 11 evidence documents cover every release-assurance task', () {
    final assurance = _read(root, 'docs/release/PHASE_11_RELEASE_ASSURANCE.md');
    for (var i = 1; i <= 9; i++) {
      expect(assurance, contains('P11-0$i'));
    }

    final pyramid = _read(root, 'docs/quality/RELEASE_TEST_PYRAMID.md');
    for (final layer in [
      'Unit',
      'State-machine and property',
      'Contract',
      'Component',
      'Real backend/client E2E',
      'Platform integration',
      'Accessibility',
      'Performance and load',
      'Security',
    ]) {
      expect(pyramid, contains(layer), reason: layer);
    }
  });

  test('Phase 11 fuzzing is scheduled and corpus-retained', () {
    final ci = _read(root, '.github/workflows/ci.yml');
    final manifest = _read(root, 'tool/fuzz_corpus/manifest.json');
    final verifyPs = _read(root, 'scripts/verify.ps1');
    final verifySh = _read(root, 'scripts/verify.sh');

    expect(ci, contains('schedule:'));
    expect(ci, contains('fuzz-seed-corpus'));
    expect(ci, contains('tool/fuzz_seed_corpus_test.dart'));
    expect(manifest, contains('"retention_days": 180'));
    expect(verifyPs, contains('phase11_release_assurance_test.dart'));
    expect(verifyPs, contains('fuzz_seed_corpus_test.dart'));
    expect(verifySh, contains('phase11_release_assurance_test.dart'));
    expect(verifySh, contains('fuzz_seed_corpus_test.dart'));
  });

  test(
    'release gates require SAST, dependency, SBOM, and provenance evidence',
    () {
      final assurance = _read(
        root,
        'docs/release/PHASE_11_RELEASE_ASSURANCE.md',
      );
      final localGate = _read(root, 'scripts/local_release_gate.ps1');
      final remoteGate = _read(root, 'scripts/remote_release_gate.ps1');

      for (final phrase in [
        'SAST',
        'dependency vulnerability review',
        'license policy',
        'reproducible SBOM',
        'signed artifact',
        'artifact checksums',
        'provenance',
      ]) {
        expect(assurance.toLowerCase(), contains(phrase.toLowerCase()));
      }
      expect(localGate, contains('generate_release_provenance.dart'));
      expect(remoteGate, contains('generate_release_provenance.dart'));
    },
  );

  test(
    'privacy, rollout, rollback, and on-call matrices cover release risks',
    () {
      final privacy = _read(root, 'docs/release/PRIVACY_EVIDENCE_MATRIX.md');
      for (final phrase in [
        'privacy inventory',
        'Retention',
        'Deletion',
        'Export',
        'Backup',
        'Telemetry',
        'App-store disclosures',
        'Data processing',
      ]) {
        expect(privacy.toLowerCase(), contains(phrase.toLowerCase()));
      }

      final rollout = _read(root, 'docs/release/STAGED_ROLLOUT_PLAN.md');
      for (final phrase in [
        'Internal',
        'Alpha',
        'Beta',
        'Percentage rollout',
        'Feature Flags',
        'Compatibility Window',
        'Automatic Halt Thresholds',
        'Crash-free sessions',
        'ANR',
      ]) {
        expect(rollout, contains(phrase), reason: phrase);
      }

      final rollback = _read(root, 'docs/release/ROLLBACK_REHEARSAL.md');
      for (final phrase in [
        'App rollback',
        'API rollback',
        'Realtime schema rollback',
        'DB migration rollback',
        'Object storage rollback',
        'Key/config rotation',
      ]) {
        expect(rollback, contains(phrase), reason: phrase);
      }

      final onCall = _read(root, 'docs/operations/INCIDENT_ONCALL_RUNBOOKS.md');
      for (final phrase in [
        'Auth outage',
        'Sync backlog',
        'Corrupt migration',
        'Key/prekey incident',
        'Privacy request failure',
        'TURN outage',
        'Data-loss suspicion',
        'Security incident',
      ]) {
        expect(onCall, contains(phrase), reason: phrase);
      }
    },
  );

  test(
    'external review gate blocks strong claims until Critical/High closure',
    () {
      final review = _read(
        root,
        'docs/security/EXTERNAL_SECURITY_REVIEW_GATE.md',
      );
      final claims = _read(root, 'docs/product/PRIVACY_CLAIM_MATRIX.md');

      expect(review, contains('Independent cryptographic review: BLOCKED'));
      expect(review, contains('Penetration test: BLOCKED'));
      expect(review, contains('Critical/High'));
      expect(claims, contains('Blocked for strong claim'));
      expect(
        claims,
        contains('Independent cryptographic review remains externally blocked'),
      );
    },
  );
}

Directory _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        File('${dir.path}/AGENTS.md').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not find repo root from ${Directory.current}');
    }
    dir = parent;
  }
}

String _read(Directory root, String path) =>
    File('${root.path}/$path').readAsStringSync();
