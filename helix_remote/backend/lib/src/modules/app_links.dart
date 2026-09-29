import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Shared invite and recovery links: `https://<host>/open#HLX-…`.
///
/// Android opens them straight in the app once it has verified this host
/// against `/.well-known/assetlinks.json`, which lists the signing
/// certificates in [androidCertFingerprints] (`HELIX_ANDROID_CERT_SHA256`).
/// Until then - or on a phone without the app - the link lands on `/open`, a
/// page whose button opens the app through the `helix://` scheme.
///
/// The code is in the URL fragment, which a browser never sends, so this
/// server does not see it; the page reads it in the browser.
class AppLinksModule {
  AppLinksModule({this.androidCertFingerprints = const []});

  static const androidPackage = 'com.helix.remote';

  /// SHA-256 fingerprints (`AB:CD:…`) of the certificates the app is signed
  /// with.
  final List<String> androidCertFingerprints;

  Response assetLinks(Request request) => Response.ok(
    jsonEncode([
      if (androidCertFingerprints.isNotEmpty)
        {
          'relation': ['delegate_permission/common.handle_all_urls'],
          'target': {
            'namespace': 'android_app',
            'package_name': androidPackage,
            'sha256_cert_fingerprints': androidCertFingerprints,
          },
        },
    ]),
    headers: {'Content-Type': 'application/json'},
  );

  Response openPage(Request request) => Response.ok(
    _page,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store',
      'Referrer-Policy': 'no-referrer',
      'Content-Security-Policy':
          "default-src 'none'; style-src 'unsafe-inline'; "
          "script-src 'unsafe-inline'",
    },
  );

  static const _page = '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Open in Helix</title>
<style>
  body { margin: 0; font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
         background: #f8fafc; color: #0f172a; display: flex; min-height: 100vh;
         align-items: center; justify-content: center; }
  main { max-width: 420px; margin: 24px; padding: 32px; background: #fff;
         border: 1px solid #e2e8f0; border-radius: 24px; text-align: center; }
  h1 { font-size: 22px; margin: 0 0 8px; }
  p { color: #475569; line-height: 1.5; margin: 0 0 20px; }
  a.button { display: block; background: #2563eb; color: #fff; text-decoration: none;
             padding: 14px; border-radius: 12px; font-weight: 600; margin-bottom: 16px; }
  code { display: block; word-break: break-all; background: #f1f5f9; padding: 12px;
         border-radius: 12px; font-size: 13px; margin-bottom: 12px; }
  button { background: none; border: 1px solid #cbd5e1; border-radius: 12px;
           padding: 10px 16px; font: inherit; cursor: pointer; }
</style>
</head>
<body>
<main>
  <h1>Open in Helix</h1>
  <p id="lead">This link has a Helix server code for you.</p>
  <a class="button" id="open" href="#">Open in Helix</a>
  <p>No Helix app yet? Install it, then open this link again.</p>
  <code id="code"></code>
  <button id="copy" type="button">Copy code</button>
</main>
<script>
  var code = decodeURIComponent((location.hash || '').slice(1)).trim();
  var valid = /^HLX-(INV|REC)-[A-Za-z0-9_-]+\$/i.test(code);
  var open = document.getElementById('open');
  if (!valid) {
    document.getElementById('lead').textContent =
        'This link is incomplete. Ask for the link or code again.';
    open.style.display = 'none';
    document.getElementById('copy').style.display = 'none';
  } else {
    document.getElementById('code').textContent = code;
    var target = 'helix://open?code=' + encodeURIComponent(code);
    open.href = /Android/i.test(navigator.userAgent)
        ? 'intent://open?code=' + encodeURIComponent(code) +
          '#Intent;scheme=helix;package=com.helix.remote;end'
        : target;
    document.getElementById('copy').onclick = function () {
      navigator.clipboard && navigator.clipboard.writeText(code);
      this.textContent = 'Copied';
    };
  }
</script>
</body>
</html>
''';
}
