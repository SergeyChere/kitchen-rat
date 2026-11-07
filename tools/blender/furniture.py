"""Furniture. Sizes in cm: length (X) × depth (Y) × height (Z). The fronts face -Y.
Surface heights match the game (the rat jumps up to 57 cm), and there is space under tables, chairs and sofas."""
import random

from lib import box, cyl, sphere, ico, torus, seg, mat, model

random.seed(11)
C = 'furniture'
WOOD, WOOD_D, WOOD_L = 0x9b7c4c, 0x63412a, 0xc8a070
WHITE, STEEL = 0xeef0f4, 0xc0c6d0


def legs4(w, d, h, inset, r, m, square=False):
    out = []
    for x in (-w / 2 + inset, w / 2 - inset):
        for y in (-d / 2 + inset, d / 2 - inset):
            out.append(box(r * 2, r * 2, h, x, y, 0, m) if square else cyl(r, h, x, y, 0, m, verts=8))
    return out


def table(name, w, d, ht, top=WOOD, leg=WOOD_D, cloth=None, cloth_drop=18):
    T, L = mat(top, 0.6), mat(leg, 0.7)
    parts = [box(w, d, 4, 0, 0, ht - 4, T, bevel=0.8)] + legs4(w, d, ht - 4, 6, 2.5, L, square=True)
    parts += [box(w - 12, 2, 6, 0, y, ht - 10, L) for y in (-d / 2 + 6, d / 2 - 6)] + [box(2, d - 12, 6, x, 0, ht - 10, L) for x in (-w / 2 + 6, w / 2 - 6)]
    movable = None
    if cloth is not None:
        cl = mat(cloth, 0.95)
        movable = {'tablecloth': [box(w + 4, d + 4, 1, 0, 0, ht, cl), box(w + 4, 1, cloth_drop, 0, -d / 2 - 2, ht - cloth_drop, cl), box(w + 4, 1, cloth_drop, 0, d / 2 + 2, ht - cloth_drop, cl),
                                  box(1, d + 4, cloth_drop, -w / 2 - 2, 0, ht - cloth_drop, cl), box(1, d + 4, cloth_drop, w / 2 + 2, 0, ht - cloth_drop, cl)]}
    return model(C, name, parts, movable)


def counter_section(sink=False, corner=False):
    body, top, door = mat(0xe8e0d0, 0.7), mat(0x6a6a74, 0.4), mat(0xd8d0c0, 0.6)
    w = 72 if corner else 60
    parts = [box(w, 72, 86, 0, 0, 6, body), box(w - 4, 66, 6, 0, 2, 0, mat(0x3a3a40)), box(w + 1, 74, 4, 0, -1, 88, top)]
    parts += [box(w / 2 - 3, 1, 70, x, -36.5, 12, door) for x in ((-w / 4, w / 4) if not corner else (0,))] + [box(1.5, 1.5, 12, x, -37.5, 66, mat(STEEL, 0.3, 0.8)) for x in ((-3, 3) if not corner else (8,))]
    name = 'counter_corner' if corner else 'counter_section'
    if sink:
        parts += [box(44, 40, 0.5, 0, 0, 92, mat(STEEL, 0.25, 0.9)), cyl(1.5, 24, 0, 22, 92, mat(STEEL, 0.25, 0.9), verts=8), cyl(1.3, 14, 0, 16, 115, mat(STEEL, 0.25, 0.9), verts=8, rot=(80, 0, 0))]
        name = 'counter_sink'
    return model(C, name, parts)


def fridge():
    b, h = mat(0xeef0f4, 0.35), mat(STEEL, 0.3, 0.8)
    parts = [box(130, 110, 185, 0, 0, 0, b, bevel=3), box(128, 1, 1, 0, -55.3, 120, mat(0x9aa0aa)), box(3, 3, 40, 55, -57, 135, h), box(3, 3, 30, 55, -57, 70, h)]
    parts += [box(10, 1, 8, x, -55.5, z, mat(c, 0.5)) for x, z, c in [(-40, 150, 0xe84a5a), (-20, 160, 0xf2c84a), (-35, 140, 0x4a9ae8)]] + [box(20, 0.6, 26, 10, -55.4, 135, mat(0xf4f0e0))]
    return model(C, 'fridge', parts)


