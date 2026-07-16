import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';

class RemoteCallConnectivityDiagnostics {
  RemoteCallConnectivityDiagnostics({
    required HelixRemoteRestClient restClient,
    required RemoteIceConfig baseIceConfig,
  }) : _restClient = restClient,
       _baseIceConfig = baseIceConfig;

  final HelixRemoteRestClient _restClient;
  final RemoteIceConfig _baseIceConfig;

  Future<Map<String, dynamic>> run() async {
    final checks = <String, dynamic>{
      'dns': 'not_checked',
      'tls': 'not_checked',
      'rest_auth': 'unknown',
      'wss': 'not_checked',
      'turn_credentials': 'unknown',
      'turn_allocation': 'not_checked',
      'relay_only': _baseIceConfig.ipPrivacy == IpPrivacyMode.relayOnly,
      'configured_stun_count': _baseIceConfig.iceServers
          .where((server) => server.url.startsWith('stun:'))
          .length,
    };

    try {
      final credentials = await _restClient.getTurnCredentials();
      final urls = credentials['urls'];
      final hasUrls =
          urls is List &&
          urls.whereType<String>().any((url) => url.startsWith('turn'));
      checks['rest_auth'] = 'ok';
      checks['turn_credentials'] = hasUrls ? 'ok' : 'missing_urls';
      checks['turn_url_count'] = urls is List ? urls.length : 0;
    } catch (error) {
      checks['rest_auth'] = 'failed';
      checks['turn_credentials'] = 'failed';
      checks['error'] = error.toString();
    }

    return checks;
  }
}
