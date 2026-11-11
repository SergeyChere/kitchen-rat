#!/usr/bin/env python3
"""Procedural textures for Kitchen Rat.

Generates the named materials from the demo-polish plan (point 2: wood must
look like wood, sofa like sofa) as 256x256 PNGs into godot/assets/textures/,
next to the 8 existing textures (floor_*/wall_*). No external assets, so no
licence questions — same approach as tools/make_audio.py.

Usage (from repo root):
    python3 tools/make_textures.py            # writes 9 PNGs
    python3 tools/make_textures.py --size 512 # larger tiles
    python3 tools/make_textures.py --out godot/assets/textures

In level_builder.gd, LevelBuilder.mat_named("wood", colour) uses the
generated texture when it exists and falls back to the flat colour until
the script has been run; pass a tiling so the grain scale stays constant
across furniture of different sizes.

Seeds are fixed, so re-running reproduces identical files.
"""
import argparse
import math
import random
from pathlib import Path

from PIL import Image

SIZE_DEFAULT = 256


# --- tileable value noise (wraps at the edges, so textures tile cleanly) ---
class Noise:
    def __init__(self, seed, period=8):
        self.rng = random.Random(seed)
        self.period = period
        self.grid = [[self.rng.random()
                      for _ in range(period + 1)] for _ in range(period + 1)]
        for y in range(period + 1):
            self.grid[y][period] = self.grid[y][0]
        for x in range(period + 1):
            self.grid[period][x] = self.grid[0][x]

    @staticmethod
    def _smooth(t):
        return t * t * (3 - 2 * t)

    def at(self, x, y):
        p = self.period
        xi, yi = int(x) % p, int(y) % p
        xf, yf = x - int(x), y - int(y)
        xf, yf = self._smooth(xf), self._smooth(yf)
        x0, y0 = xi, yi
        x1, y1 = (xi + 1) % p, (yi + 1) % p
        top = self.grid[y0][x0] * (1 - xf) + self.grid[y0][x1] * xf
        bot = self.grid[y1][x0] * (1 - xf) + self.grid[y1][x1] * xf
        return top * (1 - yf) + bot * yf

    def fbm(self, x, y, octaves=4):
        total, amp, freq, norm = 0.0, 1.0, 1.0, 0.0
        for _ in range(octaves):
            total += self.at(x * freq, y * freq) * amp
            norm += amp
            amp *= 0.5
            freq *= 2
        return total / norm


def clamp(v):
    return max(0, min(255, int(v)))


def lerp(a, b, t):
    return a + (b - a) * t


def shade(base, factor):
    return tuple(clamp(c * factor) for c in base)


def make_image(size, fn):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            px[x, y] = fn(x / size, y / size)
    return img


def wrap_dist(a, b):
    """Shortest distance on a [0, 1) torus — so dots near an edge continue
    on the opposite edge and the texture tiles seamlessly."""
    d = abs(a - b)
    return min(d, 1 - d)


