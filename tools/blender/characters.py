"""Characters with skeletons and animations, in the chunky voxel style of art/reference/characters_concept.png:
rat mother and pup, cat, dog, owner, kid, guest, exterminator, robot vacuum. Sizes in cm, facing -Y."""
import math

from lib import box, cyl, sphere, torus, seg, mat, model
from rig import build, bind, clip, finish, s

C = 'characters'
WHITE, BLACK = 0xf4f0ea, 0x141414


def shade_hex(c, f):
    return (min(255, int(((c >> 16) & 255) * f)) << 16) | (min(255, int(((c >> 8) & 255) * f)) << 8) | min(255, int((c & 255) * f))


def loop(n, f):
    return {i: f(i / n) for i in range(n)}


def eye(x, y, z, r, iris=BLACK, white=False, k=1.0):
    """A glossy eye on a front face at y (the face looks toward -Y): optional white, iris box, highlight."""
    out = []
    if white:
        out.append(box(r * 2.2, 0.6 * k, r * 2.2, x, y - 0.2 * k, z - r * 1.1, mat(WHITE, 0.4)))
    out.append(box(r * 1.5, 0.7 * k, r * 1.8, x, y - 0.45 * k, z - r * 0.9, mat(iris, 0.15)))
    out.append(box(r * 0.55, 0.5 * k, r * 0.55, x + r * 0.35, y - 0.85 * k, z + r * 0.25, mat(0xffffff, 0.1)))
    return out


# ======================= RODENTS (mother and pup) =======================
def rodent(name, k, fur, belly, dark, head_k=1.0, pup=False, gear=False):
    """k: overall scale (1 = the 25 cm mother). head_k: pups have bigger heads."""
    q = lambda *v: tuple(a * k for a in v)
    pink, nose = mat(0xe89aa4, 0.6), mat(0xd85a6a, 0.35)
    F, Bm, D = mat(fur, 0.9), mat(belly, 0.9), mat(dark, 0.9)
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
    hz, hy = 7.4 * k, -10.6 * k                      # head centre
    hw, hd, hh = 7.6 * k * h, 7.2 * k * h, 6.8 * k * h
    front = hy - hd / 2
    parts = {
        'hips': [box(10.4 * k, 13 * k, 9.4 * k, 0, 3.5 * k, 1.6 * k, F, bevel=2.2 * k),
                 box(7.6 * k, 10 * k, 3 * k, 0, 3 * k, 1.4 * k, Bm, bevel=1 * k),
                 box(6 * k, 5 * k, 1.2 * k, -1 * k, 5 * k, 10.3 * k, D, bevel=0.4 * k),
                 box(4 * k, 4 * k, 1.2 * k, 2 * k, 0, 10.4 * k, D, bevel=0.4 * k)],
        'chest': [box(9 * k, 8.4 * k, 8.4 * k, 0, -4.2 * k, 2.4 * k, F, bevel=2 * k),
                  box(6.4 * k, 6 * k, 2.4 * k, 0, -4.6 * k, 2.2 * k, Bm, bevel=0.8 * k),
                  box(4.4 * k, 3.6 * k, 1.1 * k, 1.2 * k, -3.6 * k, 10.4 * k, D, bevel=0.3 * k)],
        'head': [box(hw, hd, hh, 0, hy, hz - hh / 2, F, bevel=1.6 * k * h),
                 box(hw * 0.62, 4.6 * k * h, hh * 0.56, 0, front - 2.1 * k * h, hz - hh * 0.42, F, bevel=1.1 * k * h),
                 box(hw * 0.5, 2 * k * h, hh * 0.3, 0, front - 2.4 * k * h, hz - hh * 0.46, Bm, bevel=0.6 * k * h),
                 sphere(1.05 * k * h, 0, front - 4.5 * k * h, hz - hh * 0.06, nose, seg=8, rings=6),
                 box(3 * k * h, 2 * k * h, 1 * k * h, 0, hy + 1.2 * k * h, hz + hh / 2 - 0.2 * k, D, bevel=0.3 * k)]
                + eye(-2.2 * k * h, front, hz + 0.8 * k * h, 1.0 * k * h, k=k * h) + eye(2.2 * k * h, front, hz + 0.8 * k * h, 1.0 * k * h, k=k * h),
    }
    if pup:  # little front teeth
        parts['head'] += [box(0.7 * k * h, 0.4 * k * h, 1.1 * k * h, x * k * h, front - 4 * k * h, hz - hh * 0.42 - 1 * k * h, mat(WHITE, 0.4)) for x in (-0.4, 0.4)]
    for sx in (-1, 1):
        ex = sx * 3.3 * k * h
        parts['head'] += [cyl(2.6 * k * h, 0.7 * k, ex, hy + 0.6 * k, hz + hh / 2 + 1.6 * k * h, F, verts=14, rot=(90, 0, 0)),
                          cyl(1.8 * k * h, 0.75 * k, ex, hy + 0.3 * k, hz + hh / 2 + 1.6 * k * h, pink, verts=12, rot=(90, 0, 0))]
        for dz in (-0.5, 0.5):  # whiskers
            parts['head'].append(box(4.4 * k, 0.12 * k, 0.12 * k, sx * 2.8 * k * h, front - 3.6 * k * h, hz - hh * 0.2 + dz * k, mat(0xf2ece4), rot=(0, 0, sx * 12)))
    tail = [((0, 9, 4.5), (0, 14, 3.5), 1.2, 1.0), ((0, 14, 3.5), (0, 19, 2.5), 1.0, 0.8), ((0, 19, 2.5), (0, 24, 1.8), 0.8, 0.55), ((0, 24, 1.8), (0, 29, 1.2), 0.55, 0.25)]
    for i, (a, b, r1, r2) in enumerate(tail):
        parts['tail%d' % (i + 1)] = [seg(q(*a), q(*b), r1 * k, r2 * k, pink, verts=8)]
    for lb, x, y in [('leg_fl', -3, -6), ('leg_fr', 3, -6), ('leg_bl', -3.5, 5), ('leg_br', 3.5, 5)]:
        parts[lb] = [box(2.6 * k, 2.8 * k, 4.4 * k, x * k, y * k, 0.8 * k, F, bevel=0.7 * k),
                     box(2.2 * k, 3 * k, 0.9 * k, x * k, (y - 0.6) * k, 0, pink, bevel=0.3 * k)]
    if gear:  # the mother's outfit from art/reference/key_art.png: goggles, red scarf, leather backpack
        leather, brass, lens = mat(0x5a3420, 0.75), mat(0xc8903a, 0.3, 0.8), mat(0x6a8ab0, 0.1, 0.2)
        scarf, buckle = mat(0xc8302e, 0.9), mat(0xd8b050, 0.3, 0.8)
        parts['head'] += [box(hw + 0.8 * k, hd * 0.5, 1.2 * k, 0, hy + 0.4 * k, hz + hh / 2 - 0.6 * k, leather, bevel=0.3 * k)]          # strap over the head
        for sx in (-1, 1):
            gx = sx * 1.9 * k
            parts['head'] += [cyl(1.7 * k, 1.6 * k, gx, front + 0.9 * k, hz + hh / 2 + 0.9 * k, brass, verts=12, rot=(70, 0, 0)),
                              cyl(1.25 * k, 1.8 * k, gx, front + 0.8 * k, hz + hh / 2 + 0.95 * k, lens, verts=12, rot=(70, 0, 0)),
                              box(1 * k, hd * 0.9, 1 * k, sx * (hw / 2 + 0.2 * k), hy, hz + hh * 0.2, leather)]                              # side straps
        parts['chest'] += [torus(4.4 * k, 1.3 * k, 0, -7.2 * k, 7.6 * k, scarf, seg=12, rseg=5, rot=(65, 0, 0)),                        # scarf round the neck
                           box(4 * k, 1.2 * k, 3.6 * k, 0.8 * k, -9.4 * k, 4.2 * k, scarf, bevel=0.5 * k, rot=(10, 0, 20)),               # knot and tail
                           box(2.6 * k, 1 * k, 3 * k, 2.6 * k, -9 * k, 2.4 * k, scarf, bevel=0.4 * k, rot=(15, 0, 35))]
        parts['hips'] += [box(7.6 * k, 7 * k, 5.4 * k, 0, 1.6 * k, 10 * k, leather, bevel=1 * k),                                      # backpack
                          box(6 * k, 2 * k, 3.6 * k, 0, -2.2 * k, 10.6 * k, mat(0x4a2a18, 0.8), bevel=0.6 * k),                        # front pocket
                          box(1.4 * k, 1 * k, 1.2 * k, 0, -3.3 * k, 13 * k, buckle),
                          box(8 * k, 2.4 * k, 1 * k, 0, 1.6 * k, 15.2 * k, mat(0x4a2a18, 0.8), bevel=0.3 * k),                          # flap
                          cyl(0.8 * k, 7 * k, -4.6 * k, 4 * k, 12 * k, mat(0x2a2a2a, 0.4, 0.4), verts=8, rot=(90, 0, 0))]              # little flashlight
        parts['chest'] += [box(1 * k, 8 * k, 1 * k, x * k, -3 * k, 10.4 * k, leather) for x in (-3.2, 3.2)]                               # shoulder straps
    mesh = bind(arm, parts, name)
    rodent_clips(arm, k, pup)
    return finish(arm, mesh, C, name)


