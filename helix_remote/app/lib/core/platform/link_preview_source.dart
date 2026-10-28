import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a page says about itself: the title and the description a link card
/// shows. No picture is fetched.
final class LinkPreviewData {
  const LinkPreviewData({required this.url, this.title, this.description});

  /// The address as it is in the message.
  final String url;
  final String? title;
  final String? description;
}

/// Where a link's card comes from. It is the sender's phone that asks the
/// site (the reader's never does), and only when the person turned link
/// previews on in Settings > Chats.
abstract interface class LinkPreviewSource {
  /// The page's title and description, or null for anything that is not a
  /// plain, public, small web page that answers in time.
  Future<LinkPreviewData?> fetch(Uri url);
}

final linkPreviewSourceProvider = Provider<LinkPreviewSource>(
  (ref) => HttpLinkPreviewSource(),
);

/// The first web address in [text], exactly as it is written there (without
/// the punctuation that ends a sentence), or null.
String? firstLinkIn(String text) {
  final match = RegExp(
    r'https?://[^\s<>"]+',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  final cleaned = match.group(0)!.replaceFirst(RegExp(r'[.,;:!?)\]]+$'), '');
  final uri = Uri.tryParse(cleaned);
  return uri == null || uri.host.isEmpty ? null : cleaned;
}

/// Whether [address] is somewhere a link preview must never be fetched from:
/// this phone, a private or link-local network, a carrier-grade NAT, or an
/// address that is not a host at all. A link in a message must not make the
/// sender's phone knock on its own network.
bool isBlockedAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return true;
  }
  final b = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) return _blockedV4(b);
  if (b.every((x) => x == 0)) return true; // ::
  if ((b[0] & 0xfe) == 0xfc) return true; // fc00::/7, unique local
  if (b[0] == 0xfe && (b[1] & 0xc0) == 0xc0) return true; // fec0::/10
  if (b[0] == 0x20 && b[1] == 0x01 && b[2] == 0 && b[3] == 0) {
    return true; // 2001::/32, Teredo
  }
  // ::ffff:a.b.c.d is an IPv4 address in IPv6 clothes.
  final low = b.sublist(0, 10).every((x) => x == 0);
  if (low && b[10] == 0xff && b[11] == 0xff) return _blockedV4(b.sublist(12));
  // ::a.b.c.d, the old IPv4-compatible form.
  if (low && b[10] == 0 && b[11] == 0) return _blockedV4(b.sublist(12));
  // 64:ff9b::/96 (NAT64) and 2002::/16 (6to4) carry an IPv4 address that a
  // gateway would connect to.
  if (b[0] == 0x00 &&
      b[1] == 0x64 &&
      b[2] == 0xff &&
      b[3] == 0x9b &&
      b.sublist(4, 12).every((x) => x == 0)) {
    return _blockedV4(b.sublist(12));
  }
  if (b[0] == 0x20 && b[1] == 0x02) return _blockedV4(b.sublist(2, 6));
  return false;
}

bool _blockedV4(List<int> b) =>
    b[0] == 0 || // 0.0.0.0/8
    b[0] == 10 ||
    b[0] == 127 ||
    (b[0] == 100 && b[1] >= 64 && b[1] <= 127) || // 100.64.0.0/10
    (b[0] == 169 && b[1] == 254) ||
    (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
    (b[0] == 192 && b[1] == 168) ||
    (b[0] == 192 &&
        b[1] == 0 &&
        (b[2] == 0 || b[2] == 2)) || // 192.0.0/24, 192.0.2/24
    (b[0] == 198 && (b[1] == 18 || b[1] == 19)) || // 198.18.0.0/15
    (b[0] == 198 && b[1] == 51 && b[2] == 100) || // 198.51.100/24
    (b[0] == 203 && b[1] == 0 && b[2] == 113) || // 203.0.113/24
    b[0] >= 224; // multicast and reserved

/// The card's text from a page's HTML: Open Graph, then Twitter, then the
/// plain tags. Null when the page has neither a title nor a description.
LinkPreviewData? previewFromHtml(String html, String url) {
  final head = html.length > 200000 ? html.substring(0, 200000) : html;
  final found = <String, String>{};
  for (final m in RegExp(
    r'<meta\s+([^>]*?)/?>',
    caseSensitive: false,
  ).allMatches(head)) {
    final attrs = _attributes(m.group(1)!);
    final key = (attrs['property'] ?? attrs['name'])?.toLowerCase();
    final content = attrs['content'];
    if (key != null && content != null) found.putIfAbsent(key, () => content);
  }
  final tag = RegExp(
    r'<title[^>]*>(.*?)</title>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(head)?.group(1);
  final title = _clean(found['og:title'] ?? found['twitter:title'] ?? tag, 200);
  final description = _clean(
    found['og:description'] ??
        found['twitter:description'] ??
        found['description'],
    300,
  );
  if (title == null && description == null) return null;
  return LinkPreviewData(url: url, title: title, description: description);
}

Map<String, String> _attributes(String text) => {
  for (final m in RegExp(
    r'''([a-zA-Z:_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))''',
  ).allMatches(text))
    m.group(1)!.toLowerCase(): m.group(2) ?? m.group(3) ?? m.group(4) ?? '',
};

String? _clean(String? raw, int max) {
  if (raw == null) return null;
  final text = _decodeEntities(raw).replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return null;
  return text.length > max ? '${text.substring(0, max - 1)}…' : text;
}

String _decodeEntities(String s) => s
    .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      return code == null || code > 0x10FFFF ? '' : String.fromCharCode(code);
    })
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code == null || code > 0x10FFFF ? '' : String.fromCharCode(code);
    })
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// Fetches a page over HTTPS with `dart:io`, as plainly as it can: public
/// hosts only (checked on every redirect), port 443, no cookies, at most three
/// redirects, 256 KiB of body, six seconds, HTML only. Anything else is "no
/// preview", never an error the person sees.
final class HttpLinkPreviewSource implements LinkPreviewSource {
  HttpLinkPreviewSource({
    @visibleForTesting HttpClient Function()? clientFactory,
    @visibleForTesting
    Future<List<InternetAddress>> Function(String host)? resolve,
  }) : _clientFactory = clientFactory ?? HttpClient.new,
       _resolve = resolve ?? InternetAddress.lookup,
       _guardConnections = clientFactory == null;

