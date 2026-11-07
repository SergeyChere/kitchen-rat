"""Room pieces: walls (plain, with the mouse hole, a crack, a window, a door), lamps, the nest, rugs, wall art,
kitchen clutter, and floor/wall textures. Rooms are 960 × 600 cm with a 250 cm ceiling, assembled in Unity."""
import math
import os
import random

from lib import box, cyl, sphere, ico, torus, seg, plane, mat, model, ROOT

random.seed(5)
C = 'rooms'
WALL, TRIM = 0xe8dcc6, 0x7a4a2a


def wall(name, extra=None, cut=None):
    """120 cm wall section, 10 cm thick, 250 cm tall, with a baseboard. cut: (x0, x1, z0, z1) opening."""
    W, T = mat(WALL, 0.9), mat(TRIM, 0.7)
    parts, mov = [], {}
    if cut:
        x0, x1, z0, z1 = cut
        if x0 > -60: parts.append(box(x0 + 60, 10, 250, (-60 + x0) / 2, 0, 0, W))
        if x1 < 60: parts.append(box(60 - x1, 10, 250, (x1 + 60) / 2, 0, 0, W))
        if z0 > 0: parts.append(box(x1 - x0, 10, z0, (x0 + x1) / 2, 0, 0, W))
        parts.append(box(x1 - x0, 10, 250 - z1, (x0 + x1) / 2, 0, z1, W))
    else:
        parts.append(box(120, 10, 250, 0, 0, 0, W))
    if cut and cut[2] <= 0:  # an opening at the floor (mouse hole, door): the baseboard stops at its sides
        x0, x1 = cut[0], cut[1]
        if x0 > -60: parts.append(box(x0 + 60, 3, 14, (-60 + x0) / 2, -6.5, 0, T, bevel=0.4))
        if x1 < 60: parts.append(box(60 - x1, 3, 14, (x1 + 60) / 2, -6.5, 0, T, bevel=0.4))
    else:
        parts.append(box(120, 3, 14, 0, -6.5, 0, T, bevel=0.4))
    parts.append(box(120, 4, 6, 0, -7, 244, T, bevel=0.6))
    if extra:
        extra(parts, mov)
    return model(C, name, parts, mov or None)


def wall_mousehole():
    """A real 22 × 22 cm opening at the bottom, with an arched wooden trim: the rat walks through it to the nest."""
    def ex(parts, mov):
        T = mat(TRIM, 0.6)
        parts += [box(3.6, 3, 12, -13, -6.2, 0, T), box(3.6, 3, 12, 13, -6.2, 0, T)]  # posts
        for i in range(7):  # an arch over the opening, open at the floor
            a = math.radians(i * 30)
            parts.append(box(6.6, 3, 3.4, -13 * math.cos(a), -6.2, 10.5 + 13 * math.sin(a), T, rot=(0, -(i * 30 - 90) + 90, 0)))
    return wall('wall_mousehole', ex, cut=(-11, 11, 0, 22))


def wall_crack():
    def ex(parts, mov):
        dark = mat(0x4a3a30, 0.9)
        parts += [box(40, 12, 15, 0, -5, 0, mat(0x0a0806)), box(42, 2.5, 2, 0, -7, 15, mat(0x5a4a3a))]
        pts = [(0, 17), (3, 40), (-4, 62), (2, 85), (-6, 108), (-2, 130), (5, 150)]
        for (x0, z0), (x1, z1) in zip(pts, pts[1:]):  # a crack running up the wall
            parts.append(seg((x0, -5.2, z0), (x1, -5.2, z1), 0.6, 0.4, dark, verts=4))
        parts += [seg((-4, -5.2, 62), (-14, -5.2, 74), 0.5, 0.2, dark, verts=4), seg((2, -5.2, 85), (12, -5.2, 96), 0.5, 0.2, dark, verts=4)]
    return wall('wall_crack', ex)