def kitchen_island():
    return model(C, 'kitchen_island', [box(200, 90, 86, 0, 0, 0, mat(0x5a7a9a, 0.6)), box(206, 96, 6, 0, 0, 86, mat(0xd8d0c0, 0.4)),
                                       box(196, 1, 70, 0, -45.5, 8, mat(0x4a6a8a, 0.6))] + [box(1.5, 1.5, 14, x, -46.5, 62, mat(STEEL, 0.3, 0.8)) for x in (-60, 0, 60)])


def chair(name='chair', col=WOOD_D, seat_col=0xc95b4a):
    W, S = mat(col, 0.7), mat(seat_col, 0.85)
    parts = [box(32, 32, 3, 0, 0, 44, W)] + legs4(32, 32, 44, 2.5, 1.5, W, square=True) + [box(30, 30, 2, 0, 0, 47, S, bevel=0.8)]
    parts += [box(2.5, 2.5, 46, x, 14.75, 47, W) for x in (-13, 13)] + [box(28, 2, 5, 0, 14.75, 47 + h, W) for h in (16, 30, 41)]  # slatted back: the camera sees through it
    return model(C, name, parts)


def stool():
    W = mat(WOOD, 0.6)
    parts = [cyl(18, 3, 0, 0, 49, W, verts=16)] + [seg((x * 13, y * 13, 0), (x * 10, y * 10, 49), 1.6, 1.4, mat(WOOD_D), verts=6) for x in (-1, 1) for y in (-1, 1)] + [torus(11.5, 0.8, 0, 0, 18, mat(WOOD_D), seg=12, rseg=4)]
    return model(C, 'stool', parts)


def low_shelf(w=62, d=50):
    T, L = mat(WOOD, 0.7), mat(WOOD_D, 0.7)
    parts = [box(w, d, 4, 0, 0, 23, T, bevel=0.5)] + legs4(w, d, 23, 4, 2, L)
    parts += [box(10, 8, 12, x, 0, 27, mat(c, 0.7)) for x, c in [(-w / 3, 0x4a8ac8), (0, 0xe8a040), (w / 3, 0x6ac46a)]]
    return model(C, 'low_shelf', parts)


def cardboard_box(name, w, d, h):
    m = mat(0xc89a5a, 0.95)
    return model(C, name, [box(w, d, h, 0, 0, 0, m, bevel=0.6), box(w + 0.4, 6, 0.4, 0, 0, h, mat(0xa8784a)), box(w * 0.3, 0.4, h * 0.25, -w * 0.2, -d / 2 - 0.2, h * 0.55, mat(0xf4f0e8))])


def sofa(name='sofa', w=360, d=110, col=0x6a5a8f, arm=16, cushions=None):
    fab, fab2, leg = mat(col, 0.95), mat(0x5a4a7a if col == 0x6a5a8f else 0x7a4a3a, 0.95), mat(0x2a1e18)
    back = 26
    seat_w = w - 2 * arm
    n = cushions or max(2, round(seat_w / 90))
    parts = [cyl(2.5, 14, x, y, 0, leg, verts=8) for x in (-w / 2 + 6, w / 2 - 6) for y in (-d / 2 + 6, d / 2 - 6)]
    parts += [box(w, d, 16, 0, 0, 14, fab2, bevel=2)]
    parts += [box(seat_w / n - 3, d - back - 2, 10, -seat_w / 2 + seat_w / n * (i + 0.5), -back / 2, 30, fab, bevel=2.5) for i in range(n)]
    parts += [box(w, back, 46, 0, d / 2 - back / 2, 30, fab2, bevel=3)]
    parts += [box(arm, d, 26, x, 0, 30, fab2, bevel=3) for x in (-w / 2 + arm / 2, w / 2 - arm / 2)]
    parts += [box(seat_w / n - 10, 10, 28, -seat_w / 2 + seat_w / n * (i + 0.5), d / 2 - back - 4, 40, fab, bevel=4, rot=(-12, 0, 0)) for i in range(n)]
    return model(C, name, parts)