def sleep_pose(k):
    return {'root': {'l': (0, 0, -3 * k)}, 'hips': (8, 0, 20), 'chest': (15, 0, 25), 'head': (35, 0, 30), 'tail1': (0, 0, 55), 'tail2': (0, 0, 60), 'tail3': (0, 0, 50),
            'leg_fl': (60, 0, 0), 'leg_fr': (60, 0, 0), 'leg_bl': (-60, 0, 0), 'leg_br': (-60, 0, 0)}


def rear_pose(k, t=0.0):
    return {'hips': (55, 0, 0), 'chest': (10, 0, 0), 'leg_bl': (-55, 0, 0), 'leg_br': (-55, 0, 0), 'leg_fl': (-60, 0, 0), 'leg_fr': (-60, 0, 0),
            'tail1': (50, 0, 6 * s(t)), 'tail2': (15, 0, 0), 'root': {'l': (0, 0, 0.5 * k)}}


def rodent_clips(a, k, pup=False):
    legs = lambda amp, t: {'leg_fl': (amp * s(t), 0, 0), 'leg_br': (amp * s(t), 0, 0), 'leg_fr': (-amp * s(t), 0, 0), 'leg_bl': (-amp * s(t), 0, 0)}
    clip(a, 'idle', 48, loop(48, lambda t: {'chest': (2 * s(t), 0, 0), 'head': (2 * s(t * 2), 0, 6 * s(t)), 'tail1': (0, 0, 8 * s(t)), 'tail2': (0, 0, 10 * s(t + 0.15)), 'tail3': (0, 0, 12 * s(t + 0.3))}))
    clip(a, 'walk', 16, loop(16, lambda t: dict(legs(28, t), root={'l': (0, 0, 0.6 * k * abs(s(t)))}, head=(3 * s(t * 2), 0, 0), tail1=(0, 0, 10 * s(t)), tail2=(0, 0, 12 * s(t + 0.2)))))
    clip(a, 'run', 10, loop(10, lambda t: {'leg_fl': (45 * s(t), 0, 0), 'leg_fr': (45 * s(t), 0, 0), 'leg_bl': (-45 * s(t), 0, 0), 'leg_br': (-45 * s(t), 0, 0),
                                           'hips': (8 * s(t), 0, 0), 'chest': (-10 * s(t), 0, 0), 'root': {'l': (0, 0, 1.6 * k * max(0, s(t)))}, 'tail1': (10 * s(t), 0, 0), 'tail2': (12 * s(t), 0, 0)}))
    clip(a, 'sneak', 24, loop(24, lambda t: dict(legs(14, t), root={'l': (0, 0, -2.2 * k)}, head=(-8, 0, 3 * s(t)), tail1=(8, 0, 4 * s(t)), tail2=(6, 0, 0))))
    clip(a, 'sniff', 32, loop(32, lambda t: dict(rear_pose(k, t), head=(-15 + 4 * s(t * 4), 0, 10 * s(t)))))
    clip(a, 'carry_walk', 16, loop(16, lambda t: dict(legs(24, t), head=(-14, 0, 0), root={'l': (0, 0, 0.5 * k * abs(s(t)))}, tail1=(0, 0, 10 * s(t)))))
    clip(a, 'sleep', 48, loop(48, lambda t: dict(sleep_pose(k), chest=(15 + 2 * s(t), 0, 25))))
    clip(a, 'eat', 24, loop(24, lambda t: {'head': (24 + 8 * s(t * 2), 0, 0), 'chest': (8, 0, 0), 'leg_fl': (-25, 0, 0), 'leg_fr': (-25, 0, 0)}))
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
    else:
        clip(a, 'squeak', 16, {0: {}, 5: {'head': (-30, 0, 0), 'chest': (-10, 0, 0)}, 11: {'head': (-30, 0, 0), 'chest': (-10, 0, 0)}, 16: {}}, loop=False)
        clip(a, 'freeze', 24, loop(24, lambda t: {'root': {'l': (0, 0, -2.5 * k)}, 'head': (25, 0, 3 * s(t * 6)), 'hips': (0, 0, 2 * s(t * 6)), 'tail1': (0, 0, 60), 'tail2': (0, 0, 50),
                                                  'leg_fl': (20, 0, 0), 'leg_fr': (20, 0, 0), 'leg_bl': (-20, 0, 0), 'leg_br': (-20, 0, 0)}))
        clip(a, 'play', 20, loop(20, lambda t: {'root': {'l': (0, 0, 2.5 * k * max(0, s(t)))}, 'hips': (-10 * s(t), 0, 15 * s(t * 0.5)), 'chest': (-15 * max(0, s(t)), 0, 0),
                                                'leg_fl': (-40 * max(0, s(t)), 0, 0), 'leg_fr': (-40 * max(0, s(t)), 0, 0), 'leg_bl': (20 * s(t), 0, 0), 'leg_br': (20 * s(t), 0, 0),
                                                'head': (-10, 0, 20 * s(t * 0.5)), 'tail1': (0, 0, 40 * s(t)), 'tail2': (0, 0, 40 * s(t + 0.2))}))
        clip(a, 'rear', 36, loop(36, lambda t: dict(rear_pose(k, t), leg_fl=(-80, 0, 10), leg_fr=(-80, 0, -10), head=(-5, 0, 25 * s(t)))))