def wall_window():
    def ex(parts, mov):
        F = mat(0xf0e8da, 0.6)
        parts += [box(104, 14, 6, 0, -2, 94, F), box(104, 14, 6, 0, -2, 214, F), box(6, 14, 126, -50, -2, 94, F), box(6, 14, 126, 50, -2, 94, F), box(4, 8, 120, 0, -1, 97, F),
                  box(92, 4, 4, 0, -1, 156, F), box(112, 22, 4, 0, -10, 90, mat(TRIM, 0.6))]
        parts += [box(92, 1, 112, 0, 0, 100, mat(0x9ac4e8, 0.05, 0, 0.35))]
        mov['curtain_l'] = [box(24, 4, 150, -66, -14, 75, mat(0xc0302e, 0.95), bevel=1)] + [box(3, 4.4, 150, -66 + x, -14.2, 75, mat(0xa02626, 0.95)) for x in (-6, 4)]
        mov['curtain_r'] = [box(24, 4, 150, 66, -14, 75, mat(0xc0302e, 0.95), bevel=1)] + [box(3, 4.4, 150, 66 + x, -14.2, 75, mat(0xa02626, 0.95)) for x in (-4, 6)]
        gold = mat(0xd8a840, 0.3, 0.5)
        parts += [cyl(1.4, 170, 0, -14, 228, gold, verts=8, rot=(0, 90, 0))] + [sphere(2.6, x, -14, 228, gold, seg=8, rings=6) for x in (-86, 86)]
        parts += [cyl(6, 8, 18, -12, 94, mat(0xc8683a, 0.8), verts=10, r2=7)] + [sphere(4, 18 + dx, -14 + dy, 104 + dz, mat(0x4a9a3a, 0.7), seg=8, rings=4, scale=(1.3, 0.7, 0.6))
                                                                                 for dx, dy, dz in [(-4, 0, 0), (4, 1, 2), (0, -2, 4), (-6, -3, -6), (6, -2, -8)]]
    return wall('wall_window', ex, cut=(-50, 50, 94, 220))


def wall_door():
    def ex(parts, mov):
        T = mat(0x6a4024, 0.7)
        parts += [box(6, 14, 214, -48, -2, 0, T), box(6, 14, 214, 48, -2, 0, T), box(102, 14, 6, 0, -2, 211, T), box(8, 2, 12, 56, -6, 110, mat(0xf0ece2)), box(3, 2.4, 5, 56, -7, 113, mat(0xd8d0c0))]
        door = [box(90, 4, 208, 0, 0, 2, mat(0x8a5430, 0.7), bevel=0.8)] + [box(30, 1, 70, x, -2.4, z, mat(0x7a4626, 0.7), bevel=0.4) for x in (-20, 20) for z in (20, 115)]
        door.append(sphere(2.5, 36, -5, 100, mat(0xd8b040, 0.3, 0.6), seg=8, rings=6))
        mov['door'] = door
    return wall('wall_door', ex, cut=(-45, 45, 0, 210))


def lamp_shade():
    parts = [cyl(0.6, 40, 0, 0, 10, mat(0x2a2a2a), verts=6), cyl(22, 18, 0, 0, -8, mat(0xf2e2c0, 0.9), verts=18, r2=12)]
    return model(C, 'lamp_shade', parts, {'bulb': [sphere(5, 0, 0, -4, mat(0xfff0c0, 0.3, 0, 1, 3), seg=10, rings=6)]})


def lamp_bulb():
    parts = [cyl(0.5, 40, 0, 0, 8, mat(0x2a2a2a), verts=6), cyl(2.5, 5, 0, 0, 4, mat(0x5a5a5a, 0.4, 0.6), verts=10)]
    return model(C, 'lamp_bulb', parts, {'bulb': [sphere(4.5, 0, 0, 0, mat(0xfff0c0, 0.3, 0, 1, 3), seg=10, rings=6, scale=(1, 1, 1.2))]})


