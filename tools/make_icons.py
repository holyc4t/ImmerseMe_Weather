"""Generates the weather art for ImmerseMe: Weather as 32-bit TGA files.

The look follows the stock day/night icon: a deep radial sky, a heraldic
gold sun with wavy flame rays, a pale lavender moon with a soft halo, and
soft painterly weather on top.

Pure Python 3, no dependencies.  Re-run after tweaking:

    python tools/make_icons.py
    python tools/preview_icons.py      # docs/images/icons.png

Layers (128x128, drawn in this order by UI.lua):
  sky.tga                         grey radial gradient, tinted per sky in game
  horizon.tga                     glow from the bottom edge, tinted at dawn / dusk
  stars.tga                       night sparkles (clear / fair / hazy nights)
  sun.tga, moon_0..7.tga          the sun, or the moon in its phase (0 new, 4 full)
  wx_<name>_day / _night.tga      weather drawn over the sun / moon
Addon-list icon (128x128): icon.tga, in the shared ImmerseMe frame
Temperature badges (64x64):
  temp_freezing / cold / mild / warm / hot.tga
"""
import math
import os
import struct

OUT = os.path.join(os.path.dirname(__file__), "..", "Media")
N = 128          # layer size
K = N / 64.0     # shapes below are designed on a 64 grid and scaled by K
SS = 3           # supersampling for hard-edged shapes


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else hi if v > hi else v


