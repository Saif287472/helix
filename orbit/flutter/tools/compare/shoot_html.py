"""Screenshot prototype screens for the compare tool (the HTML half).

The prototype must be running (python orbit/prototype/serve.py). This tool
launches ONE headless Chrome for the whole batch, walks it over the DevTools
protocol, and asks each page when it is ready before taking the picture:

  python orbit/flutter/tools/compare/shoot_html.py group chat
  python orbit/flutter/tools/compare/shoot_html.py --device window-l --all
  python orbit/flutter/tools/compare/shoot_html.py --scroll 760 group
  python orbit/flutter/tools/compare/shoot_html.py --out shots/_sample/too-early/ --no-wait group

Why this is not prototype/tools/shoot.py: that tool starts a browser per
screen and takes whatever the page looks like after a fixed 4 s of virtual
time, which is where the blank and unstyled screenshots came from in Phase 1b
(one browser per screen is also far too slow for 236 states). Here the page
reports readiness itself - window.__orbitReady, set by prototype/js/boot.js
once the fonts are in, the first frame is painted and a ?scroll= request has
been applied - and only then is a capture taken. Readiness is polled, never
guessed with a sleep.

Images are named <key>[.scroll<n>].<device>.<theme>.png in --out, and every
run also writes manifest.json next to them: file, pixel size, byte size, how
long readiness took, whether the fonts loaded, whether the page had settled.
That is what the compare page reads. See README.md.

Standard library only: no pip packages, no image library (the PNG header is
enough to check a shot).
"""
import argparse
import base64
import importlib.util
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time
from itertools import cycle
from urllib.parse import quote

HERE = os.path.dirname(os.path.abspath(__file__))
PROTOTYPE = os.path.normpath(os.path.join(HERE, os.pardir, os.pardir, os.pardir, 'prototype'))
TOOLS = os.path.join(PROTOTYPE, 'tools')


def _prototype_shooter():
    """Load the prototype's own shoot.py for the device sizes and the list of
    browser binaries, so this tool and tools/shoot.py cannot drift apart."""
    spec = importlib.util.spec_from_file_location('orbit_prototype_shoot', os.path.join(TOOLS, 'shoot.py'))
    if spec is None or spec.loader is None:
        sys.exit(f'Not found: {TOOLS}{os.sep}shoot.py')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


SHOOT = _prototype_shooter()
SIZES = SHOOT.SIZES  # phone 412x866, window-m 960x720, window-l 1280x800
WINDOW = SHOOT.WINDOW  # a phone is shot in a 640 px window: Chrome refuses narrower
CHROME = SHOOT.CHROME

READY = 'window.__orbitReady === true'  # set by prototype/js/boot.js
CLEAR = 'try { localStorage.clear(); sessionStorage.clear(); } catch (e) {}'
ERRORS = 'window.__orbitErrors || []'
# Installed before the first navigation of every document, so a screen that
# throws says so in the manifest instead of only timing out.
COLLECT = """
window.__orbitErrors = [];
addEventListener('error', (e) => window.__orbitErrors.push(String((e.error && e.error.stack) || e.message || e.type)));
addEventListener('unhandledrejection', (e) => window.__orbitErrors.push('rejection: ' + e.reason));
"""


class CdpError(RuntimeError):
    pass


def find_chrome(explicit=''):
    """The browser binary. Chrome must be told where it is; --chrome wins."""
    if explicit:
        if not os.path.exists(explicit):
            sys.exit(f'No browser at {explicit}')
        return os.path.abspath(explicit)
    for path in CHROME:
        if os.path.exists(path):
            return path
    sys.exit('No Chrome or Edge found. Pass --chrome <path to the browser>.')