def chandelier():
    G = mat(0xd8b040, 0.3, 0.8)
    parts = [cyl(0.6, 40, 0, 0, 20, G, verts=6), sphere(6, 0, 0, 16, G, seg=10, rings=6), torus(30, 1.2, 0, 0, 10, G, seg=24, rseg=4)]
    bulbs = []
    for i in range(6):
        a = i * math.pi / 3
        x, y = math.cos(a) * 30, math.sin(a) * 30
        parts += [seg((0, 0, 16), (x, y, 10), 0.8, 0.8, G, verts=5), cyl(2.5, 6, x, y, 10, mat(0xf4f0e8), verts=8)]
        bulbs.append(sphere(2.2, x, y, 18, mat(0xffd890, 0.3, 0, 1, 3), seg=8, rings=6, scale=(1, 1, 1.5)))
    return model(C, 'chandelier', parts, {'bulbs': bulbs})


def nest():
    parts = [cyl(60, 4, 0, 0, 0, mat(0x8a6a44, 0.95), verts=16)]
    for i in range(26):  # shredded paper, cloth and cardboard
        a, d = random.uniform(0, 6.28), random.uniform(10, 46)
        parts.append(box(random.uniform(10, 26), random.uniform(3, 8), random.uniform(1, 3), math.cos(a) * d, math.sin(a) * d, random.uniform(2, 8),
                         mat(random.choice([0xf4f0e0, 0xd8c8a8, 0xc89a5a, 0xa8b8d8, 0xe8a0a0]), 0.95), rot=(random.uniform(-20, 20), random.uniform(-20, 20), random.uniform(0, 180))))
    twig = [0x7a4a24, 0x8a5a2e, 0x6a3e1e]
    for i in range(40):  # woven twigs round the rim
        a = i * 6.28 / 40
        r = 50 + random.uniform(-4, 4)
        x0, y0 = math.cos(a) * r, math.sin(a) * r
        x1, y1 = math.cos(a + 0.5) * r, math.sin(a + 0.5) * r
        parts.append(seg((x0, y0, 3 + (i % 3) * 3), (x1, y1, 5 + ((i + 1) % 3) * 3), 2, 1.6, mat(twig[i % 3], 0.95), verts=5))
    parts += [sphere(5, math.cos(a) * 54, math.sin(a) * 54, 13, mat(0x5aaa44, 0.7), seg=8, rings=4, scale=(1.5, 0.6, 0.3)) for a in (0.6, 2.4, 4.1, 5.4)]
    return model(C, 'nest', parts)


def rug(name, w, d, base, border, pattern):
    parts = [box(w, d, 0.8, 0, 0, 0, mat(border, 0.95)), box(w - 16, d - 16, 0.9, 0, 0, 0, mat(base, 0.95))]
    if pattern == 'stripes':
        parts += [box(w - 16, 6, 1, 0, y, 0, mat(border, 0.95)) for y in range(int(-d / 2) + 30, int(d / 2) - 20, 30)]
    elif pattern == 'diamond':
        parts += [box(40, 40, 1, x, 0, 0, mat(border, 0.95), rot=(0, 0, 45)) for x in (-w / 4, 0, w / 4)]
    else:
        parts += [cyl(r, 1 + r * 0.001, 0, 0, 0, mat(c, 0.95), verts=24) for r, c in [(min(w, d) / 2 - 20, border), (min(w, d) / 2 - 34, base)]]
        parts += [sphere(14, x, y, 1, mat(0x5a8a3a, 0.9), seg=8, rings=4, scale=(0.5, 1.2, 0.08)) for x, y in [(-14, 0), (14, 0), (0, 16)]]
    if pattern != 'round':  # fringe on the short ends
        parts += [box(2, 6, 0.6, x, sy * (d / 2 + 3), 0, mat(0xe8d8b0, 0.95)) for sy in (-1, 1) for x in range(int(-w / 2) + 6, int(w / 2) - 4, 10)]
    return model(C, name, parts)


