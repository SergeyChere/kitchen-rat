"""Small items: food, finds for the nest, traps, noisy things and things that fall. Sizes in cm."""
import math
import random

from lib import box, cyl, sphere, ico, torus, plane, wedge, seg, mat, model

random.seed(7)
P = 'props'
WHITE = 0xf4f0ea
F = 'food'
N = 'finds'

# ---------------- food ----------------
def crumb():
    m = mat(0xd8b070)
    return model(F, 'crumb', [ico(1.5, 0, 0, 1, m, sub=1, scale=(1.1, 0.9, 0.7)), ico(0.8, 1.6, 0.6, 0.6, m, sub=1)])

def cheese(poison=False):
    m = mat(0xf2c84a if not poison else 0x8ad04a, 0.6)
    hole = mat(0xc89a2a if not poison else 0x5a9a2a, 0.8)
    parts = [wedge(9, 6, 5, 0, 0, 0, m)]
    for (x, z, r) in [(-2, 2, 0.9), (1.8, 3.2, 0.7), (0.4, 1.2, 0.6)]:
        parts.append(cyl(r, 0.3, x, -3.05, z, hole, verts=8, rot=(90, 0, 0)))
    return model(F, 'cheese_poisoned' if poison else 'cheese', parts)

def plate():
    return model(F, 'plate', [cyl(15, 1, 0, 0, 0, mat(0xf0ece2, 0.4), verts=24, r2=12), cyl(10, 1.2, 0, 0, 0, mat(0xe8e2d4, 0.4), verts=24)])

def cookie():
    m, c = mat(0xc8925a), mat(0x4a2e1a)
    parts = [cyl(3, 1.2, 0, 0, 0, m, verts=14)] + [sphere(0.5, math.cos(a) * 1.6, math.sin(a) * 1.6, 1.2, c, seg=6, rings=4) for a in (0.3, 2.2, 4.1)]
    return model(F, 'cookie', parts)

def cookie_pack():
    m = mat(0x3a6ac8, 0.5)
    parts = [box(20, 8, 5, 0, 0, 0, m, bevel=0.5), box(18, 0.4, 3, 0, -4.1, 1, mat(0xf2c84a))]
    parts += [cyl(3, 1.2, 8 + i * 1.4, 0, 1.2, mat(0xc8925a), verts=12, rot=(0, 90, 0)) for i in range(2)]
    return model(F, 'cookie_pack', parts)

def sausage():
    m = mat(0xb0453a, 0.55)
    return model(F, 'sausage', [cyl(4.5, 22, 0, 0, 4.5, m, verts=12, rot=(0, 90, 0)), sphere(4.5, -11, 0, 4.5, m, seg=10, rings=6), sphere(4.5, 11, 0, 4.5, m, seg=10, rings=6),
                                cyl(1, 2, 15.5, 0, 4.5, mat(0xe8d8b0), verts=6, rot=(0, 90, 0))])

def chicken_leg():
    m, b = mat(0xc8843a, 0.6), mat(0xf0e8d8, 0.5)
    return model(F, 'chicken_leg', [sphere(7, -4, 0, 6, m, seg=12, rings=8, scale=(1.4, 1, 0.9)), cyl(1.5, 10, 7, 0, 5, b, verts=8, rot=(0, 90, 0)), sphere(2, 12, 0, 5, b, seg=8, rings=6)])

def pizza_slice():
    m, crust, pep = mat(0xf2c04a, 0.6), mat(0xc8843a), mat(0xc0392b, 0.6)
    parts = [wedge(16, 18, 1.5, 0, 0, 0, m), box(16, 2.5, 2.5, 0, -9, 0, crust, bevel=0.6)]
    parts += [cyl(1.4, 0.4, x, y, 1.5, pep, verts=10) for x, y in [(-3, -4), (2, -2), (0, 3)]]
    return model(F, 'pizza_slice', parts)

def pizza_box():
    return model(F, 'pizza_box', [box(40, 40, 5, 0, 0, 0, mat(0xd8b080), bevel=0.4), box(16, 16, 0.2, 0, 0, 5, mat(0xc0392b))])

def cake_slice():
    sp, cr, top = mat(0xf4e0c8), mat(0xffffff, 0.5), mat(0xe86a8a, 0.5)
    parts = [wedge(18, 14, 4, 0, 0, 0, sp), wedge(18, 14, 1.5, 0, 0, 4, cr), wedge(18, 14, 4, 0, 0, 5.5, sp), wedge(18, 14, 2.5, 0, 0, 9.5, top),
             sphere(1.6, 0, -4, 13, mat(0xd03040, 0.4), seg=8, rings=6)]
    return model(F, 'cake_slice', parts)

def cake_whole():
    sp, top = mat(0xf4e0c8), mat(0xe86a8a, 0.5)
    parts = [cyl(16, 10, 0, 0, 0, sp, verts=24), cyl(16.4, 2.5, 0, 0, 10, top, verts=24)]
    parts += [sphere(1.4, math.cos(a) * 12, math.sin(a) * 12, 13, mat(0xd03040, 0.4), seg=8, rings=6) for a in [i * 0.785 for i in range(8)]]
    return model(F, 'cake_whole', parts)

def potato():
    m = mat(0xb08a5a, 0.9)
    parts = [ico(8, 0, 0, 7, m, sub=2, scale=(1.3, 0.95, 0.9))] + [sphere(0.7, x, -7.3, z, mat(0x7a5a32), seg=6, rings=4) for x, z in [(-4, 7), (3, 9), (1, 5)]]
    return model(F, 'potato', parts)

def lard():
    return model(F, 'lard', [box(18, 12, 9, 0, 0, 0, mat(0xf2ead8, 0.6), bevel=1.2), box(18.2, 12.2, 1.5, 0, 0, 5, mat(0xd8a0a0))])

