"""Characters with skeletons and animations: rats, cat, dog, people, robot vacuum. Sizes in cm, facing -Y."""
import math

import bpy

from lib import box, cyl, sphere, ico, torus, seg, mat, model, CM
from rig import build, bind, clip, finish, s

C = 'characters'


# ======================= RODENTS (mother and pup) =======================
def rodent(name, k, fur, belly, head_k=1.0, age='adult'):
    """k: overall scale (1 = 25 cm mother). head_k: bigger heads for pups."""
    q = lambda *v: tuple(a * k for a in v)
    pink, black = mat(0xe8a0a8, 0.6), mat(0x111111, 0.2)
    F, Bm = mat(fur, 0.9), mat(belly, 0.9)
    bones = [
        ('root', (0, 0, 0), (0, -4 * k, 0), None),
        ('hips', q(0, 5, 6), q(0, -2, 6), 'root'),
        ('chest', q(0, -2, 6), q(0, -8, 6.5), 'hips'),
        ('head', q(0, -8, 7), q(0, -15, 7), 'chest'),
        ('tail1', q(0, 9, 4.5), q(0, 14, 3.5), 'hips'), ('tail2', q(0, 14, 3.5), q(0, 19, 2.5), 'tail1'),
        ('tail3', q(0, 19, 2.5), q(0, 24, 1.8), 'tail2'), ('tail4', q(0, 24, 1.8), q(0, 29, 1.2), 'tail3'),
        ('leg_fl', q(-3, -6, 4), q(-3, -6, 0), 'chest'), ('leg_fr', q(3, -6, 4), q(3, -6, 0), 'chest'),
        ('leg_bl', q(-3.5, 5, 4), q(-3.5, 5, 0), 'hips'), ('leg_br', q(3.5, 5, 4), q(3.5, 5, 0), 'hips'),
    ]
    arm = build(name, bones)
    h = head_k
    hz, hy = 7.3, -10.5
    parts = {
        'hips': [sphere(6 * k, 0, 3 * k, 6 * k, F, seg=14, rings=9, scale=(0.85, 1.25, 0.85)), sphere(4.6 * k, 0, 3 * k, 4.3 * k, Bm, seg=10, rings=6, scale=(0.9, 1.2, 0.6))],
        'chest': [sphere(5 * k, 0, -4 * k, 6.5 * k, F, seg=14, rings=9, scale=(0.85, 1.1, 0.88))],
        'head': [sphere(3.8 * k * h, 0, hy * k, hz * k, F, seg=12, rings=8, scale=(0.9, 1.2, 0.9)),
                 seg(q(0, hy - 2.5 * h, hz - 0.3), q(0, hy - 6.2 * h, hz - 0.6), 2.4 * k * h, 0.8 * k * h, F, verts=10),
                 sphere(0.85 * k * h, 0, (hy - 6.3 * h) * k, (hz - 0.6) * k, pink, seg=8, rings=6),
                 sphere(0.65 * k * h, -1.9 * k * h, (hy - 2.2 * h) * k, (hz + 1.4 * h) * k, black, seg=8, rings=6),
                 sphere(0.65 * k * h, 1.9 * k * h, (hy - 2.2 * h) * k, (hz + 1.4 * h) * k, black, seg=8, rings=6)],
        'tail1': [seg(q(0, 9, 4.5), q(0, 14, 3.5), 1.1 * k, 0.9 * k, pink)], 'tail2': [seg(q(0, 14, 3.5), q(0, 19, 2.5), 0.9 * k, 0.7 * k, pink)],
        'tail3': [seg(q(0, 19, 2.5), q(0, 24, 1.8), 0.7 * k, 0.5 * k, pink)], 'tail4': [seg(q(0, 24, 1.8), q(0, 29, 1.2), 0.5 * k, 0.2 * k, pink)],
    }
    for sx in (-1, 1):
        ex = sx * 2.6 * k * h
        parts['head'] += [cyl(2 * k * h, 0.5 * k, ex, (hy + 0.6) * k, (hz + 3 * h) * k, F, verts=12, rot=(90, 0, 0)),
                          cyl(1.3 * k * h, 0.55 * k, ex, (hy + 0.4) * k, (hz + 3 * h) * k, pink, verts=10, rot=(90, 0, 0))]
        for dz in (-0.4, 0.4):  # whiskers
            parts['head'].append(box(4 * k, 0.12 * k, 0.12 * k, sx * 2.6 * k, (hy - 5 * h) * k, (hz - 0.4 + dz) * k, mat(0xf2ece4), rot=(0, 0, sx * 12)))
    for lb, x, y in [('leg_fl', -3, -6), ('leg_fr', 3, -6), ('leg_bl', -3.5, 5), ('leg_br', 3.5, 5)]:
        parts[lb] = [seg(q(x, y, 4.5), q(x, y, 0.6), 1.3 * k, 0.9 * k, F), box(1.8 * k, 2.6 * k, 0.8 * k, x * k, (y - 0.6) * k, 0, pink, bevel=0.3 * k)]
    mesh = bind(arm, parts, name)
    rodent_clips(arm, k, pup=age != 'adult')
    return finish(arm, mesh, C, name)


