import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The shareable form of a group invite link (REST_V2.md, groups): the
/// server's token and the key that opens the link's encrypted preview (the
/// group's name and picture) travel together in the URL fragment, which a
/// browser never sends to a server:
///
/// ```
/// https://<server>/open#HLX-GRP-<b64url(token)>.<b64url(preview key, 32 B)>
/// ```
///
/// The token is what `POST /v1/groups/join` takes; the server keeps only its
/// hash. Neither part is ever logged.
abstract final class GroupInviteLinks {
  static const prefix = 'HLX-GRP-';

  /// The link for [token], on the server at [origin].
  static String encode(String origin, String token, List<int> previewKey) =>
      '$origin/open#$prefix${encodeBytes(utf8.encode(token))}'
      '.${encodeBytes(previewKey)}';

  /// The token and preview key in [input] (a full link, a fragment or the
  /// bare `HLX-GRP-…` code), or null when it is not a group link.
  static ({String token, Uint8List previewKey})? parse(String input) {
    var code = input.trim();
    final hash = code.indexOf('#');
    if (hash >= 0) code = code.substring(hash + 1);
    if (!code.startsWith(prefix)) return null;
    final parts = code.substring(prefix.length).split('.');
    if (parts.length != 2) return null;
    try {
      final token = utf8.decode(decodeBytes(parts[0]));
      final key = decodeBytes(parts[1]);
      if (token.isEmpty || key.length != 32) return null;
      return (token: token, previewKey: key);
    } on FormatException {
      return null;
    }
  }
}