def dog_biscuit():
    m = mat(0xc8925a)
    return model(F, 'dog_biscuit', [box(12, 4, 4, 0, 0, 0, m, bevel=1)] + [sphere(2.6, x, y, 2, m, seg=8, rings=6) for x in (-7, 7) for y in (-1.6, 1.6)])

def kibble():
    m = mat(0x8a5a32)
    return model(F, 'kibble', [ico(1.2, random.uniform(-2.5, 2.5), random.uniform(-2.5, 2.5), 1 + (i % 3) * 0.6, m, sub=1) for i in range(12)])

def rusk():
    return model(F, 'rusk', [box(10, 5, 3, 0, 0, 0, mat(0xd8a050), bevel=0.6), box(9, 4, 0.3, 0, 0, 3, mat(0xc0843a))])

def cheese_wheel():
    m = mat(0xf2c84a, 0.6)
    return model(F, 'cheese_wheel', [cyl(7, 6, 0, 0, 0, m, verts=20), cyl(7.1, 0.8, 0, 0, 2.6, mat(0xc04030), verts=20)])

# ---------------- finds for the nest ----------------
def button():
    m = mat(0xe8b84a, 0.3, 0.6)
    parts = [cyl(1.5, 0.5, 0, 0, 0, m, verts=16)] + [cyl(0.25, 0.7, x, y, 0, mat(0x6a4a10), verts=6) for x, y in [(-0.4, -0.4), (0.4, -0.4), (-0.4, 0.4), (0.4, 0.4)]]
    return model(N, 'button', parts)

def sock():
    m, s = mat(0xd84a6a), mat(0xf2e8e0)
    return model(N, 'sock', [box(11, 5, 2.5, -2, 0, 0, m, bevel=1), box(5, 9, 2.5, 4.5, 2, 0, m, bevel=1), box(3, 5, 2.6, -7, 0, 0, s, bevel=0.8)])

def toy_mouse():
    g = mat(0x9a9aa8)
    return model(N, 'toy_mouse', [sphere(2.2, 0, 0, 2, g, seg=10, rings=6, scale=(1.7, 1, 0.9)), sphere(1, -2.5, -1, 3.4, mat(0xe8a0b0), seg=8, rings=6), sphere(1, -2.5, 1, 3.4, mat(0xe8a0b0), seg=8, rings=6),
                                  cyl(0.25, 5, 5.5, 0, 1.2, mat(0x5a5a64), verts=5, rot=(0, 90, 0))])

def thimble():
    return model(N, 'thimble', [cyl(1.25, 2.5, 0, 0, 0, mat(0xc8ccd4, 0.3, 0.8), verts=14, r2=1.05), sphere(1.05, 0, 0, 2.5, mat(0xc8ccd4, 0.3, 0.8), seg=12, rings=6, scale=(1, 1, 0.5))])

def flat_paper(name, w, h, col, pic):
    return model(N, name, [box(w, h, 0.2, 0, 0, 0, mat(col, 0.9)), box(w * 0.7, h * 0.55, 0.05, 0, 0, 0.2, mat(pic, 0.9))])

def marble():
    return model(N, 'marble', [sphere(1, 0, 0, 1, mat(0x4a9ae8, 0.1, 0, 0.85), seg=12, rings=8), sphere(0.5, 0.2, -0.2, 1.1, mat(0xf2c84a, 0.2), seg=8, rings=6)])

def bottle_cap():
    m = mat(0xc04030, 0.3, 0.7)
    return model(N, 'bottle_cap', [cyl(1.5, 0.6, 0, 0, 0, m, verts=18), cyl(1.6, 0.25, 0, 0, 0, m, verts=10)])

def battery():
    return model(N, 'battery', [cyl(0.75, 4.2, 0, 0, 0.75, mat(0x2a2a2a, 0.4), verts=12, rot=(0, 90, 0)), cyl(0.76, 1, 2.5, 0, 0.75, mat(0xc8a030, 0.3, 0.6), verts=12, rot=(0, 90, 0)),
                                cyl(0.3, 0.4, 3.2, 0, 0.75, mat(0xc8ccd4, 0.3, 0.8), verts=8, rot=(0, 90, 0))])

def key():
    m = mat(0xd8b040, 0.3, 0.8)
    return model(N, 'key', [torus(1, 0.35, -2, 0, 0.35, m, seg=12, rseg=4), box(3.4, 0.6, 0.5, 1, 0, 0, m), box(0.5, 0.9, 0.5, 2.2, 0.6, 0, m), box(0.5, 0.7, 0.5, 1.4, 0.5, 0, m)])

def ring():
    return model(N, 'ring', [torus(0.85, 0.2, 0, 0, 0.85, mat(0xf0c040, 0.2, 0.9), seg=16, rseg=6, rot=(90, 0, 0)), sphere(0.35, 0, 0, 1.85, mat(0xd0f0ff, 0.05), seg=8, rings=6)])

def earring():
    return model(N, 'earring', [torus(0.8, 0.12, 0, 0, 1.6, mat(0xf0c040, 0.2, 0.9), seg=12, rseg=4, rot=(90, 0, 0)), sphere(0.5, 0, 0, 0.5, mat(0x60c0e0, 0.1), seg=8, rings=6)])

def whistle():
    m = mat(0xe84a5a, 0.4)
    return model(N, 'whistle', [cyl(1, 3.5, 0, 0, 1, m, verts=10, rot=(0, 90, 0)), cyl(0.6, 1.8, 2.4, 0, 1.2, mat(0xf2c84a), verts=8, rot=(0, 90, 0))])

