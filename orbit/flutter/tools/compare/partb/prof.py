"""prof.py html.png flutter.png [side.png]
Per 16px band: % of pixels off by >16 levels, and the vertical shift
(-8..8) of the flutter band that best matches the html band. Writes a
side-by-side PNG when asked."""
import struct
import sys
import zlib

src = open(__file__.replace('prof.py', 'bbox.py')).read().split('def bbox')[0]
exec(src)


def write_png(path, w, h, rows):
    raw = b''.join(b'\x00' + bytes(r) for r in rows)

    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))


a = read(sys.argv[1])
b = read(sys.argv[2])
w, h, ca, ra = a
_, _, cb, rb = b


def px(rows, ch, x, y):
    o = x * ch
    return rows[y][o], rows[y][o + 1], rows[y][o + 2]


def bad(y1, y2, x0=0, x1=None):
    x1 = x1 or w
    if not (0 <= y2 < h):
        return x1 - x0
    n = 0
    la, lb = ra[y1], rb[y2]
    for x in range(x0, x1, 1):
        oa, ob = x * ca, x * cb
        if max(abs(la[oa] - lb[ob]), abs(la[oa + 1] - lb[ob + 1]), abs(la[oa + 2] - lb[ob + 2])) > 16:
            n += 1
    return n


total = 0
for y0 in range(0, h, 16):
    ys = range(y0, min(h, y0 + 16))
    base = sum(bad(y, y) for y in ys)
    total += base
    best = min(range(-8, 9), key=lambda s: (sum(bad(y, y + s) for y in ys), abs(s)))
    bs = sum(bad(y, y + best) for y in ys)
    pct = 100 * base / (w * len(ys))
    flag = '' if pct < 2 else ' <<' if best == 0 else f' << shift {best:+d} ({100*bs/(w*len(ys)):.1f}%)'
    print(f'{y0:4}: {pct:5.1f}%{flag}')
print(f'total >16: {100*total/(w*h):.2f}%')
if len(sys.argv) > 3:
    rows = []
    for y in range(h):
        r = bytearray()
        for (rows_, ch) in ((ra, ca), (rb, cb)):
            line = rows_[y]
            for x in range(w):
                r += line[x * ch:x * ch + 3]
            r += b'\xff\x00\xff' * 4
        rows.append(r)
    write_png(sys.argv[3], 2 * w + 8, h, rows)