def wood(size, seed, base=(138, 90, 52), dark=(96, 58, 30), light=(172, 122, 76)):
    # Tileability rule used throughout this file: a Noise(period=p) sampled
    # at (u*a, v*b) tiles only when a and b are multiples of p (so the
    # coordinate at u=1 / v=1 wraps back to the value at 0). The old code
    # broke this (e.g. period 8 with u*2), which is why wood showed a seam.
    n_wob = Noise(seed, period=3)    # wobble: u*3, v*24 — multiples of 3
    n_g = Noise(seed + 1, period=2)  # grain: u*2, v*30 — multiples of 2
    n2 = Noise(seed + 2, period=4)   # fine detail: u*16, v*16

    def fn(u, v):
        # grain stretched along x: fibres run horizontally, wavy
        wobble = n_wob.fbm(u * 3, v * 24, 3) * 0.35
        # Smooth grain for the streak phase: 3 octaves, v*24 (was v*30 with
        # 4 octaves). The old top octave put ~1 lattice cell per pixel, so g
        # jumped randomly in the last pixel row and the streak phase (x6)
        # swung with it — a seam even though g itself is exactly periodic.
        # v*24 keeps the wrap step at the level of a normal row step.
        g = n_g.fbm(u * 2 + wobble, v * 24, 3)
        streak = 0.5 + 0.5 * math.sin((v * 26 + g * 6) * math.pi)
        col = tuple(lerp(dark[i], light[i], streak * 0.7 + g * 0.3)
                    for i in range(3))
        # round 4, stylised pass (the It Takes Two lesson: big readable shapes,
        # not noise): the board is four planks — per-plank tone, a dark seam and
        # a painted bevel highlight under it, nails near the plank ends. Plank
        # tone uses the ceramic cosine trick, so the wrap step matches the
        # internal steps; the seam line itself hides the boundary.
        pj = int(v * 4) % 4
        fv = v * 4 - int(v * 4)
        tone = 0.94 + 0.055 * math.cos(2 * math.pi * pj / 4 + 1.3)
        col = tuple(c * tone for c in col)
        if fv < 0.045:
            col = tuple(c * 0.5 for c in col)      # the seam shadow
        elif fv < 0.11:
            col = tuple(c * 1.13 for c in col)     # the bevel catching light
        for nu in (0.055, 0.945):
            if wrap_dist(u, nu) < 0.011 and abs(fv - 0.5) < 0.035:
                col = tuple(c * 0.42 for c in col)  # a nail
        # a knot or two: concentric rings around fixed points
        for kx, ky in ((0.3, 0.35), (0.72, 0.7)):
            dx, dy = (u - kx) * 1.6, (v - ky) * 1.6
            d = math.sqrt(dx * dx + dy * dy)
            if d < 0.12:
                ring = 0.5 + 0.5 * math.sin(d * 220)
                col = tuple(lerp(col[i], dark[i], (1 - d / 0.12) * ring * 0.8)
                            for i in range(3))
        fine = n2.at(u * 16, v * 16) * 0.08
        col = tuple(c + (fine - 0.04) * 255 * 0.4 for c in col)
        # fine pores along the grain: v*48 with period 2 (48 is a multiple of 2, so it still tiles)
        pore = n_g.at(u * 2 + wobble, v * 48) * 0.07
        return tuple(clamp(c * (0.965 + pore)) for c in col)

    return make_image(size, fn)


def fabric(size, seed, base=(96, 104, 96)):
    n = Noise(seed, period=16)
    mottle = Noise(seed + 7, period=4)  # at(u*4, v*4): 4 is a multiple of 4

    def fn(u, v):
        # round 4: a chunkier weave (20 threads, was 32) — at sofa scale the
        # fine weave just buzzed; big threads read as cloth from across a room
        tu = 0.5 + 0.5 * math.sin(u * math.pi * 2 * 20)
        tv = 0.5 + 0.5 * math.sin(v * math.pi * 2 * 20)
        weave = 0.82 + 0.18 * (tu * tv)
        fuzz = n.at(u * 32, v * 32) * 0.25  # 32 is a multiple of period 16
        # broad worn patches, so a whole sofa does not read as one flat weave
        patch = 0.93 + mottle.at(u * 4, v * 4) * 0.12
        # slub threads: occasional thicker, lighter weft lines (7 full cycles)
        slub = 1.0 + 0.05 * math.sin(v * math.pi * 2 * 7
                                     + mottle.at(u * 4, v * 4) * 6.0)
        return shade(base, weave * (0.85 + fuzz) * patch * slub)

    return make_image(size, fn)


def leather(size, seed, base=(122, 74, 52)):
    n = Noise(seed, period=6)
    n2 = Noise(seed + 5, period=24)

    def fn(u, v):
        blotch = n.fbm(u * 6, v * 6, 3)  # 6 is a multiple of period 6
        grain = n2.at(u * 24, v * 24)  # 24 is a multiple of period 24
        # pebbled cells: two crossed waves warped by the blotch noise (22 full
        # cycles across the tile, so the pattern wraps exactly)
        warp = blotch * 5.0
        peb = (math.sin(u * math.pi * 2 * 22 + warp) *
               math.sin(v * math.pi * 2 * 22 + warp * 0.7))
        f = 0.8 + blotch * 0.35 + (grain - 0.5) * 0.12 + peb * 0.045
        return shade(base, f)

    return make_image(size, fn)


