"""Cut-out figures for the comic prologue: the game's own rat and street cat posed mid-clip and rendered side-on as
dark silhouettes with a thin cold rim (lightning from behind), on a clear background.

    python tools/blender/comic_cutouts.py

Writes godot/assets/story/cut_<name>.png. They stand in until painted figures are dropped into the panels.
"""
import bpy  # (first: the pip build of bpy)
import math
import os
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CH = os.path.join(REPO, "godot", "assets", "models", "characters")
OUT = os.path.join(REPO, "godot", "assets", "story")

# name: model, clip (part of the action's name), point in the clip (0..1), turn about the up axis (deg)
ONLY = os.environ.get("CUT")
CUTS = {
    "rat_run": ("rat_mother", "run", 0.35, 90.0),
    "cat_run": ("cat_street", "run", 0.55, 90.0),
    "cat_pounce": ("cat_street", "pounce", 0.55, 90.0),
    "cat_sit": ("cat_street", "idle", 0.0, 60.0),
}


def render(name, model, clip, at, yaw):
    bpy.ops.wm.read_homefile(use_empty=True)
    sc = bpy.context.scene
    bpy.ops.import_scene.gltf(filepath=os.path.join(CH, model + ".glb"))
    arm = next((o for o in sc.objects if o.type == "ARMATURE"), None)
    act = None
    if arm:
        acts = [a for a in bpy.data.actions if clip in a.name.lower()]
        act = min(acts, key=lambda a: len(a.name)) if acts else None
        if arm.animation_data is None:
            arm.animation_data_create()
        for t in list(arm.animation_data.nla_tracks):
            arm.animation_data.nla_tracks.remove(t)
        arm.animation_data.action = act
        if act:
            f0, f1 = act.frame_range
            sc.frame_set(int(round(f0 + (f1 - f0) * at)))
    root = arm or next(o for o in sc.objects if o.type == "MESH")
    if arm:  # (bone display shapes and other loose meshes out: only the skinned body counts)
        for o in list(sc.objects):
            if o.type == "MESH" and not o.find_armature():
                bpy.data.objects.remove(o)
    root.rotation_mode = "XYZ"
    root.rotation_euler.z += math.radians(yaw)
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in sc.objects:
        if o.type == "MESH":
            ev = o.evaluated_get(deps)
            m = ev.to_mesh()
            pts += [ev.matrix_world @ v.co for v in m.vertices]
            ev.to_mesh_clear()
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    mid = (lo + hi) / 2
    size = hi - lo
    print("bounds", name, tuple(round(x, 3) for x in lo), tuple(round(x, 3) for x in hi))
    # black, with a thin pale rim: a fresnel-driven emission
    mat = bpy.data.materials.new("sil")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.12
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.55
    ramp.color_ramp.elements[0].color = (0.012, 0.012, 0.018, 1)
    ramp.color_ramp.elements[1].position = 0.95
    ramp.color_ramp.elements[1].color = (0.35, 0.42, 0.55, 1)
    nt.links.new(lw.outputs["Facing"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    for o in sc.objects:
        if o.type == "MESH":
            o.data.materials.clear()
            o.data.materials.append(mat)
    cam_d = bpy.data.cameras.new("c")
    cam_d.type = "ORTHO"
    w, h = max(size.x, size.y), size.z
    cam_d.ortho_scale = max(w, h) * 1.6
    cam = bpy.data.objects.new("c", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    # side-on: look along +y (the model faces -y in Blender after the glTF import, turned by yaw)
    cam.location = mid + Vector((0, -5.0, 0))
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24
    sc.render.film_transparent = True
    sc.world = bpy.data.worlds.new("w")
    sc.view_settings.view_transform = "Standard"
    sc.render.resolution_x = sc.render.resolution_y = 1800  # a roomy square frame, cut down after
    cam_d.sensor_fit = "AUTO"
    sc.render.filepath = os.path.join(OUT, "cut_%s.png" % name)
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    bpy.ops.render.render(write_still=True)
    from PIL import Image  # cut down to the figure, a little margin round it
    im = Image.open(sc.render.filepath)
    x0, y0, x1, y1 = im.split()[3].point(lambda a: 255 if a > 8 else 0).getbbox()
    m = 6
    im.crop((max(x0 - m, 0), max(y0 - m, 0), min(x1 + m, im.width), min(y1 + m, im.height))).save(sc.render.filepath)
    print("wrote", name, act.name if act else "-", sc.render.resolution_x, sc.render.resolution_y)


for k, v in CUTS.items():
    if not ONLY or ONLY == k:
        render(k, *v)
