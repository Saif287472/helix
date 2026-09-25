import 'dart:io';

import 'package:helix_remote_calls/helix_remote_calls.dart';

/// The free, shared Helix Remote server offered as a first-launch option.
/// Auto-issues its own invites (server-side gated by `global_instance_mode`)
/// so users don't need an admin-issued invite to join it.
/// Keep this endpoint fixed for the Global onboarding path; personal-server
/// URLs are resolved separately from invites and explicit server selection.
const kHelixGlobalServerUrl = 'https://helix.agiletechbd.com';

enum RemoteRuntimeProfile {
  production,
  localWindows,
  androidEmulator,
  androidPhysical,
}

enum RemoteTransportPolicy {
  strictTls,
  trustedLocalTls,
  debugPlaintextLocalhost,
  debugPlaintextEmulator,
}

enum TlsExpectation {
  required,
  trustedDevelopmentCertificate,
  notUsedDebugPlaintext,
}

class RemoteConfigurationException implements Exception {
  const RemoteConfigurationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RemoteDevelopmentConfig {
  RemoteDevelopmentConfig({
    this.profile = RemoteRuntimeProfile.production,
    String? environmentName,
    required this.restBaseUri,
    required this.webSocketUri,
    required this.allowInsecureTransport,
    RemoteTransportPolicy? transportPolicy,
    TlsExpectation? tlsExpectation,
    required this.backendHostMode,
    required this.requestTimeoutMs,
    required this.reconnectPolicy,
    required this.databaseDirectory,
    required this.attachmentCacheDir,
    required this.diagnosticLevel,
    this.callIceConfig = const RemoteIceConfig(
      iceServers: [],
      ipPrivacy: IpPrivacyMode.relayOnly,
    ),
  }) : environmentName = environmentName ?? profile.name,
       transportPolicy =
           transportPolicy ??
           _defaultTransportPolicy(
             profile,
             restBaseUri.scheme,
             webSocketUri.scheme,
           ),
       tlsExpectation =
           tlsExpectation ??
           _defaultTlsExpectation(restBaseUri.scheme, webSocketUri.scheme) {
    _validate();
  }

  final RemoteRuntimeProfile profile;
  final String environmentName;
  final Uri restBaseUri;
  final Uri webSocketUri;
  final bool allowInsecureTransport;
  final RemoteTransportPolicy transportPolicy;
  final TlsExpectation tlsExpectation;
  final String backendHostMode;
  final int requestTimeoutMs;
  final ReconnectPolicy reconnectPolicy;
  final String databaseDirectory;
  final String attachmentCacheDir;
  final DiagnosticLevel diagnosticLevel;
  final RemoteIceConfig callIceConfig;

  String get restScheme => restBaseUri.scheme;
  String get restHost => restBaseUri.host;
  int get restPort => restBaseUri.port;
  String get restBasePath => restBaseUri.path;
  String get webSocketScheme => webSocketUri.scheme;
  String get webSocketHost => webSocketUri.host;
  int get webSocketPort => webSocketUri.port;
  String get webSocketPath => webSocketUri.path;

  static RemoteDevelopmentConfig fromPlatform({
    required String databaseDirectory,
    required String attachmentCacheDir,
  }) {
    return fromEnvironmentValues(
      databaseDirectory: databaseDirectory,
      attachmentCacheDir: attachmentCacheDir,
      values: Platform.environment,
    );
  }

  static RemoteDevelopmentConfig fromEnvironmentValues({
    required String databaseDirectory,
    required String attachmentCacheDir,
    required Map<String, String> values,
  }) {
    final env = values;
    return _fromValues(
      databaseDirectory: databaseDirectory,
      attachmentCacheDir: attachmentCacheDir,
      profileValue: env['HELIX_REMOTE_PROFILE'] ?? 'production',
      hostValue: env['HELIX_REMOTE_HOST'] ?? '',
      portValue: env['HELIX_REMOTE_PORT'] ?? '',
      restSchemeValue:
          env['HELIX_REMOTE_REST_SCHEME'] ?? env['HELIX_REMOTE_SCHEME'] ?? '',
      restBasePathValue: env['HELIX_REMOTE_REST_BASE_PATH'] ?? '',
      wsSchemeValue: env['HELIX_REMOTE_WS_SCHEME'] ?? '',
      wsHostValue: env['HELIX_REMOTE_WS_HOST'] ?? '',
      wsPortValue: env['HELIX_REMOTE_WS_PORT'] ?? '',
      wsPathValue: env['HELIX_REMOTE_WS_PATH'] ?? '',
      devModeValue: _envBool(env['HELIX_REMOTE_DEV_MODE']),
      allowInsecureValue: _envBool(
        env['HELIX_REMOTE_ALLOW_INSECURE_TRANSPORT'],
      ),
      stunUrls: env['HELIX_REMOTE_STUN_URLS'] ?? '',
      turnUrl: env['HELIX_REMOTE_TURN_URL'] ?? '',
      turnUsername: env['HELIX_REMOTE_TURN_USERNAME'] ?? '',
      turnCredential: env['HELIX_REMOTE_TURN_CREDENTIAL'] ?? '',
      ipPrivacy: env['HELIX_REMOTE_IP_PRIVACY'] ?? '',
    );
  }

  static RemoteDevelopmentConfig fromDartDefine({
    required String databaseDirectory,
    required String attachmentCacheDir,
  }) {
    const profileValue = String.fromEnvironment(
      'HELIX_REMOTE_PROFILE',
      defaultValue: 'production',
    );
    const hostValue = String.fromEnvironment('HELIX_REMOTE_HOST');
    const portValue = String.fromEnvironment('HELIX_REMOTE_PORT');
    const restSchemeValue = String.fromEnvironment(
      'HELIX_REMOTE_REST_SCHEME',
      defaultValue: String.fromEnvironment('HELIX_REMOTE_SCHEME'),
    );
    const restBasePathValue = String.fromEnvironment(
      'HELIX_REMOTE_REST_BASE_PATH',
    );
    const wsSchemeValue = String.fromEnvironment('HELIX_REMOTE_WS_SCHEME');
    const wsHostValue = String.fromEnvironment('HELIX_REMOTE_WS_HOST');
    const wsPortValue = String.fromEnvironment('HELIX_REMOTE_WS_PORT');
    const wsPathValue = String.fromEnvironment('HELIX_REMOTE_WS_PATH');
    const devModeValue = bool.fromEnvironment(
      'HELIX_REMOTE_DEV_MODE',
      defaultValue: false,
    );
    const allowInsecureValue = bool.fromEnvironment(
      'HELIX_REMOTE_ALLOW_INSECURE_TRANSPORT',
      defaultValue: false,
    );
    const stunUrls = String.fromEnvironment('HELIX_REMOTE_STUN_URLS');
    const turnUrl = String.fromEnvironment('HELIX_REMOTE_TURN_URL');
    const turnUsername = String.fromEnvironment('HELIX_REMOTE_TURN_USERNAME');
    const turnCredential = String.fromEnvironment(
      'HELIX_REMOTE_TURN_CREDENTIAL',
    );
    const ipPrivacy = String.fromEnvironment('HELIX_REMOTE_IP_PRIVACY');

    return _fromValues(
      databaseDirectory: databaseDirectory,
      attachmentCacheDir: attachmentCacheDir,
      profileValue: profileValue,
      hostValue: hostValue,
      portValue: portValue,
      restSchemeValue: restSchemeValue,
      restBasePathValue: restBasePathValue,
      wsSchemeValue: wsSchemeValue,
      wsHostValue: wsHostValue,
      wsPortValue: wsPortValue,
      wsPathValue: wsPathValue,
      devModeValue: devModeValue,
      allowInsecureValue: allowInsecureValue,
      stunUrls: stunUrls,
      turnUrl: turnUrl,
      turnUsername: turnUsername,
      turnCredential: turnCredential,
      ipPrivacy: ipPrivacy,
    );
  }

  static RemoteDevelopmentConfig _fromValues({
    required String databaseDirectory,
    required String attachmentCacheDir,
    required String profileValue,
    required String hostValue,
    required String portValue,
    required String restSchemeValue,
    required String restBasePathValue,
    required String wsSchemeValue,
    required String wsHostValue,
    required String wsPortValue,
    required String wsPathValue,
    required bool devModeValue,
    required bool allowInsecureValue,
    required String stunUrls,
    required String turnUrl,
    required String turnUsername,
    required String turnCredential,
    required String ipPrivacy,
  }) {
    final profile = _profileFor(profileValue);
    final defaults = _profileDefaults(profile);
    final host = hostValue.trim().isEmpty ? defaults.host : hostValue.trim();
    final restScheme = restSchemeValue.trim().isEmpty
        ? defaults.restScheme
        : restSchemeValue.trim().toLowerCase();
    final port = _parsePort(
      portValue.trim().isEmpty ? defaults.port : portValue.trim(),
      'HELIX_REMOTE_PORT',
    );
    final wsScheme = wsSchemeValue.trim().isEmpty
        ? _webSocketSchemeFor(restScheme)
        : wsSchemeValue.trim().toLowerCase();
    final wsHost = wsHostValue.trim().isEmpty ? host : wsHostValue.trim();
    final wsPort = _parsePort(
      wsPortValue.trim().isEmpty ? '$port' : wsPortValue.trim(),
      'HELIX_REMOTE_WS_PORT',
    );
    final restBasePath = _normalizePath(restBasePathValue);
    final wsPath = wsPathValue.trim().isEmpty
        ? '/api/v1/ws'
        : _normalizePath(wsPathValue);
    final allowInsecure = devModeValue || allowInsecureValue;
    final plaintext = restScheme == 'http' || wsScheme == 'ws';

    if (profile == RemoteRuntimeProfile.androidPhysical && plaintext) {
      throw const RemoteConfigurationException(
        'Physical Android development must use HTTPS/WSS with a trusted '
        'LAN or staging endpoint. LAN HTTP is intentionally not enabled for '
        'physical devices.',
      );
    }

    final transportPolicy = _policyFor(
      profile: profile,
      restScheme: restScheme,
      wsScheme: wsScheme,
    );
    final tlsExpectation = plaintext
        ? TlsExpectation.notUsedDebugPlaintext
        : profile == RemoteRuntimeProfile.production
        ? TlsExpectation.required
        : TlsExpectation.trustedDevelopmentCertificate;

    return RemoteDevelopmentConfig(
      profile: profile,
      environmentName: profileValue,
      restBaseUri: Uri(
        scheme: restScheme,
        host: host,
        port: port,
        path: restBasePath,
      ),
      webSocketUri: Uri(
        scheme: wsScheme,
        host: wsHost,
        port: wsPort,
        path: wsPath,
      ),
      allowInsecureTransport: allowInsecure,
      transportPolicy: transportPolicy,
      tlsExpectation: tlsExpectation,
      backendHostMode: defaults.hostMode,
      requestTimeoutMs: 15000,
      reconnectPolicy: const ReconnectPolicy(),
      databaseDirectory: databaseDirectory,
      attachmentCacheDir: attachmentCacheDir,
      diagnosticLevel: DiagnosticLevel.info,
      callIceConfig: _iceConfigFromValues(
        stunUrls: stunUrls,
        turnUrl: turnUrl,
        turnUsername: turnUsername,
        turnCredential: turnCredential,
        ipPrivacy: ipPrivacy,
      ),
    );
  }

  static bool _envBool(String? value) {
    switch (value) {
      case '1':
      case 'true':
      case 'TRUE':
      case 'yes':
      case 'YES':
        return true;
      default:
        return false;
    }
  }

  static _ProfileDefaults _profileDefaults(RemoteRuntimeProfile profile) {
    switch (profile) {
      case RemoteRuntimeProfile.production:
        return const _ProfileDefaults(
          host: '',
          port: '443',
          restScheme: 'https',
          hostMode: 'production',
        );
      case RemoteRuntimeProfile.localWindows:
        return const _ProfileDefaults(
          host: '127.0.0.1',
          port: '8080',
          restScheme: 'http',
          hostMode: 'same-pc',
        );
      case RemoteRuntimeProfile.androidEmulator:
        return const _ProfileDefaults(
          host: '10.0.2.2',
          port: '8080',
          restScheme: 'http',
          hostMode: 'android-emulator-host',
        );
      case RemoteRuntimeProfile.androidPhysical:
        return const _ProfileDefaults(
          host: '',
          port: '443',
          restScheme: 'https',
          hostMode: 'android-physical-trusted-tls',
        );
    }
  }

  static RemoteRuntimeProfile _profileFor(String value) {
    switch (value.trim().toLowerCase().replaceAll('-', '_')) {
      case 'production':
      case 'prod':
        return RemoteRuntimeProfile.production;
      case 'local_windows':
      case 'windows_dev':
      case 'local':
        return RemoteRuntimeProfile.localWindows;
      case 'android_emulator':
      case 'emulator':
        return RemoteRuntimeProfile.androidEmulator;
      case 'android_physical':
      case 'physical_android':
        return RemoteRuntimeProfile.androidPhysical;
      default:
        throw RemoteConfigurationException(
          'Unknown HELIX_REMOTE_PROFILE "$value". Use production, '
          'local_windows, android_emulator, or android_physical.',
        );
    }
  }

  static int _parsePort(String value, String name) {
    final port = int.tryParse(value);
    if (port == null || port < 1 || port > 65535) {
      throw RemoteConfigurationException(
        '$name must be a port from 1 to 65535',
      );
    }
    return port;
  }

  static String _normalizePath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '/') return '';
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }

  static RemoteTransportPolicy _policyFor({
    required RemoteRuntimeProfile profile,
    required String restScheme,
    required String wsScheme,
  }) {
    final plaintext = restScheme == 'http' || wsScheme == 'ws';
    if (!plaintext) {
      return profile == RemoteRuntimeProfile.production
          ? RemoteTransportPolicy.strictTls
          : RemoteTransportPolicy.trustedLocalTls;
    }
    switch (profile) {
      case RemoteRuntimeProfile.localWindows:
        return RemoteTransportPolicy.debugPlaintextLocalhost;
      case RemoteRuntimeProfile.androidEmulator:
        return RemoteTransportPolicy.debugPlaintextEmulator;
      case RemoteRuntimeProfile.production:
      case RemoteRuntimeProfile.androidPhysical:
        return RemoteTransportPolicy.strictTls;
    }
  }

  static RemoteTransportPolicy _defaultTransportPolicy(
    RemoteRuntimeProfile profile,
    String restScheme,
    String wsScheme,
  ) => _policyFor(profile: profile, restScheme: restScheme, wsScheme: wsScheme);

  static TlsExpectation _defaultTlsExpectation(
    String restScheme,
    String wsScheme,
  ) => restScheme == 'http' || wsScheme == 'ws'
      ? TlsExpectation.notUsedDebugPlaintext
      : TlsExpectation.required;

  static RemoteIceConfig _iceConfigFromValues({
    required String stunUrls,
    required String turnUrl,
    required String turnUsername,
    required String turnCredential,
    required String ipPrivacy,
  }) {
    final servers = <IceServerConfig>[
      for (final url in stunUrls.split(',').map((s) => s.trim()))
        if (url.isNotEmpty) IceServerConfig(url: url),
    ];
    if (turnUrl.isNotEmpty ||
        turnUsername.isNotEmpty ||
        turnCredential.isNotEmpty) {
      throw const RemoteConfigurationException(
        'Static TURN configuration is not supported in the client. Fetch '
        'short-lived credentials from /api/v1/calls/turn-credentials.',
      );
    }
    return RemoteIceConfig(
      iceServers: servers,
      ipPrivacy: _ipPrivacyModeFor(ipPrivacy),
    );
  }

  static IpPrivacyMode _ipPrivacyModeFor(String value) {
    // Empty means unset, which is relay-only: the safe default has to be
    // what you get for doing nothing.
    if (value.isEmpty) return IpPrivacyMode.relayOnly;
    final mode = IpPrivacyMode.fromWire(value);
    if (mode == null) {
      throw RemoteConfigurationException(
        'Unknown HELIX_REMOTE_IP_PRIVACY "$value". Expected one of: '
        '${IpPrivacyMode.values.map((m) => m.wireName).join(', ')}.',
      );
    }
    return mode;
  }

  static String _webSocketSchemeFor(String restScheme) {
    switch (restScheme) {
      case 'http':
        return 'ws';
      case 'https':
        return 'wss';
      default:
        throw const RemoteConfigurationException(
          'Remote REST scheme must be http or https.',
        );
    }
  }

  /// Build a config pointed at Helix Global. Routes through the same
  /// validated [fromServerUrl] path as any other server - Helix Global gets
  /// no special bypass of the TLS/localhost checks.
  static RemoteDevelopmentConfig helixGlobal({
    required String databaseDirectory,
    required String attachmentCacheDir,
  }) => fromServerUrl(
    kHelixGlobalServerUrl,
    databaseDirectory: databaseDirectory,
    attachmentCacheDir: attachmentCacheDir,
  );

  /// Validates and normalizes a user-supplied server URL (e.g. ngrok, LAN
  /// IP, localhost) into its REST base [Uri], with none of
  /// [RemoteDevelopmentConfig]'s other requirements (device storage
  /// directories, WebSocket path, etc.) - for callers that only need to
  /// know where to send a request, such as validating an invite link
  /// before any device directories are known.
  static Uri restBaseUriFromServerUrl(String url) {
    var trimmed = url.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'https://$trimmed';
    }
    // Strips a trailing path slash (e.g. "https://example.com/" ->
    // "https://example.com"), but must not eat into "scheme://" itself -
    // done after the scheme is already in place, and the lookbehind skips
    // straight past a run of slashes immediately after the scheme's ':',
    // rather than stripping it down to a bare "https:" that Uri.tryParse
    // would then happily parse with the *next* segment as the host (e.g.
    // "http://" collapsing to "http:", then re-prefixed into the nonsense
    // "https://http" instead of being rejected as malformed).
    trimmed = trimmed.replaceAll(RegExp(r'(?<=[^:])/+$'), '');
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) {
      throw const RemoteConfigurationException(
        'Enter a valid server URL (e.g. https://xxxx.ngrok-free.dev).',
      );
    }
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host;
    final port = uri.port == 0 ? (scheme == 'https' ? 443 : 8080) : uri.port;

    if (scheme == 'http' && !_isLocalAddress(host)) {
      throw const RemoteConfigurationException(
        'HTTP is only allowed for local addresses. '
        'Use https:// for internet servers.',
      );
    }
    return Uri(scheme: scheme, host: host, port: port);
  }

  /// Build a config from a user-supplied URL (e.g. ngrok, LAN IP, localhost).
  ///
  /// HTTPS non-local URLs → production profile (strict TLS).
  /// HTTP local URLs → localWindows profile (dev plaintext, allowInsecure).
  static RemoteDevelopmentConfig fromServerUrl(
    String url, {
    required String databaseDirectory,
    required String attachmentCacheDir,
  }) {
    final restBaseUri = restBaseUriFromServerUrl(url);
    final scheme = restBaseUri.scheme;
    final host = restBaseUri.host;
    final port = restBaseUri.port;

    final wsScheme = scheme == 'https' ? 'wss' : 'ws';
    final profile = scheme == 'https'
        ? RemoteRuntimeProfile.production
        : RemoteRuntimeProfile.localWindows;

    return RemoteDevelopmentConfig(
      profile: profile,
      restBaseUri: restBaseUri,
      webSocketUri: Uri(
        scheme: wsScheme,
        host: host,
        port: port,
        path: '/api/v1/ws',
      ),
      allowInsecureTransport: scheme == 'http',
      backendHostMode: scheme == 'https' ? 'production' : 'same-pc',
      requestTimeoutMs: 15000,
      reconnectPolicy: const ReconnectPolicy(),
      databaseDirectory: databaseDirectory,
      attachmentCacheDir: attachmentCacheDir,
      diagnosticLevel: DiagnosticLevel.info,
    );
  }

  void _validate() {
    _validateScheme(restBaseUri.scheme, const {'http', 'https'}, 'REST');
    _validateScheme(webSocketUri.scheme, const {'ws', 'wss'}, 'WebSocket');
    if (restBaseUri.host.isEmpty) {
      throw const RemoteConfigurationException(
        'HELIX_REMOTE_HOST is required. Production must set an HTTPS host; '
        'development must choose an explicit HELIX_REMOTE_PROFILE.',
      );
    }
    if (webSocketUri.host.isEmpty) {
      throw const RemoteConfigurationException(
        'Remote WebSocket host must not be empty.',
      );
    }
    if (restBaseUri.hasQuery || restBaseUri.hasFragment) {
      throw const RemoteConfigurationException(
        'Remote REST URI must not include query or fragment components.',
      );
    }
    if (webSocketUri.hasQuery || webSocketUri.hasFragment) {
      throw const RemoteConfigurationException(
        'Remote WebSocket URI must not include query or fragment components.',
      );
    }
    if (webSocketUri.path != '/api/v1/ws') {
      throw const RemoteConfigurationException(
        'Remote WebSocket URI must use /api/v1/ws.',
      );
    }
    if (requestTimeoutMs <= 0) {
      throw const RemoteConfigurationException(
        'Remote request timeout must be positive.',
      );
    }
    if (databaseDirectory.isEmpty || attachmentCacheDir.isEmpty) {
      throw const RemoteConfigurationException(
        'Remote database and attachment cache directories must be configured.',
      );
    }

    final plaintext =
        restBaseUri.scheme == 'http' || webSocketUri.scheme == 'ws';
    if (plaintext && !allowInsecureTransport) {
      throw const RemoteConfigurationException(
        'Plaintext Remote transport requires HELIX_REMOTE_DEV_MODE=1 and a '
        'development profile.',
      );
    }
    if (profile == RemoteRuntimeProfile.production) {
      if (allowInsecureTransport || plaintext) {
        throw const RemoteConfigurationException(
          'Production Remote configuration requires HTTPS/WSS and strict TLS.',
        );
      }
      if (_isLocalAddress(restBaseUri.host) ||
          _isLocalAddress(webSocketUri.host)) {
        throw const RemoteConfigurationException(
          'Production Remote configuration must not target localhost or the '
          'Android emulator host.',
        );
      }
      if (transportPolicy != RemoteTransportPolicy.strictTls ||
          tlsExpectation != TlsExpectation.required) {
        throw const RemoteConfigurationException(
          'Production Remote configuration must use strict TLS policy.',
        );
      }
    }
    if (profile == RemoteRuntimeProfile.androidEmulator) {
      if (restBaseUri.host != '10.0.2.2') {
        throw const RemoteConfigurationException(
          'Android emulator profile must target HELIX_REMOTE_HOST=10.0.2.2.',
        );
      }
    }
    if (profile == RemoteRuntimeProfile.androidPhysical &&
        _isLocalAddress(restBaseUri.host)) {
      throw const RemoteConfigurationException(
        'Physical Android profile must target an explicit LAN/staging HTTPS '
        'host, not localhost.',
      );
    }
  }

  static void _validateScheme(String value, Set<String> allowed, String label) {
    if (!allowed.contains(value)) {
      throw RemoteConfigurationException(
        'Remote $label scheme must be one of: ${allowed.join(', ')}.',
      );
    }
  }

  static bool _isLocalAddress(String host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2';
}

class _ProfileDefaults {
  const _ProfileDefaults({
    required this.host,
    required this.port,
    required this.restScheme,
    required this.hostMode,
  });

  final String host;
  final String port;
  final String restScheme;
  final String hostMode;
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
