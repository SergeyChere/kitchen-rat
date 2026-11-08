"""Seamless grayscale detail textures for furniture and props (multiplied with the material colour in Godot,
mapped triplanar so the models need no UVs). Run: python3 tools/textures/make_detail.py godot/assets/textures"""
import sys, numpy as np
from PIL import Image

N = 512
rng = np.random.default_rng(7)
y, x = np.mgrid[0:N, 0:N] / N  # 0..1, tiles at 1


def pnoise(freq, octaves=4, seed=0):
    """Tileable value noise from a periodic random lattice."""
    r = np.random.default_rng(seed)
    out = np.zeros((N, N))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        f = freq * 2 ** o
        g = r.random((f, f))
        gx, gy = x * f, y * f
        x0, y0 = np.floor(gx).astype(int), np.floor(gy).astype(int)
        tx, ty = gx - x0, gy - y0
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        x1, y1 = (x0 + 1) % f, (y0 + 1) % f
        x0, y0 = x0 % f, y0 % f
        a = g[y0, x0] * (1 - tx) + g[y0, x1] * tx
        b = g[y1, x0] * (1 - tx) + g[y1, x1] * tx
        out += (a * (1 - ty) + b * ty) * amp
        tot += amp
        amp *= 0.5
    return out / tot


def save(name, v, lo, hi):
    v = (v - v.min()) / (v.max() - v.min() + 1e-9)
    v = lo + (hi - lo) * v
    Image.fromarray((np.clip(v, 0, 1) * 255).astype(np.uint8), "L").convert("RGB").save(f"{sys.argv[1]}/detail_{name}.png")
    print(name, round(float(v.mean()), 3))


# wood: long grain along x, wobbling, with darker late-wood lines and a few knots-free streaks
warp = pnoise(4, 3, 1) * 0.08
rings = np.sin((y + warp + pnoise(2, 2, 2) * 0.05) * 2 * np.pi * 11)
grain = 0.7 + 0.12 * rings + 0.18 * pnoise(64, 2, 3)
grain = np.where(rings > 0.8, grain - 0.45, grain)  # dark late-wood lines
save("wood", grain, 0.74, 1.0)

# paint: an almost flat surface with a faint orange-peel texture
save("paint", pnoise(32, 4, 4), 0.92, 1.0)

# stone: fine speckles
sp = rng.random((N // 2, N // 2))
sp = np.kron(sp, np.ones((2, 2)))  # 2-px specks
st = pnoise(16, 4, 5) * 0.6 + (sp > 0.97) * -0.7 + (sp < 0.02) * 0.4
save("stone", st, 0.82, 1.0)

# fabric: a plain weave
wx = 0.5 + 0.5 * np.sin(x * 2 * np.pi * 96)
wy = 0.5 + 0.5 * np.sin(y * 2 * np.pi * 96)
check = ((np.floor(x * 96) + np.floor(y * 96)) % 2)
fab = np.where(check > 0, wx, wy) * 0.6 + pnoise(16, 3, 6) * 0.4
save("fabric", fab, 0.8, 1.0)

# brushed metal: fine streaks along x
m = np.zeros((N, N))
for i, f in enumerate((128, 256)):
    r = np.random.default_rng(8 + i).random(f)
    m += np.repeat(np.interp(np.arange(N) * f / N, np.arange(f), r)[:, None], N, axis=1)
m = m * 0.7 + pnoise(8, 2, 9) * 0.3
save("metal", m, 0.86, 1.0)

# cardboard: soft fibres and faint corrugation ridges
cb = 0.6 * pnoise(48, 4, 10) + 0.25 * (0.5 + 0.5 * np.sin(y * 2 * np.pi * 20)) + 0.15 * pnoise(4, 2, 11)
save("cardboard", cb, 0.82, 1.0)
