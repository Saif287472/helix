import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/remote_config.dart';
import 'package:helix_remote/app/remote_endpoints.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';

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
    expect(secure.callIceConfig.iceServers, isEmpty);
    expect(secure.callIceConfig.ipPrivacy, IpPrivacyMode.relayOnly);
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

  test('Remote config accepts explicit call ICE servers', () {
    final config = RemoteDevelopmentConfig(
      restBaseUri: Uri.parse('https://remote.example'),
      webSocketUri: Uri.parse('wss://remote.example/api/v1/ws'),
      allowInsecureTransport: false,
      backendHostMode: 'internet',
      requestTimeoutMs: 15000,
      reconnectPolicy: const ReconnectPolicy(),
      databaseDirectory: '/tmp/db',
      attachmentCacheDir: '/tmp/cache',
      diagnosticLevel: DiagnosticLevel.info,
      callIceConfig: const RemoteIceConfig(
        iceServers: [
          IceServerConfig(url: 'stun:stun.remote.example:3478'),
          IceServerConfig(
            url: 'turns:turn.remote.example:5349',
            username: 'expiring-user',
            credential: 'expiring-credential',
          ),
        ],
        ipPrivacy: IpPrivacyMode.relayOnly,
      ),
    );

    expect(config.callIceConfig.iceServers, hasLength(2));
    expect(
      config.callIceConfig.toWebRtcIceServers().last['urls'],
      equals('turns:turn.remote.example:5349'),
    );
  });

  test('Remote API endpoints use one canonical api prefix', () {
    final fromOrigin = RemoteApiEndpoints(Uri.parse('https://remote.example'));
    final fromLegacy = RemoteApiEndpoints(
      Uri.parse('https://remote.example/api/v1'),
    );

    expect(
      fromOrigin
          .accountsChallenge(accountId: 'a b', deviceId: 'd/1')
          .toString(),
      equals(
        'https://remote.example/api/v1/accounts/challenge?account_id=a+b&device_id=d%2F1',
      ),
    );
    expect(
      fromLegacy.attachmentsUpload.toString(),
      equals('https://remote.example/api/v1/attachments/upload'),
    );
  });
}
