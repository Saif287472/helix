import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';

class RemoteIceConfigProvider {
  RemoteIceConfigProvider({
    required HelixRemoteRestClient restClient,
    required RemoteIceConfig baseConfig,
    DateTime Function()? clock,
  }) : _restClient = restClient,
       _baseConfig = baseConfig,
       _clock = clock ?? DateTime.now;

  final HelixRemoteRestClient _restClient;
  final RemoteIceConfig _baseConfig;
  final DateTime Function() _clock;

  RemoteIceConfig? _cachedConfig;
  DateTime? _expiresAt;

  Future<RemoteIceConfig> getIceConfig() async {
    final now = _clock();
    final cached = _cachedConfig;
    final expiresAt = _expiresAt;
    if (cached != null &&
        expiresAt != null &&
        expiresAt.difference(now) > const Duration(minutes: 5)) {
      return cached;
    }

    final response = await _restClient.getTurnCredentials();
    final username = response['username'] as String?;
    final credential = response['credential'] as String?;
    final expiresAtSeconds = response['expires_at'] as int?;
    final rawUrls = response['urls'];
    final urls = rawUrls is List
        ? rawUrls.whereType<String>().toList(growable: false)
        : [if (response['url'] is String) response['url'] as String];

    if (username == null ||
        credential == null ||
        expiresAtSeconds == null ||
        urls.isEmpty) {
      throw StateError('TURN credentials response is incomplete.');
    }

    final stunServers = _baseConfig.iceServers
        .where((server) => server.url.startsWith('stun:'))
        .toList(growable: false);
    final next =
        RemoteIceConfig(
          iceServers: stunServers,
          ipPrivacy: _baseConfig.ipPrivacy,
        ).withTurnCredentialUrls(
          turnUrls: urls,
          username: username,
          credential: credential,
        );

    if (next.ipPrivacy == IpPrivacyMode.relayOnly && !next.hasTurnServer) {
      throw StateError('Relay-only calls require working TURN credentials.');
    }

    _cachedConfig = next;
    _expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtSeconds * 1000);
    return next;
  }
}
