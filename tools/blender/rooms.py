"""Room pieces: walls (plain, with the mouse hole, a crack, a window, a door), lamps, the nest, rugs, wall art,
kitchen clutter, and floor/wall textures. Rooms are 960 × 600 cm with a 250 cm ceiling, assembled in Unity."""
import math
import os
import random

from lib import box, cyl, sphere, ico, torus, seg, plane, mat, model, ROOT

random.seed(5)
C = 'rooms'
WALL, TRIM = 0x8a96b0, 0x3a2e30


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
    parts += [box(120, 2, 12, 0, -6, 0, T), box(120, 2, 3, 0, -6, 247, T)]
    if extra:
        extra(parts, mov)
    return model(C, name, parts, mov or None)


def wall_mousehole():
    def ex(parts, mov):
        parts += [cyl(10, 12, 0, -5, 10, mat(0x120a08), verts=16, rot=(90, 0, 0)), box(20, 12, 10, 0, -5, 0, mat(0x120a08)),
                  torus(10.5, 1.2, 0, -7, 10, mat(TRIM), seg=16, rseg=4, rot=(90, 0, 0))]
        mov['glow'] = [cyl(8, 0.5, 0, 0, 9, mat(0xffb060, 0.5, 0, 1, 3), verts=14, rot=(90, 0, 0))]
    return wall('wall_mousehole', ex)


def wall_crack():
    def ex(parts, mov):
        parts += [box(40, 12, 15, 0, -5, 0, mat(0x0a0806)), box(42, 2.5, 2, 0, -7, 15, mat(0x2a2020))] + [box(4, 2.2, 1, x, -6.5, 15.5 + abs(x) * 0.1, mat(0x5a4a4a)) for x in (-14, 6)]
    return wall('wall_crack', ex)


def wall_window():
    def ex(parts, mov):
        F = mat(0xe8e4dc, 0.6)
        parts += [box(104, 14, 6, 0, -2, 94, F), box(104, 14, 6, 0, -2, 214, F), box(6, 14, 126, -50, -2, 94, F), box(6, 14, 126, 50, -2, 94, F), box(4, 8, 120, 0, -1, 97, F),
                  box(110, 20, 4, 0, -10, 90, F)]
        parts += [box(92, 1, 112, 0, 0, 100, mat(0x8ab4e0, 0.05, 0, 0.35))]
        mov['curtain_l'] = [box(24, 4, 150, -66, -14, 75, mat(0xa84a5a, 0.95), bevel=1)]
        mov['curtain_r'] = [box(24, 4, 150, 66, -14, 75, mat(0xa84a5a, 0.95), bevel=1)]
        parts.append(cyl(1.2, 170, 0, -14, 228, mat(0x5a4436), verts=8, rot=(0, 90, 0)))
    return wall('wall_window', ex, cut=(-50, 50, 94, 220))


def wall_door():
    def ex(parts, mov):
        T = mat(0x5a4436, 0.7)
        parts += [box(6, 14, 214, -48, -2, 0, T), box(6, 14, 214, 48, -2, 0, T), box(102, 14, 6, 0, -2, 211, T), box(8, 2, 12, 56, -6, 110, mat(0xf0ece2)), box(3, 2.4, 5, 56, -7, 113, mat(0xd8d0c0))]
        door = [box(90, 4, 208, 0, 0, 2, mat(0x7a5a3a, 0.7), bevel=0.8)] + [box(30, 1, 70, x, -2.4, z, mat(0x6a4a2e, 0.7)) for x in (-20, 20) for z in (20, 115)]
        door.append(sphere(2.5, 36, -5, 100, mat(0xd8b040, 0.3, 0.8), seg=8, rings=6))
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
    parts = [cyl(60, 4, 0, 0, 0, mat(0xb08a5a, 0.95), verts=16)]
    for i in range(26):  # shredded paper, cloth and cardboard
        a, d = random.uniform(0, 6.28), random.uniform(10, 55)
        parts.append(box(random.uniform(10, 26), random.uniform(3, 8), random.uniform(1, 3), math.cos(a) * d, math.sin(a) * d, random.uniform(2, 8),
                         mat(random.choice([0xf4f0e0, 0xd8c8a8, 0xc89a5a, 0xa8b8d8, 0xe8a0a0]), 0.95), rot=(random.uniform(-20, 20), random.uniform(-20, 20), random.uniform(0, 180))))
    parts += [torus(48, 9, 0, 0, 6, mat(0xc8a878, 0.95), seg=18, rseg=6)]
    return model(C, 'nest', parts)