# --------------------------------------------------------------- websocket
class WebSocket:
    """Just enough of RFC 6455 to talk to Chrome: a client handshake, masked
    text frames out, unmasked frames in, pings answered. Standard library
    only, single connection, blocking reads."""

    def __init__(self, url, timeout=60.0):
        if not url.startswith('ws://'):
            raise CdpError(f'only ws:// is supported, got {url}')
        hostport, _, path = url[5:].partition('/')
        host, _, port = hostport.partition(':')
        self.buf = b''
        self.sock = socket.create_connection((host, int(port or 80)), timeout)
        self.sock.settimeout(timeout)
        self.sock.sendall((
            f'GET /{path} HTTP/1.1\r\nHost: {hostport}\r\nUpgrade: websocket\r\n'
            'Connection: Upgrade\r\n'
            f'Sec-WebSocket-Key: {base64.b64encode(os.urandom(16)).decode()}\r\n'
            'Sec-WebSocket-Version: 13\r\n\r\n'
        ).encode())
        head = b''
        while b'\r\n\r\n' not in head:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise CdpError('the browser closed the connection during the handshake')
            head += chunk
        head, self.buf = head.split(b'\r\n\r\n', 1)
        if b' 101 ' not in head.split(b'\r\n', 1)[0]:
            raise CdpError(head.split(b'\r\n', 1)[0].decode(errors='replace'))

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass

    def _read(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise CdpError('the browser closed the connection')
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def _frame(self, opcode, data):
        mask = os.urandom(4)
        head = bytearray([0x80 | opcode])
        n = len(data)
        if n < 126:
            head.append(0x80 | n)
        elif n < 65536:
            head.append(0x80 | 126)
            head += struct.pack('>H', n)
        else:
            head.append(0x80 | 127)
            head += struct.pack('>Q', n)
        # A client must mask; the mask is four bytes repeated over the payload.
        head += mask + bytes(b ^ m for b, m in zip(data, cycle(mask)))
        self.sock.sendall(bytes(head))

    def send(self, text):
        self._frame(0x1, text.encode())

    def recv(self):
        parts = []
        while True:
            b0, b1 = self._read(2)
            fin, opcode = b0 & 0x80, b0 & 0x0F
            n = b1 & 0x7F
            if n == 126:
                n = struct.unpack('>H', self._read(2))[0]
            elif n == 127:
                n = struct.unpack('>Q', self._read(8))[0]
            if b1 & 0x80:  # a server must not mask, but decode it rather than crash
                mask = self._read(4)
                data = bytes(b ^ m for b, m in zip(self._read(n), cycle(mask)))
            else:
                data = self._read(n)
            if opcode == 0x9:  # ping -> pong
                self._frame(0xA, data)
                continue
            if opcode == 0xA:  # pong
                continue
            if opcode == 0x8:
                raise CdpError('the browser closed the websocket')
            parts.append(data)
            if fin:
                return b''.join(parts).decode()


class Cdp:
    """Request/response over one websocket. Events are read and dropped; only
    the reply with the matching id is returned."""

    def __init__(self, ws, timeout=90.0):
        self.ws = ws
        self.timeout = timeout
        self.seq = 0

    def call(self, method, params=None, session=None, timeout=None):
        self.seq += 1
        message = {'id': self.seq, 'method': method, 'params': params or {}}
        if session is not None:
            message['sessionId'] = session
        self.ws.send(json.dumps(message))
        end = time.monotonic() + (timeout or self.timeout)
        while True:
            if time.monotonic() > end:
                raise TimeoutError(f'{method} did not answer in {end - time.monotonic():.0f}s')
            try:
                reply = json.loads(self.ws.recv())
            except socket.timeout:
                continue  # keep waiting until the deadline above
            if reply.get('id') != self.seq:
                continue  # an event, or a late reply to something else
            if 'error' in reply:
                raise CdpError(f"{method}: {reply['error'].get('message')}")
            return reply.get('result', {})


# ------------------------------------------------------------------- chrome
class Chrome:
    """One headless Chrome, one page target, driven over the DevTools
    protocol. Launching it per screen is what made shoot.py slow and flaky."""

    def __init__(self, exe, window, profile, reduce_motion=False):
        self.window = window
        self.user_data = profile
        self.log_path = os.path.join(profile, 'chrome.log')
        port_file = os.path.join(profile, 'DevToolsActivePort')
        if os.path.exists(port_file):
            os.remove(port_file)  # a reused profile still has the last run's port in it
        self.log = open(self.log_path, 'wb')
        args = [
            exe, '--headless=new', '--disable-gpu', '--hide-scrollbars',
            '--force-device-scale-factor=1', '--no-first-run', '--no-default-browser-check',
            '--disable-extensions', '--disable-background-timer-throttling',
            '--disable-backgrounding-occluded-windows', '--disable-renderer-backgrounding',
            '--remote-debugging-port=0', f'--user-data-dir={profile}',
            f'--window-size={window[0]},{window[1]}', 'about:blank',
        ]
        self.proc = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=self.log, stderr=subprocess.STDOUT)
        self.cdp = self._connect()
        self.target = self.cdp.call('Target.createTarget', {'url': 'about:blank'})['targetId']
        self.session = self.cdp.call('Target.attachToTarget', {'targetId': self.target, 'flatten': True})['sessionId']
        self.call('Page.enable')
        # Page errors, so a state that never becomes ready says why instead of
        # only timing out. Installed before the first navigation, so none are missed.
        self.call('Page.addScriptToEvaluateOnNewDocument', {'source': COLLECT})
        # The viewport, not the window: the same CSS pixels as tools/shoot.py's
        # --window-size, whatever the host display is.
        self.call('Emulation.setDeviceMetricsOverride', {
            'width': window[0], 'height': window[1], 'deviceScaleFactor': 1, 'mobile': False})
        if reduce_motion:
            # Opt-in only: this freezes animation and transition inside the
            # phone screen (css/pages.css), which changes what is measured.
            self.call('Emulation.setEmulatedMedia', {
                'features': [{'name': 'prefers-reduced-motion', 'value': 'reduce'}]})

    def _connect(self):
        # A --remote-debugging-port=0 launch writes the port it chose into the
        # profile; reading that file is how we find it without racing a probe.
        path = os.path.join(self.user_data, 'DevToolsActivePort')
        end = time.monotonic() + 30
        while time.monotonic() < end:
            if os.path.exists(path):
                try:
                    with open(path, encoding='utf-8') as f:
                        lines = f.read().splitlines()
                    if len(lines) >= 2 and lines[0].strip():
                        self.port = int(lines[0].strip())
                        self.ws_path = lines[1].strip()
                        return Cdp(WebSocket(f'ws://127.0.0.1:{self.port}{self.ws_path}'))
                except (OSError, ValueError, CdpError):
                    pass  # the file is there, but the socket is not up yet
            if self.proc.poll() is not None:
                sys.exit('Chrome exited before it opened a debugging port:\n' + self.tail())
            time.sleep(0.05)
        sys.exit('Chrome did not open a debugging port in 30s:\n' + self.tail())

    def tail(self, lines=15):
        try:
            with open(self.log_path, encoding='utf-8', errors='replace') as f:
                return ''.join(f.readlines()[-lines:])
        except OSError:
            return '(no chrome log)'

    def call(self, method, params=None, timeout=None):
        return self.cdp.call(method, params, session=self.session, timeout=timeout)

    def close(self):
        try:
            self.cdp.call('Browser.close', timeout=5)
        except (CdpError, OSError, TimeoutError, ValueError):
            pass  # a dead socket is fine; the terminate below is the backstop
        try:
            self.proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        self.cdp.ws.close()
        self.log.close()

    # ---- the page
    def evaluate(self, expression, timeout=10.0):
        got = self.call('Runtime.evaluate', {
            'expression': expression, 'returnByValue': True}, timeout=timeout)
        if 'exceptionDetails' in got:
            raise CdpError(expression[:40] + ': ' + str(got['exceptionDetails'])[:120])
        return got.get('result', {}).get('value')

    def where(self):
        """The document the page is really showing, without the fragment."""
        try:
            return (self.evaluate('location.href') or '').split('#')[0]
        except CdpError:
            return ''  # the context is gone while a document loads

    def goto(self, url, timeout, wait=True):
        """Go to one screen state and wait until the page says it is ready.

        Page.navigate is fire and forget, and one issued while the last is
        still in flight can be dropped; the page then sits on the old document
        and the readiness flag never appears. So every address is checked
        afterwards and a lost navigation is simply asked for again.
        about:blank goes first, because a navigation that only changes the
        fragment is same-document: the previous screen would still be there
        with its flag already set, and the shot would be of the wrong screen."""
        end = time.monotonic() + timeout
        while True:
            for target in ('about:blank', url):
                wanted = target.split('#')[0]  # endswith, so a redirect still counts
                if not self.where().endswith(wanted):
                    self.call('Page.navigate', {'url': target}, timeout=60)
                    while not self.where().endswith(wanted) and time.monotonic() < end:
                        time.sleep(0.05)
            if self.where().endswith(url.split('#')[0]):
                break
            if time.monotonic() > end:
                raise TimeoutError(f'the page never reached {url} in {timeout:.0f}s{self.errors()}')
            time.sleep(0.05)
        if not wait:
            return
        while True:
            try:
                if self.evaluate(READY, timeout=8.0) is True:
                    return
            except CdpError:
                pass  # the old document's context is gone while the new one loads
            if time.monotonic() > end:
                raise TimeoutError(f'not ready after {timeout:.0f}s: {url}{self.state_line()}{self.errors()}')
            time.sleep(0.04)

    def state_line(self):
        """What the page looked like when it would not say it was ready: still
        loading, no App yet, nothing drawn, or not answering at all."""
        try:
            got = self.evaluate(
                '({ready: document.readyState, app: typeof App, els: document.querySelectorAll("#phoneScreen *").length})')
        except CdpError:
            return ' (the page is not answering at all)'
        if not got:
            return ' (no document)'
        return f' [{got.get("ready")}, App {got.get("app")}, {got.get("els")} nodes]'

    def errors(self):
        """Page errors collected since the document loaded, on one short line.
        A blank or half-drawn screen is usually a script that threw."""
        try:
            found = self.evaluate(ERRORS, timeout=5.0) or []
        except CdpError:
            return ''
        if not found:
            return ''
        first = ' '.join(str(found[0]).split())[:200]
        return f' ({len(found)} page error(s): {first})'

    def clear_storage(self):
        """Forget the device, the theme and any tweaks a previous visit saved
        in this profile. They are read when the page boots, so this has to run
        before the first navigation of the batch, not after a state is drawn."""
        try:
            self.evaluate(CLEAR)
        except CdpError:
            pass

    def still(self, clip, cap=1.5, gap=0.12):
        """True once two small captures in a row are byte-identical, so the
        page has stopped moving. Bounded: a blinking cursor or a pulsing dot
        never settles, and those states are shot anyway."""
        end = time.monotonic() + cap
        previous, stable = None, 0
        while True:
            now = self.call('Page.captureScreenshot', {
                'format': 'png', 'clip': {**clip, 'scale': 0.06}}, timeout=30).get('data', '')
            stable = stable + 1 if now == previous else 0
            previous = now
            if stable >= 1 or time.monotonic() > end:
                return stable >= 1
            time.sleep(gap)

    def capture(self, clip):
        got = self.call('Page.captureScreenshot', {
            'format': 'png', 'captureBeyondViewport': False, 'clip': clip}, timeout=90)
        data = got.get('data')
        if not data:
            raise CdpError('Chrome returned no image')
        return base64.b64decode(data)


