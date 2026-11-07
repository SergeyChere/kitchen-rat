"""Render a contact sheet of the FBX files in art/<category> to art/previews/<category>.png.
Usage: python tools/blender/preview.py props food finds"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402

TILE = 220


def render_one(path, out):
    lib.reset()
    bpy.ops.import_scene.fbx(filepath=path)
    objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    if not objs:
        return False
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    c = (mn + mx) / 2
    r = max((mx - mn).length / 2, 0.01)
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
    bpy.context.collection.objects.link(cam)
    d = Vector((0.9, -1.4, 0.8)).normalized() * r * 3.0
    cam.location = c + d
    cam.rotation_euler = (c - cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam.data.lens = 50
    cam.data.clip_start = r * 0.05
    cam.data.clip_end = r * 20
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.engine = 'BLENDER_WORKBENCH'
    sh = sc.display.shading
    sh.light = 'STUDIO'
    sh.color_type = 'MATERIAL'
    sh.show_shadows = True
    sh.show_cavity = True
    sh.show_object_outline = True
    sc.render.resolution_x = sc.render.resolution_y = TILE
    sc.render.film_transparent = False
    sc.world = bpy.data.worlds.new('w')
    sc.world.color = (0.12, 0.13, 0.17)
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)
    return True


def sheet(cat):
    from PIL import Image, ImageDraw
    src = os.path.join(lib.ROOT, cat)
    files = sorted(f for f in os.listdir(src) if f.endswith('.fbx'))
    tmp = os.path.join(lib.ROOT, 'previews', '_tmp')
    os.makedirs(tmp, exist_ok=True)
    tiles = []
    for f in files:
        out = os.path.join(tmp, f[:-4] + '.png')
        if render_one(os.path.join(src, f), out):
            tiles.append((f[:-4], out))
    cols = 6
    rows = (len(tiles) + cols - 1) // cols
    img = Image.new('RGB', (cols * TILE, rows * (TILE + 18)), (24, 26, 34))
    dr = ImageDraw.Draw(img)
    for i, (name, p) in enumerate(tiles):
        x, y = (i % cols) * TILE, (i // cols) * (TILE + 18)
        img.paste(Image.open(p).convert('RGB'), (x, y))
        dr.text((x + 6, y + TILE + 3), name, fill=(230, 226, 214))
    path = os.path.join(lib.ROOT, 'previews', cat + '.png')
    img.save(path)
    for _, p in tiles:
        os.remove(p)
    print('sheet', path, len(tiles))


for cat in (sys.argv[1:] or ['props', 'food', 'finds', 'characters', 'furniture', 'rooms']):
    sheet(cat)