def cufflink():
    return model(N, 'cufflink', [cyl(1, 0.4, 0, 0, 0.8, mat(0xc8ccd4, 0.2, 0.9), verts=14), cyl(0.3, 0.8, 0, 0, 0, mat(0xc8ccd4, 0.2, 0.9), verts=6)])

def toy_dino():
    g = mat(0x6ac46a, 0.5)
    parts = [sphere(1.6, 0, 0, 2, g, seg=10, rings=6, scale=(1.6, 1, 1)), sphere(0.9, 2.4, 0, 3.6, g, seg=8, rings=6), cyl(0.5, 2, 2, 0, 2.6, g, verts=6, rot=(0, 40, 0)),
             cyl(0.4, 2.5, -3, 0, 1.6, g, verts=6, rot=(0, -70, 0), r2=0.1)]
    parts += [cyl(0.45, 1.4, x, y, 0, g, verts=6) for x in (-1, 1) for y in (-0.8, 0.8)]
    return model(N, 'toy_dino', parts)

def toy_car():
    b = mat(0xe84a3a, 0.4)
    parts = [box(6, 3, 1.4, 0, 0, 0.6, b, bevel=0.3), box(3, 2.6, 1, -0.3, 0, 2, mat(0x8ac8e8, 0.2))]
    parts += [cyl(0.6, 0.5, x, y, 0.6, mat(0x1a1a1a), verts=10, rot=(90, 0, 0)) for x in (-2, 2) for y in (-1.6, 1.6)]
    return model(N, 'toy_car', parts)

def candle():
    return model(N, 'candle', [cyl(0.75, 7, 0, 0, 0, mat(0x7ac0e8, 0.5), verts=10), cyl(0.1, 0.8, 0, 0, 7, mat(0x2a2a2a), verts=4), sphere(0.35, 0, 0, 8.2, mat(0xffd070, 0.5, 0, 1, 3), seg=6, rings=4, scale=(1, 1, 1.6))])

def silver_spoon():
    m = mat(0xd8dce4, 0.15, 1)
    return model(N, 'silver_spoon', [box(8, 0.8, 0.3, -2, 0, 0, m), sphere(1.5, 3.5, 0, 0.4, m, seg=10, rings=6, scale=(1.4, 1, 0.3))])

def chew_toy():
    m = mat(0xe84a8a, 0.6)
    return model(N, 'chew_toy', [cyl(1.2, 7, 0, 0, 1.4, m, verts=8, rot=(0, 90, 0))] + [sphere(1.5, x, y, 1.5, m, seg=8, rings=6) for x in (-4, 4) for y in (-1, 1)])

# ---------------- things that fall ----------------
def mug(broken=False):
    m, ink = mat(0xf2e8d4, 0.4), mat(0x2a2422, 0.6)
    rat = [box(3.2, 0.3, 1.8, 0.3, -4.95, 3.4, ink), box(1.6, 0.3, 1.4, -1.8, -4.95, 4, ink), box(0.6, 0.3, 0.8, -1.8, -4.95, 5.3, ink),
           box(2.4, 0.3, 0.3, 2.9, -4.95, 3.2, ink, rot=(0, -20, 0)), box(0.4, 0.3, 0.6, -0.6, -4.95, 2.9, ink), box(0.4, 0.3, 0.6, 1.2, -4.95, 2.9, ink)]
    if broken:
        parts = [cyl(4.6, 3.5, 0, 0, 0, m, verts=14), box(4, 0.6, 5, 6, 2, 0, m, rot=(0, 0, 30)), box(3.6, 0.6, 4, -6, -3, 0, m, rot=(0, 20, -40)), box(2.5, 0.6, 3, 1, 7, 0, m, rot=(0, 0, 70)),
                 box(2.6, 0.4, 1.4, -6, -3.4, 1.6, ink, rot=(0, 20, -40))]
        return model(P, 'mug_broken', parts)
    return model(P, 'mug', [cyl(4.8, 9, 0, 0, 0, m, verts=16), torus(2.6, 0.9, 5.8, 0, 5, m, seg=12, rseg=6, rot=(90, 0, 0)), cyl(4.3, 0.3, 0, 0, 8.6, mat(0x4a2a18, 0.2), verts=16)] + rat)

def jar():
    glass = mat(0xd8e8f0, 0.05, 0, 0.35)
    cookies = [cyl(2.6, 0.9, x, y, z, mat(0xc8904a, 0.9), verts=10, rot=(rx, 0, 0)) for x, y, z, rx in [(-2, -1, 1, 10), (2, 1, 1.5, -15), (0, -2, 4, 30), (-2, 2, 5, -20), (2, -1, 7, 15), (0, 1, 9, -10)]]
    chips = [sphere(0.5, x, y - 0.5, z + 0.9, mat(0x3a2014), seg=4, rings=3) for x, y, z, rx in [(-2, -1, 1, 0), (2, 1, 1.5, 0), (0, -2, 4, 0), (2, -1, 7, 0)]]
    return model(P, 'jar', [cyl(6, 13, 0, 0, 0, glass, verts=16), cyl(5.2, 1.5, 0, 0, 13, glass, verts=16), cyl(6.2, 2.6, 0, 0, 14, mat(0xc8302e, 0.4), verts=16),
                            cyl(6.3, 0.6, 0, 0, 14.3, mat(0xe8e0d0, 0.5), verts=16)] + cookies + chips)

def apple():
    return model(P, 'apple', [sphere(8, 0, 0, 8, mat(0xc93b2e, 0.4), seg=14, rings=10, scale=(1, 1, 0.92)), cyl(0.6, 4, 0, 0, 15, mat(0x5a3a1a), verts=6), sphere(2, 1.8, 0, 17.5, mat(0x5ab04a), seg=6, rings=4, scale=(1.6, 0.6, 0.4))])

