/// Parsed target for the `helix://` protocol registered by the mobile and
/// Windows clients. Keeping parsing independent of platform channels makes
/// incoming links straightforward to validate and test before navigation.
enum HelixDeepLinkKind { invite, call, groupJoin }

class HelixDeepLink {
  const HelixDeepLink._({
    required this.kind,
    this.inviteCode,
    this.serverUrl,
    this.callId,
    this.groupId,
  });

  final HelixDeepLinkKind kind;
  final String? inviteCode;
  final String? serverUrl;
  final String? callId;
  final String? groupId;

  /// Accepts the canonical protocol forms:
  ///
  /// * `helix://invite?code=CODE&server=https%3A%2F%2Fchat.example`
  /// * `helix://call/CALL_ID`
  /// * `helix://group/join?group=GROUP_ID&invite=CODE`
  ///
  /// A self-hosted web invite (`https://server.example/join?invite=CODE`) is
  /// also accepted when supplied by another platform entry point.
  static HelixDeepLink? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '/') return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    if (uri.scheme == 'helix') {
      return switch (uri.host) {
        'invite' => _invite(
          uri.queryParameters['code'] ?? uri.queryParameters['invite'],
          uri.queryParameters['server'],
        ),
        'call' => _call(_firstPathSegment(uri)),
        'group' when uri.pathSegments.firstOrNull == 'join' => _groupJoin(
          uri.queryParameters['group'],
          uri.queryParameters['invite'] ?? uri.queryParameters['code'],
        ),
        _ => null,
      };
    }

    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.pathSegments.contains('join')) {
      return _invite(
        uri.queryParameters['invite'],
        uri.replace(path: '', query: '', fragment: '').toString(),
      );
    }
    return null;
  }

  static HelixDeepLink? _invite(String? code, String? server) {
    if (code == null || code.isEmpty) return null;
    return HelixDeepLink._(
      kind: HelixDeepLinkKind.invite,
      inviteCode: code,
      serverUrl: server,
    );
  }

  static HelixDeepLink? _call(String? callId) {
    if (callId == null || callId.isEmpty) return null;
    return HelixDeepLink._(kind: HelixDeepLinkKind.call, callId: callId);
  }

  static HelixDeepLink? _groupJoin(String? groupId, String? inviteCode) {
    if (groupId == null ||
        groupId.isEmpty ||
        inviteCode == null ||
        inviteCode.isEmpty) {
      return null;
    }
    return HelixDeepLink._(
      kind: HelixDeepLinkKind.groupJoin,
      groupId: groupId,
      inviteCode: inviteCode,
    );
  }

  static String? _firstPathSegment(Uri uri) =>
      uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
}
