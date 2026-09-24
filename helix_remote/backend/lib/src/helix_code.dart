import 'dart:convert';

/// Utilities for encoding and decoding opaque Helix Invite and Recovery codes.
///
/// These codes conceal the underlying server IP, port, and hostname so that
/// humans sharing or receiving them never see raw server infrastructure details.

const String kHelixInvitePrefix = 'HLX-INV-';
const String kHelixRecoveryPrefix = 'HLX-REC-';

/// Encodes a server URL and invite code into an opaque string:
/// `HLX-INV-<base64url>`
String encodeHelixInviteCode({
  required String serverUrl,
  required String inviteCode,
}) {
  final cleanUrl = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final payload = '$cleanUrl|${inviteCode.trim()}';
  final encoded = base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
  return '$kHelixInvitePrefix$encoded';
}

/// Decodes an opaque Helix Invite code or parses a legacy invite URL.
({String serverUrl, String inviteCode})? decodeHelixInviteCode(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  // Case 1: Opaque HLX-INV- code
  if (trimmed.toUpperCase().startsWith(kHelixInvitePrefix)) {
    try {
      final b64 = trimmed.substring(kHelixInvitePrefix.length);
      final normalizedB64 = base64Url.normalize(b64);
      final decoded = utf8.decode(base64Url.decode(normalizedB64));
      final separatorIndex = decoded.lastIndexOf('|');
      if (separatorIndex <= 0 || separatorIndex >= decoded.length - 1) {
        return null;
      }
      final serverUrl = decoded.substring(0, separatorIndex).trim();
      final inviteCode = decoded.substring(separatorIndex + 1).trim();
      if (serverUrl.isEmpty || inviteCode.isEmpty) return null;
      return (serverUrl: serverUrl, inviteCode: inviteCode);
    } catch (_) {
      return null;
    }
  }

  // Case 2: Legacy URL format with ?invite= parameter
  final withScheme =
      trimmed.startsWith('http://') || trimmed.startsWith('https://')
          ? trimmed
          : 'https://$trimmed';
  final uri = Uri.tryParse(withScheme);
  if (uri != null && uri.host.isNotEmpty) {
    final inviteParam = uri.queryParameters['invite'];
    if (inviteParam != null && inviteParam.isNotEmpty) {
      final portSuffix = uri.hasPort ? ':${uri.port}' : '';
      final serverUrl = '${uri.scheme}://${uri.host}$portSuffix';
      return (serverUrl: serverUrl, inviteCode: inviteParam.trim());
    }
  }

  return null;
}

/// Encodes a server URL, account ID, and recovery code into an opaque string:
/// `HLX-REC-<base64url>`
String encodeHelixRecoveryCode({
  required String serverUrl,
  required String accountId,
  required String recoveryCode,
}) {
  final cleanUrl = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
  final payload = '$cleanUrl|${accountId.trim()}|${recoveryCode.trim()}';
  final encoded = base64Url.encode(utf8.encode(payload)).replaceAll('=', '');
  return '$kHelixRecoveryPrefix$encoded';
}

/// Decodes an opaque Helix Recovery code: `HLX-REC-<base64url>`
({String serverUrl, String accountId, String recoveryCode})?
decodeHelixRecoveryCode(String raw) {
  final trimmed = raw.trim();
  if (!trimmed.toUpperCase().startsWith(kHelixRecoveryPrefix)) {
    return null;
  }
  try {
    final b64 = trimmed.substring(kHelixRecoveryPrefix.length);
    final normalizedB64 = base64Url.normalize(b64);
    final decoded = utf8.decode(base64Url.decode(normalizedB64));
    final parts = decoded.split('|');
    if (parts.length != 3) return null;
    final serverUrl = parts[0].trim();
    final accountId = parts[1].trim();
    final recoveryCode = parts[2].trim();
    if (serverUrl.isEmpty || accountId.isEmpty || recoveryCode.isEmpty) {
      return null;
    }
    return (
      serverUrl: serverUrl,
      accountId: accountId,
      recoveryCode: recoveryCode,
    );
  } catch (_) {
    return null;
  }
}

bool isHelixInviteCode(String raw) =>
    raw.trim().toUpperCase().startsWith(kHelixInvitePrefix);

bool isHelixRecoveryCode(String raw) =>
    raw.trim().toUpperCase().startsWith(kHelixRecoveryPrefix);