def can():
    tin, lab = mat(0xd0d4dc, 0.25, 0.85), mat(0xc8302e, 0.5)
    tom = [sphere(1.4, math.cos(a) * 5.05, math.sin(a) * 5.05, 6, mat(0xe84a3a, 0.4), seg=8, rings=6, scale=(1, 1, 1)) for a in (-1.9, -1.3, -0.7)]
    return model(P, 'can', [cyl(5, 12, 0, 0, 0, tin, verts=16), cyl(5.05, 8, 0, 0, 2, lab, verts=16), cyl(5.08, 1.6, 0, 0, 7.6, mat(0xf2e8d0, 0.5), verts=16),
                            torus(4.6, 0.3, 0, 0, 12, tin, seg=16, rseg=4)] + tom + [sphere(0.6, math.cos(a) * 5.1, math.sin(a) * 5.1, 7.3, mat(0x4a9a3a), seg=6, rings=4) for a in (-1.9, -1.3, -0.7)])

def small_box():
    return model(P, 'small_box', [box(20, 16, 16, 0, 0, 0, mat(0xc89a5a, 0.9), bevel=0.4), box(20.4, 0.4, 3, 0, 0, 13, mat(0xa8784a)), box(1, 16.4, 16.2, 0, 0, 0, mat(0xe0d0a0))])

def glass():
    g = mat(0xdceaf2, 0.05, 0, 0.35)
    return model(P, 'glass', [cyl(4, 12, 0, 0, 1.4, g, verts=10, r2=4.7), cyl(4, 1.4, 0, 0, 0, mat(0xdceaf2, 0.05, 0, 0.55), verts=10), torus(4.6, 0.25, 0, 0, 13.4, g, seg=10, rseg=4)])

def spoon():
    m = mat(0xc8ccd4, 0.25, 0.9)
    return model(P, 'spoon', [box(12, 1.2, 0.5, -3, 0, 0, m), sphere(2.6, 5.5, 0, 0.6, m, seg=10, rings=6, scale=(1.3, 0.9, 0.3))])

def ball():
    return model(P, 'ball', [sphere(6, 0, 0, 6, mat(0xd8343a, 0.4), seg=16, rings=10), cyl(6.05, 3.6, 0, 0, 4.2, mat(0xf4f0ea, 0.4), verts=20),
                             cyl(5.6, 0.8, 0, 0, 2.6, mat(0xf4f0ea, 0.4), verts=20), cyl(5.6, 0.8, 0, 0, 8.6, mat(0xf4f0ea, 0.4), verts=20)])

def bottle():
    g = mat(0x2e6a3a, 0.15, 0, 0.75)
    return model(P, 'bottle', [cyl(4, 18, 0, 0, 0, g, verts=14), cyl(4, 3, 0, 0, 18, g, verts=14, r2=1.4), cyl(1.4, 5, 0, 0, 21, g, verts=10), cyl(1.5, 1.4, 0, 0, 25.6, mat(0xc8a060, 0.8), verts=10),
                               box(6.4, 0.2, 7, 0, -4, 5, mat(0xf0e4c0)), box(4.4, 0.25, 0.8, 0, -4.05, 9, mat(0x5a2a1a)), box(3.4, 0.25, 0.5, 0, -4.05, 7.4, mat(0x5a2a1a)),
                               box(2.6, 0.2, 2, 0, -2.6, 19.4, mat(0xf0e4c0), rot=(-20, 0, 0))])
# ---------------- traps and noisy things ----------------
def mousetrap():
    wood, metal = mat(0xd2ab72), mat(0xbfc6d2, 0.3, 0.8)
    base = [box(26, 14, 1.5, 0, 0, 0, wood, bevel=0.3), box(3, 3, 0.8, 4, 0, 1.5, mat(0xf2c84a)), cyl(0.5, 12, -2, 0, 2.1, metal, verts=6, rot=(90, 0, 0))]
    bar = [box(0.6, 12, 0.6, -11, 0, 2, metal), box(9, 0.6, 0.6, -6.5, -5.7, 2, metal), box(9, 0.6, 0.6, -6.5, 5.7, 2, metal)]
    return model(P, 'mousetrap', base, movable={'bar': bar})

def napkin():
    w, r = mat(0xf4f0e8, 0.9), mat(0xc8302e, 0.8)
    parts = [box(30, 30, 0.6, 0, 0, 0, w, bevel=0.2, rot=(0, 0, 12)), box(14, 30, 0.7, 6, 0, 0.3, w, rot=(0, 0, 12))]
    for d in (-12, -10.6):
        parts += [box(30, 0.7, 0.7, -math.sin(math.radians(12)) * d, math.cos(math.radians(12)) * d, 0.1, r, rot=(0, 0, 12)),
                  box(0.7, 30, 0.7, math.cos(math.radians(12)) * d, math.sin(math.radians(12)) * d, 0.1, r, rot=(0, 0, 12))]
    return model(P, 'napkin', parts)

def foil():
    m, m2 = mat(0xe4e8f0, 0.2, 0.35), mat(0xccd0da, 0.25, 0.35)
    parts = []
    for i in range(26):
        parts.append(box(random.uniform(14, 30), random.uniform(10, 22), 0.6, random.uniform(-65, 65), random.uniform(-20, 20), random.uniform(0, 1.4), m if i % 3 else m2,
                         rot=(random.uniform(-10, 10), random.uniform(-10, 10), random.uniform(0, 180))))
    return model(P, 'foil', parts)

