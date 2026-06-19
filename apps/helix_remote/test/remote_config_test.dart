import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/remote_config.dart';

void main() {
  test('Remote config maps REST and WebSocket schemes explicitly', () {
    final secure = RemoteDevelopmentConfig(
      restBaseUri: Uri.parse('https://remote.example/api/v1'),
      webSocketUri: Uri.parse('wss://remote.example/api/v1/ws'),
      allowInsecureTransport: false,
      backendHostMode: 'internet',
      requestTimeoutMs: 15000,
      reconnectPolicy: const ReconnectPolicy(),
      databaseDirectory: '/tmp/db',
      attachmentCacheDir: '/tmp/cache',
      diagnosticLevel: DiagnosticLevel.info,
    );

    expect(secure.restBaseUri.scheme, equals('https'));
    expect(secure.webSocketUri.scheme, equals('wss'));
    expect(secure.webSocketUri.path, equals('/api/v1/ws'));
  });

  test('Remote config rejects HTTP WebSocket URI and plaintext by default', () {
    expect(
      () => RemoteDevelopmentConfig(
        restBaseUri: Uri.parse('http://localhost:8080/api/v1'),
        webSocketUri: Uri.parse('http://localhost:8080/api/v1/ws'),
        allowInsecureTransport: true,
        backendHostMode: 'same-pc',
        requestTimeoutMs: 15000,
        reconnectPolicy: const ReconnectPolicy(),
        databaseDirectory: '/tmp/db',
        attachmentCacheDir: '/tmp/cache',
        diagnosticLevel: DiagnosticLevel.info,
      ),
      throwsStateError,
    );

    expect(
      () => RemoteDevelopmentConfig(
        restBaseUri: Uri.parse('http://localhost:8080/api/v1'),
        webSocketUri: Uri.parse('ws://localhost:8080/api/v1/ws'),
        allowInsecureTransport: false,
        backendHostMode: 'same-pc',
        requestTimeoutMs: 15000,
        reconnectPolicy: const ReconnectPolicy(),
        databaseDirectory: '/tmp/db',
        attachmentCacheDir: '/tmp/cache',
        diagnosticLevel: DiagnosticLevel.info,
      ),
      throwsStateError,
    );
  });

  test('Remote config permits plaintext only in explicit development mode', () {
    final dev = RemoteDevelopmentConfig(
      restBaseUri: Uri.parse('http://localhost:8080/api/v1'),
      webSocketUri: Uri.parse('ws://localhost:8080/api/v1/ws'),
      allowInsecureTransport: true,
      backendHostMode: 'same-pc',
      requestTimeoutMs: 15000,
      reconnectPolicy: const ReconnectPolicy(),
      databaseDirectory: '/tmp/db',
      attachmentCacheDir: '/tmp/cache',
      diagnosticLevel: DiagnosticLevel.info,
    );

    expect(dev.webSocketUri.scheme, equals('ws'));
  });
}
