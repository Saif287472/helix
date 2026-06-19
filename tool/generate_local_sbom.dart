import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final checkOnly = args.contains('--check-only');
  final outputIndex = args.indexOf('--output');
  final outputPath = outputIndex >= 0 && outputIndex + 1 < args.length
      ? args[outputIndex + 1]
      : 'build/release/helix_local_sbom.json';

  final configFile = File('.dart_tool/package_config.json');
  if (!configFile.existsSync()) {
    stderr.writeln(
      'Missing .dart_tool/package_config.json. Run flutter pub get first.',
    );
    exitCode = 1;
    return;
  }

  final root =
      jsonDecode(configFile.readAsStringSync()) as Map<String, Object?>;
  final packageConfigBase = configFile.parent.absolute.uri;
  final workspaceRoot = Directory.current.absolute.path.replaceAll('\\', '/');
  final packages =
      (root['packages'] as List<Object?>)
          .cast<Map<String, Object?>>()
          .map(
            (json) => _PackageEntry.fromJson(
              json,
              packageConfigBase: packageConfigBase,
              workspaceRoot: workspaceRoot,
            ),
          )
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  final missingLicenses = <String>[];
  final entries = <Map<String, Object?>>[];
  for (final package in packages) {
    final license = package.findLicense();
    if (package.requiresLicenseFile && license == null) {
      missingLicenses.add(package.name);
    }
    entries.add({
      'name': package.name,
      'rootUri': package.rootUri.toString(),
      'workspacePackage': package.isWorkspacePackage,
      'sdkPackage': package.isSdkPackage,
      'licenseFile': license?.path,
    });
  }

  if (missingLicenses.isNotEmpty) {
    stderr.writeln('Dependency license check failed. Missing license files:');
    for (final name in missingLicenses) {
      stderr.writeln('- $name');
    }
    exitCode = 1;
    return;
  }

  final sbom = <String, Object?>{
    'schema': 'helix-local-sbom-v1',
    'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'packageCount': entries.length,
    'packages': entries,
  };

  if (!checkOnly) {
    final output = File(outputPath);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(sbom));
    stdout.writeln('Wrote SBOM: ${output.path}');
  } else {
    stdout.writeln(
      'SBOM/license inventory check passed (${entries.length} packages).',
    );
  }
}

final class _PackageEntry {
  const _PackageEntry({
    required this.name,
    required this.rootUri,
    required this.workspaceRoot,
  });

  factory _PackageEntry.fromJson(
    Map<String, Object?> json, {
    required Uri packageConfigBase,
    required String workspaceRoot,
  }) {
    final rawRootUri = Uri.parse(json['rootUri'] as String);
    return _PackageEntry(
      name: json['name'] as String,
      rootUri: rawRootUri.isAbsolute
          ? rawRootUri
          : packageConfigBase.resolveUri(rawRootUri),
      workspaceRoot: workspaceRoot,
    );
  }

  final String name;
  final Uri rootUri;
  final String workspaceRoot;

  bool get isWorkspacePackage {
    final normalized = _rootPath.replaceAll('\\', '/');
    return name == 'helix_workspace' ||
        normalized == workspaceRoot ||
        normalized.contains('/apps/') ||
        normalized.contains('/packages/local/') ||
        normalized.contains('/packages/remote/') ||
        normalized.endsWith('/tool');
  }

  bool get isSdkPackage {
    final normalized = _rootPath.replaceAll('\\', '/');
    return normalized.contains('/flutter/packages/');
  }

  bool get requiresLicenseFile => !isWorkspacePackage && !isSdkPackage;

  File? findLicense() {
    final dir = Directory(_rootPath);
    for (final name in const [
      'LICENSE',
      'LICENSE.md',
      'LICENSE.txt',
      'LICENCE',
      'COPYING',
      'NOTICE',
    ]) {
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      if (file.existsSync()) return file;
    }
    return null;
  }

  String get _rootPath {
    if (rootUri.isAbsolute && rootUri.scheme == 'file') {
      return rootUri.toFilePath(windows: Platform.isWindows);
    }
    return rootUri.toFilePath(windows: Platform.isWindows);
  }
}
