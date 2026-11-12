#!/usr/bin/env python3
"""Paint the game's surface textures in watercolour.

    python3 tools/paint_textures.py            # writes godot/assets/painted/*.png

Two kinds of picture come out, all of them tile seamlessly:

  * room pictures (floor_*, wall_*): the flat designs in godot/assets/textures/
    redrawn by a wet brush — wobbling lines, pigment pooled along every edge,
    blotchy washes, a little colour drifting from patch to patch;
  * surface patterns (wash, wood, ceramic_tile, fabric, ...): grey pictures the
    game multiplies by each model's own colour, so only their light and dark
    matter.

The game loads a file from godot/assets/painted/ before any other source
(TextureLib). Repaint any of them by hand and keep the name: yours wins.
"""
import os
import sys
import numpy as np
from PIL import Image

N = 1024
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "godot", "assets", "textures")
OUT = os.path.join(HERE, "..", "godot", "assets", "painted")


# ------------------------------------------------------------------ periodic helpers
def freq2(n=N):
    f = np.fft.fftfreq(n) * n
    return f[:, None] ** 2 + f[None, :] ** 2


def noise(seed, beta, n=N, stretch=(1.0, 1.0)):
    """Periodic noise with a 1/f^beta spectrum, zero mean, unit deviation.
    stretch = (1, k) draws it out into streaks along x, (k, 1) along y."""
    rng = np.random.default_rng(seed)
    fy = np.fft.fftfreq(n)[:, None] * n * stretch[0]
    fx = np.fft.fftfreq(n)[None, :] * n * stretch[1]
    f2 = fy ** 2 + fx ** 2
    f2[0, 0] = 1.0
    spec = (rng.normal(size=(n, n)) + 1j * rng.normal(size=(n, n))) / f2 ** (beta / 2.0)
    spec[0, 0] = 0.0
    x = np.fft.ifft2(spec).real
    return (x - x.mean()) / x.std()


def blur(a, sigma):
    """Gaussian blur that wraps around the edges."""
    if sigma <= 0:
        return a
    n = a.shape[0]
    g = np.exp(-2.0 * (np.pi * sigma / n) ** 2 * freq2(n))
    if a.ndim == 2:
        return np.fft.ifft2(np.fft.fft2(a) * g).real
    return np.stack([np.fft.ifft2(np.fft.fft2(a[..., c]) * g).real for c in range(a.shape[2])], -1)


def warp(a, dx, dy):
    """Sample a at (x + dx, y + dy), wrapping, bilinear."""
    n = a.shape[0]
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    x = (xx + dx) % n
    y = (yy + dy) % n
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    x1 = (x0 + 1) % n
    y1 = (y0 + 1) % n
    fx = (x - x0)
    fy = (y - y0)
    if a.ndim == 3:
        fx = fx[..., None]
        fy = fy[..., None]
    return (a[y0, x0] * (1 - fx) + a[y0, x1] * fx) * (1 - fy) + (a[y1, x0] * (1 - fx) + a[y1, x1] * fx) * fy


def grad_mag(a):
    gx = np.roll(a, -1, 1) - np.roll(a, 1, 1)
    gy = np.roll(a, -1, 0) - np.roll(a, 1, 0)
    return np.sqrt(gx ** 2 + gy ** 2)


# ------------------------------------------------------------------ the wash
def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def patches(seed, beta, levels, edge=0.07, rim=0.5, bend=26.0):
    """One layer of brushwork: patches where a wash was laid over the one below. `levels` is a list of
    (threshold, amount): above the threshold the paper is `amount` lighter (or darker, if negative). The
    patch outlines are bent by a second noise so they look torn, not smooth, and a thin darker line runs
    along each of them — the mark a drying puddle leaves."""
    n = noise(seed, beta)
    n = warp(n, noise(seed + 7, 2.4) * bend, noise(seed + 8, 2.4) * bend)
    out = np.zeros_like(n)
    for lvl, amt in levels:
        out += amt * sstep(lvl - edge, lvl + edge, n)
        out -= abs(amt) * rim * np.exp(-((n - lvl) ** 2) / (edge * edge * 0.35))
    return out


