import 'dart:convert';
import 'dart:io';

class RemoteCompatibilityFixtures {
  static Map<String, dynamic> loadFixture(String filename) {
    // Search upwards or directly relative to project root.
    // In test run context, working directory might be package root (packages/remote/helix_remote_api) or workspace root.
    final pathsToTry = [
      'contracts/compatibility/fixtures/$filename',
      '../../../contracts/compatibility/fixtures/$filename',
      '../../contracts/compatibility/fixtures/$filename',
    ];

    for (final path in pathsToTry) {
      final file = File(path);
      if (file.existsSync()) {
        return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      }
    }

    throw FileSystemException('Fixture file not found: $filename');
  }
}