def wall_art(name, kind):
    F, G = mat(0x7a4626, 0.6), mat(0xd8a840, 0.3, 0.6)
    if kind == 'clock':
        parts = [cyl(16, 4, 0, 0, 0, F, verts=20, rot=(90, 0, 0)), cyl(14, 4.5, 0, -0.3, 0, mat(0xf4f0e8), verts=20, rot=(90, 0, 0)),
                 box(1, 1, 10, 0, -2.6, 0, mat(0x1a1a1a)), box(7, 1, 1, 3.5, -2.6, 0, mat(0x1a1a1a))] + \
                [box(0.8, 1, 2, math.sin(a) * 12, -2.5, math.cos(a) * 12 - 1, mat(0x3a3a3a)) for a in [i * math.pi / 6 for i in range(12)]]
        return model(C, name, parts)
    cols = {'landscape': [0x8ac4e8, 0x6ac46a, 0x4a8a4a], 'flowers': [0xf4f0e0, 0xe84a5a, 0xf2c84a], 'portrait': [0xd8a870, 0xc8302e, 0x6a4a2a]}[kind]
    parts = [box(60, 3, 45, 0, 0, 0, F, bevel=0.5), box(52, 3.4, 37, 0, -0.2, 4, mat(cols[0], 0.9)), sphere(1.5, 0, 0, 58, G, seg=8, rings=6),
             seg((0, 0, 58), (-24, 0, 44), 0.25, 0.25, mat(0x5a5a5a), verts=4), seg((0, 0, 58), (24, 0, 44), 0.25, 0.25, mat(0x5a5a5a), verts=4)]
    if kind == 'landscape':
        parts += [box(52, 3.6, 12, 0, -0.4, 4, mat(cols[1])), ico(8, -10, -1.8, 20, mat(cols[2]), sub=1, scale=(1, 0.2, 1)), ico(10, 8, -1.7, 18, mat(0x5a7a9a), sub=1, scale=(1.2, 0.2, 1)),
                  sphere(4, 16, -1.8, 32, mat(0xf2c84a), seg=8, rings=6, scale=(1, 0.2, 1))]
    elif kind == 'flowers':
        parts += [cyl(5, 12, 0, -2, 6, mat(0x3a5aa8), verts=8)] + [sphere(3.5, x, -2, z, mat(cols[1 + i % 2]), seg=8, rings=6, scale=(1, 0.3, 1)) for i, (x, z) in enumerate([(-6, 24), (0, 28), (6, 24), (-3, 32), (4, 33)])]
    else:  # an apple still life
        parts += [box(52, 3.6, 10, 0, -0.4, 4, mat(cols[2])), sphere(8, 0, -2, 22, mat(cols[1], 0.5), seg=12, rings=8, scale=(1, 0.3, 0.95)), box(1, 3.8, 4, 0, -2.2, 30, mat(0x4a2a14)),
                  sphere(2.4, 3, -2.3, 31, mat(0x5ab04a), seg=6, rings=4, scale=(1.6, 0.3, 0.6))]
    return model(C, name, parts)


def kettle():
    M, G = mat(0x2a3048, 0.35, 0.3), mat(0xd8a840, 0.3, 0.6)
    return model(C, 'kettle', [cyl(10, 18, 0, 0, 0, M, verts=12, r2=7), cyl(4, 2, 0, 0, 18, M, verts=10), sphere(1.8, 0, 0, 21, G, seg=8, rings=6), torus(6, 1.4, -9, 0, 15, M, seg=8, rseg=4, rot=(90, 0, 0)),
                               seg((8, 0, 8), (15, 0, 16), 2, 1, M, verts=8), torus(9.6, 0.5, 0, 0, 3, G, seg=12, rseg=4), cyl(2, 0.4, 0, -8.6, 9, G, verts=5, rot=(80, 0, 0))])