  static const maxBytes = 256 * 1024;
  static const maxRedirects = 3;
  static const timeout = Duration(seconds: 6);

  final HttpClient Function() _clientFactory;

  /// The real client connects through [_connectVetted]; a test's own client
  /// does not.
  final bool _guardConnections;
  final Future<List<InternetAddress>> Function(String host) _resolve;

  @override
  Future<LinkPreviewData?> fetch(Uri url) async {
    try {
      return await _fetch(url).timeout(timeout);
    } on Object {
      return null;
    }
  }

  /// Whether [u] may be fetched at all: HTTPS on 443, a public host.
  @visibleForTesting
  Future<bool> allows(Uri u) async {
    if (u.scheme != 'https' || u.host.isEmpty) return false;
    if (u.hasPort && u.port != 443) return false;
    final literal = InternetAddress.tryParse(u.host);
    if (literal != null) return !isBlockedAddress(literal);
    if (!u.host.contains('.') || u.host.endsWith('.local')) return false;
    final addresses = await _resolve(u.host);
    return addresses.isNotEmpty && !addresses.any(isBlockedAddress);
  }

  /// Connects to the address that was checked, not to a second answer from
  /// DNS: the host is resolved once here, every address must be public, and
  /// the TLS handshake still names the host (SNI and the certificate check).
  /// Without this a name that answers a public address to the check and a LAN
  /// address to the connection (DNS rebinding) would reach the phone's own
  /// network.
  Future<ConnectionTask<Socket>> _connectVetted(Uri uri) async {
    final addresses = await _resolve(uri.host);
    if (addresses.isEmpty || addresses.any(isBlockedAddress)) {
      throw const SocketException('not a public address');
    }
    final port = uri.hasPort ? uri.port : 443;
    final raw = await Socket.connect(
      addresses.first,
      port,
      timeout: const Duration(seconds: 4),
    );
    return ConnectionTask.fromSocket(
      SecureSocket.secure(raw, host: uri.host),
      raw.destroy,
    );
  }

  Future<LinkPreviewData?> _fetch(Uri original) async {
    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 4)
      ..userAgent = 'Mozilla/5.0 (compatible; OrbitLinkPreview/1.0)';
    if (_guardConnections) {
      client
        ..findProxy = ((_) => 'DIRECT')
        ..connectionFactory = (uri, _, _) => _connectVetted(uri);
    }
    try {
      var current = original;
      for (var hop = 0; hop <= maxRedirects; hop++) {
        if (!await allows(current)) return null;
        final request = await client.getUrl(current);
        request.followRedirects = false;
        request.headers
          ..set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml')
          ..set(HttpHeaders.acceptLanguageHeader, 'en');
        final response = await request.close();
        final status = response.statusCode;
        if (const {301, 302, 303, 307, 308}.contains(status)) {
          final next = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>();
          if (next == null) return null;
          current = current.resolve(next);
          continue;
        }
        final type = response.headers.contentType?.mimeType;
        if (status != 200 ||
            (type != 'text/html' && type != 'application/xhtml+xml')) {
          await response.drain<void>();
          return null;
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length >= maxBytes) break;
        }
        return previewFromHtml(
          utf8.decode(bytes, allowMalformed: true),
          original.toString(),
        );
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
