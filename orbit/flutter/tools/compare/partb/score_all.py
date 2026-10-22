"""score_all.py: prof.py's total >16 for every key in review4_scores.txt, once.

compare.sh scores one key at a time with prof.py, which also searches a
vertical shift per 16 px band - 17x the work, and hours over a whole device.
The gate is only prof.py's `total >16` line, the plain same-row count, so this
computes exactly that for every key in one process:

  python orbit/flutter/tools/compare/partb/score_all.py [--dev window-l]

Reads the prototype's shots from tools/compare/shots/reduce-motion and the
preview's from tools/compare/flutter, both overridable with --html and
--flutter. Prints every key with its Review 4 number and the delta, then the
keys that moved by more than 0.25 points - a deliberate change logged in
DEVIATIONS.md gets its number in review4_scores.txt updated, not excused here.
Standard library only, like the rest of the tool.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
COMPARE = os.path.normpath(os.path.join(HERE, os.pardir))
sys.path.insert(0, HERE)
exec(open(os.path.join(HERE, 'bbox.py')).read().split('def bbox')[0])

MARGIN = 0.25


def reference():
    out = {}
    for line in open(os.path.join(HERE, 'review4_scores.txt')):
        if line.startswith('total keys:') or line.strip() == 'DONE':
            continue
        parts = line.split()
        if len(parts) >= 4 and parts[1] == 'total':
            out[parts[0]] = float(parts[3].rstrip('%'))
    return out


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


def main():
    args = sys.argv[1:]

    def flag(name, default):
        return args[args.index(name) + 1] if name in args else default

    dev = flag('--dev', 'phone')
    html = flag('--html', os.path.join(COMPARE, 'shots', 'reduce-motion'))
    flu = flag('--flutter', os.path.join(COMPARE, 'flutter'))
    base = reference()
    over = []
    for k in sorted(base):
        a, b = f'{html}/{k}.{dev}.orbit.png', f'{flu}/{k}.{dev}.orbit.png'
        if not (os.path.exists(a) and os.path.exists(b)):
            print(f'{k:28} --       {base[k]:5.2f}%  no pair')
            over.append((999.0, k, 'no pair'))
            continue
        try:
            now = score(a, b)
        except ValueError as e:
            print(f'{k:28} --       {base[k]:5.2f}%  size {e}')
            over.append((999.0, k, f'size {e}'))
            continue
        delta = now - base[k]
        if delta > MARGIN:
            over.append((delta, k, f'{now:.2f}% vs {base[k]:.2f}%'))
        print(f'{k:28} {now:5.2f}%  {base[k]:5.2f}%  {delta:+.2f}')
    print(f'\n=== more than {MARGIN} points over Review 4 ===')
    for _, k, note in sorted(over, reverse=True):
        print(f'{k:28} {note}')
    print(f'\n{len(base)} keys, {len(over)} over the margin')


if __name__ == '__main__':
    main()