def pot():
    M, G = mat(0x2a2a30, 0.35, 0.3), mat(0xd8a840, 0.3, 0.6)
    return model(C, 'pot', [cyl(13, 14, 0, 0, 0, M, verts=18), cyl(13.5, 1.5, 0, 0, 14, M, verts=18), cyl(2, 1.5, 0, 0, 15.5, G, verts=10), sphere(2.2, 0, 0, 18, G, seg=8, rings=6)] +
                 [box(6, 3, 2.4, x, 0, 10, M, bevel=0.6) for x in (-16, 16)])


def stove_top():
    parts = [box(60, 60, 2, 0, 0, 0, mat(0x1a1a1e, 0.2), bevel=0.6)] + [torus(9 if i % 2 else 7, 0.8, x, y, 2, mat(0x8a8a94, 0.3, 0.4), seg=16, rseg=4) for i, (x, y) in enumerate([(-14, -10), (14, -10), (-14, 14), (14, 14)])]
    parts += [cyl(2.2, 2, x, -25, 2, mat(0xc8ccd4, 0.3, 0.5), verts=10) for x in (-12, 0, 12)]
    return model(C, 'stove_top', parts)


def utensil_holder():
    cer, blue, wood = mat(0xeee6d4, 0.5), mat(0x3a5aa8, 0.5), mat(0xb07a44, 0.7)
    parts = [cyl(6, 14, 0, 0, 0, cer, verts=12), torus(6, 0.6, 0, 0, 14, cer, seg=12, rseg=4)]
    parts += [sphere(1.4, math.cos(a) * 6, math.sin(a) * 6, 7, blue, seg=6, rings=4, scale=(1, 1, 1.6)) for a in (-1.9, -1.2, -2.6)]
    parts += [cyl(0.7, 22, -2, 1, 6, wood, verts=6), box(4, 1, 6, -2, 1, 27, wood, bevel=0.5), cyl(0.7, 22, 2, -1, 6, wood, verts=6), sphere(2.4, 2, -1, 29, wood, seg=8, rings=6, scale=(1, 0.5, 1.4)),
              cyl(0.5, 20, 1, 2.5, 6, mat(0xc8ccd4, 0.3, 0.5), verts=6)] + [torus(2, 0.25, 1, 2.5, 28, mat(0xc8ccd4, 0.3, 0.5), seg=8, rseg=3, rot=(90, 0, a)) for a in (0, 60, 120)]
    return model(C, 'utensil_holder', parts)


def floor_panel():
    cols = [0x9a5a30, 0x8a4e28, 0xa8683a]
    parts = []
    for r in range(6):
        off = 30 if r % 2 else 0
        for c in range(-1, 3):
            x0 = -60 + c * 60 + off
            x1 = min(60, x0 + 60)
            x0 = max(-60, x0)
            if x1 - x0 < 2:
                continue
            parts.append(box(x1 - x0 - 0.8, 19.2, 1, (x0 + x1) / 2, -50 + r * 20, -1, mat(cols[(r + c) % 3], 0.7)))
    return model(C, 'floor_panel', parts)