def rat_mother():
    return rodent('rat_mother', 1.0, 0x8a868e, 0xc4bec2, 0x74707a, gear=True)


def rat_pup():
    return rodent('rat_pup', 0.56, 0x86818a, 0xccc6ca, 0x726e76, head_k=1.32, pup=True)


# ======================= CAT AND DOG =======================
def quad(name, L, H, fur, belly, kind):
    """Blocky four-legged animal. L: body length, H: shoulder height (cm)."""
    k = L / 50.0
    q = lambda *v: tuple(a * k for a in v)
    cat_ = kind == 'cat'
    F, Bm, D = mat(fur, 0.9), mat(belly, 0.9), mat(shade_hex(fur, 0.72), 0.9)
    hh = H / k
    tail = [(0, 16, hh), (0, 22, hh + 4), (0, 27, hh + 10), (0, 30, hh + 16), (0, 32, hh + 22)] if cat_ else [(0, 16, hh + 1), (0, 22, hh + 5), (0, 27, hh + 9), (0, 30, hh + 13), (0, 32, hh + 16)]
    bones = [('root', (0, 0, 0), (0, -6 * k, 0), None),
             ('hips', q(0, 12, hh), q(0, -4, hh + 1), 'root'), ('chest', q(0, -4, hh + 1), q(0, -16, hh + 3), 'hips'),
             ('head', q(0, -16, hh + 6), q(0, -27, hh + 8), 'chest')]
    for i in range(4):
        bones.append(('tail%d' % (i + 1), q(*tail[i]), q(*tail[i + 1]), 'hips' if i == 0 else 'tail%d' % i))
    for b, x, y, p in [('leg_fl', -6, -12, 'chest'), ('leg_fr', 6, -12, 'chest'), ('leg_bl', -6, 10, 'hips'), ('leg_br', 6, 10, 'hips')]:
        bones.append((b, q(x, y, hh), q(x, y, 0), p))
    arm = build(name, bones)
    hz, hy = (hh + 10) * k, -24 * k
    hw, hd, hgt = (16 if cat_ else 14) * k, (13 if cat_ else 14) * k, (14 if cat_ else 13) * k
    front = hy - hd / 2
    parts = {
        'hips': [box(15 * k, 21 * k, 14 * k, 0, 6 * k, (hh - 6) * k, F, bevel=2.5 * k), box(11 * k, 16 * k, 3 * k, 0, 6 * k, (hh - 6.4) * k, Bm, bevel=1 * k)],
        'chest': [box(15 * k, 14 * k, 15 * k, 0, -10 * k, (hh - 5) * k, F, bevel=2.5 * k), box(10 * k, 2 * k, 10 * k, 0, -17 * k, (hh - 4) * k, Bm, bevel=0.8 * k)],
        'head': [box(hw, hd, hgt, 0, hy, hz - hgt / 2, F, bevel=2.4 * k)],
    }
    if cat_:
        parts['head'] += [box(9 * k, 3.5 * k, 5.5 * k, 0, front - 1.2 * k, hz - hgt * 0.5 + 0.6 * k, Bm, bevel=1.2 * k),
                          box(2.2 * k, 1.2 * k, 1.6 * k, 0, front - 3 * k, hz - 1.6 * k, mat(0xe0707e, 0.4), bevel=0.3 * k)]
        parts['head'] += eye(-3.6 * k, front, hz + 1.6 * k, 1.9 * k, iris=0x6ac83a, white=False, k=k) + eye(3.6 * k, front, hz + 1.6 * k, 1.9 * k, iris=0x6ac83a, k=k)
        for x in (-3.6, 3.6):  # slit pupils
            parts['head'].append(box(0.9 * k, 0.6 * k, 2.8 * k, x * k - 0.3 * k, front - 1.2 * k, hz + 0.1 * k, mat(BLACK, 0.2)))
        for sx in (-1, 1):
            parts['head'] += [cyl(4 * k, 6 * k, sx * 5 * k, hy + 1 * k, hz + hgt / 2 - 1 * k, F, verts=4, r2=0.4 * k),
                              cyl(2.4 * k, 4 * k, sx * 5 * k, hy - 0.6 * k, hz + hgt / 2 - 0.8 * k, mat(0xe8a0a8, 0.6), verts=4, r2=0.3 * k)]
            for dz in (-0.6, 0.6):
                parts['head'].append(box(8 * k, 0.15 * k, 0.15 * k, sx * 6 * k, front - 2.6 * k, hz - 3.2 * k + dz * k, mat(0xf2ece4), rot=(0, 0, sx * 10)))
        parts['head'] += [box(2 * k, 4 * k, 1 * k, x * k, hy - 2 * k, hz + hgt / 2 - 0.2 * k, D, bevel=0.3 * k) for x in (-3, 0, 3)]  # forehead stripes
        parts['hips'] += [box(15.4 * k, 2.6 * k, 6 * k, 0, (y) * k, (hh + 2.5) * k, D, bevel=0.6 * k) for y in (0, 6, 12)]
        parts['chest'] += [box(15.4 * k, 2.6 * k, 6 * k, 0, -8 * k, (hh + 4) * k, D, bevel=0.6 * k),
                           torus(7 * k, 1 * k, 0, -16.5 * k, (hh + 6) * k, mat(0xc8303a, 0.5), seg=10, rseg=4, rot=(70, 0, 0)),
                           sphere(1.5 * k, 0, -20.2 * k, (hh + 2.6) * k, mat(0xf2c84a, 0.2, 0.8), seg=8, rings=6)]
    else:
        parts['head'] += [box(8.5 * k, 8 * k, 7 * k, 0, front - 3.6 * k, hz - hgt * 0.5 + 0.4 * k, Bm, bevel=1.4 * k),
                          box(4 * k, 2.4 * k, 2.6 * k, 0, front - 7.4 * k, hz - 2.8 * k, mat(0x1a1a1a, 0.3), bevel=0.6 * k),
                          box(4 * k, 1 * k, 0.8 * k, 0, front - 7.1 * k, hz - 5.8 * k, mat(0x3a2018, 0.6))]
        parts['head'] += eye(-3.4 * k, front, hz + 1.8 * k, 1.5 * k, iris=0x2a1a10, k=k) + eye(3.4 * k, front, hz + 1.8 * k, 1.5 * k, iris=0x2a1a10, k=k)
        parts['head'] += [box(3 * k, 0.8 * k, 1 * k, x * k, front - 0.3 * k, hz + 4.4 * k, D) for x in (-3.4, 3.4)]  # brows
        for sx in (-1, 1):
            parts['head'].append(box(3.4 * k, 6 * k, 11 * k, sx * 8.4 * k, hy + 1 * k, hz - 6 * k, D, bevel=1.2 * k, rot=(0, sx * 10, 0)))
        parts['chest'] += [torus(7.6 * k, 1.1 * k, 0, -16 * k, (hh + 6.5) * k, mat(0x2a2a30, 0.6), seg=10, rseg=4, rot=(70, 0, 0)),
                           cyl(1.6 * k, 0.5 * k, 0, -20.6 * k, (hh + 2.4) * k, mat(0xf2c84a, 0.2, 0.8), verts=10, rot=(80, 0, 0))]
    for i in range(4):
        r1 = (2.4 - i * 0.4) * k if cat_ else (2.6 - i * 0.45) * k
        col = D if (cat_ and i % 2 == 1) else F
        parts['tail%d' % (i + 1)] = [seg(q(*tail[i]), q(*tail[i + 1]), r1, r1 - 0.3 * k, col, verts=4)]
    paw = mat(WHITE if cat_ else shade_hex(belly, 0.95), 0.9)
    for b, x, y in [('leg_fl', -6, -12), ('leg_fr', 6, -12), ('leg_bl', -6, 10), ('leg_br', 6, 10)]:
        parts[b] = [box(5 * k, 5 * k, (hh - 3) * k, x * k, y * k, 2.6 * k, F, bevel=1 * k), box(5.4 * k, 6.4 * k, 3 * k, x * k, (y - 0.8) * k, 0, paw, bevel=1 * k)]
    mesh = bind(arm, parts, name)
    quad_clips(arm, k, kind)
    return finish(arm, mesh, C, name)