def ceramic_tile(size, seed, base=(214, 210, 198), grout=(120, 116, 108)):
    # Per-tile shade must be a smooth periodic function of the tile index:
    # the old code sampled random noise per tile, so the shade step across
    # the image boundary could be twice as big as any internal step — a
    # visible seam. With cosines every adjacent step (including the wrap
    # from tile 3 back to tile 0) is the same size, and the boundary itself
    # is a grout line, exactly like every internal tile boundary.
    tiles = 4
    phase = (seed % tiles) * math.pi / 2
    glaze = Noise(seed + 3, period=4)   # at(u*4, v*4): within-tile clouding
    gnoise = Noise(seed + 8, period=8)  # at(u*8, v*8): grout is not uniform either
    rng = random.Random(seed + 13)
    speck = [(rng.random(), rng.random()) for _ in range(46)]

    def fn(u, v):
        tu, tv = u * tiles, v * tiles
        fx, fy = tu - int(tu), tv - int(tv)
        if fx < 0.06 or fy < 0.06:  # grout lines, slightly irregular
            return shade(grout, 0.88 + gnoise.at(u * 8, v * 8) * 0.24)
        ti, tj = int(tu) % tiles, int(tv) % tiles
        s = (0.92 + 0.05 * math.cos(2 * math.pi * ti / tiles + phase)
             + 0.05 * math.cos(2 * math.pi * tj / tiles + phase))
        # round 4: a pillow bevel on every tile — dark at the grout, swelling
        # to full brightness a fifth of the way in, like a hand-glazed tile
        edge = min(fx, fy, 1.0 - fx, 1.0 - fy)
        pillow = 0.9 + 0.13 * min(edge / 0.2, 1.0)
        col = shade(base, s * (0.965 + glaze.at(u * 4, v * 4) * 0.06) * pillow)
        for sx, sy in speck:  # kiln speckles, toroidal so they tile
            if wrap_dist(u, sx) < 0.003 and wrap_dist(v, sy) < 0.003:
                return shade(col, 0.82)
        return col

    return make_image(size, fn)


def metal_matte(size, seed, base=(168, 170, 174)):
    n = Noise(seed, period=2)  # brushed: u*40, v*2 — multiples of 2
    rng = random.Random(seed + 6)
    scratches = [rng.random() for _ in range(7)]

    def fn(u, v):
        # brushed vertically: long streaks, almost no horizontal variation
        streak = n.fbm(u * 40, v * 2, 3)
        f = 0.9 + streak * 0.18
        for sx in scratches:  # a few fine vertical scratches, toroidal in u
            if wrap_dist(u, sx) < 0.0016:
                f *= 0.84
        return shade(base, f)

    return make_image(size, fn)


def cardboard(size, seed, base=(178, 140, 96)):
    n = Noise(seed, period=6)  # fbm(u*6, v*6) — multiples of 6
    rng = random.Random(seed + 9)
    flecks = [(rng.random(), rng.random()) for _ in range(60)]

    def fn(u, v):
        # the fluting underneath shows through as faint horizontal bands
        flute = 1.0 + math.sin(v * math.pi * 2 * 18) * 0.028
        # broad soft stains (the +3 offset is constant, so the wrap is intact)
        stain = 0.93 + n.fbm(u * 6 + 3.0, v * 6, 2) * 0.12
        f = (0.85 + n.fbm(u * 6, v * 6, 3) * 0.3) * flute * stain
        col = shade(base, f)
        for fx, fy in flecks:
            # toroidal distance: a fleck cut by one edge continues on the other
            if wrap_dist(u, fx) < 0.004 and wrap_dist(v, fy) < 0.004:
                return (120, 92, 60)
        return col

    return make_image(size, fn)


def plastic(size, seed, base=(226, 224, 218)):
    n = Noise(seed, period=8)
    peel = Noise(seed + 2, period=32)  # at(u*32, v*32): orange-peel grain

    def fn(u, v):
        f = 0.96 + n.at(u * 8, v * 8) * 0.07
        f *= 0.985 + peel.at(u * 32, v * 32) * 0.03
        return shade(base, f)

    return make_image(size, fn)


def counter_stone(size, seed, base=(188, 186, 180)):
    n = Noise(seed, period=3)  # fbm(u*3, v*3) — multiples of 3
    n2 = Noise(seed + 3, period=16)
    rng = random.Random(seed + 4)
    speck = [(rng.random(), rng.random(), rng.random() < 0.5)
             for _ in range(900)]
    flecks = [(rng.random(), rng.random()) for _ in range(26)]

    def fn(u, v):
        vein = n.fbm(u * 3 + 2.5, v * 3, 3)
        f = 0.9 + vein * 0.18 + (n2.at(u * 16, v * 16) - 0.5) * 0.1
        col = shade(base, f)
        for sx, sy, dark in speck:
            if wrap_dist(u, sx) < 0.0025 and wrap_dist(v, sy) < 0.0025:
                # round 4: blended in, not hard pixels — painted, not scanned
                return shade(col, 0.72) if dark else tuple(
                    clamp(lerp(col[i], 235, 0.5)) for i in range(3))
        for fx, fy in flecks:  # larger quartz flecks
            if wrap_dist(u, fx) < 0.006 and wrap_dist(v, fy) < 0.006:
                return tuple(clamp(lerp(col[i], 208, 0.6)) for i in range(3))
        return col

    return make_image(size, fn)