def coffee_table():
    T, L = mat(0x6a4a30, 0.5), mat(0x3a2a1e)
    return model(C, 'coffee_table', [box(200, 80, 5, 0, 0, 40, T, bevel=1)] + legs4(200, 80, 40, 8, 3, L, square=True) + [box(180, 60, 2, 0, 0, 12, mat(0x5a3e28))])


def tv_stand():
    B = mat(0x3a2c26, 0.6)
    parts = [box(300, 55, 51, 0, 0, 0, B), box(304, 59, 4, 0, 0, 51, mat(0x5a4436))] + [box(1.5, 0.6, 40, x, -27.8, 6, mat(0x22180f)) for x in (-50, 50)]
    tw, th = 126, 73
    parts += [box(30, 16, 6, 0, -10, 55, mat(0x111216)), box(8, 6, 8, 0, -10, 61, mat(0x111216)), box(tw, 5, th, 0, -10, 66, mat(0x111216))]
    screen = [box(tw - 8, 0.4, th - 8, 0, -12.7, 70, mat(0x2a3a5a, 0.2))]
    return model(C, 'tv_stand', parts, movable={'screen': screen})


def side_table():
    T, L = mat(0x7a5a3a, 0.6), mat(0x4a3424)
    return model(C, 'side_table', [box(50, 50, 4, 0, 0, 58, T, bevel=0.6)] + legs4(50, 50, 58, 4, 2, L) + [box(42, 42, 2, 0, 0, 20, T)])


def ottoman(name='ottoman', col=0x9a5a48, w=50, h=40):
    return model(C, name, [box(w, w, h - 4, 0, 0, 4, mat(col, 0.95), bevel=5)] + [cyl(2, 4, x, y, 0, mat(0x2a1e18), verts=8) for x in (-w / 2 + 6, w / 2 - 6) for y in (-w / 2 + 6, w / 2 - 6)])


def beanbag():
    return model(C, 'beanbag', [ico(28, 0, 0, 20, mat(0xe8664a, 0.95), sub=2, scale=(1, 1, 0.72)), ico(20, 0, 8, 34, mat(0xe8664a, 0.95), sub=2, scale=(1, 0.7, 0.6))])


def bookcase():
    B = mat(0x3e2c22, 0.7)
    cols = [0xa83a3a, 0x3a6aa8, 0xd8b04a, 0x4a8a5a, 0x7a4a8a, 0xe0d8c8, 0x2a3a5a]
    parts = [box(190, 4, 190, 0, 28, 0, B), box(4, 60, 190, -93, 0, 0, B), box(4, 60, 190, 93, 0, 0, B), box(190, 60, 4, 0, 0, 186, B), box(190, 60, 4, 0, 0, 0, B)]
    for k in range(4):
        z = 4 + k * 45
        parts.append(box(182, 56, 3, 0, 0, z + 41, B))
        x = -88
        while x < 85:
            t, hh = random.uniform(4, 9), random.uniform(24, 36)
            parts.append(box(t, random.uniform(36, 48), hh, x + t / 2, 0, z, mat(random.choice(cols), 0.8)))
            x += t + 0.4
    return model(C, 'bookcase', parts)