def rug(name, w, d, base, border, pattern):
    parts = [box(w, d, 0.8, 0, 0, 0, mat(border, 0.95)), box(w - 16, d - 16, 0.9, 0, 0, 0, mat(base, 0.95))]
    if pattern == 'stripes':
        parts += [box(w - 16, 6, 1, 0, y, 0, mat(border, 0.95)) for y in range(int(-d / 2) + 30, int(d / 2) - 20, 30)]
    elif pattern == 'diamond':
        parts += [box(40, 40, 1, x, 0, 0, mat(border, 0.95), rot=(0, 0, 45)) for x in (-w / 4, 0, w / 4)]
    else:
        parts += [cyl(r, 1 + r * 0.001, 0, 0, 0, mat(c, 0.95), verts=24) for r, c in [(min(w, d) / 2 - 20, border), (min(w, d) / 2 - 34, base)]]
    return model(C, name, parts)


def wall_art(name, kind):
    F = mat(0x5a4436, 0.6)
    if kind == 'clock':
        parts = [cyl(16, 4, 0, 0, 0, F, verts=20, rot=(90, 0, 0)), cyl(14, 4.5, 0, -0.3, 0, mat(0xf4f0e8), verts=20, rot=(90, 0, 0)),
                 box(1, 1, 10, 0, -2.6, 0, mat(0x1a1a1a)), box(7, 1, 1, 3.5, -2.6, 0, mat(0x1a1a1a))]
        return model(C, name, parts)
    cols = {'landscape': [0x8ab4e0, 0x6ac46a, 0x4a8a4a], 'flowers': [0xf4f0e0, 0xe84a5a, 0xf2c84a], 'portrait': [0x8a6a5a, 0xe8b896, 0x4a3020]}[kind]
    parts = [box(60, 3, 45, 0, 0, 0, F, bevel=0.5), box(52, 3.4, 37, 0, -0.2, 4, mat(cols[0], 0.9))]
    if kind == 'landscape':
        parts += [box(52, 3.6, 12, 0, -0.4, 4, mat(cols[1])), ico(8, -10, -1.8, 20, mat(cols[2]), sub=1, scale=(1, 0.2, 1)), sphere(4, 14, -1.8, 32, mat(0xf2c84a), seg=8, rings=6, scale=(1, 0.2, 1))]
    elif kind == 'flowers':
        parts += [cyl(5, 12, 0, -2, 6, mat(0x4a7ab8), verts=8)] + [sphere(3.5, x, -2, z, mat(cols[1 + i % 2]), seg=8, rings=6, scale=(1, 0.3, 1)) for i, (x, z) in enumerate([(-6, 24), (0, 28), (6, 24), (-3, 32), (4, 33)])]
    else:
        parts += [sphere(8, 0, -2, 24, mat(cols[1]), seg=10, rings=8, scale=(0.85, 0.2, 1)), box(26, 3.8, 10, 0, -0.6, 4, mat(cols[0]))]
    return model(C, name, parts)


def kettle():
    M = mat(0xc8ccd4, 0.25, 0.8)
    return model(C, 'kettle', [cyl(10, 18, 0, 0, 0, M, verts=16, r2=7), cyl(4, 2, 0, 0, 18, mat(0x1a1a1a), verts=10), torus(6, 1.2, -9, 0, 15, mat(0x1a1a1a), seg=12, rseg=4, rot=(90, 0, 0)),
                                seg((8, 0, 8), (15, 0, 16), 2, 1, M, verts=8)])


def pot():
    M = mat(0x3a3a40, 0.35, 0.7)
    return model(C, 'pot', [cyl(13, 14, 0, 0, 0, M, verts=18), cyl(13.5, 1.5, 0, 0, 14, M, verts=18), sphere(2, 0, 0, 16.5, mat(0x1a1a1a), seg=8, rings=6)] + [box(6, 2, 2, x, 0, 10, mat(0x1a1a1a)) for x in (-16, 16)])


def stove_top():
    parts = [box(60, 60, 2, 0, 0, 0, mat(0x1a1a1e, 0.2))] + [torus(9 if i % 2 else 7, 0.8, x, y, 2, mat(0x6a6a74, 0.3, 0.6), seg=16, rseg=4) for i, (x, y) in enumerate([(-14, -14), (14, -14), (-14, 14), (14, 14)])]
    return model(C, 'stove_top', parts)


def utensil_holder():
    parts = [cyl(5, 14, 0, 0, 0, mat(0xd8d0c0, 0.5), verts=12)] + [cyl(0.6, 22, x, y, 4, mat(c), verts=5) for x, y, c in [(-2, 0, 0x5a3a20), (1, 1.5, 0xc8ccd4), (1.5, -1.5, 0x5a3a20)]]
    return model(C, 'utensil_holder', parts)


def floor_panel():
    return model(C, 'floor_panel', [box(120, 120, 1, 0, 0, -1, mat(0x9a9aa8, 0.8))])


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