def bread_box():
    wood, light, dark = mat(0x8a5530, 0.6), mat(0xb07a48, 0.6), mat(0x5a3418, 0.7)
    loaf = mat(0xc8843a, 0.8)
    parts = [box(56, 34, 4, 0, 0, 0, wood, bevel=1), box(4, 34, 30, -26, 0, 0, wood, bevel=1), box(4, 34, 30, 26, 0, 0, wood, bevel=1), box(56, 4, 30, 0, 15, 0, wood),
             cyl(17, 56, 0, 2, 22, wood, verts=16, rot=(0, 90, 0)), box(52, 26, 2, 0, 2, 4, light)]
    parts += [box(52, 0.6, 1.2, 0, 2 - 17 * math.cos(math.radians(a)), 22 + 17 * math.sin(math.radians(a)), dark, rot=(a - 90, 0, 0)) for a in (40, 70, 100, 130)]  # roll-top slats
    parts += [ico(8, x, -2, 10, loaf, sub=2, scale=(1.3, 1, 0.75)) for x in (-11, 11)] + [box(10, 2, 2, 0, -17, 30, mat(0xd8c8a8, 0.4, 0.4))]
    return model(P, 'bread_box', parts)

def tv_remote():
    cols = [0xd83a3a, 0x4ac84a, 0xf2c84a, 0x4a8ae8]
    return model(P, 'tv_remote', [box(5, 12, 1.8, 0, 0, 0, mat(0x1a1a1e, 0.5), bevel=0.6), cyl(0.8, 0.4, 0, -4.3, 1.8, mat(0xd83a3a), verts=10)] +
                 [box(0.9, 0.9, 0.3, x, y, 1.8, mat(0x5a5a64)) for x in (-1.2, 0, 1.2) for y in (-0.6, 0.9, 2.4, 3.9)] + [box(0.8, 0.5, 0.3, -1.5 + i, -2.4, 1.8, mat(c)) for i, c in enumerate(cols)])

def squeaky_toy():
    y = mat(0xf2c84a, 0.4)
    return model(P, 'squeaky_toy', [sphere(5, 0, 0, 4.5, y, seg=14, rings=8, scale=(1.2, 1, 0.9)), sphere(3.2, 4, 0, 9.5, y, seg=12, rings=8), box(3, 2.4, 1.2, 7.5, 0, 9, mat(0xe87a2a)),
                                    sphere(0.5, 5.7, -1.4, 10.6, mat(0x1a1a1a), seg=6, rings=4), sphere(0.5, 5.7, 1.4, 10.6, mat(0x1a1a1a), seg=6, rings=4)])

def floorboard_worn():
    m, d = mat(0x9a7454, 0.9), mat(0x3a2618)
    return model(P, 'floorboard_worn', [box(120, 18, 0.6, 0, 0, 0, m)] + [box(0.8, 12, 0.7, x, 0, 0, d) for x in (-45, 15, 50)] + [cyl(0.6, 0.7, x, 0, 0, d, verts=6) for x in (-58, 58)])

def plastic_bag():
    m = mat(0xe8e4dc, 0.4, 0, 0.9)
    return model(P, 'plastic_bag', [ico(12, -6, 0, 3, m, sub=1, scale=(1.4, 1, 0.3)), ico(10, 9, 4, 2.5, m, sub=1, scale=(1.2, 1.1, 0.35)), ico(6, 2, -10, 2, m, sub=1, scale=(1, 1, 0.4))])

def grain_sack(open_=False):
    burlap, tie, mark = mat(0xc8a46a, 1), mat(0xb04a3a), mat(0x6a4a24, 0.9)
    if open_:
        spill = [box(1.4, 1, 0.8, 10 + random.uniform(-8, 10), -12 + random.uniform(-6, 6), 0, mat(0xe0b850), rot=(0, 0, random.uniform(0, 90))) for _ in range(40)]
        return model(P, 'grain_sack_open', [box(26, 18, 18, 0, 0, 0, burlap, bevel=3), cyl(9, 5, 4, -6, 6, burlap, verts=10, rot=(70, 0, 0)), ico(6, 8, -10, 1, mat(0xe0b850), sub=1, scale=(1.6, 1, 0.4))] + spill)
    return model(P, 'grain_sack', [box(26, 18, 26, 0, 0, 0, burlap, bevel=4), cyl(5, 4, 0, 0, 26, burlap, verts=8, r2=3), torus(3.5, 0.6, 0, 0, 27.5, tie, seg=10, rseg=4),
                                   box(1, 0.4, 9, 0, -9.1, 7, mark), box(4, 0.4, 1, -1.5, -9.1, 12, mark, rot=(0, 40, 0)), box(4, 0.4, 1, 1.5, -9.1, 12, mark, rot=(0, -40, 0)),
                                   box(4, 0.4, 1, -1.5, -9.1, 9.5, mark, rot=(0, 40, 0)), box(4, 0.4, 1, 1.5, -9.1, 9.5, mark, rot=(0, -40, 0))])

def grain_spill():
    m = mat(0xe0c890)
    return model(P, 'grain_spill', [box(1.4, 1, 0.8, math.cos(a) * d, math.sin(a) * d, 0, m, rot=(0, 0, a * 50)) for a, d in [(random.uniform(0, 6.28), math.sqrt(random.random()) * 30) for _ in range(70)]])

