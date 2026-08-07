import 'dart:convert';
import 'dart:io';

/// Emits a small CycloneDX 1.5 SBOM from the resolved workspace lockfile.
/// This intentionally reports resolved versions, never version constraints.
void main(List<String> args) {
  final lock = File(args.isEmpty ? 'pubspec.lock' : args.first);
  final output = File(args.length > 1 ? args[1] : 'build/sbom.cdx.json');
  final lines = lock.readAsLinesSync();
  final components = <Map<String, String>>[];
  String? name;
  String? version;
  for (final line in lines) {
    final package = RegExp(r'^  ([A-Za-z0-9_-]+):$').firstMatch(line);
    if (package != null) {
      if (name != null && version != null) {
        components.add(_component(name, version));
      }
      name = package.group(1)!;
      version = null;
      continue;
    }
    final foundVersion = RegExp(r'^    version: "?([^"\s]+)').firstMatch(line);
    if (foundVersion != null && name != null) version = foundVersion.group(1)!;
  }
  // The last package in the file has no following blank line to flush it.
  if (name != null && version != null) {
    components.add(_component(name, version));
  }
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'bomFormat': 'CycloneDX',
      'specVersion': '1.5',
      'version': 1,
      'components': components,
    }),
  );
  stdout.writeln(
    'Wrote ${components.length} resolved packages to ${output.path}',
  );
}

Map<String, String> _component(String name, String version) => {
  'type': 'library',
  'name': name,
  'version': version,
  'purl': 'pkg:dart/$name@$version',
};
