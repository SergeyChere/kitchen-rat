"""Swap one of the game's prop or food models for a new one made in Meshy, at the same size and in the same place.

    python tools/blender/swap_prop.py food/cheese_wheel path/to/meshy.glb [--tris 4000] [--keep-height]
    python tools/blender/swap_prop.py props/poison_box path/to/meshy.glb --size 0.28   (a new model: its longest side)
    ... --upright   (a candle that came in leaning: stood up along its long axis)
    ... --flat      (food that came in tilted: laid on its broadest side)
    ... --height 0.92  (an exact height in metres)
    ... --turn 90   (turn it by hand, degrees about the up axis; 0 = as it came, no automatic turn)

The old model (godot/assets/models/<name>.glb, its first copy kept in art/props/base/) gives the size: the new one
is scaled so its longest side matches the old one's (or its height, with --keep-height), centred on the old one's
middle and standing on the same floor. The mesh is cut down to a prop budget, the maps to 512 px, the metal and
roughness maps dropped (the game shades its own way).
"""
import bpy  # (first: the pip build of bpy makes bmesh importable)
import os
import shutil
import sys
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODELS = os.path.join(REPO, "godot", "assets", "models")
BASE = os.path.join(REPO, "art", "props", "base")


def bounds(objs):
    pts = []
    for o in objs:
        if o.type == "MESH":
            pts += [o.matrix_world @ Vector(c) for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def main(name, src, tris, keep_height, size=0.0, upright=False, flat=False, height=0.0, turn=None):
    path = os.path.join(MODELS, name + ".glb")
    keep = os.path.join(BASE, name + ".glb")
    if os.path.exists(path) and not os.path.exists(keep):
        os.makedirs(os.path.dirname(keep), exist_ok=True)
        shutil.copy(path, keep)
    bpy.ops.wm.read_homefile(use_empty=True)
    if os.path.exists(keep):
        bpy.ops.import_scene.gltf(filepath=keep)
        olo, ohi = bounds(bpy.context.scene.objects)
        for o in list(bpy.context.scene.objects):
            bpy.data.objects.remove(o)
    else:  # a new model: standing on the floor at the origin, its longest side `size`
        h = (size or 0.1) / 2
        olo, ohi = Vector((-h, -h, 0)), Vector((h, h, 2 * h))
    bpy.ops.import_scene.gltf(filepath=src)
    me = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    for o in list(bpy.context.scene.objects):
        if o != me:
            bpy.data.objects.remove(o)
    me.parent = None
    bpy.ops.object.select_all(action="DESELECT")
    me.select_set(True)
    bpy.context.view_layer.objects.active = me
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if flat:  # food that came in tilted as it was drawn (3/4 view): laid down on its broadest side
        import numpy as np
        co = np.array([v.co[:] for v in me.data.vertices])
        co -= co.mean(axis=0)
        w, v = np.linalg.eigh(co.T @ co)
        ax = Vector(v[:, 0].tolist())
        if ax.z < 0:
            ax = -ax
        me.data.transform(ax.rotation_difference(Vector((0, 0, 1))).to_matrix().to_4x4())
        me.data.update()
    if upright:  # a tall thin thing that came in leaning: its long axis (the vertices' main direction) straight up
        import numpy as np
        co = np.array([v.co[:] for v in me.data.vertices])
        co -= co.mean(axis=0)
        w, v = np.linalg.eigh(co.T @ co)
        ax = Vector(v[:, 2].tolist())
        if ax.z < 0:
            ax = -ax
        me.data.transform(ax.rotation_difference(Vector((0, 0, 1))).to_matrix().to_4x4())
        me.data.update()
    t0 = sum(len(p.vertices) - 2 for p in me.data.polygons)
    if t0 > tris:
        d = me.modifiers.new("cut", "DECIMATE")
        d.ratio = tris / t0
        d.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier="cut")
    for m in me.data.materials:
        bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None) if m and m.use_nodes else None
        if bsdf:
            for inp in ["Metallic", "Roughness"]:
                for link in list(bsdf.inputs[inp].links):
                    m.node_tree.links.remove(link)
            bsdf.inputs["Metallic"].default_value = 0.0
            bsdf.inputs["Roughness"].default_value = 0.9
    for img in list(bpy.data.images):
        if img.users == 0:
            bpy.data.images.remove(img)
        elif img.size[0] > 512:
            img.scale(512, 512)
    for p in me.data.polygons:
        p.use_smooth = True
    nlo, nhi = bounds([me])
    o, n = ohi - olo, nhi - nlo
    if turn is not None:  # turned by hand (0: as it came — its front already the old one's way)
        if turn:
            me.rotation_mode = "XYZ"
            me.rotation_euler = (0, 0, turn * 3.14159265 / 180.0)
            bpy.ops.object.transform_apply(rotation=True)
            nlo, nhi = bounds([me])
    elif abs(o.x - o.y) > 0.15 * max(o.x, o.y) and (o.x > o.y) != (n.x > n.y):  # long side the old model's way round
        me.rotation_mode = "XYZ"  # (glTF imports in quaternions)
        me.rotation_euler = (0, 0, 1.5707963)
        bpy.ops.object.transform_apply(rotation=True)
        nlo, nhi = bounds([me])
    if height:  # an exact height (m), whatever the old model's was
        k = height / max(nhi.z - nlo.z, 1e-6)
    elif size and not os.path.exists(keep):
        k = size / max(max(nhi - nlo), 1e-6)
    elif keep_height:
        k = (ohi.z - olo.z) / max(nhi.z - nlo.z, 1e-6)
    else:
        k = max(ohi - olo) / max(max(nhi - nlo), 1e-6)
    me.scale = (k, k, k)
    bpy.ops.object.transform_apply(scale=True)
    nlo, nhi = bounds([me])
    oc = (olo + ohi) / 2
    nc = (nlo + nhi) / 2
    me.location = Vector((oc.x - nc.x, oc.y - nc.y, olo.z - nlo.z))
    bpy.ops.object.transform_apply(location=True)
    me.name = os.path.basename(name)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True)
    print("swapped", name, "tris", sum(len(p.vertices) - 2 for p in me.data.polygons), "size", tuple(round(x, 3) for x in (nhi - nlo) * 1.0))


if __name__ == "__main__":
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    tris = int(a[a.index("--tris") + 1]) if "--tris" in a else 4000
    size = float(a[a.index("--size") + 1]) if "--size" in a else 0.0
    main(a[0], a[1], tris, "--keep-height" in a, size, "--upright" in a, "--flat" in a,
         float(a[a.index("--height") + 1]) if "--height" in a else 0.0,
         float(a[a.index("--turn") + 1]) if "--turn" in a else None)