def rodent_clips(a, k, pup=False):
    legs = lambda amp, t, ph=0: {'leg_fl': (amp * s(t + ph), 0, 0), 'leg_br': (amp * s(t + ph), 0, 0), 'leg_fr': (-amp * s(t + ph), 0, 0), 'leg_bl': (-amp * s(t + ph), 0, 0)}
    def loop(n, f):
        return {i: f(i / n) for i in range(n)}
    clip(a, 'idle', 48, loop(48, lambda t: {'chest': (2 * s(t), 0, 0), 'head': (2 * s(t * 2), 0, 6 * s(t)), 'tail1': (0, 0, 8 * s(t)), 'tail2': (0, 0, 10 * s(t + 0.15)), 'tail3': (0, 0, 12 * s(t + 0.3))}))
    clip(a, 'walk', 16, loop(16, lambda t: dict(legs(28, t), root={'l': (0, 0, 0.6 * k * abs(s(t)))}, head=(3 * s(t * 2), 0, 0), tail1=(0, 0, 10 * s(t)), tail2=(0, 0, 12 * s(t + 0.2)))))
    clip(a, 'run', 10, loop(10, lambda t: {'leg_fl': (45 * s(t), 0, 0), 'leg_fr': (45 * s(t), 0, 0), 'leg_bl': (-45 * s(t), 0, 0), 'leg_br': (-45 * s(t), 0, 0),
                                           'hips': (8 * s(t), 0, 0), 'chest': (-10 * s(t), 0, 0), 'root': {'l': (0, 0, 1.6 * k * max(0, s(t)))}, 'tail1': (10 * s(t), 0, 0), 'tail2': (12 * s(t), 0, 0)}))
    clip(a, 'sneak', 24, loop(24, lambda t: dict(legs(14, t), root={'l': (0, 0, -2.2 * k)}, head=(-8, 0, 3 * s(t)), tail1=(8, 0, 4 * s(t)), tail2=(6, 0, 0))))
    if not pup:
        clip(a, 'jump_up', 12, {0: {'root': {'l': (0, 0, -2 * k)}, 'leg_fl': (-20, 0, 0), 'leg_fr': (-20, 0, 0), 'leg_bl': (25, 0, 0), 'leg_br': (25, 0, 0), 'hips': (0, 0, 0)},
                                4: {'root': {'l': (0, 0, 3 * k)}, 'leg_fl': (-45, 0, 0), 'leg_fr': (-45, 0, 0), 'leg_bl': (45, 0, 0), 'leg_br': (45, 0, 0), 'hips': (15, 0, 0), 'tail1': (-15, 0, 0)},
                                12: {}}, loop=False)
        clip(a, 'jump_down', 12, {0: {}, 4: {'leg_fl': (-35, 0, 0), 'leg_fr': (-35, 0, 0), 'leg_bl': (20, 0, 0), 'leg_br': (20, 0, 0), 'hips': (-12, 0, 0), 'tail1': (20, 0, 0)}, 12: {}}, loop=False)
        clip(a, 'land', 8, {0: {'root': {'l': (0, 0, -2.5 * k)}, 'leg_fl': (15, 0, 0), 'leg_fr': (15, 0, 0), 'leg_bl': (-15, 0, 0), 'leg_br': (-15, 0, 0)}, 8: {}}, loop=False)
        clip(a, 'drag', 20, loop(20, lambda t: dict(legs(20, t), head=(22, 0, 0), hips=(-8, 0, 0), root={'l': (0, 0, -1 * k)}, tail1=(-5, 0, 6 * s(t)))))
        clip(a, 'gnaw', 12, loop(12, lambda t: {'head': (18 + 10 * s(t * 2), 0, 3 * s(t)), 'chest': (6, 0, 0)}))
        clip(a, 'stuck', 12, loop(12, lambda t: {'leg_fl': (35 * s(t * 2), 0, 0), 'leg_fr': (-35 * s(t * 2), 0, 0), 'leg_bl': (30 * s(t * 2 + 0.25), 0, 0), 'leg_br': (-30 * s(t * 2 + 0.25), 0, 0),
                                                 'hips': (0, 0, 8 * s(t)), 'head': (-10, 0, 15 * s(t)), 'tail1': (0, 0, 25 * s(t * 2))}))
        clip(a, 'wake_up', 36, {0: sleep_pose(k), 20: {'root': {'l': (0, 0, -1.5 * k)}, 'head': (-10, 0, 0), 'chest': (-5, 0, 0)}, 36: {}}, loop=False)
    sniff_amp = 1.0
    clip(a, 'sniff', 32, loop(32, lambda t: {'hips': (55 * sniff_amp, 0, 0), 'chest': (10, 0, 0), 'leg_bl': (-55, 0, 0), 'leg_br': (-55, 0, 0), 'leg_fl': (-60, 0, 0), 'leg_fr': (-60, 0, 0),
                                             'head': (-15 + 4 * s(t * 4), 0, 10 * s(t)), 'tail1': (50, 0, 6 * s(t)), 'tail2': (15, 0, 0), 'root': {'l': (0, 0, 0.5 * k)}}))
    clip(a, 'carry_walk', 16, loop(16, lambda t: dict(legs(24, t), head=(-14, 0, 0), root={'l': (0, 0, 0.5 * k * abs(s(t)))}, tail1=(0, 0, 10 * s(t)))))
    clip(a, 'sleep', 48, loop(48, lambda t: dict(sleep_pose(k), chest=(15 + 2 * s(t), 0, 0))))
    clip(a, 'eat', 24, loop(24, lambda t: {'head': (24 + 8 * s(t * 2), 0, 0), 'chest': (8, 0, 0), 'leg_fl': (-25, 0, 0), 'leg_fr': (-25, 0, 0)}))
    if pup:
        clip(a, 'squeak', 16, {0: {}, 5: {'head': (-30, 0, 0), 'chest': (-10, 0, 0)}, 11: {'head': (-30, 0, 0), 'chest': (-10, 0, 0)}, 16: {}}, loop=False)
        clip(a, 'freeze', 24, loop(24, lambda t: {'root': {'l': (0, 0, -2.5 * k)}, 'head': (25, 0, 3 * s(t * 6)), 'hips': (0, 0, 2 * s(t * 6)), 'tail1': (0, 0, 60), 'tail2': (0, 0, 50),
                                                  'leg_fl': (20, 0, 0), 'leg_fr': (20, 0, 0), 'leg_bl': (-20, 0, 0), 'leg_br': (-20, 0, 0)}))