def lamp_cord():
    m = mat(0x1a1a1a, 0.5)
    pts = [(-60 + i * 10, math.sin(i * 0.9) * 3) for i in range(13)]
    parts = [cyl(0.9, 10.5, (a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0.9, m, verts=6, rot=(0, 90, math.degrees(math.atan2(b[1] - a[1], b[0] - a[0])))) for a, b in zip(pts, pts[1:])]
    parts.append(box(4, 3, 3, 62, 0, 0, mat(0xf0ece2)))
    return model(P, 'lamp_cord', parts)

def puddle():
    return model(P, 'puddle', [cyl(25, 0.3, 0, 0, 0, mat(0x8ab4e0, 0.05, 0, 0.45), verts=20), cyl(12, 0.32, 18, 8, 0, mat(0x8ab4e0, 0.05, 0, 0.45), verts=14)])

def cat_bed():
    f, c, p = mat(0x5a3a8a, 0.9), mat(0xe8d8b8, 1), mat(0xf4f0ea, 0.8)
    return model(P, 'cat_bed', [torus(24, 7, 0, 0, 7, f, seg=20, rseg=8), cyl(24, 5, 0, 0, 0, f, verts=20), cyl(19, 2, 0, 0, 4.5, c, verts=20), torus(22, 3, 0, 0, 12.5, c, seg=20, rseg=6),
                                box(7, 1, 6, 0, -30.6, 4, p, bevel=0.6)] + [sphere(1, x, -31.3, z, mat(0x5a3a8a), seg=6, rings=4, scale=(1, 0.3, 1)) for x, z in [(-2, 8), (0, 8.6), (2, 8), (0, 6)]])

def cat_bowl(dog=False):
    r = 22 if dog else 16
    col, food = (0x2a5ac8 if dog else 0xc8302e), mat(0x8a5a2a)
    parts = [cyl(r, 6, 0, 0, 0, mat(col, 0.35), verts=20, r2=r - 3), torus(r - 3, 0.8, 0, 0, 6, mat(col, 0.35), seg=20, rseg=4), cyl(r - 4, 0.5, 0, 0, 5.2, food, verts=16)]
    if dog:  # white bone on the side
        parts += [box(8, 0.6, 2, 0, -r + 1.2, 2.2, mat(WHITE), rot=(-12, 0, 0))] + [sphere(1.4, x, -r + 1.4, z, mat(WHITE), seg=6, rings=4, scale=(1, 0.4, 1)) for x in (-4, 4) for z in (2.4, 3.8)]
    else:  # white paw
        parts += [sphere(1.8, 0, -r + 1.6, 2.6, mat(WHITE), seg=8, rings=4, scale=(1, 0.4, 0.8))] + [sphere(0.8, x, -r + 1.7, 4.6 - abs(x) * 0.3, mat(WHITE), seg=6, rings=4, scale=(1, 0.4, 1)) for x in (-2, -0.7, 0.7, 2)]
    return model(P, 'dog_bowl' if dog else 'cat_bowl', parts)

def bucket_mop():
    steel, wood, mop = mat(0xb8bcc4, 0.3, 0.4), mat(0xc8904a, 0.6), mat(0xf0ead8, 1)
    parts = [cyl(15, 30, 0, 0, 0, steel, verts=16, r2=13), torus(15, 0.8, 0, 0, 30, steel, seg=16, rseg=4), torus(14, 0.5, 0, 0, 8, mat(0x9aa0a8, 0.3, 0.4), seg=16, rseg=4),
             cyl(13, 0.4, 0, 0, 24, mat(0x8ab4d0, 0.1, 0, 0.6), verts=16), torus(9, 0.5, 0, -8, 32, steel, seg=12, rseg=4, rot=(90, 0, 0)),
             seg((30, 0, 6), (6, 0, 95), 1.2, 1.2, wood, verts=8)]
    parts += [seg((30, 0, 6), (30 + math.cos(a) * 9, math.sin(a) * 9, 0.6), 1.1, 0.9, mop, verts=5) for a in [i * 0.63 for i in range(10)]]
    return model(P, 'bucket_mop', parts)

def flashlight():
    body, chrome = mat(0x1e1e22, 0.4), mat(0xd0d4dc, 0.2, 0.9)
    return model(P, 'flashlight', [cyl(2, 14, -2, 0, 2.5, body, verts=12, rot=(0, 90, 0)), cyl(2.5, 6, 8, 0, 2.5, body, verts=12, rot=(0, 90, 0), r2=3.2),
                                   cyl(3.3, 1.2, 11.2, 0, 2.5, chrome, verts=12, rot=(0, 90, 0)), cyl(2.9, 0.4, 11.9, 0, 2.5, mat(0xfff0c0, 0.2, 0, 1, 3), verts=12, rot=(0, 90, 0)),
                                   box(2, 1, 1, 2, 0, 4.4, mat(0x5a5a64))] + [cyl(2.05, 0.6, x, 0, 2.5, mat(0x3a3a40), verts=12, rot=(0, 90, 0)) for x in (-6, -4, -2)])

def hangers():
    m = mat(0xb8bcc4, 0.3, 0.8)
    parts = []
    for i, (x, y, a) in enumerate([(-12, 0, 10), (2, 5, -20), (13, -3, 40)]):
        parts.append(box(16, 0.5, 0.5, x, y, 0, m, rot=(0, 0, a)))
        parts.append(box(9, 0.5, 0.5, x - 3, y + 3, 0, m, rot=(0, 0, a + 35)))
        parts.append(box(9, 0.5, 0.5, x + 3, y + 3, 0, m, rot=(0, 0, a - 35)))
    return model(P, 'hangers', parts)

def balloon(col, name):
    m = mat(col, 0.3)
    return model(P, name, [sphere(9, 0, 0, 15, m, seg=16, rings=10, scale=(1, 1, 1.18)), cyl(1, 2, 0, 0, 3.5, m, verts=6, r2=0.4), cyl(0.1, 3.5, 0, 0, 0, mat(0xe8e4dc), verts=4)])

def confetti():
    cols = [0xe84a5a, 0x4a9ae8, 0xf2c84a, 0x6ac46a, 0xd88ab0]
    return model(P, 'confetti', [box(2, 1.4, 0.2, random.uniform(-40, 40), random.uniform(-25, 25), 0, mat(cols[i % 5], 0.5), rot=(0, 0, random.uniform(0, 180))) for i in range(70)])

def sticky_tape():
    return model(P, 'sticky_tape', [box(90, 56, 0.6, 0, 0, 0, mat(0xd8c8a0, 0.9)), box(84, 50, 0.3, 0, 0, 0.6, mat(0xe8d070, 0.1, 0, 0.8))])

def lego_bricks():
    cols = [0xe84a5a, 0x4a9ae8, 0xf2c84a, 0x6ac46a]
    parts = []
    for i in range(14):
        x, y, r = random.uniform(-22, 22), random.uniform(-22, 22), random.uniform(0, 90)
        m = mat(cols[i % 4], 0.35)
        parts.append(box(4, 2, 1.8, x, y, 0, m, rot=(0, 0, r)))
        ca, sa = math.cos(math.radians(r)), math.sin(math.radians(r))
        parts += [cyl(0.45, 0.5, x + ca * dx, y + sa * dx, 1.8, m, verts=8) for dx in (-1, 1)]
    return model(P, 'lego_bricks', parts)

def music_box():
    p, g = mat(0xd88ab0, 0.5), mat(0xf2d06a, 0.3, 0.6)
    return model(P, 'music_box', [box(12, 9, 7, 0, 0, 0, p, bevel=0.5), box(12.4, 9.4, 1.5, 0, 0, 7, g), cyl(0.4, 3, 6.5, 0, 3.5, g, verts=6, rot=(0, 90, 0)),
                                  sphere(1.2, 0, 0, 9.5, mat(0xf4e8f0), seg=8, rings=6)])

def night_light():
    return model(P, 'night_light', [box(7, 2, 9, 0, 0, 0, mat(0xf0e4c8, 0.5), bevel=0.6), sphere(3.4, 0, -2.4, 5.4, mat(0xffd860, 0.3, 0, 1, 2.5), seg=12, rings=8, scale=(1, 0.6, 1)),
                                    sphere(2.6, 1.2, -4.2, 6, mat(0xf0e4c8, 0.5), seg=10, rings=6, scale=(1, 0.3, 1)), box(0.6, 1.4, 2, x, 1.6, 3.5, mat(0xc8ccd4, 0.3, 0.8)) if False else box(1, 0.5, 1, 0, -1.2, 1, mat(0xc8ccd4))]
                 + [box(0.6, 2, 2.4, x, 1.8, 3.5, mat(0xc8ccd4, 0.3, 0.8)) for x in (-1.4, 1.4)])

def backpack(open_=False):
    b, s, zip_ = mat(0x2f5ab8, 0.7), mat(0x24468e, 0.7), mat(0xd8b050, 0.3, 0.8)
    parts = [box(30, 16, 32, 0, 0, 0, b, bevel=5), box(22, 5, 14, 0, -9.5, 3, s, bevel=2), box(20, 0.6, 0.8, 0, -12.2, 12, zip_), box(26, 0.6, 0.8, 0, -8.3, 27, zip_),
             box(5, 10, 10, -16, 0, 4, s, bevel=1.5), box(5, 10, 10, 16, 0, 4, s, bevel=1.5), torus(3, 0.7, 0, 1, 32.4, s, seg=10, rseg=4, rot=(90, 0, 0))]
    parts += [box(3, 0.8, 7, -7, -12.4, 6, mat(WHITE)), box(2, 0.9, 2.6, -7, -12.5, 13, mat(0xd8343a)), box(5, 0.9, 1.6, -7, -12.5, 5, mat(0xd8343a)),            # rocket patch
              cyl(2, 0.8, 6, -12.4, 9, mat(0xf2c84a), verts=5, rot=(90, 0, 0)), cyl(1.6, 0.8, 7, -8.4, 22, mat(0xd8343a), verts=10, rot=(90, 0, 0))]               # star and badge patches
    if open_:
        parts += [box(26, 12, 1, 0, 1, 33, b, rot=(-40, 0, 0)), box(20, 8, 6, 0, 1, 27, mat(0xe8e0c8)), box(4, 8, 7, -6, 1, 27, mat(0x4a9a4a)), box(3, 8, 7, 5, 1, 27, mat(0xd8343a)),
                  cyl(3, 1.2, -6, -16, 0, mat(0xd8a050, 0.3, 0.8), verts=12), cyl(3, 1.2, 4, -18, 0, mat(0xd8a050, 0.3, 0.8), verts=12)]
        return model(P, 'backpack_open', parts)
    parts += [box(3, 1.6, 24, x, 8.6, 3, s, bevel=0.5) for x in (-8, 8)]
    return model(P, 'backpack', parts)

def party_popper():
    cols = [0xe84a5a, 0xf2c84a, 0x4a9ae8, 0x6ac46a]
    parts = [cyl(2.6 - i * 0.35, 2.4, 0, 0, i * 2.3, mat(cols[i % 4], 0.4), verts=12, r2=2.6 - (i + 1) * 0.35) for i in range(4)] + [cyl(2.8, 1.2, 0, 0, 8.8, mat(0xe84a5a, 0.4), verts=12)]
    parts += [box(0.6, 0.6, 6, math.cos(a) * 1.4, math.sin(a) * 1.4, 10, mat(cols[i % 4], 0.4), rot=(math.sin(a) * 30, math.cos(a) * 30, 0)) for i, a in enumerate([0, 1.6, 3.2, 4.8])]
    parts.append(cyl(0.2, 3, 0, 0, -3, mat(0xf2e8e0), verts=4))
    return model(P, 'party_popper', parts)

def litter_box():
    t = mat(0x6aa0d8, 0.5)
    return model(P, 'litter_box', [box(60, 44, 10, 0, 0, 0, t, bevel=1.5), box(54, 38, 0.6, 0, 0, 8.4, mat(0xe0d0a8, 1)), box(62, 46, 1.4, 0, 0, 9.6, t, bevel=0.6),
                                   box(12, 7, 1, 14, 6, 9.4, mat(0xc8ccd4, 0.3, 0.6), rot=(0, -10, 20)), box(2, 14, 1, 20, 14, 10, mat(0xc8ccd4, 0.3, 0.6), rot=(20, 0, 20))])

def pipe():
    m, j = mat(0xb87048, 0.35, 0.8), mat(0x8a5030, 0.4, 0.8)
    return model(P, 'pipe', [cyl(6, 200, 0, 0, 6, m, verts=12, rot=(0, 90, 0))] + [cyl(7, 4, x, 0, 6, j, verts=12, rot=(0, 90, 0)) for x in (-90, 0, 90)])

def vent_grate():
    m = mat(0xb0b6be, 0.35, 0.8)
    return model(P, 'vent_grate', [box(32, 1.4, 22, 0, 0, 0, m, bevel=0.6), box(27, 1.2, 17, 0, -0.4, 2.5, mat(0x2a2a2a))] +
                 [box(26, 2, 1.4, 0, -0.9, z, m, rot=(30, 0, 0)) for z in (4, 7.5, 11, 14.5, 18)] + [cyl(0.7, 0.8, x, -0.9, z, m, verts=6, rot=(90, 0, 0)) for x in (-14, 14) for z in (2, 20)])

def cage_trap():
    m = mat(0xaab0b8, 0.3, 0.85)
    parts = [box(44, 44, 1, 0, 0, 0, m), box(44, 44, 0.8, 0, 0, 26, m), box(14, 2, 2, 0, 0, 31, mat(0x2a2a2a, 0.5), bevel=0.6)] + [box(1, 1, 4.5, x, 0, 26.8, m) for x in (-6, 6)]
    for i in range(7):
        t = -22 + i * 44 / 6
        parts += [cyl(0.4, 26, t, -22, 0, m, verts=4), cyl(0.4, 26, t, 22, 0, m, verts=4), cyl(0.4, 26, 22, t, 0, m, verts=4), cyl(0.3, 44, t, 0, 26.4, m, verts=4, rot=(90, 0, 0))]
    door = [box(0.8, 44, 26, -22, 0, 0, m)]
    return model(P, 'cage_trap', parts, movable={'door': door})

def spray_can():
    g = mat(0x3a8a3a, 0.4, 0.5)
    return model(P, 'spray_can', [cyl(3.5, 18, 0, 0, 0, g, verts=14), cyl(3.5, 2, 0, 0, 18, mat(0xc8ccd4, 0.3, 0.8), verts=14, r2=1.6), cyl(1.6, 2.4, 0, 0, 20, mat(0xd8302e), verts=10),
                                  cyl(3.55, 6, 0, 0, 5, mat(WHITE, 0.6), verts=14), cyl(2, 0.4, 0, -3.6, 8, mat(0xd8302e), verts=12, rot=(90, 0, 0)),
                                  box(3, 0.5, 0.5, 0, -3.8, 8, mat(0x1a1a1a), rot=(0, 45, 0)), box(5, 0.3, 1.4, 0, -3.6, 12.4, mat(WHITE))])

def sleeping_bag():
    b, i, strap = mat(0x4a7a3a, 0.75), mat(0x6a9a5a, 0.8), mat(0x2a3a22, 0.7)
    return model(P, 'sleeping_bag', [box(190, 75, 12, 0, 0, 0, b, bevel=5), box(42, 70, 15, -78, 0, 0, i, bevel=6), box(188, 0.6, 1.2, 0, -37.5, 11, mat(0xc8ccd4, 0.3, 0.8))] +
                 [box(4, 77, 12.6, x, 0, 0, strap) for x in (20, 60)] + [cyl(9, 70, 85, 0, 9, b, verts=12, rot=(90, 0, 0))])

def vacuum_dock():
    return model(P, 'vacuum_dock', [box(30, 15, 10, 0, 0, 0, mat(0x2a2a30, 0.4), bevel=1), box(30, 6, 1, 0, -10, 0, mat(0x2a2a30, 0.4)), sphere(0.8, 0, -7.5, 8, mat(0x4ae86a, 0.3, 0, 1, 3), seg=6, rings=4)])


ALL = [crumb, cheese, lambda: cheese(True), plate, cookie, cookie_pack, sausage, chicken_leg, pizza_slice, pizza_box, cake_slice, cake_whole, potato, lard, dog_biscuit, kibble, rusk, cheese_wheel,
       button, sock, toy_mouse, thimble, lambda: flat_paper('photo', 10, 7, 0xd8d0c0, 0x6a8aa8), marble, bottle_cap, battery, key, ring, earring, whistle, cufflink, toy_dino, toy_car,
       lambda: flat_paper('drawing', 21, 15, 0xf4f0e0, 0x9a7a6a), candle, silver_spoon, chew_toy, lambda: flat_paper('letter', 21, 15, 0xe8e0c8, 0x8a8a8a),
       mug, lambda: mug(True), jar, apple, can, small_box, glass, spoon, ball, bottle,
       mousetrap, napkin, foil, bread_box, tv_remote, squeaky_toy, floorboard_worn, plastic_bag, grain_sack, lambda: grain_sack(True), grain_spill, lamp_cord, puddle, cat_bed, cat_bowl,
       lambda: cat_bowl(True), bucket_mop, flashlight, hangers, lambda: balloon(0xe84a5a, 'balloon_red'), lambda: balloon(0x4a9ae8, 'balloon_blue'), lambda: balloon(0xf2c84a, 'balloon_yellow'),
       confetti, sticky_tape, lego_bricks, music_box, night_light, backpack, lambda: backpack(True), party_popper, litter_box, pipe, vent_grate, cage_trap, spray_can, sleeping_bag, vacuum_dock]
