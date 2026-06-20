import 'dart:io';

class RemoteDevelopmentConfig {
  RemoteDevelopmentConfig({
    required this.restBaseUri,
    required this.webSocketUri,
    required this.allowInsecureTransport,
    required this.backendHostMode,
    required this.requestTimeoutMs,
    required this.reconnectPolicy,
    required this.databaseDirectory,
    required this.attachmentCacheDir,
    required this.diagnosticLevel,
  }) {
    _validateTransport();
  }

  final Uri restBaseUri;
  final Uri webSocketUri;
  final bool allowInsecureTransport;
  final String backendHostMode;
  final int requestTimeoutMs;
  final ReconnectPolicy reconnectPolicy;
  final String databaseDirectory;
  final String attachmentCacheDir;
  final DiagnosticLevel diagnosticLevel;

  static RemoteDevelopmentConfig fromPlatform({
    required String databaseDirectory,
    required String attachmentCacheDir,
  }) {
    final host = Platform.environment['HELIX_REMOTE_HOST'] ?? 'localhost';
    final port = Platform.environment['HELIX_REMOTE_PORT'] ?? '8080';
    final wsPort = Platform.environment['HELIX_REMOTE_WS_PORT'] ?? port;
    final scheme = Platform.environment['HELIX_REMOTE_SCHEME'] ?? 'http';
    final allowInsecure =
        Platform.environment['HELIX_REMOTE_DEV_MODE'] == '1' ||
        Platform.environment['HELIX_REMOTE_ALLOW_INSECURE_TRANSPORT'] == '1';

    final mode = host == 'localhost' || host == '127.0.0.1' ? 'same-pc' : 'lan';
    final restScheme = scheme;
    final wsScheme = _webSocketSchemeFor(restScheme);

    return RemoteDevelopmentConfig(
      restBaseUri: Uri.parse('$restScheme://$host:$port'),
      webSocketUri: Uri.parse('$wsScheme://$host:$wsPort/api/v1/ws'),
      allowInsecureTransport: allowInsecure,
      backendHostMode: mode,
      requestTimeoutMs: 15000,
      reconnectPolicy: const ReconnectPolicy(),
      databaseDirectory: databaseDirectory,
      attachmentCacheDir: attachmentCacheDir,
      diagnosticLevel: DiagnosticLevel.info,
    );
  }

  static RemoteDevelopmentConfig fromDartDefine({
    required String databaseDirectory,
    required String attachmentCacheDir,
  }) {
    final host = const String.fromEnvironment(
      'HELIX_REMOTE_HOST',
      defaultValue: 'localhost',
    );
    final port = const String.fromEnvironment(
      'HELIX_REMOTE_PORT',
      defaultValue: '8080',
    );
    final wsPort = const String.fromEnvironment(
      'HELIX_REMOTE_WS_PORT',
      defaultValue: '8080',
    );
    final scheme = const String.fromEnvironment(
      'HELIX_REMOTE_SCHEME',
      defaultValue: 'https',
    );
    const allowInsecure =
        bool.fromEnvironment('HELIX_REMOTE_DEV_MODE', defaultValue: false) ||
        bool.fromEnvironment(
          'HELIX_REMOTE_ALLOW_INSECURE_TRANSPORT',
          defaultValue: false,
        );
    final wsScheme = _webSocketSchemeFor(scheme);

    return RemoteDevelopmentConfig(
      restBaseUri: Uri.parse('$scheme://$host:$port'),
      webSocketUri: Uri.parse('$wsScheme://$host:$wsPort/api/v1/ws'),
      allowInsecureTransport: allowInsecure,
      backendHostMode: host == 'localhost' || host == '127.0.0.1'
          ? 'same-pc'
          : 'lan',
      requestTimeoutMs: 15000,
      reconnectPolicy: const ReconnectPolicy(),
      databaseDirectory: databaseDirectory,
      attachmentCacheDir: attachmentCacheDir,
      diagnosticLevel: DiagnosticLevel.info,
    );
  }

  static String _webSocketSchemeFor(String restScheme) {
    switch (restScheme) {
      case 'http':
        return 'ws';
      case 'https':
        return 'wss';
      default:
        throw ArgumentError.value(restScheme, 'scheme', 'Use http or https');
    }
  }

  void _validateTransport() {
    if (restBaseUri.scheme != 'http' && restBaseUri.scheme != 'https') {
      throw StateError('Remote REST URI must use http or https');
    }
    if (webSocketUri.scheme != 'ws' && webSocketUri.scheme != 'wss') {
      throw StateError('Remote WebSocket URI must use ws or wss');
    }
    if (webSocketUri.path != '/api/v1/ws') {
      throw StateError('Remote WebSocket URI must use /api/v1/ws');
    }
    final plaintext =
        restBaseUri.scheme == 'http' || webSocketUri.scheme == 'ws';
    if (plaintext && !allowInsecureTransport) {
      throw StateError(
        'Plaintext Remote transport requires explicit development mode',
      );
    }
  }
}

class ReconnectPolicy {
  const ReconnectPolicy({
    this.baseDelayMs = 1000,
    this.maxDelayMs = 30000,
    this.maxAttempts = 10,
    this.jitterFactor = 0.2,
  });

  final int baseDelayMs;
  final int maxDelayMs;
  final int maxAttempts;
  final double jitterFactor;
}

enum DiagnosticLevel { silent, error, warn, info, debug }
