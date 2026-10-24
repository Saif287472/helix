"""Screenshot Helix Admin prototype screens with headless Chrome.

The prototype must be running (python serve.py). Each shot opens the bare
mode (?bare), so the image is the device at true size (a phone shot has a
grey strip on the right; see WINDOW):
  phone      412 x 866
  window-m   960 x 720
  window-l   1280 x 800

  python tools/shoot.py overview users account
  python tools/shoot.py --device window-l overview ops_reports
  python tools/shoot.py --all --device window-m       # every screen in screens.json
  python tools/shoot.py --out shots/ overview

Invites only exist on invite-mode servers, so add --query invites=1 for them.

Images are named <key>.<device>.png in --out (default: shots/).
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import quote

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SIZES = {'phone': (412, 866), 'window-m': (960, 720), 'window-l': (1280, 800)}
# Chrome will not make a window narrower than about 500 px, so a phone is shot
# in a 640 px window: the phone sits at the top left at its true 412 px.
WINDOW = {'phone': (640, 866)}
CHROME = [
    r'C:\Program Files\Google\Chrome\Application\chrome.exe',
    r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    '/usr/bin/google-chrome', '/usr/bin/chromium',
]


def browser():
    for path in CHROME:
        if os.path.exists(path):
            return path
    sys.exit('No Chrome or Edge found.')


def shoot(exe, base, key, device, out, profile_root, query='', page=''):
    w, h = WINDOW.get(device, SIZES[device])
    # page is empty for the prototype app; a direction board sets it explicitly.
    sep = '&' if '?' in page else '?'
    prefix = f'{base}/{page}' if page else f'{base}/'
    url = f'{prefix}{sep}bare&device={device}{"&" + query if query else ""}#{quote(key)}'
    path = os.path.join(out, f'{key}.{device}.png')
    for _ in range(3):  # fresh profiles and retries: headless Chrome can shoot before the page paints
        if os.path.exists(path):
            os.remove(path)  # never report an old shot as this run's
        with tempfile.TemporaryDirectory(dir=profile_root) as profile:
            subprocess.run([
                exe, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
                '--no-first-run', '--no-default-browser-check', '--disable-extensions',
                f'--user-data-dir={profile}', f'--window-size={w},{h}', '--virtual-time-budget=12000',
                f'--screenshot={path}', url,
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=90, check=False)
        if os.path.exists(path) and os.path.getsize(path) > 20000:
            return path  # smaller means Chrome painted the shell but not the page yet
    return path if os.path.exists(path) else None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('keys', nargs='*', help='screen keys (the part after # in the address)')
    ap.add_argument('--device', default='phone', choices=sorted(SIZES))
    ap.add_argument('--all', action='store_true', help='every key in screens.json')
    ap.add_argument('--out', default=os.path.join(ROOT, 'shots'))
    ap.add_argument('--base', default='http://127.0.0.1:5318')
    ap.add_argument('--query', default='', help='extra address options, like invites=1')
    ap.add_argument('--page', default='', help='page under the server root, like directions/control.html?screen=overview')
    ap.add_argument('--jobs', type=int, default=1, help='parallel browsers; more than 1 can catch pages before their styles load')
    a = ap.parse_args()
    keys = a.keys
    if a.all:
        with open(os.path.join(ROOT, 'screens.json'), encoding='utf-8') as f:
            keys = [s['key'] for s in json.load(f)['screens']]
    if not keys:
        ap.error('name at least one screen key, or use --all')
    a.out = os.path.abspath(a.out)  # Chrome resolves a relative --screenshot path somewhere else
    os.makedirs(a.out, exist_ok=True)
    exe = browser()
    with tempfile.TemporaryDirectory() as tmp:
        # The first launch of a brand-new headless profile can paint the shell
        # before the page; one discarded launch makes the timed shots reliable.
        with tempfile.TemporaryDirectory(dir=tmp) as profile:
            subprocess.run([
                exe, '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
                f'--user-data-dir={profile}', '--window-size=640,720', '--virtual-time-budget=1000',
                '--screenshot=' + os.path.join(tmp, 'warm.png'), 'about:blank',
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=90, check=False)
        def run(key):
            return key, shoot(exe, a.base, key, a.device, a.out, tmp, a.query, a.page)
        with ThreadPoolExecutor(a.jobs) as pool:
            for key, path in pool.map(run, keys):
                print(('ok    ' if path else 'FAIL  ') + (path or key))


if __name__ == '__main__':
    main()
