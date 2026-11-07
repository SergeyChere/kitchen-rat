"""Render a thumbnail of every model in art/library/<source>/<pack>/*.glb and a contact sheet per pack.
  python tools/blender/library_previews.py art/library/quaternius   (Blender's Python, bpy; needs Pillow)"""
import glob
import math
import os
import sys

import bpy
from mathutils import Vector

root = sys.argv[-1]
tmp = os.path.join(root, "_thumbs")
os.makedirs(tmp, exist_ok=True)


def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'MATERIAL'
    sc.display.shading.show_cavity = True
    sc.render.resolution_x = sc.render.resolution_y = 200
    sc.render.film_transparent = False
    sc.world = bpy.data.worlds.new("w")
    sc.world.color = (0.12, 0.13, 0.18)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    return sc, cam


for pack in sorted(os.listdir(root)):
    pdir = os.path.join(root, pack)
    if not os.path.isdir(pdir) or pack.startswith("_"):
        continue
    for f in sorted(glob.glob(os.path.join(pdir, "*.glb"))):
        out = os.path.join(tmp, pack + "__" + os.path.basename(f)[:-4] + ".png")
        if os.path.exists(out):
            continue
        sc, cam = setup()
        bpy.ops.import_scene.gltf(filepath=f)
        lo = Vector((1e9,) * 3)
        hi = Vector((-1e9,) * 3)
        for o in sc.objects:
            if o.type == 'MESH':
                for v in o.bound_box:
                    w = o.matrix_world @ Vector(v)
                    lo = Vector(map(min, lo, w))
                    hi = Vector(map(max, hi, w))
        c = (lo + hi) / 2
        r = max((hi - lo).length / 2, 0.01)
        d = Vector((1.0, -1.3, 0.8)).normalized()
        cam.location = c + d * r * 2.6
        cam.rotation_euler = (c - cam.location).to_track_quat('-Z', 'Y').to_euler()
        cam.data.clip_end = r * 20
        sc.render.filepath = out
        bpy.ops.render.render(write_still=True)

from PIL import Image, ImageDraw
for pack in sorted(os.listdir(root)):
    if pack.startswith("_") or not os.path.isdir(os.path.join(root, pack)):
        continue
    thumbs = sorted(glob.glob(os.path.join(tmp, pack + "__*.png")))
    cols = 10
    rows = math.ceil(len(thumbs) / cols)
    sheet = Image.new("RGB", (cols * 200, rows * 222), (20, 22, 30))
    dr = ImageDraw.Draw(sheet)
    for i, t in enumerate(thumbs):
        x, y = (i % cols) * 200, (i // cols) * 222
        sheet.paste(Image.open(t).convert("RGB"), (x, y))
        dr.text((x + 6, y + 204), os.path.basename(t).split("__")[1][:-4][:30], fill=(230, 225, 210))
    sheet.save(os.path.join(root, "preview_" + pack + ".png"))
    print("sheet", pack, len(thumbs))