def wash(seed, blotch=1.0, pools=1.0, grain=1.0, streak=0.0, along_x=True):
    """A watercolour wash as a value map around 1.0: big soft clouds, two layers of overlapping brush
    patches with drying lines, small dabs, the tooth of the paper and (optionally) the drag of the brush."""
    clouds = np.tanh(noise(seed, 3.0) * 1.2)
    v = 1.0 + 0.05 * blotch * clouds
    v += blotch * patches(seed + 10, 2.5, [(-0.5, 0.05), (0.35, -0.055), (1.1, -0.04)], rim=0.45 * pools)
    v += blotch * patches(seed + 20, 2.15, [(-0.9, 0.035), (0.1, 0.03), (0.75, -0.045)], edge=0.05, rim=0.5 * pools, bend=14.0)
    v += blotch * patches(seed + 30, 1.9, [(1.25, -0.04), (-1.35, 0.04)], edge=0.05, rim=0.3 * pools, bend=8.0)
    paper = blur(noise(seed + 1, 0.9), 0.7)
    v += 0.02 * grain * paper / paper.std()
    if streak > 0:
        st = (1.0, 16.0) if along_x else (16.0, 1.0)
        v += 0.045 * streak * noise(seed + 2, 2.2, stretch=st)
    return v


def save_grey(name, v):
    v = v / v.mean() * 0.72
    img = Image.fromarray(np.clip(v * 255.0, 0, 255).astype(np.uint8), "L")
    img.save(os.path.join(OUT, name + ".png"), optimize=True)
    print("painted", name)


def save_rgb(name, rgb):
    Image.fromarray(np.clip(rgb * 255.0, 0, 255).astype(np.uint8), "RGB").save(os.path.join(OUT, name + ".png"), optimize=True)
    print("painted", name)


