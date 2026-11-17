"""Renders docs/images/icons.png: the orb composited the way UI.lua draws it
(sky gradient tinted by hour and weather, horizon glow, stars, the sun or
moon on its arc, the weather overlay).  Pure Python, no dependencies.

    python tools/make_icons.py      # regenerate Media/*.tga first
    python tools/preview_icons.py

Rows:
  1. a clear day and night, hour by hour (04:30 ... 02:00)
  2. every weather at midday      3. every weather at dusk      4. every weather at midnight
  5. moon phases (new -> full -> new)      6. temperature badges
  7. the orb at its real in-game size (24 px), enlarged 4x
Weather columns: clear, fair, overcast, mist, fog, drizzle, rain, storm,
flurries, snow, blizzard, haze, sandstorm, ashfall, miasma.
"""
import math
import os
import re
import struct
import zlib

ROOT = os.path.join(os.path.dirname(__file__), "..")
MEDIA = os.path.join(ROOT, "Media")
OUT = os.path.join(ROOT, "docs", "images", "icons.png")
BG = (0.15, 0.13, 0.10)
S, PAD = 96, 6

WEATHER = ["clear", "fair", "overcast", "mist", "fog", "drizzle", "rain", "storm",
           "flurries", "snow", "blizzard", "haze", "sandstorm", "ashfall", "miasma"]

# ---- mirrors of Data.lua / Core.lua / UI.lua ---------------------------------
def load_sky_rows():
    src = open(os.path.join(ROOT, "Data.lua"), encoding="utf-8").read()
    block = src[src.index("ns.SkyByHour"):]
    block = block[:block.index("\n}")]
    num = r"([\d.]+)"
    trip = r"\{\s*" + r",\s*".join([num] * 3) + r"\s*\}"
    rows = []
    for m in re.finditer(r"\{\s*" + num + r",\s*" + trip + r",\s*" + trip + r",\s*" + num + r"\s*\}", block):
        v = [float(x) for x in m.groups()]
        rows.append((v[0], tuple(v[1:4]), tuple(v[4:7]), v[7]))
    return rows


ROWS = load_sky_rows()
SUNRISE, SUNSET = 5.5, 21
MOODS = {
    "clear": dict(desat=0, dark=1, glow=1),
    "grey": dict(desat=0.65, dark=0.85, glow=0.4),
    "dark": dict(desat=0.75, dark=0.60, glow=0.25),
    "dust": dict(tint=(0.85, 0.62, 0.38), amount=0.55, dark=0.95, glow=0.5),
    "ember": dict(tint=(0.60, 0.22, 0.10), amount=0.60, dark=0.80, glow=0.6),
    "sick": dict(tint=(0.48, 0.60, 0.28), amount=0.50, dark=0.85, glow=0.4),
}
MOOD_OF = {"overcast": "grey", "fog": "grey", "drizzle": "grey", "flurries": "grey", "snow": "grey", "mist": "grey",
           "rain": "dark", "storm": "dark", "blizzard": "dark",
           "sandstorm": "dust", "ashfall": "ember", "miasma": "sick"}
STARRY = {"clear", "fair", "haze"}