def quad_clips(a, k, kind):
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
        clip(a, 'groom', 40, loop(40, lambda t: dict(sit, leg_fl=(-70 + 10 * s(t * 2), 0, 15), head=(30 + 10 * s(t * 2), 0, -20), chest=(15, 0, -10))))
    else:
        clip(a, 'idle', 48, loop(48, lambda t: {'chest': (2 * s(t), 0, 0), 'head': (3 * s(t * 2), 0, 10 * s(t)), 'tail1': (0, 0, 20 * s(t * 2)), 'tail2': (0, 0, 20 * s(t * 2 + 0.2))}))
        clip(a, 'sniff_ground', 24, loop(24, lambda t: dict(walkl(18, t), head=(40 + 5 * s(t * 4), 0, 15 * s(t)), chest=(10, 0, 0), tail1=(0, 0, 15 * s(t * 2)))))
        clip(a, 'bark', 16, {0: {}, 4: {'head': (-25, 0, 0), 'chest': (-8, 0, 0), 'root': {'l': (0, 0, 2 * k)}}, 8: {'head': (5, 0, 0)}, 12: {'head': (-25, 0, 0)}, 16: {}}, loop=False)
        clip(a, 'play', 16, loop(16, lambda t: {'tail1': (0, 0, 40 * s(t * 2)), 'tail2': (0, 0, 40 * s(t * 2 + 0.2)), 'root': {'l': (0, 0, 4 * k * max(0, s(t)))},
                                                'chest': (-15 + 10 * s(t), 0, 0), 'leg_fl': (-30 * max(0, s(t)), 0, 0), 'leg_fr': (-30 * max(0, s(t)), 0, 0)}))
        clip(a, 'sit', 48, loop(48, lambda t: dict(sit, head=(-10, 0, 6 * s(t)), tail1=(40, 0, 25 * s(t * 2)))))


def cat():
    return quad('cat', 50, 30, 0xe08a34, 0xf6ead8, 'cat')


def dog():
    return quad('dog', 70, 45, 0xc08a4a, 0xe6c088, 'dog')


