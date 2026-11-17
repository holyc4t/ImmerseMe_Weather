"""Renders the addon-list icon at 512x512 for the CurseForge project avatar: docs/images/avatar.png.

Pure Python 3, no dependencies (takes a while):

    py tools/make_avatar.py

It reuses suite_icon() and weather_emblem() from make_icons.py, drawn on a bigger canvas, so the
avatar always matches Media/icon.tga. Nothing in Media/ is touched.
"""
import os
import struct
import sys
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_icons as m  # noqa: E402

SIZE = 512


def main():
    m.N, m.K = SIZE, SIZE / 64.0
    m.Canvas.__init__.__defaults__ = (SIZE,)
    with tempfile.TemporaryDirectory() as tmp:
        m.OUT = tmp
        m.suite_icon("avatar", (0.16, 0.30, 0.62), (0.95, 0.55, 0.35), m.weather_emblem)
        data = open(os.path.join(tmp, "avatar.tga"), "rb").read()
    w, h = struct.unpack("<HH", data[12:16])
    px = data[18:]
    rows = []
    for y in range(h):                       # TGA rows run bottom-up
        src = px[(h - 1 - y) * w * 4:(h - y) * w * 4]
        row = bytearray([0])
        for i in range(0, len(src), 4):
            b, g, r, a = src[i:i + 4]
            row += bytes((r, g, b, a))
        rows.append(bytes(row))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    out = os.path.join(HERE, "..", "docs", "images", "avatar.png")
    with open(out, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b""))
    print("wrote", os.path.abspath(out), w, "x", h)


if __name__ == "__main__":
    main()
