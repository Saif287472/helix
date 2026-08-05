import 'dart:io';

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
      throwsA(isA<RemoteConfigurationException>()),
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
      throwsA(isA<RemoteConfigurationException>()),
    );
  });

  test('Remote config permits plaintext only in explicit development mode', () {
    final dev = RemoteDevelopmentConfig(
      profile: RemoteRuntimeProfile.localWindows,
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
    expect(dev.transportPolicy, RemoteTransportPolicy.debugPlaintextLocalhost);
    expect(dev.tlsExpectation, TlsExpectation.notUsedDebugPlaintext);
  });

  test('Remote config parser supports documented development profiles', () {
    final windows = RemoteDevelopmentConfig.fromEnvironmentValues(
      databaseDirectory: '/tmp/db',
      attachmentCacheDir: '/tmp/cache',
      values: {
        'HELIX_REMOTE_PROFILE': 'local_windows',
        'HELIX_REMOTE_DEV_MODE': '1',
      },
    );
    expect(windows.restBaseUri.toString(), equals('http://127.0.0.1:8080'));
    expect(
      windows.webSocketUri.toString(),
      equals('ws://127.0.0.1:8080/api/v1/ws'),
    );

    final emulator = RemoteDevelopmentConfig.fromEnvironmentValues(
      databaseDirectory: '/tmp/db',
      attachmentCacheDir: '/tmp/cache',
      values: {
        'HELIX_REMOTE_PROFILE': 'android_emulator',
        'HELIX_REMOTE_DEV_MODE': '1',
      },
    );
    expect(emulator.restHost, equals('10.0.2.2'));
    expect(emulator.webSocketHost, equals('10.0.2.2'));
    expect(
      emulator.transportPolicy,
      RemoteTransportPolicy.debugPlaintextEmulator,
    );

    final physical = RemoteDevelopmentConfig.fromEnvironmentValues(
      databaseDirectory: '/tmp/db',
      attachmentCacheDir: '/tmp/cache',
      values: {
        'HELIX_REMOTE_PROFILE': 'android_physical',
        'HELIX_REMOTE_HOST': 'helix-lan.example',
      },
    );
    expect(physical.restScheme, equals('https'));
    expect(physical.webSocketScheme, equals('wss'));
    expect(
      physical.tlsExpectation,
      TlsExpectation.trustedDevelopmentCertificate,
    );
  });

  test('Remote config rejects invalid and incomplete profiles', () {
    expect(
      () => RemoteDevelopmentConfig.fromEnvironmentValues(
        databaseDirectory: '/tmp/db',
        attachmentCacheDir: '/tmp/cache',
        values: const {},
      ),
      throwsA(isA<RemoteConfigurationException>()),
    );

    expect(
      () => RemoteDevelopmentConfig.fromEnvironmentValues(
        databaseDirectory: '/tmp/db',
        attachmentCacheDir: '/tmp/cache',
        values: {
          'HELIX_REMOTE_PROFILE': 'android_emulator',
          'HELIX_REMOTE_HOST': 'localhost',
          'HELIX_REMOTE_DEV_MODE': '1',
        },
      ),
      throwsA(isA<RemoteConfigurationException>()),
    );

    expect(
      () => RemoteDevelopmentConfig.fromEnvironmentValues(
        databaseDirectory: '/tmp/db',
        attachmentCacheDir: '/tmp/cache',
        values: {
          'HELIX_REMOTE_PROFILE': 'local_windows',
          'HELIX_REMOTE_PORT': '70000',
          'HELIX_REMOTE_DEV_MODE': '1',
        },
      ),
      throwsA(isA<RemoteConfigurationException>()),
    );
  });

  test(
    'Production policy rejects HTTP, WS, local hosts, and insecure flags',
    () {
      expect(
        () => RemoteDevelopmentConfig.fromEnvironmentValues(
          databaseDirectory: '/tmp/db',
          attachmentCacheDir: '/tmp/cache',
          values: {
            'HELIX_REMOTE_PROFILE': 'production',
            'HELIX_REMOTE_HOST': 'api.example.com',
            'HELIX_REMOTE_REST_SCHEME': 'http',
            'HELIX_REMOTE_DEV_MODE': '1',
          },
        ),
        throwsA(isA<RemoteConfigurationException>()),
      );

      expect(
        () => RemoteDevelopmentConfig.fromEnvironmentValues(
          databaseDirectory: '/tmp/db',
          attachmentCacheDir: '/tmp/cache',
          values: {
            'HELIX_REMOTE_PROFILE': 'production',
            'HELIX_REMOTE_HOST': 'localhost',
          },
        ),
        throwsA(isA<RemoteConfigurationException>()),
      );
    },
  );

  test('Physical Android development does not enable LAN HTTP', () {
    expect(
      () => RemoteDevelopmentConfig.fromEnvironmentValues(
        databaseDirectory: '/tmp/db',
        attachmentCacheDir: '/tmp/cache',
        values: {
          'HELIX_REMOTE_PROFILE': 'android_physical',
          'HELIX_REMOTE_HOST': '192.168.1.20',
          'HELIX_REMOTE_REST_SCHEME': 'http',
          'HELIX_REMOTE_DEV_MODE': '1',
        },
      ),
      throwsA(isA<RemoteConfigurationException>()),
    );
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

  test('Remote config rejects static TURN credentials from environment', () {
    expect(
      () => RemoteDevelopmentConfig.fromEnvironmentValues(
        databaseDirectory: '/tmp/db',
        attachmentCacheDir: '/tmp/cache',
        values: {
          'HELIX_REMOTE_PROFILE': 'production',
          'HELIX_REMOTE_HOST': 'remote.example',
          'HELIX_REMOTE_TURN_URL': 'turn:turn.remote.example:3478',
          'HELIX_REMOTE_TURN_USERNAME': 'static-user',
          'HELIX_REMOTE_TURN_CREDENTIAL': 'static-password',
        },
      ),
      throwsA(isA<RemoteConfigurationException>()),
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

  test('Android cleartext policy is debug-only and host-scoped', () {
    final mainManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final debugManifest = File(
      'android/app/src/debug/AndroidManifest.xml',
    ).readAsStringSync();
    final networkSecurity = File(
      'android/app/src/debug/res/xml/helix_remote_debug_network_security.xml',
    ).readAsStringSync();

    expect(mainManifest, isNot(contains('usesCleartextTraffic')));
    expect(mainManifest, isNot(contains('networkSecurityConfig')));
    expect(debugManifest, contains('networkSecurityConfig'));
    expect(networkSecurity, contains('<domain>10.0.2.2</domain>'));
    expect(networkSecurity, contains('<domain>127.0.0.1</domain>'));
    expect(networkSecurity, isNot(contains('<base-config')));
  });

  group('restBaseUriFromServerUrl', () {
    test('normalizes a bare host into an https REST base URI', () {
      final uri = RemoteDevelopmentConfig.restBaseUriFromServerUrl(
        'their-server.example',
      );

      expect(uri.scheme, equals('https'));
      expect(uri.host, equals('their-server.example'));
      expect(uri.port, equals(443));
    });

    test(
      'does not require device storage directories, unlike fromServerUrl',
      () {
        // This is the exact bug an invite-link entry screen hit: it only
        // needs a REST base URI to probe an invite code, not a full
        // RemoteDevelopmentConfig, so it must not be forced to supply
        // directories that don't exist yet at that point in the app's
        // lifecycle.
        expect(
          () => RemoteDevelopmentConfig.restBaseUriFromServerUrl(
            'https://remote.example',
          ),
          returnsNormally,
        );
      },
    );

    test('rejects a malformed URL', () {
      expect(
        () => RemoteDevelopmentConfig.restBaseUriFromServerUrl('http://'),
        throwsA(isA<RemoteConfigurationException>()),
      );
    });

    test('rejects HTTP for a non-local address', () {
      expect(
        () => RemoteDevelopmentConfig.restBaseUriFromServerUrl(
          'http://remote.example',
        ),
        throwsA(isA<RemoteConfigurationException>()),
      );
    });

    test('allows HTTP for a local address', () {
      final uri = RemoteDevelopmentConfig.restBaseUriFromServerUrl(
        'http://127.0.0.1:8080',
      );

      expect(uri.scheme, equals('http'));
      expect(uri.port, equals(8080));
    });
  });
}