def sleep_pose(k):
    return {'root': {'l': (0, 0, -3 * k)}, 'hips': (8, 0, 20), 'chest': (15, 0, 25), 'head': (35, 0, 30), 'tail1': (0, 0, 55), 'tail2': (0, 0, 60), 'tail3': (0, 0, 50),
            'leg_fl': (60, 0, 0), 'leg_fr': (60, 0, 0), 'leg_bl': (-60, 0, 0), 'leg_br': (-60, 0, 0)}


def rat_mother():
    return rodent('rat_mother', 1.0, 0x8f8580, 0xc8bcb4)


def rat_pup():
    return rodent('rat_pup', 0.56, 0xc4aaa6, 0xe8dcd8, head_k=1.28, age='pup')


# ======================= CAT AND DOG =======================
def quad(name, L, H, fur, belly, kind):
    """L: body length, H: shoulder height (cm)."""
    k = L / 50.0
    q = lambda *v: tuple(a * k for a in v)
    F, Bm = mat(fur, 0.9), mat(belly, 0.9)
    dark = mat(0x111111, 0.2)
    hh = H / k  # leg top height in model units
    tail = [(0, 16, hh), (0, 22, hh + 4), (0, 27, hh + 10), (0, 30, hh + 16), (0, 32, hh + 22)] if kind == 'cat' else [(0, 16, hh + 1), (0, 22, hh + 5), (0, 27, hh + 8), (0, 31, hh + 9), (0, 34, hh + 9)]
    bones = [('root', (0, 0, 0), (0, -6 * k, 0), None),
             ('hips', q(0, 12, hh), q(0, -4, hh + 1), 'root'), ('chest', q(0, -4, hh + 1), q(0, -16, hh + 3), 'hips'),
             ('head', q(0, -16, hh + 6), q(0, -27, hh + 8), 'chest')]
    for i in range(4):
        bones.append(('tail%d' % (i + 1), q(*tail[i]), q(*tail[i + 1]), 'hips' if i == 0 else 'tail%d' % i))
    for b, x, y, p in [('leg_fl', -6, -12, 'chest'), ('leg_fr', 6, -12, 'chest'), ('leg_bl', -6, 10, 'hips'), ('leg_br', 6, 10, 'hips')]:
        bones.append((b, q(x, y, hh), q(x, y, 0), p))
    arm = build(name, bones)
    hz, hy = (hh + 9) * k, -24 * k
    parts = {
        'hips': [sphere(9 * k, 0, 6 * k, (hh + 1) * k, F, seg=14, rings=9, scale=(0.85, 1.35, 0.85)), sphere(7 * k, 0, 6 * k, (hh - 2.5) * k, Bm, seg=10, rings=6, scale=(0.8, 1.2, 0.6))],
        'chest': [sphere(8.5 * k, 0, -10 * k, (hh + 2) * k, F, seg=14, rings=9, scale=(0.85, 1.2, 0.95))],
        'head': [sphere(7 * k, 0, hy, hz, F, seg=14, rings=10, scale=(1, 1, 0.92)),
                 sphere(3.4 * k, 0, hy - 5.5 * k, hz - 2 * k, Bm if kind == 'cat' else F, seg=10, rings=6, scale=(1.1, 1 if kind == 'cat' else 1.6, 0.8)),
                 sphere(1.1 * k, 0, hy - (8.4 if kind == 'cat' else 10.8) * k, hz - 1.2 * k, mat(0xd86a7a if kind == 'cat' else 0x1a1a1a, 0.4), seg=8, rings=6),
                 sphere(1.4 * k, -2.8 * k, hy - 5.6 * k, hz + 1.8 * k, mat(0x8ad04a if kind == 'cat' else 0x3a2a1a, 0.2), seg=8, rings=6),
                 sphere(1.4 * k, 2.8 * k, hy - 5.6 * k, hz + 1.8 * k, mat(0x8ad04a if kind == 'cat' else 0x3a2a1a, 0.2), seg=8, rings=6),
                 sphere(0.7 * k, -2.9 * k, hy - 6.8 * k, hz + 1.9 * k, dark, seg=6, rings=4), sphere(0.7 * k, 2.9 * k, hy - 6.8 * k, hz + 1.9 * k, dark, seg=6, rings=4)],
    }
    for sx in (-1, 1):
        if kind == 'cat':
            parts['head'] += [seg((sx * 4 * k, hy, hz + 4.5 * k), (sx * 5.2 * k, hy, hz + 10.5 * k), 2.8 * k, 0.3 * k, F, verts=4)]
            for dz in (-0.5, 0.5):
                parts['head'].append(box(7 * k, 0.15 * k, 0.15 * k, sx * 4.5 * k, hy - 7 * k, hz - 2 * k + dz * k, mat(0xf2ece4), rot=(0, 0, sx * 10)))
        else:
            parts['head'].append(box(3 * k, 4.5 * k, 9 * k, sx * 6.5 * k, hy + 1 * k, hz - 6 * k, mat(shade_hex(fur, 0.7), 0.9), bevel=1 * k, rot=(0, sx * 12, 0)))
    for i in range(4):
        r1 = (2.2 - i * 0.35) * k if kind == 'cat' else (2.4 - i * 0.4) * k
        parts['tail%d' % (i + 1)] = [seg(q(*tail[i]), q(*tail[i + 1]), r1, r1 - 0.3 * k, F)]
    for b, x, y in [('leg_fl', -6, -12), ('leg_fr', 6, -12), ('leg_bl', -6, 10), ('leg_br', 6, 10)]:
        parts[b] = [seg(q(x, y, hh), q(x, y, 1.5), 2.6 * k, 2.1 * k, F), sphere(2.4 * k, x * k, (y - 1) * k, 1.3 * k, Bm if kind == 'cat' else F, seg=8, rings=6, scale=(1, 1.3, 0.6))]
    if kind == 'cat':  # stripes and a collar with a bell
        for i in range(3):
            parts['hips'].append(box(14 * k, 1.5 * k, 3 * k, 0, (2 + i * 5) * k, (hh + 7) * k, mat(shade_hex(fur, 0.7), 0.9), bevel=0.5 * k))
        parts['chest'] += [torus(5.5 * k, 0.8 * k, 0, -15 * k, (hh + 5) * k, mat(0xd8343a, 0.5), seg=14, rseg=4, rot=(70, 0, 0)), sphere(1.3 * k, 0, -19.5 * k, (hh + 1.5) * k, mat(0xf2c84a, 0.2, 0.8), seg=8, rings=6)]
    mesh = bind(arm, parts, name)
    quad_clips(arm, k, kind)
    return finish(arm, mesh, C, name)