def smoothstep(e0, e1, x):
    t = clamp((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


class Canvas:
    def __init__(self, size=N):
        self.n = size
        self.px = [[0.0, 0.0, 0.0, 0.0] for _ in range(size * size)]

    def _blend(self, px, py, c, a):
        if a <= 0:
            return
        d = self.px[py * self.n + px]
        da = d[3]
        oa = a + da * (1 - a)
        for i in range(3):
            d[i] = (c[i] * a + d[i] * da * (1 - a)) / oa
        d[3] = oa

    def _box(self, bbox, pad=1):
        x0, y0, x1, y1 = bbox
        return (max(0, int(x0) - pad), max(0, int(y0) - pad),
                min(self.n, int(x1) + pad + 1), min(self.n, int(y1) + pad + 1))

    def fill(self, shape, color, alpha=1.0):
        """Hard-edged shape: shape = (inside(x,y) -> bool, bbox). Supersampled."""
        inside, bbox = shape
        x0, y0, x1, y1 = self._box(bbox)
        st = 1.0 / SS
        for py in range(y0, y1):
            for px in range(x0, x1):
                hits = 0
                for sy in range(SS):
                    for sx in range(SS):
                        if inside(px + (sx + .5) * st, py + (sy + .5) * st):
                            hits += 1
                if hits:
                    c = color(px + .5, py + .5) if callable(color) else color
                    self._blend(px, py, c, alpha * hits / (SS * SS))

    def glow(self, sdf, bbox, color, alpha, soft):
        """Soft shape: sdf(x,y) = signed distance (negative inside); fades over `soft` px."""
        x0, y0, x1, y1 = self._box(bbox, int(soft) + 2)
        for py in range(y0, y1):
            for px in range(x0, x1):
                d = sdf(px + .5, py + .5)
                a = 1.0 if d <= 0 else 1.0 - smoothstep(0, soft, d)
                if a > 0.003:
                    c = color(px + .5, py + .5) if callable(color) else color
                    self._blend(px, py, c, alpha * a)

    def save(self, name):
        n = self.n
        data = bytearray(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, n, n, 32, 8))
        for row in range(n - 1, -1, -1):  # bottom-left origin
            for col in range(n):
                r, g, b, a = self.px[row * n + col]
                data += bytes((b8(b), b8(g), b8(r), b8(a)))
        with open(os.path.join(OUT, name + ".tga"), "wb") as f:
            f.write(data)


def b8(v):
    return int(clamp(v) * 255 + 0.5)


# ---------------------------------------------------------------- shapes (64-grid coords, scaled by K)
def circle(cx, cy, r):
    cx, cy, r = cx * K, cy * K, r * K
    return (lambda x, y: (x - cx) ** 2 + (y - cy) ** 2 <= r * r), (cx - r, cy - r, cx + r, cy + r)


def circle_sdf(cx, cy, r):
    cx, cy, r = cx * K, cy * K, r * K
    return (lambda x, y: math.hypot(x - cx, y - cy) - r), (cx - r, cy - r, cx + r, cy + r)


def seg_dist(x, y, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = clamp(((x - ax) * dx + (y - ay) * dy) / ((dx * dx + dy * dy) or 1e-9))
    return math.hypot(x - ax - t * dx, y - ay - t * dy)


def capsule_sdf(ax, ay, bx, by, r):
    ax, ay, bx, by, r = ax * K, ay * K, bx * K, by * K, r * K
    return (lambda x, y: seg_dist(x, y, ax, ay, bx, by) - r), \
           (min(ax, bx) - r, min(ay, by) - r, max(ax, bx) + r, max(ay, by) + r)


def capsule(ax, ay, bx, by, r):
    f, bb = capsule_sdf(ax, ay, bx, by, r)
    return (lambda x, y: f(x, y) <= 0), bb


def polygon_px(pts):
    """pts already in pixel space."""
    def inside(x, y):
        c = False
        j = len(pts) - 1
        for i in range(len(pts)):
            xi, yi = pts[i]
            xj, yj = pts[j]
            if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
                c = not c
            j = i
        return c
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return inside, (min(xs), min(ys), max(xs), max(ys))


def polygon(pts):
    return polygon_px([(x * K, y * K) for x, y in pts])


def union_sdf(*shapes):
    fns = [s[0] for s in shapes]
    bb = (min(s[1][0] for s in shapes), min(s[1][1] for s in shapes),
          max(s[1][2] for s in shapes), max(s[1][3] for s in shapes))
    return (lambda x, y: min(f(x, y) for f in fns)), bb


def hard(sdf_shape, grow=0.0):
    f, bb = sdf_shape
    g = grow * K
    return (lambda x, y: f(x, y) <= g), (bb[0] - g, bb[1] - g, bb[2] + g, bb[3] + g)


def vgrad(top, bottom, y0, y1):
    y0, y1 = y0 * K, y1 * K
    return lambda x, y: mix(top, bottom, clamp((y - y0) / (y1 - y0)))


def rgrad(inner, outer, cx, cy, r):
    cx, cy, r = cx * K, cy * K, r * K
    return lambda x, y: mix(inner, outer, clamp(math.hypot(x - cx, y - cy) / r))


# ---------------------------------------------------------------- sky + stars
def horizon():
    """White glow rising from the bottom edge: tinted per time of day (dawn, dusk...)."""
    c = Canvas()
    for py in range(N):
        a = smoothstep(0.42, 1.0, (py + .5) / N) ** 1.3
        for px in range(N):
            c._blend(px, py, (1.0, 1.0, 1.0), a)
    c.save("horizon")


def sky():
    """Grey radial gradient: UI.lua tints it with the sky colour (vertex colour)."""
    c = Canvas()
    cx, cy = 28 * K, 26 * K           # light source a little up and left
    for py in range(N):
        for px in range(N):
            d = math.hypot(px + .5 - cx, py + .5 - cy) / (40 * K)
            v = 1.0 - 0.5 * smoothstep(0.0, 1.0, d)
            c._blend(px, py, (v, v, v), 1.0)
    c.save("sky")


STAR = (0.86, 0.86, 1.0)


def sparkle(c, x, y, size, alpha=1.0):
    """Four-point star with a soft glow, the stock icon's star shape."""
    c.glow(*circle_sdf(x, y, size * 0.3), STAR, 0.35 * alpha, size * K * 0.9)
    arm = size
    c.fill(polygon([(x - arm, y), (x - size * .18, y - size * .18), (x, y - arm), (x + size * .18, y - size * .18),
                    (x + arm, y), (x + size * .18, y + size * .18), (x, y + arm), (x - size * .18, y + size * .18)]),
           (0.95, 0.95, 1.0), alpha)


def stars():
    c = Canvas()
    # few and bold: tiny stars turn into noise at minimap size
    for x, y, s in ((15, 18, 4.2), (51, 15, 3.4), (53, 47, 4.0), (13, 45, 3.0)):
        sparkle(c, x, y, s)
    for x, y in ((32, 7), (58, 31), (31, 58)):
        c.glow(*circle_sdf(x, y, 0.8), STAR, 0.9, 1.6 * K)
    c.save("stars")


# ---------------------------------------------------------------- sun
SUN_LINE = (0.50, 0.20, 0.02)


def ray(angle, r0, r1, half_w, amp=0.0, waves=1.25, grow=0.0):
    """A tapered ray from radius r0 to r1 (64 grid). amp > 0 makes it a wavy flame."""
    ca, sa = math.cos(angle), math.sin(angle)
    steps = 18 if amp else 2
    left, right = [], []
    for i in range(steps + 1):
        t = i / steps
        r = r0 + (r1 + grow * 1.4 - r0) * t
        off = amp * math.sin(t * math.pi * 2 * waves) * (1 - t * 0.3)
        w = half_w * (1 - t) ** 0.9 + grow + (0.25 if t == 1 else 0)
        cx, cy = 32 + ca * r - sa * off, 32 + sa * r + ca * off
        left.append((cx - sa * w, cy + ca * w))
        right.append((cx + sa * w, cy - ca * w))
    return polygon(left + right[::-1])


def sun():
    sun_canvas().save("sun")


def sun_canvas():
    c = Canvas()
    c.glow(*circle_sdf(32, 32, 12), (1.0, 0.92, 0.55), 0.45, 14 * K)
    rays = []
    for i in range(8):
        a = i * math.pi / 4 - math.pi / 2
        rays.append((a, 10.5, 30.5, 4.2, 2.2))                    # long wavy flame
        rays.append((a + math.pi / 8, 10.5, 23.0, 3.4, 0.0))      # short straight ray
    for a, r0, r1, w, amp in rays:                                # outlines first
        c.fill(ray(a, r0, r1, w, amp, grow=1.3), SUN_LINE)
    ray_col = rgrad((1.0, 0.93, 0.45), (1.0, 0.58, 0.10), 32, 32, 30)
    for a, r0, r1, w, amp in rays:
        c.fill(ray(a, r0, r1, w, amp), ray_col)
    c.fill(circle(32, 32, 13.6), SUN_LINE)
    c.fill(circle(32, 32, 12.2), rgrad((1.0, 1.0, 0.80), (1.0, 0.66, 0.12), 28.5, 28.5, 15))
    c.glow(*circle_sdf(28.5, 28, 3.5), (1.0, 1.0, 0.95), 0.55, 4 * K)
    return c


# ---------------------------------------------------------------- moon
def moon(i):
    """i = 0 new .. 4 full .. 7; lit side follows the northern-hemisphere view."""
    p = i / 8.0
    k = math.cos(2 * math.pi * p)
    lit_frac = (1 - k) / 2
    R = 24 * K
    cx = cy = 32 * K
    c = Canvas()

    def lit(x, y, grow=0.0):
        u, v = (x - cx) / (R + grow), (y - cy) / (R + grow)
        if u * u + v * v > 1:
            return False
        t = k * math.sqrt(max(0.0, 1 - v * v))
        return u > t if p <= 0.5 else u < -t

    bb = (cx - R - 3, cy - R - 3, cx + R + 3, cy + R + 3)
    c.glow(*circle_sdf(32, 32, 22), (0.74, 0.74, 1.0), 0.30 + 0.30 * lit_frac, 8 * K)  # halo
    c.fill(circle(32, 32, 24), (0.30, 0.32, 0.62), 0.16)                                 # faint dark side
    c.fill(((lambda x, y: lit(x, y, 1.2 * K)), bb), (0.36, 0.34, 0.66))                    # rim line
    shade = lambda x, y: mix((0.98, 0.97, 1.0), (0.62, 0.62, 0.90),
                             clamp(((x - cx) * 0.55 + (y - cy) * 0.85) / (R * 1.6) + 0.45))
    c.fill((lit, bb), shade)
    for mx, my, mr in ((24, 25, 5.5), (38, 38, 6.5), (32, 50, 3.8), (44, 22, 3.4), (18, 40, 3.6)):
        f, mbb = circle(mx, my, mr)
        c.fill(((lambda x, y, f=f: f(x, y) and lit(x, y)), mbb), (0.55, 0.55, 0.85), 0.22)
    c.save("moon_%d" % i)


# ---------------------------------------------------------------- weather overlays
SMALL = ([(36, 46, 7), (45, 40, 9), (54, 47, 6)], (33, 45, 57, 53))
HEAVY_BACK = ([(45, 25, 7), (54, 30, 6)], (40, 28, 58, 34))
HEAVY = ([(16, 48, 7), (26, 42, 10), (38, 36, 12), (50, 42, 9), (55, 49, 5)], (11, 45, 58, 56))
PRECIP = ([(13, 32, 6), (22, 26, 9), (34, 21, 12), (46, 27, 9), (53, 33, 6)], (9, 29, 58, 39))

# (top, bottom, outline, rim light) per mood
PAL = {
    "day":        ((1.00, 1.00, 1.00), (0.78, 0.82, 0.95), (0.26, 0.32, 0.55), (1.0, 1.0, 1.0)),
    "day_grey":   ((0.90, 0.91, 0.96), (0.58, 0.61, 0.74), (0.20, 0.23, 0.38), (1.0, 1.0, 1.0)),
    "day_dark":   ((0.66, 0.68, 0.80), (0.34, 0.36, 0.48), (0.10, 0.10, 0.20), (0.85, 0.87, 0.97)),
    "night":      ((0.64, 0.66, 0.88), (0.34, 0.36, 0.58), (0.05, 0.06, 0.16), (0.88, 0.88, 1.0)),
    "night_grey": ((0.50, 0.52, 0.72), (0.26, 0.28, 0.44), (0.03, 0.04, 0.12), (0.78, 0.78, 0.98)),
    "night_dark": ((0.38, 0.39, 0.55), (0.17, 0.18, 0.30), (0.02, 0.02, 0.08), (0.62, 0.62, 0.85)),
}


def cloud_sdf(puffs, rect, dx=0.0, dy=0.0):
    x0, y0, x1, y1 = rect
    h = (y1 - y0) / 2
    shapes = [circle_sdf(cx + dx, cy + dy, r) for cx, cy, r in puffs]
    shapes.append(capsule_sdf(x0 + dx, (y0 + y1) / 2 + dy, x1 + dx, (y0 + y1) / 2 + dy, h))
    return union_sdf(*shapes)


def draw_cloud(c, puffs, rect, top, bottom, line, rim, alpha=1.0):
    shadow = cloud_sdf(puffs, rect, 1.2, 1.8)
    c.glow(shadow[0], shadow[1], (0.0, 0.0, 0.08), 0.35 * alpha, 3 * K)
    body = cloud_sdf(puffs, rect)
    c.fill(hard(body, 1.4), line, 0.9 * alpha)
    ys = [cy - r for _, cy, r in puffs]
    c.fill(hard(body), vgrad(top, bottom, min(ys), rect[3]), alpha)
    # rim light along the upper edge of each puff
    for cx, cy, r in puffs:
        outer, obb = circle(cx, cy, r - 0.6)
        inner, _ = circle(cx + 1.0, cy + 1.6, r - 1.2)
        c.fill(((lambda x, y, o=outer, i=inner: o(x, y) and not i(x, y)), obb), rim, 0.75 * alpha)


def pal(tod, mood=""):
    return PAL[tod + ("_" + mood if mood else "")]


def rain(c, rows, night, light=False):
    col = (0.62, 0.86, 1.0) if not night else (0.66, 0.80, 1.0)
    xs = [15, 24, 33, 42, 51]
    for ri, y in enumerate([44, 53][:rows]):
        for xi, x in enumerate(xs):
            if light and (xi + ri) % 2:
                continue
            x += 4 if ri % 2 else 0
            c.glow(*capsule_sdf(x, y, x - 2.4, y + 6.5, 0.9), col, 0.35, 2 * K)
            c.fill(capsule(x, y, x - 2.4, y + 6.5, 1.7), (0.04, 0.10, 0.30), 0.75)
            c.fill(capsule(x, y, x - 2.4, y + 6.5, 1.0), col)


def snowflake(c, x, y, r, alpha=1.0):
    c.glow(*circle_sdf(x, y, r * 0.5), (0.85, 0.92, 1.0), 0.35 * alpha, r * K)
    for w, col, al in ((0.95, (0.08, 0.12, 0.32), 0.8), (0.45, (1.0, 1.0, 1.0), 1.0)):
        for i in range(3):
            a = i * math.pi / 3 + math.pi / 2
            dx, dy = math.cos(a) * r, math.sin(a) * r
            c.fill(capsule(x - dx, y - dy, x + dx, y + dy, w), col, al * alpha)


def bolt(c):
    pts = [(36, 33), (26.5, 48), (33, 48), (28, 62), (43, 43.5), (36, 43.5), (41, 33)]
    c.glow(*polygon_sdf(pts), (1.0, 0.85, 0.3), 0.45, 5 * K)
    mx = sum(p[0] for p in pts) / len(pts)
    my = sum(p[1] for p in pts) / len(pts)
    big = [(mx + (x - mx) * 1.2, my + (y - my) * 1.1) for x, y in pts]
    c.fill(polygon(big), (0.35, 0.15, 0.0), 0.95)
    c.fill(polygon(pts), vgrad((1.0, 1.0, 0.75), (1.0, 0.70, 0.10), 33, 62))


def polygon_sdf(pts):
    inside, bb = polygon(pts)
    pp = [(x * K, y * K) for x, y in pts]

    def f(x, y):
        d = min(seg_dist(x, y, *pp[i], *pp[(i + 1) % len(pp)]) for i in range(len(pp)))
        return -d if inside(x, y) else d
    return f, bb


def soft_band(c, x0, x1, y, half, color, alpha):
    c.glow(*capsule_sdf(x0, y, x1, y, half * 0.5), color, alpha, half * K)


def wavy(c, x0, x1, y0, amp, period, half, color, alpha, phase=0.0, soft=1.2):
    X0, X1, Y0, A, P, H = x0 * K, x1 * K, y0 * K, amp * K, period * K, half * K

    def sdf(x, y):
        if x < X0:
            return math.hypot(X0 - x, y - (Y0 + A * math.sin((X0 + phase * K) / P * 2 * math.pi))) - H
        if x > X1:
            return math.hypot(x - X1, y - (Y0 + A * math.sin((X1 + phase * K) / P * 2 * math.pi))) - H
        return abs(y - (Y0 + A * math.sin((x + phase * K) / P * 2 * math.pi))) - H
    c.glow(sdf, (X0 - H, Y0 - A - H, X1 + H, Y0 + A + H), color, alpha, soft * K)


def overlay(name, night):
    c = Canvas()
    tod = "night" if night else "day"
    if name == "clear":
        return None                       # the sun / moon and stars say it all
    elif name == "fair":
        draw_cloud(c, *SMALL, *pal(tod))
    elif name == "overcast":
        draw_cloud(c, *HEAVY_BACK, *pal(tod, "dark"))
        draw_cloud(c, *HEAVY, *pal(tod, "grey"))
    elif name == "mist":
        col = (0.95, 0.96, 1.0) if not night else (0.72, 0.76, 0.95)
        for i, y in enumerate((36, 44, 52)):
            soft_band(c, 8 + (i % 2) * 6, 56 - ((i + 1) % 2) * 6, y, 2.6, col, 0.8)
    elif name == "fog":
        col = (0.92, 0.93, 0.98) if not night else (0.62, 0.66, 0.86)
        draw_cloud(c, *HEAVY_BACK, *pal(tod, "grey"), alpha=0.55)
        for i, y in enumerate((22, 30, 38, 46, 54)):
            soft_band(c, 6 + (i % 2) * 4, 58 - ((i + 1) % 2) * 4, y, 3.6, col, 0.88)
    elif name == "drizzle":
        draw_cloud(c, *PRECIP, *pal(tod, "grey"))
        rain(c, 1, night, light=True)
    elif name == "rain":
        draw_cloud(c, *PRECIP, *pal(tod, "dark"))
        rain(c, 2, night)
    elif name == "storm":
        draw_cloud(c, *PRECIP, *pal(tod, "dark"))
        for x, y in ((15, 45), (52, 45), (19, 54), (49, 55)):
            c.fill(capsule(x, y, x - 2.4, y + 6.5, 1.7), (0.04, 0.10, 0.30), 0.75)
            c.fill(capsule(x, y, x - 2.4, y + 6.5, 1.0), (0.62, 0.84, 1.0))
        bolt(c)
    elif name == "flurries":
        draw_cloud(c, *PRECIP, *pal(tod, "grey"))
        for x, y in ((18, 48), (34, 52), (49, 47), (26, 58)):
            snowflake(c, x, y, 3.2)
    elif name == "snow":
        draw_cloud(c, *PRECIP, *pal(tod, "grey"))
        for x, y in ((14, 46), (25, 50), (37, 46), (49, 50), (19, 58), (31, 59), (43, 58), (55, 57)):
            snowflake(c, x, y, 2.7)
    elif name == "blizzard":
        draw_cloud(c, *PRECIP, *pal(tod, "dark"))
        for y, x0, x1 in ((45, 10, 34), (52, 26, 56), (59, 14, 40)):
            soft_band(c, x0, x1, y, 1.4, (0.92, 0.96, 1.0), 0.75)
        for x, y in ((40, 44), (14, 50), (50, 48), (22, 56), (45, 57), (33, 51)):
            snowflake(c, x, y, 2.5)
    elif name == "haze":
        col = (1.0, 0.86, 0.55) if not night else (0.80, 0.68, 0.62)
        for i, y in enumerate((40, 47, 54)):
            wavy(c, 9 + i * 3, 55 - i * 3, y, 1.8, 11, 1.0, col, 0.9, i * 4)
    elif name == "sandstorm":
        sand = (0.90, 0.72, 0.42) if not night else (0.58, 0.46, 0.34)
        for i, y in enumerate((18, 27, 36, 45, 54)):
            wavy(c, 4 + (i % 2) * 6, 60 - ((i + 1) % 2) * 6, y, 1.6, 22, 1.7, sand, 0.8, i * 1.5, soft=2.2)
        for x, y in ((14, 22), (44, 31), (22, 40), (50, 49), (30, 57), (40, 15), (54, 22)):
            c.fill(circle(x, y, 1.3), (0.45, 0.30, 0.15))
    elif name == "ashfall":
        smoke = ((0.48, 0.44, 0.46), (0.24, 0.20, 0.22), (0.06, 0.03, 0.03), (0.70, 0.55, 0.45)) if not night else \
                ((0.32, 0.27, 0.30), (0.14, 0.11, 0.13), (0.02, 0.01, 0.01), (0.65, 0.35, 0.20))
        draw_cloud(c, *PRECIP, *smoke)
        for x, y, r in ((15, 46, 1.8), (28, 50, 1.5), (41, 45, 2.0), (52, 52, 1.4), (22, 58, 1.6), (36, 59, 1.9)):
            c.glow(*circle_sdf(x, y, r * 0.6), (1.0, 0.45, 0.08), 0.6, 3.5 * K)
            c.fill(circle(x, y, r), (1.0, 0.80, 0.35))
    elif name == "miasma":
        sick = ((0.74, 0.88, 0.42), (0.40, 0.55, 0.20), (0.10, 0.18, 0.04), (0.90, 1.0, 0.65)) if not night else \
               ((0.46, 0.60, 0.30), (0.22, 0.32, 0.12), (0.03, 0.07, 0.02), (0.65, 0.80, 0.45))
        c.glow(*cloud_sdf(*HEAVY), sick[0], 0.35, 4 * K)
        draw_cloud(c, *HEAVY, *sick, alpha=0.92)
        for x, y, r in ((22, 22, 3), (46, 17, 2.4), (14, 32, 2)):
            ring, rbb = circle(x, y, r)
            hole, _ = circle(x, y, r - 0.9)
            c.fill(((lambda px, py, a=ring, b=hole: a(px, py) and not b(px, py)), rbb), sick[3])
    return c


WEATHER = ["clear", "fair", "overcast", "mist", "fog", "drizzle", "rain", "storm",
           "flurries", "snow", "blizzard", "haze", "sandstorm", "ashfall", "miasma"]


# ---------------------------------------------------------------- temperature badges (64x64)
def thermometer(name, level, color):
    global K
    saved, K = K, 1.0
    c = Canvas(64)
    dark = (0.10, 0.07, 0.04)
    gold = (0.85, 0.66, 0.30)
    c.fill(capsule(32, 9, 32, 40, 9.5), dark, 0.95)
    c.fill(circle(32, 48, 13.5), dark, 0.95)
    c.fill(capsule(32, 9, 32, 40, 7.6), gold)
    c.fill(circle(32, 48, 11.6), gold)
    c.fill(capsule(32, 9, 32, 40, 5.6), (0.93, 0.95, 1.0))
    c.fill(circle(32, 48, 9.6), (0.93, 0.95, 1.0))
    top = 42 - level * 31
    c.fill(capsule(32, top, 32, 44, 3.4), color)
    c.fill(circle(32, 48, 7.6), rgrad(mix(color, (1, 1, 1), 0.45), color, 29, 45, 8))
    c.glow(*circle_sdf(29, 45, 1.8), (1, 1, 1), 0.7, 2)
    c.save("temp_" + name)
    K = saved


def badge_snowflake():
    global K
    saved, K = K, 1.0
    c = Canvas(64)
    c.glow(*circle_sdf(32, 32, 10), (0.6, 0.85, 1.0), 0.35, 14)
    for w, col, al in ((4.6, (0.05, 0.12, 0.32), 0.95), (2.4, (0.80, 0.94, 1.0), 1.0)):
        for i in range(6):
            a = i * math.pi / 3 + math.pi / 2
            ex, ey = 32 + math.cos(a) * 25, 32 + math.sin(a) * 25
            c.fill(capsule(32, 32, ex, ey, w), col, al)
            bx, by = 32 + math.cos(a) * 15, 32 + math.sin(a) * 15
            for s in (-1, 1):
                b = a + s * math.pi / 4
                c.fill(capsule(bx, by, bx + math.cos(b) * 8, by + math.sin(b) * 8, w * 0.8), col, al)
    c.save("temp_freezing")
    K = saved


# ---------------------------------------------------------------- addon-list icon (ImmerseMe suite)
# Every ImmerseMe module shares this frame: a dark carved-stone square with a
# gold bevelled edge (like Blizzard's ability icons) holding a round sky
# medallion in a gold ring (like the minimap's day/night icon). Only the
# medallion's sky colours and the emblem inside it change per module.
# Copy suite_icon() into a new module's tools/ and give it its own emblem.

def rounded_rect_sdf(x0, y0, x1, y1, r):
    X0, Y0, X1, Y1, R = x0 * K, y0 * K, x1 * K, y1 * K, r * K
    cx, cy, hx, hy = (X0 + X1) / 2, (Y0 + Y1) / 2, (X1 - X0) / 2 - R, (Y1 - Y0) / 2 - R

    def f(x, y):
        dx, dy = abs(x - cx) - hx, abs(y - cy) - hy
        return math.hypot(max(dx, 0), max(dy, 0)) + min(max(dx, dy), 0) - R
    return f, (X0, Y0, X1, Y1)


def blit(dst, src, cx, cy, size):
    """Draws canvas `src` scaled to `size` (64 grid) centred at (cx, cy), bilinear."""
    n = src.n
    x0, y0, s = (cx - size / 2) * K, (cy - size / 2) * K, size * K
    for py in range(max(0, int(y0)), min(dst.n, int(y0 + s) + 1)):
        for px in range(max(0, int(x0)), min(dst.n, int(x0 + s) + 1)):
            u, v = (px + .5 - x0) / s * n - .5, (py + .5 - y0) / s * n - .5
            iu, iv = int(math.floor(u)), int(math.floor(v))
            fu, fv = u - iu, v - iv
            acc = [0.0, 0.0, 0.0, 0.0]
            for (ox, oy, w) in ((0, 0, (1 - fu) * (1 - fv)), (1, 0, fu * (1 - fv)), (0, 1, (1 - fu) * fv), (1, 1, fu * fv)):
                qx, qy = iu + ox, iv + oy
                if 0 <= qx < n and 0 <= qy < n:
                    r, g, b, a = src.px[qy * n + qx]
                    acc[0] += r * a * w; acc[1] += g * a * w; acc[2] += b * a * w; acc[3] += a * w
            if acc[3] > 0.003:
                dst._blend(px, py, (acc[0] / acc[3], acc[1] / acc[3], acc[2] / acc[3]), acc[3])


def suite_icon(name, sky_top, sky_bottom, emblem):
    c = Canvas()
    gold_light, gold_dark = (1.0, 0.86, 0.48), (0.55, 0.35, 0.12)
    # gold bevelled square
    c.fill(hard(rounded_rect_sdf(0.5, 0.5, 63.5, 63.5, 7)), (0.10, 0.06, 0.03))
    c.fill(hard(rounded_rect_sdf(1.6, 1.6, 62.4, 62.4, 6)),
           lambda x, y: mix(gold_light, gold_dark, clamp((x + y) / (2 * N))))
    c.fill(hard(rounded_rect_sdf(4.2, 4.2, 59.8, 59.8, 4)), (0.12, 0.08, 0.04))
    # carved stone, lit from the top-left
    c.fill(hard(rounded_rect_sdf(5.2, 5.2, 58.8, 58.8, 3.4)),
           rgrad((0.30, 0.24, 0.18), (0.10, 0.07, 0.05), 20, 18, 52))
    # sky medallion in a gold ring
    c.glow(*circle_sdf(32, 33, 24), (0.0, 0.0, 0.0), 0.5, 3 * K)          # drop shadow
    c.fill(circle(32, 32, 25.5), (0.12, 0.07, 0.02))
    c.fill(circle(32, 32, 24.4), lambda x, y: mix(gold_light, gold_dark, clamp((x * 0.4 + y) / (1.4 * N))))
    c.fill(circle(32, 32, 21.6), (0.10, 0.06, 0.02))
    c.fill(circle(32, 32, 20.8), vgrad(sky_top, sky_bottom, 11, 53))
    inner = Canvas()                                                    # emblem, clipped to the medallion
    emblem(inner)
    clip = circle(32, 32, 20.8)[0]
    for i, p in enumerate(inner.px):
        if p[3] and not clip((i % N) + .5, (i // N) + .5):
            p[3] = 0.0
    blit(c, inner, 32, 32, 64)
    c.glow(*circle_sdf(26, 22, 6), (1.0, 1.0, 1.0), 0.10, 10 * K)     # glassy highlight
    c.save(name)


def weather_emblem(c):
    """The orb's gold sun, half behind a soft cloud."""
    blit(c, sun_canvas(), 28, 27, 50)
    draw_cloud(c, [(31, 46, 6), (40, 41, 8), (49, 46, 6)], (27, 45, 55, 52), *PAL["day"])


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".tga"):
            os.remove(os.path.join(OUT, f))
    suite_icon("icon", (0.16, 0.30, 0.62), (0.95, 0.55, 0.35), weather_emblem)
    sky()
    horizon()
    stars()
    sun()
    for i in range(8):
        moon(i)
    for name in WEATHER:
        for night in (False, True):
            c = overlay(name, night)
            if c:
                c.save("wx_%s_%s" % (name, "night" if night else "day"))
    badge_snowflake()
    thermometer("cold", 0.2, (0.30, 0.62, 1.0))
    thermometer("mild", 0.5, (0.40, 0.82, 0.40))
    thermometer("warm", 0.75, (1.0, 0.62, 0.15))
    thermometer("hot", 1.0, (0.92, 0.18, 0.10))
    print("wrote", len(os.listdir(OUT)), "files to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
