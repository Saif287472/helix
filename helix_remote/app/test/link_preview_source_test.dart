import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/link_preview_source.dart';

/// What a link preview may fetch, and how a page becomes a card.
void main() {
  group('the first link in a message', () {
    test('is found, exactly as written', () {
      expect(
        firstLinkIn('look at https://example.org/a?b=1#c now'),
        'https://example.org/a?b=1#c',
      );
      expect(
        firstLinkIn('HTTPS://Example.org/Path'),
        'HTTPS://Example.org/Path',
      );
      expect(
        firstLinkIn('two http://a.example/x and https://b.example/y'),
        'http://a.example/x',
      );
    });

    test('loses the punctuation that ends a sentence', () {
      expect(
        firstLinkIn('see https://example.org/page.'),
        'https://example.org/page',
      );
      expect(
        firstLinkIn('(https://example.org/page)'),
        'https://example.org/page',
      );
      expect(
        firstLinkIn('yes: https://example.org/a, and'),
        'https://example.org/a',
      );
    });

    test('is null when there is none, or it names no host', () {
      expect(firstLinkIn('no link here'), isNull);
      expect(firstLinkIn('ftp://example.org'), isNull);
      expect(firstLinkIn('https://'), isNull);
    });
  });

  group('addresses a preview must never be fetched from', () {
    bool blocked(String ip) => isBlockedAddress(InternetAddress(ip));

    test('this phone, private and link-local networks', () {
      for (final ip in [
        '127.0.0.1',
        '10.1.2.3',
        '172.16.0.1',
        '172.31.255.255',
        '192.168.1.1',
        '169.254.169.254',
        '0.0.0.0',
        '100.64.0.1',
        '224.0.0.1',
        '::1',
        '::',
        'fe80::1',
        'fc00::1',
        'fd12:3456::1',
        '::ffff:192.168.0.5',
        '::ffff:127.0.0.1',
        // Documentation, benchmarking and translation ranges.
        '192.0.0.8',
        '192.0.2.10',
        '198.18.0.1',
        '198.19.255.255',
        '198.51.100.7',
        '203.0.113.9',
        'fec0::1',
        '2001:0:4136:e378:8000:63bf:3fff:fdd2',
        '::127.0.0.1',
        '::10.0.0.1',
        '64:ff9b::7f00:1',
        '64:ff9b::c0a8:101',
        '2002:c0a8:101::1',
        '2002:7f00:1::1',
      ]) {
        expect(blocked(ip), isTrue, reason: ip);
      }
    });

    test('public ones are fine', () {
      for (final ip in [
        '8.8.8.8',
        '93.184.216.34',
        '172.15.0.1',
        '172.32.0.1',
        '100.63.0.1',
        '2606:2800:220:1:248:1893:25c8:1946',
        '::ffff:8.8.8.8',
        '64:ff9b::808:808',
        '2002:808:808::1',
        '198.20.0.1',
      ]) {
        expect(blocked(ip), isFalse, reason: ip);
      }
    });
  });

  group('the fetcher\'s own rules', () {
    HttpLinkPreviewSource source(Map<String, List<String>> dns) =>
        HttpLinkPreviewSource(
          resolve: (host) async => [
            for (final ip in dns[host] ?? const <String>[]) InternetAddress(ip),
          ],
        );

    Future<bool> allows(HttpLinkPreviewSource s, String url) =>
        s.allows(Uri.parse(url));

    test('HTTPS on the standard port, to a public host', () async {
      final s = source({
        'example.org': ['93.184.216.34'],
      });
      expect(await allows(s, 'https://example.org/a'), isTrue);
      expect(await allows(s, 'https://example.org:443/a'), isTrue);
      expect(
        await allows(s, 'http://example.org/a'),
        isFalse,
        reason: 'cleartext',
      );
      expect(
        await allows(s, 'https://example.org:8443/a'),
        isFalse,
        reason: 'port',
      );
    });

    test('never a host that is, or resolves to, a private address', () async {
      final s = source({
        'intranet.example': ['192.168.0.9'],
        'mixed.example': ['93.184.216.34', '10.0.0.1'],
        'gone.example': [],
      });
      expect(await allows(s, 'https://intranet.example/'), isFalse);
      expect(await allows(s, 'https://mixed.example/'), isFalse);
      expect(await allows(s, 'https://gone.example/'), isFalse);
      expect(await allows(s, 'https://localhost/'), isFalse);
      expect(await allows(s, 'https://printer/'), isFalse, reason: 'no dot');
      expect(await allows(s, 'https://nas.local/'), isFalse);
      expect(await allows(s, 'https://127.0.0.1/'), isFalse);
      expect(await allows(s, 'https://[::1]/'), isFalse);
      expect(await allows(s, 'https://8.8.8.8/'), isTrue);
    });

    test('a lookup that fails is no preview, not an error', () async {
      final s = HttpLinkPreviewSource(
        resolve: (host) async => throw const SocketException('no network'),
      );
      expect(await s.fetch(Uri.parse('https://example.org/')), isNull);
    });
  });

  group('a page becomes a card', () {
    test('Open Graph first', () {
      final card = previewFromHtml(
        '<html><head><title>Plain title</title>'
            '<meta property="og:title" content="The &amp; title">'
            '<meta property="og:description" content="Line one.\n   Line two.">'
            '<meta name="description" content="Not this"></head></html>',
        'https://example.org/p',
      );
      expect(card!.url, 'https://example.org/p');
      expect(card.title, 'The & title');
      expect(card.description, 'Line one. Line two.');
    });

    test('then Twitter, then the plain tags', () {
      expect(
        previewFromHtml('<meta name="twitter:title" content="Tw">', 'u')!.title,
        'Tw',
      );
      final plain = previewFromHtml(
        '<TITLE>\n  A  page\n</TITLE><meta content=\'About it\' name=\'description\'>',
        'u',
      )!;
      expect(plain.title, 'A page');
      expect(plain.description, 'About it');
    });

    test('decodes entities, and never runs a tag', () {
      final card = previewFromHtml(
        '<meta property="og:title" content="Caf&#233; &#x2603; &lt;b&gt;">',
        'u',
      )!;
      expect(card.title, 'Café ☃ <b>');
    });

    test('is bounded', () {
      final card = previewFromHtml(
        '<meta property="og:title" content="${'t' * 500}">'
            '<meta property="og:description" content="${'d' * 900}">',
        'u',
      )!;
      expect(card.title!.length, 200);
      expect(card.title, endsWith('…'));
      expect(card.description!.length, 300);
    });

    test('a page with nothing to say has no card', () {
      expect(previewFromHtml('<html><body>hello</body></html>', 'u'), isNull);
      expect(
        previewFromHtml('<meta property="og:title" content="  ">', 'u'),
        isNull,
      );
    });
  });
}