def shade_hex(c, f):
    return (int(((c >> 16) & 255) * f) << 16) | (int(((c >> 8) & 255) * f) << 8) | int((c & 255) * f)


def quad_clips(a, k, kind):
    def loop(n, f):
        return {i: f(i / n) for i in range(n)}
    walkl = lambda amp, t: {'leg_fl': (amp * s(t), 0, 0), 'leg_br': (amp * s(t), 0, 0), 'leg_fr': (-amp * s(t), 0, 0), 'leg_bl': (-amp * s(t), 0, 0)}
    sit = {'hips': (-35, 0, 0), 'chest': (10, 0, 0), 'head': (-10, 0, 0), 'leg_bl': (-55, 0, 0), 'leg_br': (-55, 0, 0), 'leg_fl': (25, 0, 0), 'leg_fr': (25, 0, 0), 'root': {'l': (0, 0, -4 * k)}, 'tail1': (40, 0, 30)}
    curl = {'root': {'l': (0, 0, -18 * k)}, 'hips': (0, 0, 20), 'chest': (10, 0, 25), 'head': (30, 0, 35), 'tail1': (50, 0, 50), 'tail2': (0, 0, 50), 'tail3': (0, 0, 40),
            'leg_fl': (70, 0, 0), 'leg_fr': (70, 0, 0), 'leg_bl': (-70, 0, 0), 'leg_br': (-70, 0, 0)}
    clip(a, 'walk', 24, loop(24, lambda t: dict(walkl(26, t), root={'l': (0, 0, 0.8 * k * abs(s(t)))}, head=(3 * s(t * 2), 0, 0), tail1=(0, 0, 8 * s(t)), tail2=(0, 0, 10 * s(t + 0.2)))))
    clip(a, 'run', 12, loop(12, lambda t: {'leg_fl': (45 * s(t), 0, 0), 'leg_fr': (40 * s(t + 0.1), 0, 0), 'leg_bl': (-45 * s(t), 0, 0), 'leg_br': (-40 * s(t + 0.1), 0, 0),
                                           'hips': (10 * s(t), 0, 0), 'chest': (-10 * s(t), 0, 0), 'root': {'l': (0, 0, 3 * k * max(0, s(t)))}, 'tail1': (-15, 0, 0)}))
    clip(a, 'sleep', 48, loop(48, lambda t: dict(curl, chest=(10 + 2 * s(t), 0, 25))))
    clip(a, 'wake_up', 36, {0: curl, 18: sit, 36: {}}, loop=False)
    if kind == 'cat':
        clip(a, 'idle_sit', 48, loop(48, lambda t: dict(sit, head=(-10, 0, 8 * s(t)), tail2=(0, 0, 15 * s(t)), tail3=(0, 0, 20 * s(t + 0.2)))))
        clip(a, 'stir', 24, loop(24, lambda t: dict(curl, head=(30, 0, 35 + 6 * s(t * 2)))))
        clip(a, 'head_up', 32, loop(32, lambda t: dict(curl, head=(-5, 0, 10 + 25 * s(t)), chest=(0, 0, 20))))
        clip(a, 'look_around', 48, loop(48, lambda t: {'head': (-5, 0, 45 * s(t)), 'chest': (0, 0, 10 * s(t))}))
        clip(a, 'eat', 24, loop(24, lambda t: {'head': (35 + 8 * s(t * 2), 0, 0), 'chest': (12, 0, 0), 'leg_fl': (8, 0, 0), 'leg_fr': (8, 0, 0)}))
        clip(a, 'pounce', 20, {0: {}, 8: {'root': {'l': (0, 0, -8 * k)}, 'hips': (10, 0, 0), 'leg_bl': (35, 0, 0), 'leg_br': (35, 0, 0), 'leg_fl': (-20, 0, 0), 'leg_fr': (-20, 0, 0), 'tail1': (0, 0, 20)},
                               13: {'root': {'l': (0, 0, 12 * k)}, 'leg_fl': (-60, 0, 0), 'leg_fr': (-60, 0, 0), 'leg_bl': (50, 0, 0), 'leg_br': (50, 0, 0), 'hips': (-10, 0, 0)}, 20: {}}, loop=False)
        clip(a, 'carry_pup', 24, loop(24, lambda t: dict(walkl(22, t), head=(-15, 0, 0), tail1=(0, 0, 8 * s(t)))))
        clip(a, 'meow', 20, {0: {}, 6: {'head': (-25, 0, 0)}, 14: {'head': (-25, 0, 0)}, 20: {}}, loop=False)
    else:
        clip(a, 'idle', 48, loop(48, lambda t: {'chest': (2 * s(t), 0, 0), 'head': (3 * s(t * 2), 0, 10 * s(t)), 'tail1': (0, 0, 20 * s(t * 2)), 'tail2': (0, 0, 20 * s(t * 2 + 0.2))}))
        clip(a, 'sniff_ground', 24, loop(24, lambda t: dict(walkl(18, t), head=(40 + 5 * s(t * 4), 0, 15 * s(t)), chest=(10, 0, 0), tail1=(0, 0, 15 * s(t * 2)))))
        clip(a, 'bark', 16, {0: {}, 4: {'head': (-25, 0, 0), 'chest': (-8, 0, 0), 'root': {'l': (0, 0, 2 * k)}}, 8: {'head': (5, 0, 0)}, 12: {'head': (-25, 0, 0)}, 16: {}}, loop=False)
        clip(a, 'play', 16, loop(16, lambda t: {'tail1': (0, 0, 40 * s(t * 2)), 'tail2': (0, 0, 40 * s(t * 2 + 0.2)), 'root': {'l': (0, 0, 4 * k * max(0, s(t)))},
                                                'chest': (-15 + 10 * s(t), 0, 0), 'leg_fl': (-30 * max(0, s(t)), 0, 0), 'leg_fr': (-30 * max(0, s(t)), 0, 0)}))