# ======================= PEOPLE =======================
def person(name, height, top, pants, skin=0xe8b896, hair=0x4a3020, shoes=0x2a3a8a, head_k=1.0, stripes=None, sole=None, extra=None):
    """A chunky voxel person. stripes: a second colour for horizontal bands on the top (the owner's pajamas)."""
    k = height / 180.0
    q = lambda *v: tuple(a * k for a in v)
    T, Pm, K, Hm, Sh = mat(top, 0.85), mat(pants, 0.85), mat(skin, 0.7), mat(hair, 0.9), mat(shoes, 0.8)
    T2 = mat(stripes, 0.85) if stripes else T
    bones = [('root', (0, 0, 0), (0, -10 * k, 0), None), ('hips', q(0, 0, 92), q(0, 0, 104), 'root'), ('spine', q(0, 0, 104), q(0, 0, 148), 'hips'),
             ('head', q(0, 0, 150), q(0, 0, 172), 'spine')]
    for sd, sx in (('l', -1), ('r', 1)):
        bones += [('upper_arm_' + sd, q(sx * 23, 0, 145), q(sx * 23, 0, 119), 'spine'), ('forearm_' + sd, q(sx * 23, 0, 119), q(sx * 23, 0, 92), 'upper_arm_' + sd),
                  ('thigh_' + sd, q(sx * 9.5, 0, 92), q(sx * 9.5, 0, 50), 'hips'), ('shin_' + sd, q(sx * 9.5, 0, 50), q(sx * 9.5, 0, 6), 'thigh_' + sd)]
    arm = build(name, bones)

    def banded(w, d, z0, z1, x=0.0, n=1, bev=1.5):
        """A vertical block from z0 to z1 (cm, unscaled), split into n alternating bands when the top is striped."""
        out = []
        n = n if stripes else 1
        step = (z1 - z0) / n
        for i in range(n):
            out.append(box(w * k, d * k, step * k + 0.05, x * k, 0, (z0 + i * step) * k, T if (n - 1 - i) % 2 == 0 else T2, bevel=bev * k if n == 1 else 0))
        return out

    # head: a big rounded block with a face on the front (-Y)
    hw, hd, hgt = 22 * k * head_k, 21 * k * head_k, 24 * k * head_k
    hz0 = 149 * k
    front = -hd / 2
    face_z = hz0 + hgt * 0.5
    H = dict(w=hw, d=hd, h=hgt, z0=hz0, front=front, eye_z=face_z, k=k, hk=head_k)
    head = [box(hw, hd, hgt, 0, 0, hz0, K, bevel=2.4 * k * head_k),
            box(hw + 0.6 * k, hd + 0.6 * k, hgt * 0.24, 0, 0.3 * k, hz0 + hgt * 0.8, Hm, bevel=1.6 * k),          # hair on top
            box(hw + 0.6 * k, hd * 0.35, hgt * 0.62, 0, hd * 0.34, hz0 + hgt * 0.4, Hm, bevel=1.4 * k),          # hair at the back
            box(hw * 0.14, 3 * k, hgt * 0.22, -hw * 0.43, front - 0.1 * k, hz0 + hgt * 0.7, Hm),                  # sideburns / fringe edges
            box(hw * 0.14, 3 * k, hgt * 0.22, hw * 0.43, front - 0.1 * k, hz0 + hgt * 0.7, Hm),
            box(4.6 * k * head_k, 3 * k, 5 * k * head_k, 0, front - 1.4 * k, face_z - 5 * k * head_k, mat(shade_hex(skin, 0.86), 0.7)),   # nose
            box(6 * k * head_k, 0.6 * k, 1.2 * k, 0, front - 0.3 * k, face_z - 8.5 * k * head_k, mat(0x5a2a24, 0.6))]                # mouth
    for sx in (-1, 1):
        head += eye(sx * 5 * k * head_k, front, face_z + 1.4 * k * head_k, 1.9 * k * head_k, iris=0x2a1c14, white=True, k=k)
        head.append(box(6 * k * head_k, 1 * k, 1.5 * k * head_k, sx * 5.2 * k * head_k, front - 0.4 * k, face_z + 4.6 * k * head_k, Hm))   # eyebrows
        head.append(box(2.4 * k, 4 * k, 5 * k * head_k, sx * (hw / 2 + 0.6 * k), 0, face_z - 3 * k * head_k, K, bevel=0.6 * k))          # ears
    parts = {'hips': [box(33 * k, 19 * k, 15 * k, 0, 0, 89 * k, Pm, bevel=2 * k)],
             'spine': banded(37, 21, 102, 148, n=6, bev=3) + [box(10 * k, 10 * k, 4 * k, 0, 0, 146 * k, K)],
             'head': head}
    for sd, sx in (('l', -1), ('r', 1)):
        parts['upper_arm_' + sd] = banded(10.5, 10.5, 119, 147, x=sx * 23, n=3)
        parts['forearm_' + sd] = banded(9.5, 9.5, 96, 119.5, x=sx * 23, n=3) + [box(8.5 * k, 8.5 * k, 9 * k, sx * 23 * k, 0, 87 * k, K, bevel=1.5 * k)]
        parts['thigh_' + sd] = [box(13.5 * k, 13.5 * k, 44 * k, sx * 9.5 * k, 0, 50 * k, Pm, bevel=1.5 * k)]
        parts['shin_' + sd] = [box(12.5 * k, 12.5 * k, 42 * k, sx * 9.5 * k, 0, 8 * k, Pm, bevel=1.5 * k), box(13.5 * k, 25 * k, 9 * k, sx * 9.5 * k, -4.5 * k, 0, Sh, bevel=2 * k)]
        if sole:
            parts['shin_' + sd].append(box(14 * k, 25.6 * k, 2.4 * k, sx * 9.5 * k, -4.5 * k, 0, mat(sole, 0.6)))
    attach = {}
    if extra:
        extra(parts, attach, k, q, H)
    mesh = bind(arm, parts, name, attach)
    return arm, mesh, k


