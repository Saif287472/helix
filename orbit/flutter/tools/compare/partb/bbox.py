"""Print the bounding box of 'ink' pixels (differing from the background) in
regions of two PNGs, to compare positions. Usage: bbox.py a.png b.png"""
import struct
import sys
import zlib


def read(path):
    data = open(path, 'rb').read()
    pos = 8
    idat = b''
    while pos < len(data):
        n, kind = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if kind == b'IHDR':
            w, h, depth, ctype = struct.unpack('>IIBB', body[:10])
        elif kind == b'IDAT':
            idat += body
        pos += 12 + n
    ch = {2: 3, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = w * ch
    rows = []
    prev = bytearray(stride)
    i = 0
    for _ in range(h):
        f = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - ch] if x >= ch else 0
            b = prev[x]
            c = prev[x - ch] if x >= ch else 0
            if f == 1:
                line[x] = (line[x] + a) & 255
            elif f == 2:
                line[x] = (line[x] + b) & 255
            elif f == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(bytes(line))
        prev = line
    return w, h, ch, rows


def bbox(img, region, dark=60):
    w, h, ch, rows = img
    x0, y0, x1, y1 = region
    bg = rows[y0][x0 * ch:x0 * ch + 3]
    xs, ys = [], []
    for y in range(y0, y1):
        for x in range(x0, x1):
            px = rows[y][x * ch:x * ch + 3]
            if sum(abs(px[k] - bg[k]) for k in range(3)) > dark:
                xs.append(x)
                ys.append(y)
    return (min(xs), min(ys), max(xs), max(ys)) if xs else None


regions = {
    'time': (20, 5, 80, 38),
    'icons': (320, 5, 400, 38),
    'logo': (130, 360, 280, 480),
    'text': (130, 482, 280, 505),
    'bar': (130, 510, 280, 530),
    'gesture': (100, 846, 312, 866),
}
a, b = read(sys.argv[1]), read(sys.argv[2])
for name, r in regions.items():
    print(f'{name:8} prototype {bbox(a, r)}  flutter {bbox(b, r)}')