def cat():
    return quad('cat', 50, 30, 0xd8843a, 0xf2e4c8, 'cat')


def dog():
    return quad('dog', 70, 45, 0xa8784a, 0xe8d8b8, 'dog')


# ======================= PEOPLE =======================
def person(name, height, shirt, pants, skin=0xe8b896, hair=0x4a3020, shoes=0x2a3a8a, head_k=1.0, extra=None):
    k = height / 180.0
    q = lambda *v: tuple(a * k for a in v)
    S, Pm, K, Hm, Sh = mat(shirt, 0.85), mat(pants, 0.85), mat(skin, 0.7), mat(hair, 0.9), mat(shoes, 0.8)
    bones = [('root', (0, 0, 0), (0, -10 * k, 0), None), ('hips', q(0, 0, 92), q(0, 0, 104), 'root'), ('spine', q(0, 0, 104), q(0, 0, 148), 'hips'),
             ('head', q(0, 0, 150), q(0, 0, 172), 'spine')]
    for sd, sx in (('l', -1), ('r', 1)):
        bones += [('upper_arm_' + sd, q(sx * 21, 0, 144), q(sx * 23, 0, 118), 'spine'), ('forearm_' + sd, q(sx * 23, 0, 118), q(sx * 24, -2, 92), 'upper_arm_' + sd),
                  ('thigh_' + sd, q(sx * 9, 0, 92), q(sx * 9, 0, 50), 'hips'), ('shin_' + sd, q(sx * 9, 0, 50), q(sx * 9, 0, 6), 'thigh_' + sd)]
    arm = build(name, bones)
    hk = head_k
    parts = {'hips': [box(34 * k, 20 * k, 16 * k, 0, 0, 88 * k, Pm, bevel=3 * k)],
             'spine': [box(38 * k, 22 * k, 48 * k, 0, 0, 102 * k, S, bevel=5 * k), cyl(5 * k, 6 * k, 0, 0, 146 * k, K, verts=10)],
             'head': [sphere(11 * k * hk, 0, 0, (162 + 6 * (hk - 1)) * k, K, seg=14, rings=10, scale=(0.92, 1, 1.12)),
                      sphere(11.6 * k * hk, 0, 1.5 * k, (166 + 6 * (hk - 1)) * k, Hm, seg=14, rings=8, scale=(0.95, 1.02, 0.85)),
                      sphere(1.4 * k * hk, 0, -11 * k * hk, (161 + 6 * (hk - 1)) * k, mat(shade_hex(skin, 0.85), 0.7), seg=8, rings=6),
                      sphere(1.2 * k * hk, -4 * k * hk, -9.8 * k * hk, (164 + 6 * (hk - 1)) * k, mat(0x1a1a1a, 0.2), seg=8, rings=6),
                      sphere(1.2 * k * hk, 4 * k * hk, -9.8 * k * hk, (164 + 6 * (hk - 1)) * k, mat(0x1a1a1a, 0.2), seg=8, rings=6)]}
    for sd, sx in (('l', -1), ('r', 1)):
        parts['upper_arm_' + sd] = [seg(q(sx * 21, 0, 145), q(sx * 23, 0, 118), 5.5 * k, 4.8 * k, S)]
        parts['forearm_' + sd] = [seg(q(sx * 23, 0, 118), q(sx * 24, -2, 95), 4.6 * k, 4 * k, S), sphere(4.4 * k, sx * 24 * k, -2.5 * k, 90 * k, K, seg=8, rings=6, scale=(0.8, 1, 1.2))]
        parts['thigh_' + sd] = [seg(q(sx * 9, 0, 94), q(sx * 9, 0, 50), 7.5 * k, 6.5 * k, Pm)]
        parts['shin_' + sd] = [seg(q(sx * 9, 0, 50), q(sx * 9, 0, 8), 6.2 * k, 5.4 * k, Pm), box(11 * k, 27 * k, 8 * k, sx * 9 * k, -6 * k, 0, Sh, bevel=2.5 * k)]
    attach = {}
    if extra:
        extra(parts, attach, k, q)
    mesh = bind(arm, parts, name, attach)
    return arm, mesh, k


