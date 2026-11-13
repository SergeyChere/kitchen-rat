"""Restyle the game's people, cat and dog for the painted look (round 17, asked: "rework the Blender models of the
person, the cat and the dog — they are really bad").

The models came from free low-poly packs: hard facets, thin realistic limbs, small heads. This keeps each model's
skeleton, materials and every game clip (the game depends on all three) and changes only the mesh:

  1. the cut-apart flat-shaded triangles are welded and paired into quads, so the surface can be smoothed;
  2. proportions are pushed toward a storybook look by moving the REST mesh around its own bones: a bigger head
     (scaled about the neck), plumper body and limbs (pushed out from the bone's line), bigger paws, hands and feet,
     a fuller tail. Each vertex moves by the blend of its skin weights, so the joints stay smooth and every
     animation still fits;
  3. the body is subdivided (Catmull-Clark) into round shapes; the eyes keep their own geometry and are enlarged.

  python tools/blender/restyle_characters.py            (Blender's Python, bpy)
  ONLY=cat,dog python tools/blender/restyle_characters.py
  in:  art/characters/base/<name>.glb  (the models as the import pipeline built them)
  out: godot/assets/models/characters/<name>.glb
"""
import math
import os

import bpy  # (first: the pip build of bpy makes bmesh importable)
import bmesh
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BASE = os.path.join(REPO, "art", "characters", "base")
OUT = os.environ.get("OUTDIR") or os.path.join(REPO, "godot", "assets", "models", "characters")

# A morph: (mode, bones, factor, pivot bone or None)
#   "grow":   scale about the pivot bone's joint (default: each bone's own joint) — a head, a paw, a hand
#   "plump":  push out from the bone's line — a body, a leg, a tail
HUMAN_ARMS = ["UpperArm.L", "LowerArm.L", "UpperArm.R", "LowerArm.R"]
HUMAN_LEGS = ["UpperLeg.L", "LowerLeg.L", "UpperLeg.R", "LowerLeg.R"]
HANDS_L = ["Palm.L", "MiddleHand.L", "Fingers.L", "Thumb1.L", "Thumb2.L"]
HANDS_R = ["Palm.R", "MiddleHand.R", "Fingers.R", "Thumb1.R", "Thumb2.R"]


def human(head=1.32, limbs=1.24, body=1.1, hands=1.3, feet=1.2):
    return {
        "morph": [
            ("grow", ["Head"], head, "Neck"),
            ("plump", ["Abdomen", "Torso", "Hips", "Body"], body, None),
            ("plump", HUMAN_ARMS + HUMAN_LEGS + ["Shoulder.L", "Shoulder.R"], limbs, None),
            ("grow", HANDS_L, hands, "Palm.L"),
            ("grow", HANDS_R, hands, "Palm.R"),
            ("grow", ["Foot.L"], feet, "Foot.L"),
            ("grow", ["Foot.R"], feet, "Foot.R"),
        ],
        "keep": ["Eyes", "Blush"],
        "eyes": (["Eyes"], 1.12),
        "subdiv": 1,
    }


STYLES = {
    "cat": {
        "morph": [
            ("grow", ["Bone.003", "Eyes"], 1.36, "Bone.003"),
            ("plump", ["Bone", "Bone.001", "Bone.002"], 1.2, None),
            ("plump", ["Bone.014", "Bone.015", "Bone.017", "Bone.018", "Bone.008", "Bone.009", "Bone.011", "Bone.012"], 1.32, None),
            ("grow", ["Bone.016"], 1.35, None), ("grow", ["Bone.019"], 1.35, None),
            ("grow", ["Bone.010"], 1.35, None), ("grow", ["Bone.013"], 1.35, None),
            ("plump", ["Bone.004", "Bone.005", "Bone.006", "Bone.007"], 1.55, None),
        ],
        "keep": ["CatIris", "Eye", "EyeShine"],
        "eyes": (["CatIris", "Eye", "EyeShine"], 1.32),
        "subdiv": 1,
    },
    "dog": {
        "morph": [
            ("grow", ["Head", "Ear1.L", "Ear2.L", "Ear3.L", "Ear4.L", "Ear1.R", "Ear2.R", "Ear3.R", "Ear4.R"], 1.3, "Neck3"),
            ("plump", ["Body", "Back", "Torso", "Torso2", "Torso3", "Neck1", "Neck2", "Neck3"], 1.12, None),
            ("plump", ["BackUpperLeg.L", "BackLowerLeg.L", "BackLeg.L", "BackUpperLeg.R", "BackLowerLeg.R", "BackLeg.R",
                       "FrontUpperLeg.L", "FrontLowerLeg.L", "FrontUpperLeg.R", "FrontLowerLeg.R"], 1.28, None),
            ("plump", ["Tail1", "Tail2", "Tail3"], 1.35, None),
        ],
        "keep": ["Eyes_White", "Eyes_Pupil", "Eyes_Black"],
        "eyes": (["Eyes_White", "Eyes_Pupil", "Eyes_Black"], 1.5),
        "subdiv": 1,
    },
    "owner": human(),
    "kid": human(head=1.4, limbs=1.24, hands=1.26),
    "guest": human(),
}


