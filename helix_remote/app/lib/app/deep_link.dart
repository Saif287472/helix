import 'package:helix_remote/app/helix_code.dart';

/// Parsed target for the `helix://` protocol registered by the mobile and
/// Windows clients. Keeping parsing independent of platform channels makes
/// incoming links straightforward to validate and test before navigation.
enum HelixDeepLinkKind { invite, serverCode, call, groupJoin, contactAdd }

/// The host of shared invite and recovery links. Always Helix Global's, even
/// for a personal server's code: the code travels in the URL fragment, which
/// a browser never sends to the server, and it names its own server.
const kHelixLinkHost = 'helix.agiletechbd.com';

/// A shareable link that opens [code] (an `HLX-INV-…` or `HLX-REC-…` code) in
/// the app's advanced mode.
String helixCodeLink(String code) => 'https://$kHelixLinkHost/open#$code';

class HelixDeepLink {
  const HelixDeepLink._({
    required this.kind,
    this.inviteCode,
    this.serverUrl,
    this.code,
    this.callId,
    this.groupId,
    this.contactLinkId,
    this.contactAccountId,
    this.contactNonce,
    this.contactExpiresAt,
    this.contactSignature,
  });

  final HelixDeepLinkKind kind;
  final String? inviteCode;
  final String? serverUrl;

  /// [HelixDeepLinkKind.serverCode]: the `HLX-INV-…` or `HLX-REC-…` code.
  final String? code;
  final String? callId;
  final String? groupId;
  final String? contactLinkId;
  final String? contactAccountId;
  final String? contactNonce;
  final int? contactExpiresAt;
  final String? contactSignature;

  /// Accepts the canonical protocol forms:
  ///
  /// * `https://helix.agiletechbd.com/open#HLX-INV-…` (or `#HLX-REC-…`) - the
  ///   shared form, see [helixCodeLink]
  /// * `helix://open?code=HLX-…` - what that page's "Open in Helix" button
  ///   launches when the app did not open the link directly
  /// * `helix://invite?code=CODE&server=https%3A%2F%2Fchat.example`
  /// * `helix://call/CALL_ID`
  /// * `helix://group/join?group=GROUP_ID&invite=CODE`
  /// * `helix://contact/add?v=1&id=ID&a=ACCOUNT&n=NONCE&e=MS&s=SIG`
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
        'open' => _serverCode(uri.queryParameters['code']),
        'invite' => _invite(
          uri.queryParameters['code'] ?? uri.queryParameters['invite'],
          uri.queryParameters['server'],
        ),
        'call' => _call(_firstPathSegment(uri)),
        'group' when uri.pathSegments.firstOrNull == 'join' => _groupJoin(
          uri.queryParameters['group'],
          uri.queryParameters['invite'] ?? uri.queryParameters['code'],
        ),
        'contact' when uri.pathSegments.firstOrNull == 'add' => _contactAdd(
          uri.queryParameters,
        ),
        _ => null,
      };
    }

    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.pathSegments.firstOrNull == 'open') {
      return _serverCode(Uri.decodeComponent(uri.fragment));
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

  /// The code this link hands to sign-in's advanced mode, if it is an invite
  /// or recovery link.
  String? get setupCode => switch (kind) {
    HelixDeepLinkKind.serverCode => code,
    HelixDeepLinkKind.invite when serverUrl != null && serverUrl!.isNotEmpty =>
      encodeHelixInviteCode(serverUrl: serverUrl!, inviteCode: inviteCode!),
    _ => null,
  };

  static HelixDeepLink? _serverCode(String? code) {
    final trimmed = code?.trim() ?? '';
    final upper = trimmed.toUpperCase();
    if (!upper.startsWith('HLX-INV-') && !upper.startsWith('HLX-REC-')) {
      return null;
    }
    return HelixDeepLink._(kind: HelixDeepLinkKind.serverCode, code: trimmed);
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

  static HelixDeepLink? _contactAdd(Map<String, String> params) {
    if (params['v'] != '1') return null;
    final linkId = params['id'];
    final accountId = params['a'];
    final nonce = params['n'];
    final expiresAt = int.tryParse(params['e'] ?? '');
    final signature = params['s'];
    if (linkId == null ||
        linkId.isEmpty ||
        accountId == null ||
        accountId.isEmpty ||
        nonce == null ||
        nonce.isEmpty ||
        expiresAt == null ||
        signature == null ||
        signature.isEmpty) {
      return null;
    }
    return HelixDeepLink._(
      kind: HelixDeepLinkKind.contactAdd,
      contactLinkId: linkId,
      contactAccountId: accountId,
      contactNonce: nonce,
      contactExpiresAt: expiresAt,
      contactSignature: signature,
    );
  }

  static String? _firstPathSegment(Uri uri) =>
      uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
}
