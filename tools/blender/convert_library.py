"""Convert the free Quaternius packs (CC0, OpenUSD copy at github.com/chibifire-stages/quaternius-stage) to .glb
for Blender and Godot, and render a contact sheet per pack.

  git clone --depth 1 https://github.com/chibifire-stages/quaternius-stage.git /tmp/q
  python tools/blender/convert_library.py /tmp/q/models art/library/quaternius     (Blender's Python, bpy)
"""
import glob
import json
import math
import os
import sys

import bpy
from mathutils import Vector

PACKS = ["UltimateHomeInterior", "Furniture", "UltimateFurniture", "UltimateFood", "JunkFood", "UltimateAnimatedAnimals"]
src, dst = sys.argv[-2], sys.argv[-1]


def bounds():
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in bpy.data.objects:
        if o.type == 'MESH':
            for v in o.bound_box:
                w = o.matrix_world @ Vector(v)
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
    return lo, hi


index = {}
for pack in PACKS:
    files = sorted(glob.glob(os.path.join(src, pack, "*.usda")))
    out = os.path.join(dst, pack)
    os.makedirs(out, exist_ok=True)
    index[pack] = []
    for f in files:
        name = os.path.splitext(os.path.basename(f))[0]
        for p in ("SK_", "S_"):
            if name.startswith(p):
                name = name[len(p):]
        bpy.ops.wm.read_factory_settings(use_empty=True)
        try:
            bpy.ops.wm.usd_import(filepath=f)
        except Exception as e:
            print("skip", f, e)
            continue
        lo, hi = bounds()
        size = hi - lo
        bpy.ops.export_scene.gltf(filepath=os.path.join(out, name + ".glb"), export_format='GLB', export_animations=False)
        index[pack].append({"file": pack + "/" + name + ".glb", "size_blender_units": [round(size.x, 3), round(size.y, 3), round(size.z, 3)]})
        print(pack, name, "%.2f x %.2f x %.2f" % tuple(size), flush=True)
with open(os.path.join(dst, "index.json"), "w") as fh:
    json.dump(index, fh, indent=1)