def load(path):
    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    for o in list(bpy.data.objects):  # the importer's bone-shape sphere
        if o.type == "MESH" and o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o)
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    if arm.animation_data:
        arm.animation_data.action = None
    me = next(o for o in bpy.context.scene.objects if o.type == "MESH" and o.find_armature() == arm)
    return arm, me


def weld(me, height):
    """Weld the cut-apart triangles and pair them into quads (Catmull-Clark wants quads)."""
    bm = bmesh.new()
    bm.from_mesh(me.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=height * 2e-5)
    bmesh.ops.join_triangles(bm, faces=bm.faces, angle_face_threshold=math.radians(45),
                             angle_shape_threshold=math.radians(45), cmp_materials=True)
    bm.to_mesh(me.data)
    bm.free()
    me.data.update()


def morph(arm, me, spec):
    to_arm = arm.matrix_world.inverted() @ me.matrix_world
    back = to_arm.inverted()
    bones = arm.data.bones
    gname = {g.index: g.name for g in me.vertex_groups}
    rules = {}
    for mode, names, f, pivot in spec:
        for n in names:
            if n in bones:
                rules[n] = (mode, f, pivot)
    for v in me.data.vertices:
        p = to_arm @ v.co
        total = 0.0
        move = Vector()
        for g in v.groups:
            n = gname.get(g.group)
            if n is None or n not in bones or g.weight <= 0.0:
                continue
            total += g.weight
            rule = rules.get(n)
            if rule is None:
                continue
            mode, f, pivot = rule
            b = bones[n]
            if mode == "grow":
                c = bones[pivot].head_local if pivot and pivot in bones else b.head_local
                q = c + (p - c) * f
            else:
                a, t = b.head_local, b.tail_local
                ax = t - a
                k = max(0.0, min(1.0, (p - a).dot(ax) / max(ax.length_squared, 1e-12)))
                c = a + ax * k
                q = c + (p - c) * f
            move += (q - p) * g.weight
        if total > 0.0:
            v.co = back @ (p + move / total)
    me.data.update()


def enlarge_islands(me, mats, f):
    """Scale each connected piece made of these materials about its own centre (the eyes)."""
    idx = {i for i, m in enumerate(me.data.materials) if m and m.name in mats}
    if not idx:
        return
    bm = bmesh.new()
    bm.from_mesh(me.data)
    faces = {fc for fc in bm.faces if fc.material_index in idx}
    seen = set()
    for f0 in faces:
        if f0 in seen:
            continue
        stack, island = [f0], set()
        while stack:
            fc = stack.pop()
            if fc in island:
                continue
            island.add(fc)
            for e in fc.edges:
                for nb in e.link_faces:
                    if nb in faces and nb not in island:
                        stack.append(nb)
        seen |= island
        verts = {v for fc in island for v in fc.verts}
        c = sum((v.co for v in verts), Vector()) / len(verts)
        for v in verts:
            v.co = c + (v.co - c) * f
    bm.to_mesh(me.data)
    bm.free()
    me.data.update()


def islands(me, mats):
    """Centres of the connected pieces made of these materials (in the mesh's own space)."""
    idx = {i for i, m in enumerate(me.data.materials) if m and m.name in mats}
    bm = bmesh.new()
    bm.from_mesh(me.data)
    faces = {fc for fc in bm.faces if fc.material_index in idx}
    out, seen = [], set()
    for f0 in faces:
        if f0 in seen:
            continue
        stack, island = [f0], set()
        while stack:
            fc = stack.pop()
            if fc in island:
                continue
            island.add(fc)
            for e in fc.edges:
                for nb in e.link_faces:
                    if nb in faces and nb not in island:
                        stack.append(nb)
        seen |= island
        verts = {v for fc in island for v in fc.verts}
        out.append((sum((v.co for v in verts), Vector()) / len(verts), len(verts)))
    bm.free()
    return out