def person_clips(a, k, set_):
    walk = lambda amp, t: {'thigh_l': (amp * s(t), 0, 0), 'thigh_r': (-amp * s(t), 0, 0), 'shin_l': (-amp * 0.9 * max(0, -s(t + 0.1)), 0, 0), 'shin_r': (-amp * 0.9 * max(0, s(t + 0.1)), 0, 0),
                           'upper_arm_l': (-amp * 0.7 * s(t), 0, 0), 'upper_arm_r': (amp * 0.7 * s(t), 0, 0), 'forearm_l': (-15, 0, 0), 'forearm_r': (-15, 0, 0), 'root': {'l': (0, 0, 1.5 * k * abs(s(t * 2)))}}
    crouch = {'root': {'l': (0, 0, -42 * k)}, 'thigh_l': (-95, 0, 0), 'thigh_r': (-95, 0, 0), 'shin_l': (110, 0, 0), 'shin_r': (110, 0, 0), 'spine': (45, 0, 0), 'head': (20, 0, 0),
              'upper_arm_r': (-80, 0, 0), 'upper_arm_l': (-20, 0, 0)}
    kneel = {'root': {'l': (0, 0, -36 * k)}, 'thigh_l': (-90, 0, 0), 'shin_l': (90, 0, 0), 'thigh_r': (-10, 0, 0), 'shin_r': (100, 0, 0), 'spine': (40, 0, 0), 'head': (25, 0, 0),
             'upper_arm_r': (-60, 0, 0), 'upper_arm_l': (-50, 0, 0), 'forearm_r': (-20, 0, 0), 'forearm_l': (-20, 0, 0)}
    lying = {'root': {'r': (-90, 0, 0), 'l': (0, 0, 12 * k)}, 'upper_arm_l': (0, 0, -10), 'upper_arm_r': (0, 0, 10)}
    sitting_bed = {'root': {'r': (-10, 0, 0), 'l': (0, 0, 12 * k)}, 'thigh_l': (-85, 0, 0), 'thigh_r': (-85, 0, 0), 'spine': (5, 0, 0)}
    if 'idle' in set_:
        clip(a, 'idle', 60, loop(60, lambda t: {'spine': (1.5 * s(t), 0, 0), 'head': (2 * s(t), 0, 4 * s(t * 0.5)), 'upper_arm_l': (0, 0, -4), 'upper_arm_r': (0, 0, 4)}))
    if 'walk' in set_:
        clip(a, 'walk', 30, loop(30, lambda t: walk(25, t)))
    if 'run' in set_:
        clip(a, 'run', 18, loop(18, lambda t: dict(walk(45, t), spine=(-10, 0, 0), forearm_l=(-70, 0, 0), forearm_r=(-70, 0, 0))))
    if 'look_around' in set_:
        clip(a, 'look_around', 72, loop(72, lambda t: {'head': (8, 0, 55 * s(t)), 'spine': (0, 0, 15 * s(t)), 'upper_arm_r': (-30, 0, 30), 'forearm_r': (-120, 0, 0)}))
    if 'drink' in set_:
        clip(a, 'drink', 48, {0: {}, 12: {'upper_arm_r': (-60, 0, 15), 'forearm_r': (-110, 0, 0), 'head': (-25, 0, 0)}, 36: {'upper_arm_r': (-60, 0, 15), 'forearm_r': (-110, 0, 0), 'head': (-25, 0, 0)}, 48: {}})
    if 'flashlight_sweep' in set_:
        clip(a, 'flashlight_sweep', 60, loop(60, lambda t: {'upper_arm_r': (-75, 0, 25 * s(t)), 'forearm_r': (-10, 0, 0), 'spine': (8, 0, 20 * s(t)), 'head': (15, 0, 20 * s(t))}))
    if 'crouch_look' in set_:
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
        clip(a, 'spray', 40, loop(40, lambda t: {'upper_arm_r': (-80, 0, 20 * s(t)), 'forearm_r': (-5, 0, 0), 'upper_arm_l': (-60, 0, -10), 'forearm_l': (-30, 0, 0),
                                                 'spine': (10, 0, 15 * s(t)), 'head': (15, 0, 15 * s(t)), 'thigh_l': (-15, 0, 0), 'shin_l': (10, 0, 0)}))
    if 'sleep_bed' in set_:
        clip(a, 'sleep_bed', 60, loop(60, lambda t: dict(lying, spine=(2 * s(t), 0, 0), head=(-8, 0, 20))))
        clip(a, 'toss', 48, {0: lying, 16: dict(lying, spine=(0, 25, 0), thigh_l=(-30, 0, 0), head=(-8, 0, -30)), 32: dict(lying, spine=(0, -20, 0), thigh_r=(-30, 0, 0)), 48: lying})
        clip(a, 'sit_up_scream', 30, {0: lying, 12: dict(sitting_bed, upper_arm_l=(-40, 0, -30), upper_arm_r=(-40, 0, 30), head=(-20, 0, 0)),
                                      30: dict(sitting_bed, upper_arm_l=(-150, 0, -30), upper_arm_r=(-150, 0, 30), head=(-30, 0, 0))}, loop=False)
        clip(a, 'sit_bed', 60, loop(60, lambda t: dict(sitting_bed, head=(5, 0, 15 * s(t)), upper_arm_l=(-20, 0, -10), upper_arm_r=(-20, 0, 10))))
    if 'excited' in set_:
        clip(a, 'excited', 20, loop(20, lambda t: {'root': {'l': (0, 0, 8 * k * max(0, s(t)))}, 'upper_arm_l': (-160, 0, -25 + 10 * s(t * 2)), 'upper_arm_r': (-160, 0, 25 - 10 * s(t * 2)),
                                                   'forearm_l': (-15, 0, 0), 'forearm_r': (-15, 0, 0), 'head': (-15, 0, 0), 'thigh_l': (-20 * max(0, s(t)), 0, 0), 'thigh_r': (-20 * max(0, s(t)), 0, 0),
                                                   'shin_l': (30 * max(0, s(t)), 0, 0), 'shin_r': (30 * max(0, s(t)), 0, 0)}))
    if 'scream' in set_:
        clip(a, 'scream', 24, loop(24, lambda t: {'upper_arm_l': (-50, 0, -30), 'upper_arm_r': (-50, 0, 30), 'forearm_l': (-130, 0, 0), 'forearm_r': (-130, 0, 0),
                                                  'head': (-20, 0, 6 * s(t * 3)), 'spine': (-8, 0, 3 * s(t * 3)), 'root': {'l': (0, 0, 0.6 * k * s(t * 4))}}))
    if 'climb' in set_:
        clip(a, 'climb', 30, loop(30, lambda t: {'upper_arm_l': (-150 + 30 * s(t), 0, -10), 'upper_arm_r': (-150 - 30 * s(t), 0, 10), 'forearm_l': (-30, 0, 0), 'forearm_r': (-30, 0, 0),
                                                 'thigh_l': (-50 - 30 * s(t), 0, 0), 'thigh_r': (-50 + 30 * s(t), 0, 0), 'shin_l': (60, 0, 0), 'shin_r': (60, 0, 0), 'head': (-25, 0, 0),
                                                 'root': {'l': (0, 0, 6 * k * abs(s(t)))}}))
    if 'sleep_floor' in set_:
        clip(a, 'sleep_floor', 60, loop(60, lambda t: dict(lying, spine=(2 * s(t), 0, 0), head=(-5, 0, 25))))
        clip(a, 'sit_up', 30, {0: lying, 30: {'root': {'r': (-5, 0, 0), 'l': (0, 0, 10 * k)}, 'thigh_l': (-88, 0, 0), 'thigh_r': (-88, 0, 0), 'spine': (10, 0, 0), 'upper_arm_l': (-20, 0, -20),
                                                'upper_arm_r': (-20, 0, 20)}}, loop=False)
    if 'use_phone' in set_:
        clip(a, 'use_phone', 48, loop(48, lambda t: dict(crouch, upper_arm_r=(-40, 0, 10), forearm_r=(-80, 0, 0), upper_arm_l=(-40, 0, -10), forearm_l=(-80, 0, 0),
                                                         head=(30 + 3 * s(t * 2), 0, 0), spine=(30, 0, 0))))
    if 'crouch' in set_:
        clip(a, 'crouch', 48, loop(48, lambda t: dict(crouch, head=(10, 0, 20 * s(t)), upper_arm_r=(-30, 0, 0), upper_arm_l=(-30, 0, 0), forearm_r=(-40, 0, 0), forearm_l=(-40, 0, 0))))
        clip(a, 'stand_up', 30, {0: dict(crouch, upper_arm_r=(-30, 0, 0)), 30: {}}, loop=False)
    if 'react_scared' in set_:
        scared = {'root': {'l': (0, -8 * k, 5 * k)}, 'spine': (-15, 0, 0), 'head': (-20, 0, 0), 'upper_arm_l': (-120, 0, -40), 'upper_arm_r': (-120, 0, 40),
                  'forearm_l': (-60, 0, 0), 'forearm_r': (-60, 0, 0), 'thigh_r': (-30, 0, 0), 'shin_r': (40, 0, 0)}
        clip(a, 'react_scared', 30, {0: {}, 6: scared, 22: dict(scared, root={'l': (0, -10 * k, 0)}), 30: {}}, loop=False)
    if 'inspect' in set_:
        clip(a, 'inspect', 60, loop(60, lambda t: dict(kneel, upper_arm_l=(-80, 0, -20 + 25 * s(t)), forearm_l=(-10, 0, 0), head=(30, 0, 20 * s(t)), spine=(40, 0, 10 * s(t)))))
    if 'set_trap' in set_:
        place = dict(kneel, upper_arm_r=(-45, 0, 0), upper_arm_l=(-45, 0, 0), forearm_r=(-10, 0, 0), forearm_l=(-10, 0, 0), spine=(55, 0, 0))
        clip(a, 'set_trap', 48, {0: kneel, 16: place, 32: place, 48: kneel}, loop=False)
    if 'check_trap' in set_:
        clip(a, 'check_trap', 48, loop(48, lambda t: dict(kneel, upper_arm_r=(-55 + 10 * s(t * 2), 0, 10), forearm_r=(-30 + 15 * s(t * 2), 0, 0), head=(35, 0, 10 * s(t)))))
    if 'note' in set_:
        clip(a, 'note', 48, loop(48, lambda t: {'upper_arm_l': (-30, 0, -15), 'forearm_l': (-90, 0, 20), 'upper_arm_r': (-35, 0, 15), 'forearm_r': (-85 + 6 * s(t * 4), 0, -10),
                                                'head': (25, 0, 0), 'spine': (5, 0, 0)}))
    if 'stand_ready' in set_:
        clip(a, 'stand_ready', 60, loop(60, lambda t: {'upper_arm_l': (-12, 0, 0), 'forearm_l': (-88, 0, -62), 'upper_arm_r': (-12, 0, 0), 'forearm_r': (-84, 0, 62),
                                                       'spine': (-3 + 1.5 * s(t), 0, 0), 'head': (-5, 0, 6 * s(t * 0.5)), 'thigh_l': (0, 0, -6), 'thigh_r': (0, 0, 6)}))
    if 'leave' in set_:
        clip(a, 'leave', 30, loop(30, lambda t: dict(walk(22, t), head=(12, 0, 0), spine=(4, 0, 0), upper_arm_l=(-30, 0, -10), forearm_l=(-90, 0, 0))))


