import 'dart:io';

import 'extract_support.dart';

// Usage (from helix_local/):
//   dart run tool/extract_all.dart
//   dart run tool/extract_all.dart --list
//   dart run tool/extract_all.dart --only local_packages_features

Future<void> main(List<String> args) async {
  try {
    await runExtractionCli(args: args, scope: 'agent_upload', specs: _specs);
  } on ExtractionException catch (error) {
    stderr.writeln(error.message);
    exit(2);
  }
}

const _corePackages = [
  'helix_local_domain',
  'helix_local_protocol',
  'helix_local_crypto',
  'helix_local_transport',
  'helix_local_storage',
  'helix_local_platform',
];

const _featurePackages = [
  'helix_local_messaging',
  'helix_local_transfer',
  'helix_local_calls',
  'helix_local_discovery',
  'helix_local_groups',
];

final _specs = [
  ExtractSpec(
    id: 'local_app',
    outputPath: 'agent_upload/01_helix_local_app.txt',
    title: 'HELIX LOCAL - APP',
    subtitle:
        'Local Flutter app: pubspec, entrypoints, composition root, providers, workflows, screens, widgets, services, and l10n.',
    collectFiles: (context) {
      final files = <String>[];
      addFile(files, context, 'app/pubspec.yaml');
      files.addAll(
        collectDir(context, 'app/lib', exts: ['.dart', '.arb', '.json']),
      );
      return files;
    },
  ),
  ExtractSpec(
    id: 'local_packages_core',
    outputPath: 'agent_upload/02_helix_local_packages_core.txt',
    title: 'HELIX LOCAL - PACKAGES: CORE',
    subtitle:
        'Local domain, protocol, crypto, transport, storage, and platform packages.',
    collectFiles: (context) => _collectPackages(context, _corePackages),
  ),
  ExtractSpec(
    id: 'local_packages_features',
    outputPath: 'agent_upload/03_helix_local_packages_features.txt',
    title: 'HELIX LOCAL - PACKAGES: FEATURES',
    subtitle:
        'Local messaging, transfer, calls, discovery, and groups packages.',
    collectFiles: (context) => _collectPackages(context, _featurePackages),
  ),
];

List<String> _collectPackages(
  ExtractionContext context,
  List<String> packages,
) {
  final files = <String>[];
  for (final package in packages) {
    addFile(files, context, 'packages/$package/pubspec.yaml');
    files.addAll(collectDir(context, 'packages/$package/lib'));
  }
  return files;
}
