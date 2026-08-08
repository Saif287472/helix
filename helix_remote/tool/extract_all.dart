import 'dart:io';

import 'extract_support.dart';

// Usage (from helix_remote/):
//   dart run tool/extract_all.dart
//   dart run tool/extract_all.dart --list
//   dart run tool/extract_all.dart --only remote_backend_identity_messaging

const _backendSharedFiles = [
  'backend/lib/src/app_error.dart',
  'backend/lib/src/jwt.dart',
  'backend/lib/src/repositories.dart',
];

const _identityMessagingModules = [
  'admin_pairing',
  'auth',
  'contacts',
  'messaging',
  'prekeys',
  's2s_module',
];

const _mediaGroupsCallsModules = [
  'attachments',
  'calls',
  'group_calls',
  'groups',
];

const _operationsDataModules = ['backups', 'operability', 'privacy_compliance'];

const _apiStoragePackages = [
  'helix_remote_domain',
  'helix_remote_api',
  'helix_remote_storage',
];

const _callsGroupsUiPackages = [
  'helix_remote_calls',
  'helix_remote_groups',
  'helix_remote_ui',
];

Future<void> main(List<String> args) async {
  try {
    await runExtractionCli(args: args, scope: 'agent_upload', specs: _specs);
  } on ExtractionException catch (error) {
    stderr.writeln(error.message);
    exit(2);
  }
}