def textures():
    """Floor and wall textures (512 px, tile seamlessly) to art/rooms/textures."""
    from PIL import Image, ImageDraw
    out = os.path.join(ROOT, C, 'textures')
    os.makedirs(out, exist_ok=True)
    N = 512
    def save(img, name):
        img.save(os.path.join(out, name + '.png'))
    img = Image.new('RGB', (N, N)); d = ImageDraw.Draw(img)  # kitchen tile: checker
    for i in range(4):
        for j in range(4):
            c = (59, 64, 88) if (i + j) % 2 else (74, 80, 112)
            d.rectangle([i * 128, j * 128, i * 128 + 127, j * 128 + 127], fill=c)
            d.rectangle([i * 128, j * 128, i * 128 + 127, j * 128 + 127], outline=(40, 42, 58), width=3)
    save(img, 'floor_tile')
    img = Image.new('RGB', (N, N)); d = ImageDraw.Draw(img)  # wood planks
    for j in range(8):
        off = random.randint(0, N)
        base = random.randint(76, 96)
        d.rectangle([0, j * 64, N, j * 64 + 63], fill=(base + 14, int(base * 0.72), int(base * 0.5)))
        for _ in range(26):
            y = j * 64 + random.randint(4, 60)
            d.line([0, y, N, y + random.randint(-2, 2)], fill=(base, int(base * 0.62), int(base * 0.42)), width=1)
        d.line([0, j * 64, N, j * 64], fill=(40, 28, 20), width=3)
        for x in (off % N, (off + N // 2) % N):
            d.line([x, j * 64, x, j * 64 + 63], fill=(40, 28, 20), width=3)
    save(img, 'floor_wood')
    img = Image.new('RGB', (N, N), (62, 69, 65)); px = img.load()  # concrete
    for _ in range(40000):
        x, y = random.randrange(N), random.randrange(N)
        v = random.randint(-14, 14)
        r, g, b = px[x, y]
        px[x, y] = (max(0, r + v), max(0, g + v), max(0, b + v))
    d = ImageDraw.Draw(img); d.line([0, 256, N, 256], fill=(48, 52, 50), width=2); d.line([256, 0, 256, N], fill=(48, 52, 50), width=2)
    save(img, 'floor_concrete')
    img = Image.new('RGB', (N, N), (85, 92, 102)); d = ImageDraw.Draw(img)  # small bathroom tiles
    for i in range(0, N, 64):
        d.line([i, 0, i, N], fill=(60, 64, 72), width=3); d.line([0, i, N, i], fill=(60, 64, 72), width=3)
    save(img, 'floor_laundry')
    for name, a, b in [('wall_stripes', (75, 82, 114), (84, 92, 128)), ('wall_damask', (60, 86, 85), (70, 99, 97)), ('wall_panel', (92, 58, 70), (46, 31, 26))]:
        img = Image.new('RGB', (N, N), a); d = ImageDraw.Draw(img)
        if name == 'wall_stripes':
            for x in range(0, N, 64): d.rectangle([x, 0, x + 31, N], fill=b)
        elif name == 'wall_damask':
            for x in range(0, N, 128):
                for y in range(0, N, 128):
                    d.polygon([(x + 64, y + 20), (x + 100, y + 64), (x + 64, y + 108), (x + 28, y + 64)], fill=b)
        else:
            d.rectangle([0, 340, N, N], fill=b)
            for x in range(0, N, 128): d.rectangle([x + 12, 360, x + 116, 500], outline=(60, 40, 34), width=4)
        save(img, name)
    img = Image.new('RGB', (N, N), (106, 70, 54)); d = ImageDraw.Draw(img)  # brick
    for j in range(0, N, 32):
        off = 32 if (j // 32) % 2 else 0
        for i in range(-64, N, 64):
            c = random.randint(-10, 10)
            d.rectangle([i + off + 2, j + 2, i + off + 61, j + 29], fill=(106 + c, 70 + c // 2, 54 + c // 2))
    save(img, 'wall_brick')
    return [(os.path.join(out, 'floor_tile.png'), 0)]


ALL = [lambda: wall('wall_section'), wall_mousehole, wall_crack, wall_window, wall_door, lamp_shade, lamp_bulb, chandelier, nest,
       lambda: rug('rug_stripes', 300, 200, 0x6a5a8f, 0xd8b04a, 'stripes'), lambda: rug('rug_diamond', 300, 200, 0xa84a3a, 0xe8d8b0, 'diamond'),
       lambda: rug('rug_round', 220, 220, 0x4a7a6a, 0xe8d8b0, 'round'),
       lambda: wall_art('wall_art_landscape', 'landscape'), lambda: wall_art('wall_art_flowers', 'flowers'), lambda: wall_art('wall_art_portrait', 'portrait'), lambda: wall_art('wall_clock', 'clock'),
       kettle, pot, stove_top, utensil_holder, floor_panel, textures]