def owner():
    def extra(parts, attach, k, q, H):
        hw, hd, h, z0, front = H['w'], H['d'], H['h'], H['z0'], H['front']
        beard = mat(0x4a2e1c, 0.95)
        parts['head'] += [box(hw + 0.8 * k, hd * 0.55, h * 0.36, 0, front + hd * 0.26, z0 - 0.4 * k, beard, bevel=1.4 * k),        # beard wrapping the jaw
                          box(hw * 0.6, 2.4 * k, h * 0.14, 0, front - 0.9 * k, z0 + h * 0.3, beard, bevel=0.5 * k),               # moustache
                          box(6 * k, 0.6 * k, 1.2 * k, 0, front - 2.2 * k, z0 + h * 0.18, mat(0x7a3a30, 0.6))]                   # mouth over the beard
        attach['forearm_r'] = [('flashlight', [cyl(2.2 * k, 16 * k, 23 * k, -10 * k, 88 * k, mat(0xc8343a, 0.4), verts=10, rot=(90, 0, 0)),
                                               cyl(3 * k, 0.6 * k, 23 * k, -18.3 * k, 88 * k, mat(0xfff0c0, 0.2, 0, 1, 2), verts=10, rot=(90, 0, 0))]),
                               ('glass', [cyl(3.4 * k, 11 * k, 23 * k, -6 * k, 85 * k, mat(0xcfe0ee, 0.05, 0, 0.5), verts=12)])]
        attach['forearm_l'] = [('slipper', [box(9 * k, 24 * k, 4.5 * k, -23 * k, -10 * k, 84 * k, mat(0xb8343a, 0.9), bevel=2 * k)])]
    a, m, k = person('owner', 180, 0x2f4f9a, 0x24305a, hair=0x4a2e1c, shoes=0xb8343a, stripes=0xe8eef8, extra=extra)
    person_clips(a, k, {'idle', 'walk', 'run', 'look_around', 'drink', 'flashlight_sweep', 'crouch_look', 'swat', 'place_trap', 'yawn'})
    return finish(a, m, C, 'owner')


def kid():
    def extra(parts, attach, k, q, H):
        hw, hd, h, z0, front = H['w'], H['d'], H['h'], H['z0'], H['front']
        hair = mat(0x8a5430, 0.9)
        parts['head'] += [box(6 * k, 5 * k, 5 * k, x * k, y * k, z0 + h + z * k, hair, bevel=1 * k, rot=(rx, 0, rz))
                          for x, y, z, rx, rz in [(-6, -4, -1, 20, 15), (2, -6, 0, 25, -10), (8, -2, -2, 10, -25), (-2, 4, 0, -10, 5)]]   # messy hair tufts
        parts['head'].append(box(hw * 0.8, 3 * k, h * 0.16, 0, front - 0.3 * k, z0 + h * 0.8, hair, bevel=0.8 * k))                  # fringe
        parts['spine'] += [box(26 * k, 8 * k, 12 * k, 0, 12 * k, 136 * k, mat(0x23509e, 0.85), bevel=3 * k),                            # hood
                           box(6 * k, 1.2 * k, 12 * k, 0, -11 * k, 118 * k, mat(WHITE, 0.6)),                                          # rocket body
                           box(3 * k, 1.4 * k, 4 * k, 0, -11.2 * k, 130 * k, mat(0xd8343a, 0.6)),                                      # rocket nose
                           box(9 * k, 1.3 * k, 3 * k, 0, -11.1 * k, 116 * k, mat(0xd8343a, 0.6)),                                      # fins
                           box(2.4 * k, 1.4 * k, 3 * k, 0, -11.3 * k, 113 * k, mat(0xf2c84a, 0.5, 0, 1, 1))]                            # flame
    a, m, k = person('kid', 120, 0x2a5ab8, 0x24408a, hair=0x8a5430, shoes=WHITE, sole=0xd8343a, head_k=1.32, extra=extra)
    person_clips(a, k, {'idle', 'walk', 'run', 'sleep_bed', 'excited', 'scream', 'climb'})
    return finish(a, m, C, 'kid')


def guest():
    def extra(parts, attach, k, q, H):
        hw, hd, h, z0, front = H['w'], H['d'], H['h'], H['z0'], H['front']
        beanie, band = mat(0x34343a, 0.95), mat(0x44444c, 0.95)
        parts['head'] += [box(hw + 1.6 * k, hd + 1.6 * k, h * 0.42, 0, 0, z0 + h * 0.68, beanie, bevel=2.4 * k),
                          box(hw + 2.2 * k, hd + 2.2 * k, h * 0.14, 0, 0, z0 + h * 0.62, band, bevel=1 * k)]
        pack = mat(0x1e1e22, 0.8)
        parts['spine'] += [box(28 * k, 12 * k, 36 * k, 0, 16 * k, 106 * k, pack, bevel=4 * k), box(20 * k, 4 * k, 12 * k, 0, 23 * k, 110 * k, mat(0x2a2a30, 0.8), bevel=2 * k)]
        parts['spine'] += [box(4 * k, 22 * k, 3 * k, x * k, 0, 144 * k, pack) for x in (-11, 11)] + [box(4 * k, 2 * k, 30 * k, x * k, -11 * k, 116 * k, pack) for x in (-11, 11)]
        attach['forearm_r'] = [('phone', [box(5 * k, 1 * k, 9 * k, 23 * k, -6 * k, 84 * k, mat(0x1a1a1e, 0.3)), box(4.2 * k, 0.3 * k, 7.6 * k, 23 * k, -6.6 * k, 84.7 * k, mat(0x8ac8f0, 0.2, 0, 1, 1.5))])]
    a, m, k = person('guest', 175, 0x3a7a4a, 0x2a2a30, skin=0x9a6a48, hair=0x1a1a1a, shoes=0x1e1e22, extra=extra)
    person_clips(a, k, {'idle', 'walk', 'look_around', 'sleep_floor', 'use_phone', 'crouch', 'react_scared'})
    return finish(a, m, C, 'guest')