def fireplace():
    S, D = mat(0x7a4a3a, 0.9), mat(0x120a08)
    parts = [box(150, 46, 108, 0, 0, 0, S), box(174, 58, 6, 0, -4, 108, mat(0x5a3e30)), box(76, 2, 54, 0, -22.5, 6, D)]
    parts += [cyl(3.5, 30, x, -10, 8, mat(0x5a3a22), verts=8, rot=(0, 90, 0)) for x in (-6, 6)]
    for i in range(12):
        parts.append(box(24, 1, 10, -66 + (i % 6) * 26 + (13 if (i // 6) % 2 else 0), -23.2, 70 + (i // 6) * 12, mat(0x8a5a48, 0.9)))
    return model(C, 'fireplace', parts)


def floor_lamp():
    parts = [cyl(13, 3, 0, 0, 0, mat(0x2a2420), verts=16), cyl(1.4, 125, 0, 0, 3, mat(0x2a2420), verts=8), cyl(17, 26, 0, 0, 124, mat(0xf2e2c0, 0.9), verts=16, r2=11)]
    return model(C, 'floor_lamp', parts, movable={'bulb': [sphere(5, 0, 0, 130, mat(0xfff0c0, 0.3, 0, 1, 3), seg=10, rings=6)]})


def plant():
    parts = [cyl(20, 30, 0, 0, 0, mat(0xb85a3a, 0.8), verts=14, r2=24), cyl(21, 2, 0, 0, 28, mat(0x4a3424), verts=14)]
    for i in range(9):
        a = i * 0.7
        parts.append(ico(12, random.uniform(-10, 10), random.uniform(-10, 10), 45 + random.uniform(0, 30), mat(random.choice([0x4a8a4a, 0x5a9a4a, 0x3a7a3a]), 0.8), sub=1, scale=(1, 1, 1.3)))
    return model(C, 'plant', parts)


def shelf_unit():
    fr, sh = mat(0x7a7f88, 0.5, 0.6), mat(0x9a9fa8, 0.5, 0.5)
    jc = [0xd8b04a, 0xc95b4a, 0x9ab86a, 0xe6dcc8, 0x8a5a3a]
    parts = [cyl(2, 160, x, y, 0, fr, verts=6) for x in (-98, 98) for y in (-23, 23)]
    for k, z in enumerate((4, 52, 104, 156)):
        parts.append(box(200, 50, 3, 0, 0, z, sh))
        if k < 3:
            x = -86
            while x < 86:
                jh = random.uniform(18, 30)
                parts.append(cyl(7, jh, x, random.uniform(-8, 8), z + 3, mat(random.choice(jc), 0.6), verts=10))
                x += random.uniform(22, 32)
    return model(C, 'shelf_unit', parts)


def washer(dryer=False):
    b = mat(0xd2d6de if dryer else WHITE, 0.4)
    parts = [box(90, 80, 85, 0, 0, 0, b, bevel=2), torus(20, 3, 0, -40.5, 38, mat(0x9aa0aa, 0.3, 0.6), seg=24, rseg=6, rot=(90, 0, 0)), box(80, 6, 10, 0, -37, 72, mat(0xc8ccd4))]
    parts += [cyl(18, 1, 0, -40.2, 38, mat(0x2a2a34 if dryer else 0x2a3a5a, 0.05, 0, 0.7), verts=24, rot=(90, 0, 0)), cyl(3, 2, 28, -40.5, 77, mat(0x5a5a64), verts=10, rot=(90, 0, 0))]
    button = [box(5, 5, 1.5, 22, -10, 85, mat(0x3ac04a, 0.3, 0, 1, 1.5))]
    return model(C, 'dryer' if dryer else 'washer', parts, movable={'button': button})


def laundry_basket():
    w = mat(0xc8a070, 0.9)
    parts = [box(52, 44, 45, 0, 0, 0, w, bevel=2)] + [box(52.4, 0.6, 2, 0, y, z, mat(0xa8804a)) for y in (-22, 22) for z in (10, 20, 30)]
    parts += [ico(14, x, 0, 44, mat(c, 0.95), sub=1, scale=(1.3, 1, 0.5)) for x, c in [(-10, 0x6a9ad8), (10, 0xf2e8e0)]]
    return model(C, 'laundry_basket', parts)


def crate():
    W = mat(0xa8804a, 0.9)
    parts = [box(60, 60, 40, 0, 0, 0, W)] + [box(61, 61, 3, 0, 0, z, mat(0x8a6638)) for z in (2, 18, 35)] + [box(3, 61.2, 40, x, 0, 0, mat(0x8a6638)) for x in (-28, 28)]
    return model(C, 'crate', parts)


def workbench():
    T, L = mat(0x8a6a48, 0.7), mat(0x5a4430)
    parts = [box(180, 90, 6, 0, 0, 74, T)] + legs4(180, 90, 74, 6, 3, L, square=True) + [box(170, 80, 3, 0, 0, 20, L)]
    parts += [box(26, 14, 10, -66, -20, 80, mat(0x5a6470), bevel=1), box(40, 8, 4, 30, 20, 80, mat(0xb08a5a)), cyl(1.5, 20, 10, -10, 82, mat(0xc04030), verts=6, rot=(0, 90, 0))]
    return model(C, 'workbench', parts)


def cans_stack():
    parts = []
    for i, (x, y, z) in enumerate([(-5.5, -5.5, 0), (5.5, -5.5, 0), (-5.5, 5.5, 0), (5.5, 5.5, 0), (0, -5.5, 12), (0, 5.5, 12), (0, 0, 24)]):
        parts += [cyl(5, 12, x, y, z, mat(0xc0c4cc, 0.3, 0.8), verts=12), cyl(5.05, 7, x, y, z + 2.5, mat([0xc95b4a, 0x4a8ac8, 0xe8a040][i % 3], 0.5), verts=12)]
    return model(C, 'cans_stack', parts)


def boiler():
    parts = [cyl(40, 190, 0, 0, 0, mat(0xc8ccd2, 0.4, 0.5), verts=20), cyl(41, 4, 0, 0, 190, mat(0x9aa0aa, 0.4, 0.6), verts=20), box(20, 2, 14, 0, -40.5, 120, mat(0xe8e8e8)), sphere(3, 0, -41, 127, mat(0xd04030), seg=8, rings=6)]
    parts += [cyl(3, 40, x, 0, 194, mat(0x8a6a4a, 0.4, 0.7), verts=8) for x in (-15, 15)]
    return model(C, 'boiler', parts)


def sideboard():
    B, T = mat(0x5a3a2a, 0.6), mat(0x7a5a3a, 0.5)
    parts = [box(260, 55, 79, 0, 0, 6, B), box(264, 59, 4, 0, 0, 85, T)] + [cyl(2.5, 6, x, y, 0, mat(0x2a1e18), verts=8) for x in (-122, 122) for y in (-20, 20)]
    parts += [box(60, 1, 64, -95 + i * 63.5, -27.8, 12, mat(0x6a4a34, 0.6)) for i in range(4)] + [sphere(1.4, -72 + i * 63.5, -29, 46, mat(0xd8b040, 0.3, 0.8), seg=6, rings=4) for i in range(4)]
    return model(C, 'sideboard', parts)


def cabinet_tall():
    B = mat(0x4a3024, 0.6)
    parts = [box(56, 220, 200, 0, 0, 0, B), box(1, 100, 150, 28.5, -55, 30, mat(0xcfe0ee, 0.05, 0, 0.4)), box(1, 100, 150, 28.5, 55, 30, mat(0xcfe0ee, 0.05, 0, 0.4))]
    parts += [box(40, 200, 2, 0, 0, z, B) for z in (80, 130)] + [cyl(5, 10, 10, y, 82, mat(0xf0ece2), verts=10) for y in (-70, -40, 40, 70)]
    return model(C, 'cabinet_tall', parts)


def bar_cart():
    M = mat(0xd8b040, 0.3, 0.8)
    parts = [box(70, 52, 2, 0, 0, z, mat(0x3a2a24, 0.5)) for z in (20, 60)] + [cyl(1.2, 60, x, y, 2, M, verts=6) for x in (-33, 33) for y in (-24, 24)]
    parts += [torus(5, 1.2, x, y, 5, mat(0x1a1a1a), seg=10, rseg=4, rot=(90, 0, 0)) for x in (-30, 30) for y in (-24, 24)]
    parts += [cyl(4, 18, x, 0, 62, mat(c, 0.15, 0, 0.8), verts=10) for x, c in [(-20, 0x3a6a3a), (-6, 0x8a2a3a)]]
    return model(C, 'bar_cart', parts)


def bed_kid():
    W = mat(0xe8e0d0, 0.6)
    parts = [box(240, 150, 30, 0, 0, 10, W)] + legs4(240, 150, 10, 6, 3, mat(0x9a7a5a), square=True) + [box(6, 150, 80, 117, 0, 0, W, bevel=1), box(6, 150, 50, -117, 0, 0, W, bevel=1)]
    parts += [box(230, 145, 12, 0, 0, 40, mat(0xf4f0e8, 0.9), bevel=3)]
    movable = {'blanket': [box(170, 152, 4, -30, 0, 50, mat(0x6a9ad8, 0.95), bevel=1.5), box(170, 2, 20, -30, -76, 34, mat(0x6a9ad8, 0.95))],
               'pillow': [box(40, 60, 10, 90, 0, 52, mat(0xf4f0e8, 0.9), bevel=4)]}
    return model(C, 'bed_kid', parts, movable)


def desk():
    T = mat(0xc8a070, 0.6)
    parts = [box(170, 90, 4, 0, 0, 71, T, bevel=0.6), box(4, 86, 71, -81, 0, 0, T), box(50, 86, 71, 58, 0, 0, mat(0xb89060))] + [box(46, 1, 20, 58, -43.5, z, mat(0xa8804a)) for z in (8, 30, 50)]
    parts += [cyl(8, 2, -50, 20, 75, mat(0x3a6ac8), verts=12), seg((-50, 20, 77), (-45, 15, 110), 1, 1, mat(0x3a6ac8)), cyl(9, 10, -42, 10, 108, mat(0x3a6ac8), verts=12, r2=5)]
    parts += [cyl(0.5, 14, x, -20, 75, mat(c), verts=6) for x, c in [(-10, 0xe84a5a), (-8, 0xf2c84a), (-6, 0x4a9ae8)]] + [box(30, 22, 1.5, 10, 5, 75, mat(0xf4f0e8))]
    return model(C, 'desk', parts)


def toy_chest():
    return model(C, 'toy_chest', [box(60, 50, 40, 0, 0, 0, mat(0xe8664a, 0.7), bevel=1.5), box(62, 52, 5, 0, 0, 40, mat(0xf2c84a, 0.6), bevel=1.5),
                                  box(14, 1, 10, 0, -25.5, 26, mat(0x4a9ae8)), sphere(4, 20, -26, 14, mat(0x6ac46a), seg=8, rings=6)])


def wall_doorway():
    W, T = mat(0xd8d0c8, 0.9), mat(0x5a4436)
    parts = [box(240, 8, 230, -180, 0, 0, W), box(240, 8, 230, 180, 0, 0, W), box(120, 8, 20, 0, 0, 210, W), box(600, 9, 10, 0, 0, 0, T)]
    parts += [box(6, 10, 210, x, 0, 0, T) for x in (-60, 60)] + [box(126, 10, 6, 0, 0, 210, T)]
    return model(C, 'wall_doorway', parts)


ALL = [lambda: counter_section(), lambda: counter_section(sink=True), lambda: counter_section(corner=True), fridge, kitchen_island,
       lambda: table('table_kitchen', 200, 130, 79, cloth=0xc95b4a), chair, stool, low_shelf, lambda: cardboard_box('cardboard_box', 44, 44, 44),
       lambda: cardboard_box('cardboard_box_tall', 60, 50, 92), sofa, lambda: sofa('armchair', 96, 96, 0x9a5a48, 14, 1), coffee_table, tv_stand, side_table, ottoman,
       bookcase, fireplace, floor_lamp, plant, shelf_unit, washer, lambda: washer(True), laundry_basket, crate, workbench, cans_stack, boiler,
       lambda: table('table_dining', 300, 160, 79, top=0x5a3a2a, leg=0x3a2418, cloth=0xd8d0c0, cloth_drop=30), sideboard, cabinet_tall, bar_cart,
       lambda: table('table_folding', 200, 110, 79, top=0xd8dce4, leg=0x9aa0aa), bed_kid, desk, toy_chest, beanbag, wall_doorway]