def shaft_gradient(size):
    """Not a surface: the alpha gradient for the fake moon shaft (bright at
    the window, fading along the beam, soft at the side edges). Written as
    shaft.png next to the materials; level_builder uses it when present."""
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        v = y / size
        fade = (1.0 - v) ** 1.7
        for x in range(size):
            u = x / size
            edge = math.sin(math.pi * u) ** 0.8
            px[x, y] = (255, 255, 255, int(255 * edge * fade))
    return img


MATERIALS = {
    "wood": lambda s: wood(s, 11),
    "wood_dark": lambda s: wood(s, 23, base=(96, 60, 36),
                               dark=(62, 36, 18), light=(128, 84, 48)),
    "fabric": lambda s: fabric(s, 31),
    "leather": lambda s: leather(s, 41),
    "ceramic_tile": lambda s: ceramic_tile(s, 51),
    "metal_matte": lambda s: metal_matte(s, 61),
    "cardboard": lambda s: cardboard(s, 71),
    "plastic": lambda s: plastic(s, 81),
    "counter_stone": lambda s: counter_stone(s, 91),
}


def _edge_diff(img):
    """Mean per-channel difference between opposite edges, and the mean
    adjacent-pixel step (sampled). A texture tiles when its edge step is no
    bigger than a normal step inside it — busy textures (wood grain, weave)
    legitimately have large steps, so the comparison is relative, not an
    absolute threshold. For ceramic_tile the raw edge diff is grout-vs-shade
    by design, so the caller compares the wrap step with an internal
    tile-boundary step instead."""
    px = img.load()
    w, h = img.size

    def d(a, b):
        return sum(abs(a[i] - b[i]) for i in range(3)) / 3

    lr = sum(d(px[0, y], px[w - 1, y]) for y in range(h)) / h
    tb = sum(d(px[x, 0], px[x, h - 1]) for x in range(w)) / w
    mean_row = sum(d(px[x, y], px[x, y + 1])
                   for x in range(0, w, 4) for y in range(0, h - 1, 4)) / (
                       (w // 4) * (h // 4))
    mean_col = sum(d(px[x, y], px[x + 1, y])
                   for x in range(0, w - 1, 4) for y in range(0, h, 4)) / (
                       (w // 4) * (h // 4))
    return lr, tb, mean_row, mean_col


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=SIZE_DEFAULT)
    ap.add_argument("--out", default="godot/assets/textures")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    shaft_gradient(args.size).save(out / "shaft.png")
    print(f"wrote {out / 'shaft.png'} (alpha gradient for the moon shaft)")
    for name, fn in MATERIALS.items():
        img = fn(args.size)
        path = out / f"{name}.png"
        img.save(path)
        lr, tb, mean_row, mean_col = _edge_diff(img)
        if name == "ceramic_tile":
            # wrap step (last col -> first col of the next tile) vs an
            # internal tile-boundary step (col 63 -> 64): both shade->grout
            px = img.load()
            w, h = img.size

            def d(a, b):
                return sum(abs(a[i] - b[i]) for i in range(3)) / 3

            wrap = sum(d(px[w - 1, y], px[0, y]) for y in range(h)) / h
            inner = sum(d(px[w // 4 - 1, y], px[w // 4, y])
                        for y in range(h)) / h
            print(f"wrote {path} ({args.size}x{args.size}) "
                  f"[ceramic wrap step {wrap:.2f} vs internal {inner:.2f}]")
        else:
            ok = tb <= 2 * mean_row + 0.5 and lr <= 2 * mean_col + 0.5
            flag = "" if ok else "  <-- SEAM, investigate"
            print(f"wrote {path} ({args.size}x{args.size}) "
                  f"[tile check: L-R {lr:.2f} vs col step {mean_col:.2f}, "
                  f"T-B {tb:.2f} vs row step {mean_row:.2f}]{flag}")


if __name__ == "__main__":
    main()
