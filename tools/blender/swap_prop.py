"""Swap one of the game's prop or food models for a new one made in Meshy, at the same size and in the same place.

    python tools/blender/swap_prop.py food/cheese_wheel path/to/meshy.glb [--tris 4000] [--keep-height]

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


def main(name, src, tris, keep_height):
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
    else:
        olo, ohi = Vector((-0.05, -0.05, 0)), Vector((0.05, 0.05, 0.1))
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
    if keep_height:
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
    main(a[0], a[1], tris, "--keep-height" in a)