def person_clips(a, k, set_):
    def loop(n, f):
        return {i: f(i / n) for i in range(n)}
    walk = lambda amp, t: {'thigh_l': (amp * s(t), 0, 0), 'thigh_r': (-amp * s(t), 0, 0), 'shin_l': (-amp * 0.9 * max(0, -s(t + 0.1)), 0, 0), 'shin_r': (-amp * 0.9 * max(0, s(t + 0.1)), 0, 0),
                           'upper_arm_l': (-amp * 0.7 * s(t), 0, 0), 'upper_arm_r': (amp * 0.7 * s(t), 0, 0), 'forearm_l': (-15, 0, 0), 'forearm_r': (-15, 0, 0), 'root': {'l': (0, 0, 1.5 * k * abs(s(t * 2)))}}
    if 'idle' in set_:
        clip(a, 'idle', 60, loop(60, lambda t: {'spine': (1.5 * s(t), 0, 0), 'head': (2 * s(t), 0, 4 * s(t * 0.5)), 'upper_arm_l': (0, 0, -4), 'upper_arm_r': (0, 0, 4)}))
    if 'walk' in set_:
        clip(a, 'walk', 30, loop(30, lambda t: walk(25, t)))
    if 'run' in set_:
        clip(a, 'run', 18, loop(18, lambda t: dict(walk(45, t), spine=(-10, 0, 0), forearm_l=(-70, 0, 0), forearm_r=(-70, 0, 0))))
    if 'look_around' in set_:
        clip(a, 'look_around', 72, loop(72, lambda t: {'head': (8, 0, 55 * s(t)), 'spine': (0, 0, 15 * s(t))}))
    if 'drink' in set_:
        clip(a, 'drink', 48, {0: {}, 12: {'upper_arm_r': (-60, 0, 15), 'forearm_r': (-110, 0, 0), 'head': (-25, 0, 0)}, 36: {'upper_arm_r': (-60, 0, 15), 'forearm_r': (-110, 0, 0), 'head': (-25, 0, 0)}, 48: {}})
    if 'flashlight_sweep' in set_:
        clip(a, 'flashlight_sweep', 60, loop(60, lambda t: {'upper_arm_r': (-75, 0, 25 * s(t)), 'forearm_r': (-10, 0, 0), 'spine': (8, 0, 20 * s(t)), 'head': (15, 0, 20 * s(t))}))
    if 'crouch_look' in set_:
        crouch = {'root': {'l': (0, 0, -42 * k)}, 'thigh_l': (-95, 0, 0), 'thigh_r': (-95, 0, 0), 'shin_l': (110, 0, 0), 'shin_r': (110, 0, 0), 'spine': (45, 0, 0), 'head': (20, 0, 0),
                  'upper_arm_r': (-80, 0, 0), 'upper_arm_l': (-20, 0, 0)}
        clip(a, 'crouch_look', 48, {0: {}, 14: crouch, 34: dict(crouch, head=(20, 0, 25)), 48: {}}, loop=False)
    if 'swat' in set_:
        clip(a, 'swat', 20, {0: {}, 8: {'upper_arm_r': (-170, 0, 0), 'forearm_r': (-30, 0, 0), 'spine': (-10, 0, 0)}, 12: {'upper_arm_r': (-40, 0, 0), 'spine': (35, 0, 0), 'head': (20, 0, 0)}, 20: {}}, loop=False)
    if 'place_trap' in set_:
        bend = {'spine': (75, 0, 0), 'head': (10, 0, 0), 'upper_arm_r': (-50, 0, 0), 'upper_arm_l': (-50, 0, 0), 'thigh_l': (-20, 0, 0), 'thigh_r': (-20, 0, 0), 'shin_l': (25, 0, 0), 'shin_r': (25, 0, 0),
                'root': {'l': (0, 0, -6 * k)}}
        clip(a, 'place_trap', 48, {0: {}, 16: bend, 32: bend, 48: {}}, loop=False)
    if 'yawn' in set_:
        up = {'upper_arm_l': (-160, 0, -20), 'upper_arm_r': (-160, 0, 20), 'forearm_l': (-20, 0, 0), 'forearm_r': (-20, 0, 0), 'head': (-25, 0, 0), 'spine': (-8, 0, 0)}
        clip(a, 'yawn', 48, {0: {}, 16: up, 32: up, 48: {}}, loop=False)
    if 'spray' in set_:
        clip(a, 'spray', 40, loop(40, lambda t: {'upper_arm_r': (-80, 0, 20 * s(t)), 'forearm_r': (-5, 0, 0), 'spine': (10, 0, 15 * s(t)), 'head': (15, 0, 15 * s(t))}))
    lying = {'root': {'r': (-90, 0, 0), 'l': (0, 0, 12 * k)}, 'upper_arm_l': (0, 0, -10), 'upper_arm_r': (0, 0, 10)}
    if 'sleep_bed' in set_:
        clip(a, 'sleep_bed', 60, loop(60, lambda t: dict(lying, spine=(2 * s(t), 0, 0), head=(-8, 0, 20))))
        clip(a, 'toss', 48, {0: lying, 16: dict(lying, spine=(0, 25, 0), thigh_l=(-30, 0, 0), head=(-8, 0, -30)), 32: dict(lying, spine=(0, -20, 0), thigh_r=(-30, 0, 0)), 48: lying})
        clip(a, 'sit_up_scream', 30, {0: lying, 12: {'root': {'r': (-15, 0, 0), 'l': (0, 0, 12 * k)}, 'thigh_l': (-80, 0, 0), 'thigh_r': (-80, 0, 0), 'upper_arm_l': (-40, 0, -30),
                                                     'upper_arm_r': (-40, 0, 30), 'head': (-20, 0, 0)}, 30: {'root': {'r': (-10, 0, 0), 'l': (0, 0, 12 * k)}, 'thigh_l': (-85, 0, 0),
                                                     'thigh_r': (-85, 0, 0), 'upper_arm_l': (-150, 0, -30), 'upper_arm_r': (-150, 0, 30), 'head': (-30, 0, 0)}}, loop=False)
    if 'sleep_floor' in set_:
        clip(a, 'sleep_floor', 60, loop(60, lambda t: dict(lying, spine=(2 * s(t), 0, 0), head=(-5, 0, 25))))
        clip(a, 'sit_up', 30, {0: lying, 30: {'root': {'r': (-5, 0, 0), 'l': (0, 0, 10 * k)}, 'thigh_l': (-88, 0, 0), 'thigh_r': (-88, 0, 0), 'spine': (10, 0, 0), 'upper_arm_l': (-20, 0, -20),
                                                'upper_arm_r': (-20, 0, 20)}}, loop=False)


