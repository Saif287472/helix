import 'dart:convert';
import 'dart:io';

import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:test/test.dart';

class _InMemoryKeyValueStore implements KeyValueStore {
  final _store = <String, String>{};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }
}

RemoteProductConfig _productConfig(String dir) => RemoteProductConfig(
  displayName: 'Helix Remote',
  packageId: 'com.helix.remote',
  secureStoragePrefix: 'helix_remote_v1_',
  methodChannelNamespace: 'com.helix.remote',
  logNamespace: 'helix_remote',
  databaseDirectory: dir,
);

RemoteDevelopmentConfig _devConfig(String dir, Uri restBaseUri) =>
    RemoteDevelopmentConfig(
      profile: RemoteRuntimeProfile.localWindows,
      restBaseUri: restBaseUri,
      webSocketUri: restBaseUri.replace(scheme: 'ws', path: '/api/v1/ws'),
      allowInsecureTransport: true,
      backendHostMode: 'same-pc',
      requestTimeoutMs: 200,
      reconnectPolicy: const ReconnectPolicy(),
      databaseDirectory: dir,
      attachmentCacheDir: '$dir/attachments_cache',
      diagnosticLevel: DiagnosticLevel.info,
    );

void main() {
  test(
    'interrupted registration reuses pending account and device on retry',
    () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'helix_remote_registration_retry_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final store = _InMemoryKeyValueStore();
      Map<String, dynamic>? firstRegistration;
      Map<String, dynamic>? secondRegistration;

      final firstServer = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(() => firstServer.close(force: true));
      firstServer.listen((request) async {
        if (request.method == 'POST' &&
            request.uri.path == '/api/v1/accounts/register') {
          firstRegistration =
              jsonDecode(await utf8.decodeStream(request))
                  as Map<String, dynamic>;
          _writeJson(request, {
            'message': 'Registration successful',
            'account_id': firstRegistration!['account_id'],
            'device_id': firstRegistration!['device_id'],
          });
        } else if (request.uri.path == '/api/v1/accounts/challenge') {
          request.response.statusCode = 503;
          request.response.headers.set('Retry-After', '0');
          _writeJson(request, {'error': 'try later'});
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });

      final root1 = RemoteCompositionRoot.withConfig(
        _productConfig(tempDir.path),
        devConfig: _devConfig(
          tempDir.path,
          Uri.parse('http://127.0.0.1:${firstServer.port}'),
        ),
        keyValueStore: store,
      );
      await root1.initialize();

      Object? firstError;
      try {
        await root1.registerAndLogin('retry_user', 'Retry User');
      } catch (e) {
        firstError = e;
      }
      await root1.dispose();

      expect(firstError, isNotNull);
      expect(
        firstRegistration,
        isNotNull,
        reason: 'first error before registration POST: $firstError',
      );

      final secondServer = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(() => secondServer.close(force: true));
      secondServer.listen((request) async {
        if (request.method == 'POST' &&
            request.uri.path == '/api/v1/accounts/register') {
          secondRegistration =
              jsonDecode(await utf8.decodeStream(request))
                  as Map<String, dynamic>;
          _writeJson(request, {
            'message': 'Registration successful',
            'account_id': secondRegistration!['account_id'],
            'device_id': secondRegistration!['device_id'],
          });
        } else if (request.uri.path == '/api/v1/accounts/challenge') {
          request.response.statusCode = 503;
          request.response.headers.set('Retry-After', '0');
          _writeJson(request, {'error': 'try later'});
        } else if (request.uri.path == '/api/v1/messages/device-events') {
          _writeJson(request, {'events': []});
        } else {
          request.response.statusCode = 404;
          _writeJson(request, {'error': 'not found'});
        }
        await request.response.close();
      });

      final root2 = RemoteCompositionRoot.withConfig(
        _productConfig(tempDir.path),
        devConfig: _devConfig(
          tempDir.path,
          Uri.parse('http://127.0.0.1:${secondServer.port}'),
        ),
        keyValueStore: store,
      );
      await root2.initialize();
      Object? secondError;
      try {
        await root2.registerAndLogin('retry_user', 'Retry User');
      } catch (e) {
        secondError = e;
      }
      await root2.dispose();

      expect(secondError, isNotNull);
      expect(secondRegistration, isNotNull);
      expect(
        secondRegistration!['account_id'],
        equals(firstRegistration!['account_id']),
      );
      expect(
        secondRegistration!['device_id'],
        equals(firstRegistration!['device_id']),
      );
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}

void _writeJson(HttpRequest request, Map<String, dynamic> body) {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
}
