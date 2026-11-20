"""Solid box collision for a painted (Meshy) furniture model.

    python tools/blender/collision_boxes.py furniture/sofa [furniture/chair ...] [--cell 0.015] [--below 0.4]

The model is one painted skin: hollow inside, a table top often a single sheet. Used as a triangle mesh for
collision the rat could end up inside it (in the sofa, between the sheets of a table top) and stay stuck there.
This casts rays straight up through the model on a grid, turns what each column passes through into solid spans (a
lone sheet becomes a 2 cm slab), merges neighbouring columns with matching spans into boxes and writes them next to
the model as <name>.collision.json, in the model's own Godot space (x, y up, z). LevelBuilder.collide builds box
shapes from it instead of using the skin: no hollow inside, flat tops, clean edges to climb.

--below H keeps only what is under H metres (a plant: its pot, not the leaves).
"""
import bpy  # (first: the pip build of bpy makes bmesh importable)
import json
import os
import sys
from mathutils import Vector
from mathutils.bvhtree import BVHTree

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODELS = os.path.join(REPO, "godot", "assets", "models")

SLAB = 0.02      # a lone sheet (a face with nothing behind it) becomes a slab this thick
TOL_TOP = 0.015  # columns merge when their tops differ less than this (she walks over smaller steps)
TOL_BOT = 0.025  # ... and their bottoms less than this
MIN_T = 0.008    # thinner spans are thickened to this


def column_spans(bvh, x, y, z0, z1):
    hits = []
    o = Vector((x, y, z0 - 0.01))
    d = Vector((0.0, 0.0, 1.0))
    for _ in range(60):
        loc, nor, _i, dist = bvh.ray_cast(o, d, (z1 + 0.02) - o.z)
        if loc is None:
            break
        hits.append((loc.z, nor.z))
        o = loc + d * 1e-4
    spans = []
    start = None
    for z, nz in hits:
        if nz < -0.05:  # a face looking down: going up, she enters the solid here
            if start is None:
                start = z
        elif nz > 0.05:  # a face looking up: the solid ends here
            if start is not None:
                spans.append([start, z])
                start = None
            else:
                spans.append([z - SLAB, z])  # a lone top sheet
    if start is not None:
        spans.append([start, start + SLAB])  # a lone bottom sheet
    spans.sort()
    out = []
    for s in spans:
        if s[1] - s[0] < MIN_T:
            s = [s[1] - MIN_T, s[1]]
        s[0] = max(s[0], z0) if s[0] > z0 + 0.006 else z0  # down to the floor when it nearly touches it
        if out and s[0] <= out[-1][1] + 0.004:
            out[-1][1] = max(out[-1][1], s[1])
        else:
            out.append(s)
    return out


def compatible(a, b):
    if a is None or b is None or len(a) != len(b):
        return False
    return all(abs(p[0] - q[0]) < TOL_BOT and abs(p[1] - q[1]) < TOL_TOP for p, q in zip(a, b))


def boxes_for(obj, cell, below):
    deps = bpy.context.evaluated_depsgraph_get()
    bvh = BVHTree.FromObject(obj, deps)
    pts = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    nx = max(1, int((hi.x - lo.x) / cell + 0.999))
    ny = max(1, int((hi.y - lo.y) / cell + 0.999))
    cx = (hi.x - lo.x) / nx
    cy = (hi.y - lo.y) / ny
    grid = [[None] * ny for _ in range(nx)]
    for i in range(nx):
        for j in range(ny):
            sp = column_spans(bvh, lo.x + (i + 0.5) * cx, lo.y + (j + 0.5) * cy, lo.z, hi.z)
            if below > 0.0:
                sp = [[s[0], min(s[1], lo.z + below)] for s in sp if s[0] < lo.z + below - 0.01]
            grid[i][j] = sp if sp else None
    used = [[False] * ny for _ in range(nx)]
    boxes = []
    for j in range(ny):
        for i in range(nx):
            seed = grid[i][j]
            if seed is None or used[i][j]:
                continue
            i1 = i
            while i1 + 1 < nx and not used[i1 + 1][j] and compatible(seed, grid[i1 + 1][j]):
                i1 += 1
            j1 = j
            while j1 + 1 < ny and all(not used[k][j1 + 1] and compatible(seed, grid[k][j1 + 1]) for k in range(i, i1 + 1)):
                j1 += 1
            cells = [grid[k][m] for k in range(i, i1 + 1) for m in range(j, j1 + 1)]
            for k in range(i, i1 + 1):
                for m in range(j, j1 + 1):
                    used[k][m] = True
            for n in range(len(seed)):
                zb = min(c[n][0] for c in cells)
                zt = max(c[n][1] for c in cells)
                boxes.append((lo.x + i * cx, lo.y + j * cy, zb, lo.x + (i1 + 1) * cx, lo.y + (j1 + 1) * cy, zt))
    return boxes, lo, hi


def main(name, cell, below):
    path = os.path.join(MODELS, name + ".glb")
    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    boxes, lo, hi = boxes_for(obj, cell, below)
    # Blender (x, y, z up) → Godot (x, y up, z = -y)
    out = []
    for b in boxes:
        c = ((b[0] + b[3]) / 2, (b[2] + b[5]) / 2, -(b[1] + b[4]) / 2)
        s = (b[3] - b[0], b[5] - b[2], b[4] - b[1])
        out.append([round(v, 4) for v in c + s])
    dst = os.path.join(MODELS, name + ".collision.json")
    with open(dst, "w") as f:
        json.dump({"cell": cell, "boxes": out}, f, separators=(",", ":"))
    print("boxes", name, len(out), "size", tuple(round(v, 3) for v in (hi - lo)))


if __name__ == "__main__":
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    cell = float(a[a.index("--cell") + 1]) if "--cell" in a else 0.015
    below = float(a[a.index("--below") + 1]) if "--below" in a else 0.0
    skip = set()
    for k in ("--cell", "--below"):
        if k in a:
            skip |= {a.index(k), a.index(k) + 1}
    for i, n in enumerate(a):
        if i not in skip:
            main(n, cell, below)
