import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';
import 'package:helix_remote/app/remote_rest_client.dart';

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

    final Map<String, dynamic> response;
    try {
      response = await _restClient.getTurnCredentials();
    } on RemoteRestException catch (e) {
      // Classify here, where the HTTP status is still visible. Letting the
      // raw RemoteRestException travel up meant the call layer could only
      // report "check your connectivity" for what is often a server-side
      // configuration problem the user cannot do anything about.
      throw RemoteCallSetupException(
        e.statusCode == 503
            ? RemoteCallSetupFailure.turnNotConfigured
            : e.isTransportFailure
            ? RemoteCallSetupFailure.network
            : RemoteCallSetupFailure.turnUnavailable,
        detail: e.message,
      );
    }
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
      throw const RemoteCallSetupException(
        RemoteCallSetupFailure.turnUnavailable,
        detail: 'TURN credentials response is incomplete.',
      );
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
      // Deliberately fails rather than falling back to STUN. relayOnly is a
      // privacy guarantee - media is relayed so peers never learn each
      // other's IP - and silently degrading it because of a server
      // misconfiguration would leak addresses between users with no notice.
      throw const RemoteCallSetupException(
        RemoteCallSetupFailure.turnUnavailable,
        detail: 'Relay-only calls require working TURN credentials.',
      );
    }

    _cachedConfig = next;
    _expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtSeconds * 1000);
    return next;
  }
}