final _specs = [
  ExtractSpec(
    id: 'remote_backend_infrastructure',
    outputPath: 'agent_upload/04_helix_remote_backend_infrastructure.txt',
    title: 'HELIX REMOTE - BACKEND INFRASTRUCTURE',
    subtitle:
        'Backend pubspec, server entrypoint, exported library, and non-module backend/lib/src files.',
    collectFiles: (context) {
      final files = <String>[];
      addFile(files, context, 'backend/pubspec.yaml');
      addFile(files, context, 'backend/bin/server.dart');
      addFile(files, context, 'backend/lib/helix_remote_backend.dart');
      files.addAll(
        collectDir(context, 'backend/lib/src', exclude: ['/modules/']),
      );
      return files;
    },
  ),
  ExtractSpec(
    id: 'remote_backend_identity_messaging',
    outputPath: 'agent_upload/05_helix_remote_backend_identity_messaging.txt',
    title: 'HELIX REMOTE - BACKEND: IDENTITY + MESSAGING',
    subtitle:
        'Admin pairing, auth, contacts, messaging, prekeys, server-to-server module, and shared backend context.',
    collectFiles: (context) => _collectBackendModules(
      context,
      _identityMessagingModules,
      includeSharedContext: true,
    ),
  ),
  ExtractSpec(
    id: 'remote_backend_media_groups_calls',
    outputPath: 'agent_upload/06_helix_remote_backend_media_groups_calls.txt',
    title: 'HELIX REMOTE - BACKEND: MEDIA + GROUPS + CALLS',
    subtitle:
        'Attachments, calls, group calls, groups, and shared backend context.',
    collectFiles: (context) => _collectBackendModules(
      context,
      _mediaGroupsCallsModules,
      includeSharedContext: true,
    ),
  ),
  ExtractSpec(
    id: 'remote_backend_operations_data',
    outputPath: 'agent_upload/07_helix_remote_backend_operations_data.txt',
    title: 'HELIX REMOTE - BACKEND: OPERATIONS + DATA',
    subtitle:
        'Backups, operability, privacy compliance, and shared backend context.',
    collectFiles: (context) => _collectBackendModules(
      context,
      _operationsDataModules,
      includeSharedContext: true,
    ),
  ),
  ExtractSpec(
    id: 'remote_app_core_services',
    outputPath: 'agent_upload/08_helix_remote_app_core_services.txt',
    title: 'HELIX REMOTE - APP: CORE + SERVICES',
    subtitle:
        'Remote Flutter app pubspec, entrypoint, app shell, services, l10n, and presentation support.',
    collectFiles: (context) {
      final files = <String>[];
      addFile(files, context, 'app/pubspec.yaml');
      addFile(files, context, 'app/lib/main.dart');
      files.addAll(collectDir(context, 'app/lib/app'));
      files.addAll(collectDir(context, 'app/lib/services', required: false));
      files.addAll(
        collectDir(
          context,
          'app/lib/l10n',
          exts: ['.dart', '.arb', '.json'],
          required: false,
        ),
      );
      files.addAll(
        collectDir(context, 'app/lib/presentation', required: false),
      );
      return files;
    },
  ),
  ExtractSpec(
    id: 'remote_app_screens_widgets',
    outputPath: 'agent_upload/09_helix_remote_app_screens_widgets.txt',
    title: 'HELIX REMOTE - APP: SCREENS + WIDGETS',
    subtitle: 'Remote Flutter screens and reusable widgets.',
    collectFiles: (context) {
      final files = <String>[];
      files.addAll(collectDir(context, 'app/lib/screens'));
      files.addAll(collectDir(context, 'app/lib/widgets', required: false));
      return files;
    },
  ),
  ExtractSpec(
    id: 'remote_packages_crypto_sync',
    outputPath: 'agent_upload/10_helix_remote_packages_crypto_sync.txt',
    title: 'HELIX REMOTE - PACKAGES: CRYPTO + SYNC',
    subtitle: 'Remote crypto and sync packages.',
    collectFiles: (context) =>
        _collectPackages(context, ['helix_remote_crypto', 'helix_remote_sync']),
  ),
  ExtractSpec(
    id: 'remote_packages_api_storage_contracts',
    outputPath:
        'agent_upload/11_helix_remote_packages_api_storage_contracts.txt',
    title: 'HELIX REMOTE - PACKAGES: API + STORAGE + CONTRACTS',
    subtitle: 'Remote domain, API, storage packages, plus JSON/YAML contracts.',
    collectFiles: (context) {
      final files = _collectPackages(context, _apiStoragePackages);
      files.addAll(collectDir(context, 'contracts', exts: ['.json', '.yaml']));
      return files;
    },
  ),
  ExtractSpec(
    id: 'remote_packages_calls_groups_ui',
    outputPath: 'agent_upload/12_helix_remote_packages_calls_groups_ui.txt',
    title: 'HELIX REMOTE - PACKAGES: CALLS + GROUPS + UI',
    subtitle: 'Remote calls, groups, and shared UI packages.',
    collectFiles: (context) =>
        _collectPackages(context, _callsGroupsUiPackages),
  ),
  ExtractSpec(
    id: 'remote_admin_cli',
    outputPath: 'agent_upload/13_helix_remote_admin_cli.txt',
    title: 'HELIX REMOTE - ADMIN + CLI',
    subtitle: 'Admin Flutter ops console and helix_remote_cli package.',
    collectFiles: (context) {
      final files = <String>[];
      addFile(files, context, 'admin/pubspec.yaml');
      files.addAll(
        collectDir(context, 'admin/lib', exts: ['.dart', '.arb', '.json']),
      );
      addFile(files, context, 'packages/helix_remote_cli/pubspec.yaml');
      files.addAll(collectDir(context, 'packages/helix_remote_cli/bin'));
      files.addAll(collectDir(context, 'packages/helix_remote_cli/lib'));
      return files;
    },
  ),
];

List<String> _collectBackendModules(
  ExtractionContext context,
  List<String> modules, {
  required bool includeSharedContext,
}) {
  final files = <String>[];
  for (final module in modules) {
    addFile(
      files,
      context,
      'backend/lib/src/modules/$module.module.md',
      required: false,
    );
    addFile(
      files,
      context,
      'backend/lib/src/modules/$module/MODULE.md',
      required: false,
    );
    addFile(
      files,
      context,
      'backend/lib/src/modules/$module.dart',
      required: false,
    );
    files.addAll(
      collectDir(
        context,
        'backend/lib/src/modules/$module',
        exts: ['.dart'],
        required: false,
      ),
    );
  }

  if (includeSharedContext) {
    for (final sharedFile in _backendSharedFiles) {
      addFile(files, context, sharedFile);
    }
  }
  return files;
}

List<String> _collectPackages(
  ExtractionContext context,
  List<String> packages,
) {
  final files = <String>[];
  for (final package in packages) {
    addFile(files, context, 'packages/$package/pubspec.yaml');
    files.addAll(collectDir(context, 'packages/$package/bin', required: false));
    files.addAll(collectDir(context, 'packages/$package/lib', required: false));
  }
  return files;
}