def lerp3(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def sky_at(hour, mood):
    a, b = ROWS[-1], ROWS[0]
    for i, row in enumerate(ROWS):
        if hour >= row[0]:
            a, b = row, ROWS[i + 1] if i + 1 < len(ROWS) else ROWS[0]
    span = (b[0] - a[0]) % 24 or 24
    t = ((hour - a[0]) % 24) / span
    t = t * t * (3 - 2 * t)
    sky, glow_col, glow = lerp3(a[1], b[1], t), lerp3(a[2], b[2], t), a[3] + (b[3] - a[3]) * t
    m = MOODS[mood]
    if m.get("desat"):
        l = sky[0] * 0.3 + sky[1] * 0.59 + sky[2] * 0.11
        sky = lerp3(sky, (l, l, l * 1.08), m["desat"])
        glow_col = lerp3(glow_col, (l + .3, l + .3, l + .3), m["desat"] * 0.7)
    if m.get("tint"):
        sky = lerp3(sky, m["tint"], m["amount"])
    sky = tuple(c * m["dark"] for c in sky)
    return sky, glow_col, glow * m["glow"]


def arc_at(hour):
    if SUNRISE <= hour < SUNSET:
        return (hour - SUNRISE) / (SUNSET - SUNRISE), True
    return ((hour - SUNSET) % 24) / (24 - (SUNSET - SUNRISE)), False


# ---- image helpers ------------------------------------------------------------
_cache = {}


def load(name):
    if name not in _cache:
        d = open(os.path.join(MEDIA, name + ".tga"), "rb").read()
        n = struct.unpack("<H", d[12:14])[0]
        px = d[18:]
        img = [[None] * n for _ in range(n)]
        for row in range(n):
            for col in range(n):
                b, g, r, a = px[(row * n + col) * 4:(row * n + col) * 4 + 4]
                img[n - 1 - row][col] = (r / 255, g / 255, b / 255, a / 255)
        _cache[name] = (img, n)
    return _cache[name]


def sample(tex, u, v):
    img, n = tex
    x, y = int(u * n), int(v * n)
    return img[y][x] if 0 <= x < n and 0 <= y < n else (0, 0, 0, 0)


def over(dst, src, tint=(1, 1, 1), alpha=1.0):
    a = src[3] * alpha
    return tuple(src[i] * tint[i] * a + dst[i] * (1 - a) for i in range(3))


def orb(hour, key, moon_index=4, S=S):
    mood = MOOD_OF.get(key, "clear")
    sky, glow_col, glow = sky_at(hour, mood)
    f, is_sun = arc_at(hour)
    lift = math.sin(math.pi * f)
    clear = key in ("clear", "fair", "haze")
    falling = key in ("drizzle", "rain", "storm", "flurries", "snow", "blizzard", "ashfall")
    raise_ = 0.2 if falling else 0
    if is_sun:
        body, size = "sun", 0.62 if falling else (0.9 + 0.1 * lift) if clear else 0.8
        low = 1 - min(1, lift * 2.2)
        body_tint = (1, 1 - 0.28 * low, 1 - 0.45 * low)
        stars = 0
    else:
        body, size = "moon_%d" % moon_index, 0.62 if falling else 0.88 if clear else 0.78
        body_tint = (1, 1, 1)
        stars = (0.45 + 0.55 * lift) if key in STARRY else 0
    bx, by = -0.15 + 0.30 * f, -0.16 + 0.24 * lift + raise_   # window units, y up
    night = not (SUNRISE <= hour < SUNSET)
    ov = None if key == "clear" else "wx_%s_%s" % (key, "night" if night else "day")
    t_sky, t_hor, t_star, t_body = load("sky"), load("horizon"), load("stars"), load(body)
    t_wx = load(ov) if ov else None
    out = []
    for py in range(S):
        row = []
        for px in range(S):
            u, v = (px + .5) / S, (py + .5) / S
            if (u - .5) ** 2 + (v - .5) ** 2 > .25:
                row.append(BG)
                continue
            c = over((0, 0, 0), sample(t_sky, u, v), sky)
            c = over(c, sample(t_hor, u, v), glow_col, glow)
            if stars:
                c = over(c, sample(t_star, u, v), alpha=stars)
            c = over(c, sample(t_body, (u - .5 - bx) / size + .5, (v - .5 + by) / size + .5), body_tint)
            if t_wx:
                c = over(c, sample(t_wx, u, v))
            row.append(c)
        out.append(row)
    return out


def small(img, scale=4):
    """Nearest-neighbour upscale: shows what a tiny in-game icon really looks like."""
    return [[px for px in row for _ in range(scale)] for row in img for _ in range(scale)]


def badge(name):
    t = load("temp_" + name)
    return [[over(BG, sample(t, (x + .5) / S, (y + .5) / S)) for x in range(S)] for y in range(S)]


def write_png(rows, path):
    h, w = len(rows), len(rows[0])
    raw = b"".join(b"\x00" + bytes(int(max(0, min(1, c)) * 255 + .5) for p in r for c in p) for r in rows)

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    hours = [4.5, 6.0, 7.5, 9.5, 12.5, 15.5, 18.0, 19.3, 20.4, 21.6, 0.0, 2.5]
    grid = [[orb(h, "clear", 2) for h in hours]]
    for h in (12.5, 19.6, 1.0):
        grid.append([orb(h, w, 2) for w in WEATHER])
    grid.append([orb(1.0, "clear", i) for i in range(8)])
    grid.append([badge(n) for n in ("freezing", "cold", "mild", "warm", "hot")])
    # in-game size (24 px), blown up 4x: the honest readability check
    grid.append([small(orb(h, k, 2, S=24)) for h, k in ((12.5, "clear"), (19.6, "clear"), (1.0, "clear"), (22.0, "clear"),
                                                         (1.0, "overcast"), (12.5, "rain"), (1.0, "snow"), (12.5, "fog"))])

    cols = max(len(line) for line in grid)
    canvas = [[BG] * (cols * (S + PAD)) for _ in range(len(grid) * (S + PAD))]
    for r, line in enumerate(grid):
        for c, img in enumerate(line):
            for y in range(S):
                canvas[r * (S + PAD) + y][c * (S + PAD):c * (S + PAD) + S] = img[y]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    write_png(canvas, OUT)
    print("wrote", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