def owner():
    def extra(parts, attach, k, q):
        parts['spine'] += [box(39 * k, 0.6 * k, 4 * k, 0, -11.2 * k, (110 + z) * k, mat(0xe8eef8, 0.8)) for z in (0, 12, 24)]  # pajama stripes
        attach['forearm_r'] = [('flashlight', [cyl(2 * k, 16 * k, 25 * k, -12 * k, 88 * k, mat(0x2a2a2a, 0.4), verts=10, rot=(90, 0, 0)),
                                               cyl(2.8 * k, 0.5 * k, 25 * k, -20.5 * k, 88 * k, mat(0xfff0c0, 0.2, 0, 1, 2), verts=10, rot=(90, 0, 0))]),
                               ('glass', [cyl(3.2 * k, 10 * k, 24 * k, -7 * k, 86 * k, mat(0xcfe0ee, 0.05, 0, 0.5), verts=12)])]
        attach['forearm_l'] = [('slipper', [box(9 * k, 24 * k, 4 * k, -24 * k, -10 * k, 84 * k, mat(0x8a3a3a, 0.9), bevel=2 * k)])]
    a, m, k = person('owner', 180, 0x5a7ab8, 0x3a4a7a, shoes=0x8a3a3a, extra=extra)
    person_clips(a, k, {'idle', 'walk', 'run', 'look_around', 'drink', 'flashlight_sweep', 'crouch_look', 'swat', 'place_trap', 'yawn'})
    return finish(a, m, C, 'owner')


