"""Write screens.json: every screen state in the prototype's index.

The prototype must be running (python serve.py). Headless Chrome opens
?manifest, which prints the index as JSON. Each entry has its key (the part
after # in the address), group, label, screen, parameters, the screens
underneath it (base) and where it opens on a window (placement). This is the
Flutter port's checklist; tools/shoot.py --all screenshots every entry.

  python tools/manifest.py
"""
import html
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from shoot import browser  # noqa: E402


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else 'http://127.0.0.1:5317'
    m = None
    for _ in range(3):  # a fresh headless profile sometimes returns before the page runs
        with tempfile.TemporaryDirectory() as tmp:
            out = subprocess.run([browser(), '--headless=new', '--disable-gpu', f'--user-data-dir={tmp}',
                                  '--virtual-time-budget=4000', '--dump-dom', f'{base}/?manifest'],
                                 capture_output=True, text=True, encoding='utf-8', timeout=90).stdout
        m = re.search(r'<pre id="manifest">(.*?)</pre>', out, re.S)
        if m:
            break
    if not m:
        sys.exit('No manifest in the page. Is the prototype running?')
    data = json.loads(html.unescape(m.group(1)))
    path = os.path.join(ROOT, 'screens.json')
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write('\n')
    groups = {}
    for s in data['screens']:
        groups[s['group']] = groups.get(s['group'], 0) + 1
    print(f"{len(data['screens'])} screen states in {len(groups)} groups -> {path}")


if __name__ == '__main__':
    main()
