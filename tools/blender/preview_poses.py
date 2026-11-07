"""Import each character FBX, list its animation clips and render a sheet of poses to art/previews/characters_poses.png."""
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib  # noqa: E402

TILE = 240
SHOTS = {
    'rat_mother': [('idle', 0), ('walk', 4), ('run', 2), ('sneak', 6), ('sniff', 8), ('drag', 5), ('stuck', 3), ('sleep', 0)],
    'rat_pup': [('walk', 4), ('sniff', 8), ('squeak', 8), ('freeze', 0), ('play', 5), ('rear', 9), ('eat', 6), ('sleep', 0)],
    'cat': [('idle_sit', 0), ('walk', 6), ('run', 3), ('pounce', 13), ('eat', 0), ('head_up', 8), ('groom', 10), ('sleep', 0)],
    'dog': [('idle', 0), ('walk', 6), ('run', 3), ('sniff_ground', 4), ('play', 4), ('bark', 4), ('sit', 0), ('sleep', 0)],
    'owner': [('idle', 0), ('walk', 7), ('run', 4), ('drink', 24), ('flashlight_sweep', 15), ('crouch_look', 24), ('swat', 8), ('yawn', 24)],
    'kid': [('idle', 0), ('walk', 7), ('run', 4), ('excited', 5), ('sit_bed', 0), ('sleep_bed', 0), ('scream', 3), ('climb', 7)],
    'guest': [('walk', 7), ('look_around', 18), ('sit_up', 30), ('sleep_floor', 0), ('use_phone', 0), ('crouch', 0), ('react_scared', 8), ('idle', 0)],
    'exterminator': [('walk', 7), ('spray', 10), ('inspect', 15), ('set_trap', 20), ('check_trap', 10), ('note', 0), ('stand_ready', 0), ('leave', 7)],
}


def setup_cam(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    c = (mn + mx) / 2
    r = max((mx - mn).length / 2, 0.05)
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
    bpy.context.collection.objects.link(cam)
    cam.location = c + Vector((1.3, -1.0, 0.6)).normalized() * r * 3.2
    cam.rotation_euler = (c - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'MATERIAL'
    sc.display.shading.show_object_outline = True
    sc.render.resolution_x = sc.render.resolution_y = TILE
    sc.world = bpy.data.worlds.new('w')


def frame_pose(meshes):
    """Point the camera at the evaluated (posed) meshes."""
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in meshes:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        pts += [ev.matrix_world @ v.co for v in me.vertices]
        ev.to_mesh_clear()
    if not pts:
        return
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    c, r = (mn + mx) / 2, max((mx - mn).length / 2, 0.05)
    cam = bpy.context.scene.camera
    cam.location = c + Vector((0.9, -1.3, 0.5)).normalized() * r * 3.0
    cam.rotation_euler = (c - cam.location).to_track_quat('-Z', 'Y').to_euler()


def main():
    from PIL import Image, ImageDraw
    tmp = os.path.join(lib.DOCS, 'previews', '_tmp')
    os.makedirs(tmp, exist_ok=True)
    tiles = []
    for name, shots in SHOTS.items():
        lib.reset()
        bpy.ops.import_scene.fbx(filepath=os.path.join(lib.ROOT, 'characters', name + '.fbx'))
        arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
        acts = {a.name.split('|')[-1]: a for a in bpy.data.actions}
        print(name, 'clips:', ', '.join(sorted(acts)))
        meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
        setup_cam(meshes)
        for clipname, fr in shots:
            act = acts.get(clipname)
            if not act:
                print('  missing', clipname)
                continue
            arm.animation_data.action = act
            try:
                if act.slots:
                    arm.animation_data.action_slot = act.slots[0]
            except Exception:
                pass
            bpy.context.scene.frame_set(int(act.frame_range[0]) + fr)
            frame_pose(meshes)
            out = os.path.join(tmp, '%s_%s.png' % (name, clipname))
            bpy.context.scene.render.filepath = out
            bpy.ops.render.render(write_still=True)
            tiles.append(('%s: %s' % (name, clipname), out))
    cols = 8
    rows = (len(tiles) + cols - 1) // cols
    img = Image.new('RGB', (cols * TILE, rows * (TILE + 18)), (24, 26, 34))
    dr = ImageDraw.Draw(img)
    for i, (label, p) in enumerate(tiles):
        x, y = (i % cols) * TILE, (i // cols) * (TILE + 18)
        img.paste(Image.open(p).convert('RGB'), (x, y))
        dr.text((x + 6, y + TILE + 3), label, fill=(230, 226, 214))
        os.remove(p)
    img.save(os.path.join(lib.DOCS, 'previews', 'characters_poses.png'))


main()
