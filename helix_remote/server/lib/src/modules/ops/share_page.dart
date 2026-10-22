/// `GET /u/<~name>`: the landing page for a share link
/// `https://<host>/u/<~name>`, the one link a Helix user hands to somebody
/// who is not in their phone book.
///
/// Android opens these straight in the app once it has verified the host
/// against `/.well-known/assetlinks.json`; until then, or on a machine without
/// the app, the link lands here and the button opens it through the `helix://`
/// scheme.
///
/// The page is one static document. It never looks the name up: whether a
/// `~name` exists is answered only to a signed-in account through
/// `GET /v1/people/by-name/{name}`, which honours "Find me by ~name" and
/// blocking. A page that answered would be a way to list every name on the
/// server without an account. The name comes from `location.pathname`, which
/// the browser already has.
const sharePageHtml = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Message on Helix</title>
<style>
  body { margin: 0; font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
         background: #f8fafc; color: #0f172a; display: flex; min-height: 100vh;
         align-items: center; justify-content: center; }
  main { max-width: 420px; margin: 24px; padding: 32px; background: #fff;
         border: 1px solid #e2e8f0; border-radius: 24px; text-align: center; }
  h1 { font-size: 22px; margin: 0 0 8px; }
  p { color: #475569; line-height: 1.5; margin: 0 0 20px; }
  a.button { display: block; background: #2563eb; color: #fff; text-decoration: none;
             padding: 14px; border-radius: 12px; font-weight: 600; }
  code { display: block; word-break: break-all; background: #f1f5f9; padding: 12px;
         border-radius: 12px; font-size: 13px; }
</style>
</head>
<body>
<main>
  <h1 id="lead">Open this link in Helix</h1>
  <p id="hint">It is a Helix code for somebody you want to message.</p>
  <a class="button" id="open" href="#">Open in Helix</a>
  <p>No Helix app yet? Install it, then open this link again.</p>
  <code id="name"></code>
</main>
<script>
  // The last path segment is the ~name; a leading "~" is the way it is shown,
  // not part of it. Names are 3-32 characters, a letter first.
  var parts = location.pathname.split('/').filter(function (p) { return p; });
  var raw = decodeURIComponent(parts[parts.length - 1] || '')
      .replace(/^~/, '').toLowerCase();
  var valid = /^[a-z][a-z0-9_.]{2,31}$/.test(raw);
  var open = document.getElementById('open');
  if (!valid) {
    document.getElementById('lead').textContent = 'This link is incomplete.';
    document.getElementById('hint').textContent =
        'Ask for the link again, from the Helix app.';
    open.style.display = 'none';
    document.getElementById('name').style.display = 'none';
  } else {
    document.getElementById('lead').textContent = 'Message ~' + raw + ' on Helix';
    document.getElementById('name').textContent = '~' + raw;
    var path = 'u/' + encodeURIComponent(raw);
    open.href = /Android/i.test(navigator.userAgent)
        ? 'intent://' + path + '#Intent;scheme=helix;package=com.helix.remote;end'
        : 'helix://' + path;
  }
</script>
</body>
</html>
''';
