#!/usr/bin/env python3
"""Extract a pixel-art grid from a PNG without PIL.

Usage: python3 extract_grid.py <image.png> [grid_size]

Decodes the PNG (pure python), auto-detects the pixel grid size if not
given (the coarsest grid with ~zero within-cell color variance), quantizes
near-identical colors (compression noise), and prints the palette + grid.
"""
import zlib, struct, sys, collections


def decode_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos = 8
    width = height = bitdepth = colortype = None
    idat = b""
    while pos < len(data):
        length, ctype = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + length]
        if ctype == b"IHDR":
            width, height, bitdepth, colortype = struct.unpack(">IIBB", chunk[:10])
        elif ctype == b"IDAT":
            idat += chunk
        pos += 12 + length
    assert bitdepth == 8, f"bitdepth {bitdepth}"
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[colortype]
    raw = zlib.decompress(idat)
    stride = width * channels
    out = bytearray(width * height * channels)
    prev = bytearray(stride)
    p = 0
    for y in range(height):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        if f == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return width, height, channels, out


def px(out, w, ch, x, y):
    i = (y * w + x) * ch
    return out[i], out[i + 1], out[i + 2]


def cell_spread(out, w, ch, n):
    cs = w / n
    total = 0
    for gy in range(n):
        for gx in range(n):
            pts = [px(out, w, ch, int((gx + fx) * cs), int((gy + fy) * cs))
                   for fx, fy in ((0.3, 0.3), (0.7, 0.3), (0.3, 0.7), (0.7, 0.7))]
            for c in range(3):
                vals = [p[c] for p in pts]
                total += max(vals) - min(vals)
    return total / (n * n)


def main():
    path = sys.argv[1]
    w, h, ch, out = decode_png(path)
    print(f"{w}x{h} channels={ch}", file=sys.stderr)

    if len(sys.argv) > 2:
        N = int(sys.argv[2])
    else:
        candidates = [16, 20, 24, 32, 40, 48, 64]
        spreads = {n: cell_spread(out, w, ch, n) for n in candidates}
        for n, s in spreads.items():
            print(f"grid {n}: avg spread {s:.2f}", file=sys.stderr)
        N = min((n for n in candidates if spreads[n] < 2.0), default=None)
        assert N, "no clean grid found; pass grid size explicitly"
        print(f"using grid {N}", file=sys.stderr)

    cs = w / N
    grid, palette = [], {}

    def close(a, b, tol=12):
        return all(abs(x - y) <= tol for x, y in zip(a, b))

    for gy in range(N):
        row = []
        for gx in range(N):
            acc = [0, 0, 0]
            for fx, fy in ((0.3, 0.3), (0.7, 0.3), (0.3, 0.7), (0.7, 0.7)):
                p = px(out, w, ch, int((gx + fx) * cs), int((gy + fy) * cs))
                for c in range(3):
                    acc[c] += p[c]
            col = tuple(v // 4 for v in acc)
            for k in palette:
                if close(col, k):
                    col = k
                    break
            else:
                palette[col] = len(palette)
            row.append(palette[col])
        grid.append(row)

    counts = collections.Counter(i for row in grid for i in row)
    print("palette:")
    for col, idx in sorted(palette.items(), key=lambda kv: -counts[kv[1]]):
        print(f"  {idx:2d}: #{col[0]:02x}{col[1]:02x}{col[2]:02x}  count={counts[idx]}")
    print()
    sym = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    print("grid ('.' = palette idx 0, letters = idx 1+):")
    print("   " + "".join(str(x % 10) for x in range(N)))
    for y, row in enumerate(grid):
        print(f"{y:2d} " + "".join("." if i == 0 else sym[i - 1] for i in row))


if __name__ == "__main__":
    main()