def add_blush(arm, me):
    """Rosy cheeks under the eyes, as the faces in a picture book have: a soft pink disc lying on each cheek,
    skinned to the head."""
    from mathutils.bvhtree import BVHTree
    eyes = sorted(islands(me, ["Eyes"]), key=lambda e: -e[1])[:2]
    if len(eyes) < 2:
        return
    a, b = eyes[0][0], eyes[1][0]
    spacing = (a - b).length
    to_arm = arm.matrix_world.inverted() @ me.matrix_world
    head = to_arm.inverted() @ arm.data.bones["Head"].head_local
    mid = (a + b) / 2
    fwd = mid - head
    up = Vector((0, 0, 1))
    fwd = (fwd - up * fwd.dot(up)).normalized()
    tree = BVHTree.FromObject(me, bpy.context.evaluated_depsgraph_get(), deform=False)
    pink = bpy.data.materials.new("Blush")
    pink.use_nodes = True
    pink.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (0.9, 0.42, 0.42, 1.0)
    parts = []
    for e in (a, b):
        side = (e - mid).normalized()
        target = e - up * spacing * 0.42 + side * spacing * 0.16
        hit, nrm, _, _ = tree.ray_cast(target + fwd * spacing, -fwd, spacing * 3)
        if hit is None:
            continue
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, location=me.matrix_world @ (hit + nrm * spacing * 0.02))
        o = bpy.context.active_object
        r = spacing * 0.24
        o.scale = (r, r, r * 0.18)
        o.rotation_euler = nrm.to_track_quat("Z", "Y").to_euler()
        o.data.materials.append(pink)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        parts.append(o)
    for o in parts:
        vg = o.vertex_groups.new(name="Head")
        vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
    if parts:
        bpy.ops.object.select_all(action="DESELECT")
        for o in parts:
            o.select_set(True)
        me.select_set(True)
        bpy.context.view_layer.objects.active = me
        bpy.ops.object.join()


def subdivide(me, levels, keep):
    """Catmull-Clark on the body only: the eyes are split off first (already round) and joined back after."""
    bpy.ops.object.select_all(action="DESELECT")
    me.select_set(True)
    bpy.context.view_layer.objects.active = me
    kept = None
    idx = [i for i, m in enumerate(me.data.materials) if m and m.name in keep]
    if idx:
        for p in me.data.polygons:
            p.select = p.material_index in idx
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_mode(type="FACE")
        bpy.ops.object.mode_set(mode="OBJECT")
        for p in me.data.polygons:
            p.select = p.material_index in idx
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.separate(type="SELECTED")
        bpy.ops.object.mode_set(mode="OBJECT")
        kept = next((o for o in bpy.context.selected_objects if o != me), None)
    mod = me.modifiers.new("Round", "SUBSURF")
    mod.levels = levels
    mod.render_levels = levels
    mod.quality = 3
    bpy.context.view_layer.objects.active = me
    while me.modifiers[0] != mod:
        bpy.ops.object.modifier_move_up(modifier=mod.name)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    if kept:
        bpy.ops.object.select_all(action="DESELECT")
        kept.select_set(True)
        me.select_set(True)
        bpy.context.view_layer.objects.active = me
        bpy.ops.object.join()
    for p in me.data.polygons:
        p.use_smooth = True
    if me.data.has_custom_normals:
        bpy.ops.object.select_all(action="DESELECT")
        me.select_set(True)
        bpy.context.view_layer.objects.active = me
        bpy.ops.mesh.customdata_custom_splitnormals_clear()


def restyle(name, st):
    arm, me = load(os.path.join(BASE, name + ".glb"))
    lo = min((me.matrix_world @ Vector(c)).z for c in me.bound_box)
    hi = max((me.matrix_world @ Vector(c)).z for c in me.bound_box)
    height = (hi - lo) / max(me.matrix_world.to_scale().z, 1e-9)
    before = len(me.data.polygons)
    weld(me, height)
    morph(arm, me, st["morph"])
    mats, f = st.get("eyes", ([], 1.0))
    if f != 1.0:
        enlarge_islands(me, mats, f)
    subdivide(me, st.get("subdiv", 1), st.get("keep", []))
    me = next(o for o in bpy.context.scene.objects if o.type == "MESH" and o.find_armature() == arm)
    if st.get("blush"):
        add_blush(arm, me)
        me = next(o for o in bpy.context.scene.objects if o.type == "MESH" and o.find_armature() == arm)
    after = len(me.data.polygons)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", use_selection=True,
                              export_animations=True, export_animation_mode="ACTIONS", export_apply=False,
                              export_force_sampling=True, export_yup=True)
    print("restyled", name, "faces", before, "->", after, "clips", len(bpy.data.actions))


only = [s for s in os.environ.get("ONLY", "").split(",") if s]
for n, st in STYLES.items():
    if not only or n in only:
        restyle(n, st)
