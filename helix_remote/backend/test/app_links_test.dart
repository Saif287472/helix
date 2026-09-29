import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late BackendServer server;
  late HttpClient client;
  late int port;

  Future<(int, String, String?)> get(String path) async {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    final response = await request.close();
    return (
      response.statusCode,
      await response.transform(utf8.decoder).join(),
      response.headers.contentType?.mimeType,
    );
  }

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'app_links_test_secret_at_least_32_bytes_long',
      androidCertFingerprints: const ['AA:BB:CC'],
    );
    client = HttpClient();
    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  test('assetlinks.json lets Android verify the app for this host', () async {
    final (status, body, type) = await get('/.well-known/assetlinks.json');
    expect(status, 200);
    expect(type, 'application/json');
    final statements = jsonDecode(body) as List<dynamic>;
    final target =
        (statements.single as Map<String, dynamic>)['target']
            as Map<String, dynamic>;
    expect(target['package_name'], 'com.helix.remote');
    expect(target['sha256_cert_fingerprints'], ['AA:BB:CC']);
  });

  test('the landing page is public and never sees the code', () async {
    final (status, body, type) = await get('/open');
    expect(status, 200);
    expect(type, 'text/html');
    // The code lives in the fragment, read by the page's script.
    expect(body, contains('location.hash'));
    expect(body, contains('package=com.helix.remote'));
  });
}
