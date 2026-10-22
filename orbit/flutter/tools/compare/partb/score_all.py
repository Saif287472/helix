"""score_all.py: prof.py's total >16 for every key of a device, once.

compare.sh scores one key at a time with prof.py, which also searches a
vertical shift per 16 px band - 17x the work, and hours over a whole device.
The gate is only prof.py's `total >16` line, the plain same-row count, so this
computes exactly that for every key in one process:

  python orbit/flutter/tools/compare/partb/score_all.py [--dev window-l] \
      [--keys auto] [--ref partb/window_scores.txt]

`--keys auto` takes every key shot on both sides of that device instead of the
reference file's list, which is what a wide-window batch needs (the phone's
241 keys are not the window's 27). A key with no reference line prints `-` and
is never reported as a drift.

Reads the prototype's shots from tools/compare/shots/reduce-motion and the
preview's from tools/compare/flutter, both overridable with --html and
--flutter. Prints every key with its reference number and the delta, then the
keys that moved by more than 0.25 points - a deliberate change logged in
DEVIATIONS.md gets its number in the reference file updated, not excused here.
Standard library only, like the rest of the tool.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
COMPARE = os.path.normpath(os.path.join(HERE, os.pardir))
sys.path.insert(0, HERE)
exec(open(os.path.join(HERE, 'bbox.py')).read().split('def bbox')[0])

MARGIN = 0.25


def fmt(x):
    return '    -' if x is None else f'{x:5.2f}%'


def reference(path):
    out = {}
    for line in open(path):
        if line.startswith('total keys:') or line.strip() == 'DONE':
            continue
        parts = line.split()
        if len(parts) >= 4 and parts[1] == 'total':
            out[parts[0]] = float(parts[3].rstrip('%'))
    return out


def shot_keys(dir_, dev):
    suffix = f'.{dev}.orbit.png'
    return {f[: -len(suffix)] for f in os.listdir(dir_) if f.endswith(suffix)}


def score(a, b):
    """The share of pixels off by more than 16 levels, as prof.py's total."""
    wa, ha, ca, ra = read(a)
    wb, hb, cb, rb = read(b)
    if (wa, ha) != (wb, hb):
        raise ValueError(f'{wa}x{ha} vs {wb}x{hb}')
    n = 0
    for y in range(ha):
        la, lb = ra[y], rb[y]
        for x in range(wa):
            oa, ob = x * ca, x * cb
            if (
                abs(la[oa] - lb[ob]) > 16
                or abs(la[oa + 1] - lb[ob + 1]) > 16
                or abs(la[oa + 2] - lb[ob + 2]) > 16
            ):
                n += 1
    return 100.0 * n / (wa * ha)


def ref_for(base, key, dev):
    """A window file keys its lines `chat.window-l`; the phone's keys are bare."""
    return base.get(f'{key}.{dev}', base.get(key))


def main():
    args = sys.argv[1:]

    def flag(name, default):
        return args[args.index(name) + 1] if name in args else default

    dev = flag('--dev', 'phone')
    html = flag('--html', os.path.join(COMPARE, 'shots', 'reduce-motion'))
    flu = flag('--flutter', os.path.join(COMPARE, 'flutter'))
    base = reference(flag('--ref', os.path.join(HERE, 'review4_scores.txt')))
    if flag('--keys', 'file') == 'auto':
        keys = sorted(shot_keys(html, dev) & shot_keys(flu, dev))
    else:
        keys = sorted(base)
    over = []
    for k in keys:
        ref = ref_for(base, k, dev)
        a, b = f'{html}/{k}.{dev}.orbit.png', f'{flu}/{k}.{dev}.orbit.png'
        if not (os.path.exists(a) and os.path.exists(b)):
            print(f'{k:28} --       {fmt(ref)}  no pair')
            over.append((999.0, k, 'no pair'))
            continue
        try:
            now = score(a, b)
        except ValueError as e:
            print(f'{k:28} --       {fmt(ref)}  size {e}')
            over.append((999.0, k, f'size {e}'))
            continue
        if ref is None:
            print(f'{k:28} {now:5.2f}%     -')
            continue
        delta = now - ref
        print(f'{k:28} {now:5.2f}%  {ref:5.2f}%  {delta:+.2f}')
        if delta > MARGIN:
            over.append((delta, k, f'{now:.2f}% vs {ref:.2f}%'))
    print(f'\n=== more than {MARGIN} points over reference ===')
    for _, k, note in sorted(over, reverse=True):
        print(f'{k:28} {note}')
    print(f'\n{len(keys)} keys, {len(over)} over the margin')


if __name__ == '__main__':
    main()