# ------------------------------------------------------------------ surface patterns (grey)
def paint_patterns():
    save_grey("wash", wash(101, blotch=1.25, pools=1.1))
    save_grey("leather", wash(131, blotch=1.0, pools=0.6, grain=1.6))
    save_grey("plastic", wash(141, blotch=0.7, pools=0.5, grain=0.5))
    save_grey("metal_matte", wash(151, blotch=0.7, pools=0.4, grain=0.6, streak=1.0))
    save_grey("counter_stone", wash(161, blotch=0.9, pools=1.2, grain=2.2))

    # wood: the brush follows the grain (along x), with a few darker lines wandering through it
    v = wash(111, blotch=0.8, pools=0.6, streak=1.6)
    lines = noise(112, 2.6, stretch=(1.0, 22.0))
    v -= 0.07 * np.exp(-((lines - 0.5) ** 2) / 0.004) + 0.05 * np.exp(-((lines + 0.7) ** 2) / 0.003)
    save_grey("wood", v)
    v = wash(121, blotch=0.9, pools=0.6, streak=1.8)
    lines = noise(122, 2.6, stretch=(1.0, 22.0))
    v -= 0.09 * np.exp(-((lines - 0.4) ** 2) / 0.004) + 0.06 * np.exp(-((lines + 0.6) ** 2) / 0.003)
    save_grey("wood_dark", v)

    # cardboard: faint flutes across the sheet under a dry wash
    yy = np.mgrid[0:N, 0:N][0]
    v = wash(171, blotch=0.9, pools=0.5, grain=1.5) + 0.018 * np.sin(yy * 2 * np.pi * 48 / N)
    save_grey("cardboard", v)

    # fabric: a wash with the weave showing through as soft crossed strokes
    yy, xx = np.mgrid[0:N, 0:N]
    weave = np.sin(xx * 2 * np.pi * 96 / N) * 0.5 + np.sin(yy * 2 * np.pi * 96 / N) * 0.5
    wob = noise(181, 2.4) * 5.0
    weave = warp(weave, wob, np.roll(wob, 200, 0))
    save_grey("fabric", wash(182, blotch=1.0, pools=0.7, grain=1.2) + 0.03 * weave)

    # tiles: 2 x 2, each its own shade, a soft uneven joint between them, paint pooled along the joint
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
    wobx = noise(191, 2.8) * 3.0
    woby = noise(192, 2.8) * 3.0
    u = ((xx + wobx) / (N / 2.0)) % 1.0
    w = ((yy + woby) / (N / 2.0)) % 1.0
    d = np.minimum(np.minimum(u, 1 - u), np.minimum(w, 1 - w)) * (N / 2.0)   # px to the nearest joint
    joint = np.exp(-(d / 5.0) ** 2)
    pool = np.exp(-(d / 22.0) ** 2)
    shade = np.zeros((N, N))
    tones = np.array([[0.05, -0.04], [-0.05, 0.03]])
    ix = (((xx + wobx) // (N / 2.0)) % 2).astype(int)
    iy = (((yy + woby) // (N / 2.0)) % 2).astype(int)
    shade = tones[iy, ix]
    v = wash(194, blotch=1.5, pools=1.0) + shade - 0.34 * joint - 0.07 * pool
    save_grey("ceramic_tile", blur(v, 0.6))


# ------------------------------------------------------------------ room pictures (colour)
def repaint(name, seed, wobble=3.5, soften=1.3, blotch=1.3, edge=0.16, drift=0.05, streak=0.0):
    src = Image.open(os.path.join(SRC, name + ".png")).convert("RGB").resize((N, N), Image.BICUBIC)
    a = np.asarray(src).astype(np.float64) / 255.0
    dx = noise(seed, 2.7) * wobble                 # the hand is not a ruler
    dy = noise(seed + 1, 2.7) * wobble
    a = warp(a, dx, dy)
    a = blur(a, soften)                            # wet edges
    lum = a.mean(-1)
    e = grad_mag(blur(lum, 1.0))
    e = blur(np.clip(e / max(e.max(), 1e-6) * 4.0, 0, 1), 2.2)   # where two colours meet…
    v = wash(seed + 2, blotch=blotch, pools=1.2, streak=streak)
    a = a * v[..., None] * (1.0 - edge * e[..., None])            # …the pigment pools
    # the colour itself drifts a little from patch to patch (warm here, cool there)
    warm = blur(noise(seed + 3, 3.0), 6.0)
    warm /= max(abs(warm).max(), 1e-6)
    a[..., 0] *= 1.0 + drift * warm
    a[..., 2] *= 1.0 - drift * warm
    save_rgb(name, a)


def paint_rooms():
    repaint("floor_tile", 201, blotch=1.9)
    repaint("floor_wood", 211, blotch=1.7, streak=1.6, wobble=2.5)
    repaint("floor_concrete", 221, blotch=2.4, edge=0.1)
    repaint("floor_laundry", 231, blotch=1.9)
    repaint("wall_stripes", 241, blotch=2.4, wobble=5.0, soften=2.0)
    repaint("wall_damask", 251, blotch=2.2, wobble=4.0)
    repaint("wall_panel", 261, blotch=2.2)
    repaint("wall_brick", 271, blotch=1.9, wobble=3.0)


def paint_paper():
    """The sheet itself: the tooth of cold-pressed paper, laid over the whole picture by PaperFilter (one texel
    per screen pixel), and read again much enlarged as the slow wobble of the hand."""
    global N
    keep = N
    N = 512
    tooth = blur(noise(301, 1.1, n=N), 0.8)
    tooth /= tooth.std()
    lumps = noise(302, 2.2, n=N)
    v = 0.5 + 0.14 * tooth + 0.07 * lumps
    Image.fromarray(np.clip(v * 255.0, 0, 255).astype(np.uint8), "L").save(os.path.join(OUT, "paper.png"), optimize=True)
    print("painted paper")
    N = keep


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    paint_paper()
    if "--paper" in sys.argv:
        sys.exit(0)
    paint_patterns()
    paint_rooms()