def kid():
    def extra(parts, attach, k, q):
        parts['spine'] += [sphere(1.8 * k, x * k, -11.3 * k, z * k, mat(0xf2c84a, 0.6), seg=6, rings=4, scale=(1, 0.3, 1)) for x, z in [(-8, 140), (6, 128), (-3, 116), (10, 108)]]
    a, m, k = person('kid', 120, 0x6a9ad8, 0x6a9ad8, hair=0xc8843a, shoes=0xf2e8e0, head_k=1.25, extra=extra)
    person_clips(a, k, {'idle', 'walk', 'sleep_bed'})
    return finish(a, m, C, 'kid')


def guest():
    a, m, k = person('guest', 175, 0x4a8a5a, 0x3a3a44, skin=0xc89070, hair=0x1a1a1a, shoes=0x2a2a2a)
    person_clips(a, k, {'idle', 'walk', 'look_around', 'sleep_floor'})
    return finish(a, m, C, 'guest')


def exterminator():
    def extra(parts, attach, k, q):
        parts['spine'].append(box(26 * k, 12 * k, 40 * k, 0, 15 * k, 104 * k, mat(0x6ac04a, 0.4, 0.4), bevel=5 * k))  # tank on the back
        parts['head'] += [box(16 * k, 6 * k, 9 * k, 0, -10 * k, 152 * k, mat(0x2a2a2a, 0.5), bevel=2 * k), cyl(3 * k, 4 * k, 0, -14 * k, 152 * k, mat(0x5a5a5a), verts=10, rot=(90, 0, 0))]
        attach['forearm_r'] = [('spray_can', [cyl(3.5 * k, 18 * k, 25 * k, -6 * k, 80 * k, mat(0x6ac04a, 0.4, 0.5), verts=12), box(2 * k, 4 * k, 2 * k, 25 * k, -9 * k, 97 * k, mat(0xe84a3a))])]
    a, m, k = person('exterminator', 180, 0xb8a46a, 0xb8a46a, hair=0x3a3a3a, shoes=0x2a2a2a, extra=extra)
    person_clips(a, k, {'idle', 'walk', 'look_around', 'spray'})
    return finish(a, m, C, 'exterminator')


# ======================= ROBOT VACUUM =======================
def robot_vacuum():
    body = [cyl(17, 7, 0, 0, 1.5, mat(0x2a2a30, 0.35), verts=28), cyl(16.5, 0.6, 0, 0, 8.5, mat(0x4a4a54, 0.3, 0.3), verts=28), box(14, 3, 1, 0, -12, 8.5, mat(0x1a1a1a)),
            cyl(3, 1, 0, 6, 8.8, mat(0x6a6a74, 0.3, 0.5), verts=14), cyl(2.5, 1.6, -9, 0, 0, mat(0x1a1a1a), verts=10, rot=(0, 90, 0)), cyl(2.5, 1.6, 9, 0, 0, mat(0x1a1a1a), verts=10, rot=(0, 90, 0))]
    brush_l = [cyl(0.4, 9, -11, -11, 0.6, mat(0x8a8a94), verts=4, rot=(0, 90, 30)), cyl(0.4, 9, -11, -11, 0.6, mat(0x8a8a94), verts=4, rot=(0, 90, -30)), cyl(1.2, 1.5, -11, -11, 0, mat(0x5a5a64), verts=8)]
    brush_r = [cyl(0.4, 9, 11, -11, 0.6, mat(0x8a8a94), verts=4, rot=(0, 90, 30)), cyl(0.4, 9, 11, -11, 0.6, mat(0x8a8a94), verts=4, rot=(0, 90, -30)), cyl(1.2, 1.5, 11, -11, 0, mat(0x5a5a64), verts=8)]
    light = [sphere(1, 0, -13, 9.2, mat(0x4ae86a, 0.3, 0, 1, 3), seg=8, rings=6, scale=(1, 1, 0.5))]
    return model(C, 'robot_vacuum', body, movable={'brush_l': brush_l, 'brush_r': brush_r, 'light': light})


ALL = [rat_mother, rat_pup, cat, dog, owner, kid, guest, exterminator, robot_vacuum]