def exterminator():
    def extra(parts, attach, k, q, H):
        hw, hd, h, z0, front = H['w'], H['d'], H['h'], H['z0'], H['front']
        cap, mask, rim = mat(0x34343a, 0.8), mat(0x2a2a2e, 0.6), mat(0x4a8a4a, 0.5)
        parts['head'] += [box(hw + 1.4 * k, hd + 1.4 * k, h * 0.3, 0, 0, z0 + h * 0.76, cap, bevel=2 * k),
                          box(hw * 0.9, 9 * k, 2 * k, 0, front - 4 * k, z0 + h * 0.76, cap, bevel=0.6 * k),                     # brim
                          box(hw * 0.86, 2 * k, 5 * k, 0, front - 0.8 * k, H['eye_z'] - 1 * k, mat(0x1a1a1a, 0.3)),             # goggles frame
                          box(hw * 0.78, 4 * k, h * 0.4, 0, front - 2 * k, z0 + 0.2 * k, mask, bevel=1.4 * k)]               # gas mask
        for sx in (-1, 1):
            parts['head'] += [box(5.4 * k, 1 * k, 3.6 * k, sx * 5 * k, front - 1.4 * k, H['eye_z'] - 0.8 * k, mat(0x9ac0d0, 0.1, 0, 0.6)),
                              cyl(3.6 * k, 5 * k, sx * 7 * k, front - 4.4 * k, z0 + 4 * k, mask, verts=10, rot=(90, 0, 0)),
                              cyl(3.8 * k, 1.2 * k, sx * 7 * k, front - 7.2 * k, z0 + 4 * k, rim, verts=10, rot=(90, 0, 0))]
        tank = mat(0x2a5a3a, 0.5, 0.3)
        parts['spine'] += [box(26 * k, 13 * k, 40 * k, 0, 16 * k, 104 * k, tank, bevel=5 * k), cyl(4 * k, 6 * k, 0, 16 * k, 144 * k, mat(0x1a1a1a, 0.5), verts=10),
                           box(38 * k, 21.6 * k, 4 * k, 0, 0, 102 * k, mat(0x6a5a30, 0.7))]                                            # belt
        parts['spine'] += [box(4 * k, 22 * k, 3 * k, x * k, 0, 144 * k, mat(0x1a1a1a, 0.6)) for x in (-11, 11)]
        parts['spine'] += [box(8 * k, 1.4 * k, 8 * k, x * k, -11 * k, 128 * k, mat(0xa88c44, 0.85), bevel=0.6 * k) for x in (-9, 9)]   # chest pockets
        parts['hips'].append(box(10 * k, 3 * k, 13 * k, -18 * k, 0, 88 * k, mat(0x1e1e22, 0.4), bevel=0.8 * k))                       # tablet on the belt
        glove = mat(0x3a6a3a, 0.7)
        for sd, sx in (('l', -1), ('r', 1)):
            parts['forearm_' + sd].append(box(9.4 * k, 9.4 * k, 10 * k, sx * 23 * k, 0, 86.5 * k, glove, bevel=1.6 * k))
            parts['shin_' + sd].append(box(13.6 * k, 13.6 * k, 16 * k, sx * 9.5 * k, 0, 6 * k, mat(0x1e1e22, 0.6), bevel=1.5 * k))      # boots
        attach['forearm_r'] = [('spray_gun', [cyl(1.6 * k, 30 * k, 23 * k, -14 * k, 88 * k, mat(0x1a1a1a, 0.4), verts=8, rot=(90, 0, 0)),
                                              box(5 * k, 8 * k, 9 * k, 23 * k, -2 * k, 82 * k, mat(0x3a7a3a, 0.4), bevel=1 * k),
                                              cyl(2.4 * k, 2 * k, 23 * k, -29 * k, 88 * k, mat(0xd8343a, 0.4), verts=8, rot=(90, 0, 0))])]
        attach['forearm_l'] = [('flashlight', [cyl(2.2 * k, 15 * k, -23 * k, -9 * k, 88 * k, mat(0x2a2a2a, 0.4), verts=10, rot=(90, 0, 0)),
                                               cyl(3 * k, 0.6 * k, -23 * k, -16.8 * k, 88 * k, mat(0xfff0c0, 0.2, 0, 1, 2), verts=10, rot=(90, 0, 0))])]
    a, m, k = person('exterminator', 180, 0xc8a858, 0xc8a858, skin=0xd8a07a, hair=0x3a2a20, shoes=0x1e1e22, extra=extra)
    person_clips(a, k, {'idle', 'walk', 'look_around', 'spray', 'inspect', 'set_trap', 'check_trap', 'note', 'stand_ready', 'leave'})
    return finish(a, m, C, 'exterminator')


# ======================= ROBOT VACUUM =======================
def robot_vacuum():
    body = [cyl(17, 7, 0, 0, 1.5, mat(0x2a2a30, 0.35), verts=28), cyl(16.5, 0.6, 0, 0, 8.5, mat(0x4a4a54, 0.3, 0.3), verts=28), box(14, 3, 1, 0, -12, 8.5, mat(0x1a1a1a)),
            cyl(3, 1, 0, 6, 8.8, mat(0x6a6a74, 0.3, 0.5), verts=14), cyl(2.5, 1.6, -9, 0, 0, mat(0x1a1a1a), verts=10, rot=(0, 90, 0)), cyl(2.5, 1.6, 9, 0, 0, mat(0x1a1a1a), verts=10, rot=(0, 90, 0))]
    brush_l = [cyl(0.4, 9, -11, -11, 0.6, mat(0x8a8a94), verts=4, rot=(0, 90, 30)), cyl(0.4, 9, -11, -11, 0.6, mat(0x8a8a94), verts=4, rot=(0, 90, -30)), cyl(1.2, 1.5, -11, -11, 0, mat(0x5a5a64), verts=8)]
    brush_r = [cyl(0.4, 9, 11, -11, 0.6, mat(0x8a8a94), verts=4, rot=(0, 90, 30)), cyl(0.4, 9, 11, -11, 0.6, mat(0x8a8a94), verts=4, rot=(0, 90, -30)), cyl(1.2, 1.5, 11, -11, 0, mat(0x5a5a64), verts=8)]
    light = [sphere(1, 0, -13, 9.2, mat(0x4ae86a, 0.3, 0, 1, 3), seg=8, rings=6, scale=(1, 1, 0.5))]
    return model(C, 'robot_vacuum', body, movable={'brush_l': brush_l, 'brush_r': brush_r, 'light': light})


# rat_mother, rat_pup, cat, dog, owner, kid and guest now come from free animated models: tools/blender/import_characters.py.
# Add them back here to regenerate the old blocky versions.
ALL = [exterminator, robot_vacuum]
