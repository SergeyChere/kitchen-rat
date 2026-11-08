"""Swap the game's generated furniture for Quaternius library models (CC0), fitted exactly into the old model's box
(so surface heights, footprints and every placement in the night data stay the same).

  bvenv/bin/python tools/blender/library_swap.py            # swap all in SWAP, write previews
  ONLY=chair,fridge bvenv/bin/python tools/blender/library_swap.py
  PREVIEW_ONLY=1 ...                                          # only render old vs new, don't overwrite

The old generated model is kept in art/furniture_generated/ the first time (tools/blender/furniture.py remakes it too).
Fronts face -Y in Blender (the game's convention); ROT turns a library model whose front faces elsewhere."""
import os, sys, shutil, math
import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LIB = os.path.join(ROOT, "art/library/quaternius/UltimateHomeInterior")
GAME = os.path.join(ROOT, "godot/assets/models/furniture")
KEEP = os.path.join(ROOT, "art/furniture_generated")
OUT_PREV = os.environ.get("PREVIEW_DIR", "/tmp")

# game model -> (library model, extra yaw in degrees so its front faces -Y)
SWAP = {
    "chair": ("Chair_1", 0),
    "bookcase": ("Bookshelf", 0),
    "fridge": ("KitchenFridge", 0),
    "counter_section": ("KitchenCabinet1", 0),
    "counter_corner": ("Kitchen3Drawers", 0),
    "counter_sink": ("KitchenSink", 0),
    "sideboard": ("Drawer_1", 0),
    "tv_stand": ("Drawer_2", 0),
    "side_table": ("NightStand_1", 0),
    "stool": ("Stool", 0),
    "plant": ("Houseplant_1", 0),
    "floor_lamp": ("LightFloor2", 0),
    "washer": ("BathroomWashingMachine", 0),
    "fireplace": ("Fireplace", 0),
    "shelf_unit": ("ShelfLarge", 0),
    "low_shelf": ("ShelfSmall1", 0),
}
ROT = {k: float(os.environ.get("ROT_" + k, v[1])) for k, v in SWAP.items()}


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def imp(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def bbox(objs):
    lo = Vector((1e9, 1e9, 1e9)); hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector((min(lo[i], w[i]) for i in range(3))); hi = Vector((max(hi[i], w[i]) for i in range(3)))
    return lo, hi


def fit(name, lib, yaw):
    clear()
    old = imp(os.path.join(GAME, name + ".glb"))
    lo, hi = bbox(old)
    bpy.ops.object.select_all(action="DESELECT")
    for o in old:
        o.select_set(True)
    bpy.ops.object.delete()
    new = imp(os.path.join(LIB, lib + ".glb"))
    meshes = [o for o in new if o.type == "MESH"]
    # bake every transform into the meshes and drop the empties, so one root holds plain meshes
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in new:
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.rotation_euler = (0, 0, math.radians(yaw))
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    nlo, nhi = bbox([ob])
    size, nsize = hi - lo, nhi - nlo
    s = Vector((size[i] / max(nsize[i], 1e-6) for i in range(3)))
    ob.scale = s
    bpy.ops.object.transform_apply(scale=True)
    nlo, nhi = bbox([ob])
    ob.location += lo - nlo
    bpy.ops.object.transform_apply(location=True)
    return ob, size, s


def preview(name, path):
    # front-left, a little above, orthographic: old (left) vs new (right) are rendered separately
    scn = bpy.context.scene
    scn.render.engine = "BLENDER_WORKBENCH"
    scn.display.shading.light = "STUDIO"
    scn.display.shading.color_type = "MATERIAL"
    scn.render.resolution_x = scn.render.resolution_y = 360
    scn.render.film_transparent = False
    lo, hi = bbox([o for o in scn.objects if o.type == "MESH"])
    c = (lo + hi) / 2
    r = max((hi - lo)) * 1.25
    cam = bpy.data.cameras.new("c")
    cam.type = "ORTHO"
    cam.ortho_scale = r * 1.3
    co = bpy.data.objects.new("c", cam)
    scn.collection.objects.link(co)
    d = Vector((-0.6, -1.0, 0.55)).normalized()
    co.location = c + d * r * 3
    co.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    scn.camera = co
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    only = [s for s in os.environ.get("ONLY", "").split(",") if s]
    os.makedirs(KEEP, exist_ok=True)
    for name, (lib, _) in SWAP.items():
        if only and name not in only:
            continue
        src = os.path.join(GAME, name + ".glb")
        kept = os.path.join(KEEP, name + ".glb")
        if not os.path.exists(kept):
            shutil.copy(src, kept)
        clear()
        imp(kept)
        preview(name, os.path.join(OUT_PREV, f"swap_{name}_old.png"))
        # fit against the original generated model (not an earlier swap)
        shutil.copy(kept, src) if not os.environ.get("PREVIEW_ONLY") else None
        ob, size, s = fit(name, lib, ROT[name])
        preview(name, os.path.join(OUT_PREV, f"swap_{name}_new.png"))
        print(f"SWAP {name:16s} <- {lib:22s} size {tuple(round(v, 3) for v in size)} scale {tuple(round(v, 2) for v in s)}")
        if not os.environ.get("PREVIEW_ONLY"):
            bpy.ops.object.select_all(action="DESELECT")
            ob.select_set(True)
            bpy.ops.export_scene.gltf(filepath=src, export_format="GLB", use_selection=True, export_apply=True)


main()