def png_size(data):
    """Width and height out of the PNG header. Enough to prove a shot is a
    real image at the size asked for; no image library is involved."""
    if len(data) < 24 or data[:8] != b'\x89PNG\r\n\x1a\n':
        return None
    return struct.unpack('>II', data[16:24])


# ------------------------------------------------------------------- shooting
def url_for(base, key, device, theme, scroll, query=''):
    extra = [p for p in (query, f'scroll={scroll}' if scroll else '') if p]
    search = f'?bare&device={device}&theme={theme}' + (f'&{"&".join(extra)}' if extra else '')
    return f'{base.rstrip("/")}/{search}#{quote(key)}'


def screen_of(key):
    """The screen id a key opens (screens.json), or None when unknown."""
    try:
        with open(os.path.join(PROTOTYPE, 'screens.json'), encoding='utf-8') as f:
            screens = json.load(f)['screens']
    except (OSError, KeyError, ValueError):
        return None
    return next((s.get('screen') for s in screens if s.get('key') == key), None)


# The id of the page on top of the stack: the screen the shot shows.
OPEN_SCREEN = "(() => { const p = [...document.querySelectorAll('#stack .page')].pop(); return p ? p.dataset.screen : null; })()"


def shoot(chrome, base, key, a):
    """One screen state: navigate, wait for readiness, let the page settle,
    capture. Retries once, because the documented failure mode is a shot taken
    before everything had loaded."""
    dw, dh = SIZES[a.device]
    ww, wh = WINDOW.get(a.device, SIZES[a.device])
    clip = {'x': 0, 'y': 0, 'scale': 1,
            'width': ww if a.full_window else dw, 'height': wh if a.full_window else dh}
    url = url_for(base, key, a.device, a.theme, a.scroll, a.query)
    name = f'{key}{f".scroll{a.scroll}" if a.scroll else ""}.{a.device}.{a.theme}.png'
    path = os.path.join(a.out, name)
    entry = {'key': key, 'file': name, 'url': url, 'ok': False, 'reason': '', 'tries': 0,
             'settled': None, 'recovered': []}
    started = time.monotonic()
    data = b''
    for attempt in range(1, a.tries + 1):
        entry['tries'] = attempt
        entry['reason'] = ''  # only the last attempt's problem belongs to the state
        data = b''
        state = time.monotonic()
        try:
            chrome.goto(url, a.timeout, wait=not a.no_wait)
            ready_ms = round((time.monotonic() - state) * 1000)
            info = chrome.evaluate('window.__orbitReadyInfo || null') or {}
            # What the gate actually saw, recorded in the manifest: false only
            # under --no-wait, which is how the failure mode is demonstrated.
            entry['readyFlag'] = chrome.evaluate(READY) is True
            entry['fonts'] = info.get('fonts', 'unknown')  # prototype/js/boot.js
            entry['frames'] = info.get('frames', 'unknown')
            # How much is actually on the device: a bare page has about thirty
            # of these, a drawn screen hundreds. A diagnostic, not a gate.
            entry['drawn'] = chrome.evaluate("document.querySelectorAll('#phoneScreen *').length") or 0
            if info.get('scroll') == 'unreached':
                entry['scroll'] = 'unreached'  # the page never scrolled to ?scroll=
            elif a.scroll:
                entry['scroll'] = 'applied'
            if a.no_wait:
                entry['settled'] = False
            else:
                entry['settled'] = chrome.still(clip, cap=a.settle_cap)
                time.sleep(a.settle)  # a last beat for transitions at their end
            data = chrome.capture(clip)
            size = png_size(data)
            entry['width'], entry['height'] = size or (0, 0)
            entry['bytes'] = len(data)
            entry['readyMs'] = ready_ms
            # A dropped navigation leaves the previous screen up, which still
            # photographs and scores; so the open screen must be the key's.
            want, shown = screen_of(key), chrome.evaluate(OPEN_SCREEN)
            if want and shown != want:
                entry['reason'] = f'wrong screen: {shown} is open, not {want}'
            elif size != (clip['width'], clip['height']):
                entry['reason'] = f'wrong size {size}, wanted {clip["width"]}x{clip["height"]}'
            elif len(data) < a.blank_bytes:
                entry['reason'] = f'blank? only {len(data)} bytes'
            else:
                entry['ok'] = True
        except (CdpError, TimeoutError, OSError) as e:
            entry['reason'] = f'{type(e).__name__}: {e}'
            entry['width'], entry['height'], entry['bytes'] = 0, 0, 0
        if entry['ok']:
            break
        if attempt < a.tries:
            entry['recovered'].append(entry['reason'])
    entry['ms'] = round((time.monotonic() - started) * 1000)
    if data:
        with open(path, 'wb') as f:
            f.write(data)
        entry['path'] = path
    return entry


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('keys', nargs='*', help='screen keys (the part after # in the address)')
    ap.add_argument('--all', action='store_true', help='every key in screens.json')
    ap.add_argument('--device', default='phone', choices=sorted(SIZES))
    ap.add_argument('--theme', default='orbit')
    ap.add_argument('--scroll', type=int, default=0, help='scroll the open page to this many px')
    ap.add_argument('--query', default='', help='extra address options, like profile=orbit')
    ap.add_argument('--out', default=os.path.join(HERE, 'shots'), help='where the PNGs go')
    ap.add_argument('--base', default='http://127.0.0.1:5317', help='the running prototype')
    ap.add_argument('--chrome', default='', help='the browser binary, if not the default Chrome')
    ap.add_argument('--full-window', action='store_true',
                    help='shoot the whole window, not just the device (a phone shot is 640 wide, '
                         'with the device at the left 412, like tools/shoot.py)')
    ap.add_argument('--reduce-motion', action='store_true',
                    help='emulate prefers-reduced-motion: reduce. Freezes animation and transition '
                         'inside the phone screen, which makes animated states repeatable but is a '
                         'change to what is measured. Off by default.')
    ap.add_argument('--profile', default='', help='reuse this Chrome profile directory (warms the font cache)')
    ap.add_argument('--keep-profile', action='store_true', help='do not delete the temporary profile')
    ap.add_argument('--no-settle', action='store_true', help='do not wait for the page to stop moving')
    ap.add_argument('--no-wait', action='store_true',
                    help='capture as soon as the page starts loading. Only to show the failure mode this '
                         'tool exists to avoid; the shots are blank or unstyled.')
    ap.add_argument('--no-manifest', action='store_true', help='do not write manifest.json')
    ap.add_argument('--timeout', type=float, default=30.0, help='seconds to wait for window.__orbitReady')
    ap.add_argument('--tries', type=int, default=2, help='attempts per state')
    ap.add_argument('--settle', type=float, default=0.12, help='seconds after the page has stopped moving')
    ap.add_argument('--settle-cap', type=float, default=1.5, help='seconds to keep waiting for that')
    ap.add_argument('--blank-bytes', type=int, default=6000,
                    help='a smaller PNG than this counts as blank and is retaken (the smallest real '
                         'screen of the 236 is 10.2 kB)')
    a = ap.parse_args()
    keys = list(a.keys)
    if a.all:
        with open(os.path.join(PROTOTYPE, 'screens.json'), encoding='utf-8') as f:
            keys = [s['key'] for s in json.load(f)['screens']]
    if not keys:
        ap.error('name at least one screen key, or use --all')
    a.out = os.path.abspath(a.out)  # Chrome would resolve a relative path elsewhere
    os.makedirs(a.out, exist_ok=True)
    exe = find_chrome(a.chrome)
    window = WINDOW.get(a.device, SIZES[a.device])
    shots, failed = [], 0
    tmp = a.profile or tempfile.mkdtemp(prefix='orbit-compare-')
    chrome = None
    started = time.monotonic()
    try:
        chrome = Chrome(exe, window, tmp, reduce_motion=a.reduce_motion)
        if a.profile:
            # A reused profile may hold a device, a theme and tweaks from a
            # previous visit, and they change what the page draws.
            chrome.goto(f'{a.base.rstrip("/")}/', a.timeout, wait=False)
            chrome.clear_storage()
        for n, key in enumerate(keys, 1):
            entry = shoot(chrome, a.base, key, a)
            shots.append(entry)
            failed += 0 if entry['ok'] else 1
            bits = [f"{entry.get('width')}x{entry.get('height')}", f"{entry.get('bytes', 0) / 1024:.0f}kB"]
            if entry.get('settled') is not None:
                bits.append('settled' if entry['settled'] else 'unsettled')
            if entry.get('recovered'):
                bits.append(f"retried after: {entry['recovered'][0][:60]}")
            if entry['reason']:
                bits.append(entry['reason'])
            print(f"[{n:>3}/{len(keys)}] {'ok  ' if entry['ok'] else 'FAIL'} {entry['key']:<26} {' '.join(bits)}", flush=True)
        print(f"{len(keys) - failed}/{len(keys)} shots in {time.monotonic() - started:.0f}s -> {a.out}")
    finally:
        if chrome is not None:
            chrome.close()
        if not a.profile:
            if a.keep_profile:
                print(f'profile kept: {tmp}')
            else:
                shutil.rmtree(tmp, ignore_errors=True)  # our own Chrome only
    if not a.no_manifest:
        manifest = {
            'tool': 'shoot_html', 'generated': time.strftime('%Y-%m-%dT%H:%M:%S'),
            'browser': exe, 'base': a.base.rstrip('/'), 'device': a.device, 'theme': a.theme,
            'deviceSize': list(SIZES[a.device]), 'window': list(window),
            'scroll': a.scroll, 'query': a.query, 'fullWindow': a.full_window,
            'reduceMotion': a.reduce_motion, 'waitedForReady': not a.no_wait, 'shots': shots,
        }
        path = os.path.join(a.out, 'manifest.json')
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(manifest, f, indent=2)
        print(f'manifest: {path}')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
