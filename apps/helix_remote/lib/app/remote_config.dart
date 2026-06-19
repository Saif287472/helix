import 'dart:io';

class RemoteDevelopmentConfig {
  const RemoteDevelopmentConfig({
    required this.restBaseUri,
    required this.webSocketUri,
    required this.backendHostMode,
    required this.requestTimeoutMs,
    required this.reconnectPolicy,
    required this.databaseDirectory,
    required this.attachmentCacheDir,
    required this.diagnosticLevel,
  });

  final Uri restBaseUri;
  final Uri webSocketUri;
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

    final mode = host == 'localhost' || host == '127.0.0.1' ? 'same-pc' : 'lan';

    return RemoteDevelopmentConfig(
      restBaseUri: Uri.parse('$scheme://$host:$port/api/v1'),
      webSocketUri: Uri.parse('$scheme://$host:$wsPort/ws'),
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
      defaultValue: 'http',
    );

    return RemoteDevelopmentConfig(
      restBaseUri: Uri.parse('$scheme://$host:$port/api/v1'),
      webSocketUri: Uri.parse('$scheme://$host:$wsPort/ws'),
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
