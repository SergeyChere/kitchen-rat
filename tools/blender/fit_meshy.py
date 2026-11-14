"""Put a new character mesh (made in Meshy, from the player's own design) onto one of the game's skeletons, keeping
every animation clip the game plays.

    python tools/blender/fit_meshy.py cat path/to/meshy.glb [out.glb]

What it does, for a four-legged animal:
  1. imports the game's model of that animal (art/characters/base/<name>.glb: skeleton + clips) and the new mesh;
  2. cuts the new mesh down to a game budget (Meshy gives ~400k triangles; a game character wants ~12k);
  3. sizes the new mesh like the old one (its body length, its feet on the floor), facing the same way (-Y);
  4. fits the skeleton to the new body: an overall stretch so the feet land on the new paws (found as the lowest
     parts of the mesh, one per corner) and the head reaches the new head, then each leg moved onto its own paw;
     the bones keep their directions, so the clips (which turn bones, they don't place them) still work;
  5. weights the skin to the bones by Blender's "automatic weights" (bone heat) on a closed, smoothed copy of the
     mesh (a Meshy mesh is full of holes and thin bits that bone heat chokes on), then copies those weights onto
     the real mesh;
  6. names the material as the game expects and exports the skeleton, the new skin and all the clips as GLB.
"""
import bpy  # (first: the pip build of bpy makes bmesh importable)
import bmesh
import os
import sys
from mathutils import Vector

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BASE = os.path.join(REPO, "art", "characters", "base")
OUT = os.path.join(REPO, "godot", "assets", "models", "characters")

# per animal: the feet (front left/right, back left/right: the bone whose head is the paw), the head bone, the
# IK bones that ride under each paw, the bones that should not hold skin, and the triangle budget
RIGS = {
    "cat": {
        "feet": {"FL": "Bone.019", "FR": "Bone.016", "BL": "Bone.010", "BR": "Bone.013"},
        "legs": {"FL": ["Bone.017", "Bone.018", "Bone.019", "IKFrontLeft"], "FR": ["Bone.014", "Bone.015", "Bone.016", "IKFrontRight"],
                 "BL": ["Bone.008", "Bone.009", "Bone.010", "IKBackLeft"], "BR": ["Bone.011", "Bone.012", "Bone.013", "IKBackRight"]},
        "head": "Bone.003",
        "no_skin": ["IKBackLeft", "IKBackRight", "IKFrontLeft", "IKFrontRight", "Eyes"],
        "tris": 14000,
        "material": "Main",
    },
    # the rats' bones are points (head and tail together), which bone heat cannot weigh skin to: their skin takes
    # the weights of the old rat's skin instead, stretched the same way as the skeleton
    "rat_mother": {
        "feet": {"FL": "FrontFoot.L", "FR": "FrontFoot.R", "BL": "BackFoot.L", "BR": "BackFoot.R"},
        "legs": {"FL": ["FrontUpLeg.L", "FrontLowLeg.L", "FrontFoot.L"], "FR": ["FrontUpLeg.R", "FrontLowLeg.R", "FrontFoot.R"],
                 "BL": ["BackUpLeg.L", "BackLowLeg.L", "BackFoot.L"], "BR": ["BackUpLeg.R", "BackLowLeg.R", "BackFoot.R"]},
        "head": "Head",
        "no_skin": [],
        "tris": 12000,
        "material": "RatSkin",
    },
}
RIGS["dog"] = {
    "feet": {"FL": "FF.L", "FR": "FF.R", "BL": "FFB.L", "BR": "FFB.R"},
    "legs": {"FL": ["FrontUpperLeg.L", "FrontLowerLeg.L", "IKFrontLeg.L", "FF.L"], "FR": ["FrontUpperLeg.R", "FrontLowerLeg.R", "IKFrontLeg.R", "FF.R"],
             "BL": ["BackUpperLeg.L", "BackLowerLeg.L", "IKBackLeg.L", "FFB.L"], "BR": ["BackUpperLeg.R", "BackLowerLeg.R", "IKBackLeg.R", "FFB.R"]},
    "head": "Head",
    "no_skin": ["IKFrontLeg.L", "IKFrontLeg.R", "IKBackLeg.L", "IKBackLeg.R", "FF.L", "FF.R", "FFB.L", "FFB.R",
                "PoleTarget.L", "PoleTarget.R", "PoleTargetBack.L", "PoleTargetBack.R"],
    "tris": 14000,
    "material": "Main",
}
RIGS["cat_street"] = dict(RIGS["cat"], base="cat")
RIGS["rat_pup"] = dict(RIGS["rat_mother"], tris=6000)


def world_verts(o):
    mw = o.matrix_world
    return [mw @ v.co for v in o.data.vertices]


def bbox(points):
    lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return lo, hi


def select_only(*objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def paws(points, floor, height):
    """The four paws: the mesh's lowest points, split into corners round their middle."""
    low = [p for p in points if p.z < floor + height * 0.05]
    my = sum(p.y for p in low) / len(low)
    out = {}
    for key, fx, fy in [("FL", 1, -1), ("FR", -1, -1), ("BL", 1, 1), ("BR", -1, 1)]:
        g = [p for p in low if (p.x > 0) == (fx > 0) and (p.y > my) == (fy > 0)]
        out[key] = sum(g, Vector()) / len(g)
    return out


def fit(name, src, out_path):
    rig = RIGS[name]
    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(BASE, rig.get("base", name) + ".glb"))
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o)
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    if arm.animation_data:
        arm.animation_data.action = None
    old = next(o for o in bpy.context.scene.objects if o.type == "MESH" and o.find_armature() == arm)
    ov = world_verts(old)
    olo, ohi = bbox(ov)

    # the new mesh
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=src)
    new = next(o for o in bpy.data.objects if o not in before and o.type == "MESH")
    for o in list(bpy.data.objects):
        if o not in before and o != new and o.type != "MESH":
            bpy.data.objects.remove(o)
    new.parent = None
    select_only(new)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # its textures: the colour and the surface detail at 1024 px (Meshy gives three 2048 px maps, 18 MB); the
    # metal/roughness map goes — the game shades its own way
    for m in new.data.materials:
        if not (m and m.use_nodes):
            continue
        bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf:
            for inp in ["Metallic", "Roughness"]:
                for l in list(bsdf.inputs[inp].links):
                    m.node_tree.links.remove(l)
            bsdf.inputs["Metallic"].default_value = 0.0
            bsdf.inputs["Roughness"].default_value = 0.9
    for img in list(bpy.data.images):
        if img.users == 0:
            bpy.data.images.remove(img)
        elif img.size[0] > 1024:
            img.scale(1024, 1024)
    tris = sum(len(p.vertices) - 2 for p in new.data.polygons)
    if tris > rig["tris"]:
        dec = new.modifiers.new("cut", "DECIMATE")
        dec.ratio = rig["tris"] / tris
        dec.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier="cut")
    # its size: the body (its paws to its nose, not the tail) as long as the old one's, the paws on the floor
    nv = world_verts(new)
    nlo, nhi = bbox(nv)
    np_ = paws(nv, nlo.z, nhi.z - nlo.z)
    front_y = (np_["FL"].y + np_["FR"].y) / 2
    nose_y = nlo.y
    op_ = {k: arm.matrix_world @ arm.data.bones[b].head_local for k, b in rig["feet"].items()}
    o_front = (op_["FL"].y + op_["FR"].y) / 2
    o_back = (op_["BL"].y + op_["BR"].y) / 2
    o_nose = olo.y
    n_back = (np_["BL"].y + np_["BR"].y) / 2
    # as tall as the old one (the top of the head): a fat cat stays a cat-sized cat, not a bigger one
    k = (max(p.z for p in ov if p.y < o_front) - olo.z) / (max(p.z for p in nv if p.y < front_y) - nlo.z)
    new.scale = (k, k, k)
    select_only(new)
    bpy.ops.object.transform_apply(scale=True)
    nv = world_verts(new)
    nlo, nhi = bbox(nv)
    new.location = Vector((-(nlo.x + nhi.x) / 2, o_nose - nlo.y, -nlo.z))
    bpy.ops.object.transform_apply(location=True)
    nv = world_verts(new)
    nlo, nhi = bbox(nv)
    np_ = paws(nv, nlo.z, nhi.z - nlo.z)
    print("new body", tuple(round(x, 3) for x in nlo), tuple(round(x, 3) for x in nhi), "paws", {k2: tuple(round(x, 3) for x in v) for k2, v in np_.items()})

    # fit the skeleton: an overall stretch, then each leg onto its paw
    o_px = sum(abs(p.x) for p in op_.values()) / 4
    n_px = sum(abs(p.x) for p in np_.values()) / 4
    n_front = (np_["FL"].y + np_["FR"].y) / 2
    n_back = (np_["BL"].y + np_["BR"].y) / 2
    sx = n_px / o_px
    # lengthwise: nose to back paws (the paws alone mislead: a sitting rat has her front paws under her chest)
    n_nose = min(p.y for p in nv)
    sy = (n_back - n_nose) / (o_back - o_nose)
    head = arm.matrix_world @ arm.data.bones[rig["head"]].head_local
    head_top_new = max(p.z for p in nv if p.y < n_front)
    head_top_old = max(p.z for p in ov if p.y < o_front)
    sz = head_top_new / head_top_old

    def stretch(p):
        return Vector((p.x * sx, n_nose + (p.y - o_nose) * sy, p.z * sz))

    to_local = arm.matrix_world.inverted()
    if rig.get("weights") == "transfer":  # the old skin, stretched like the skeleton, to take its weights from
        omw = old.matrix_world
        oinv = omw.inverted()
        for v in old.data.vertices:
            v.co = oinv @ stretch(omw @ v.co)
        old.data.update()
    select_only(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    for b in eb:
        b.use_connect = False
    for b in eb:
        h = stretch(arm.matrix_world @ b.head)
        t = stretch(arm.matrix_world @ b.tail)
        b.head = to_local @ h
        b.tail = to_local @ t
    for key, chain in rig["legs"].items():
        # the whole leg moved onto its paw, every bone by the same step: a bone's direction must not change, or the
        # clips (which turn bones from their rest) bend the leg somewhere else and tear the paw off
        foot = arm.matrix_world @ eb[rig["feet"][key]].head
        d = np_[key] - foot
        d.z = 0.0
        for bn in chain:
            b = eb[bn]
            b.head = to_local @ ((arm.matrix_world @ b.head) + d)
            b.tail = to_local @ ((arm.matrix_world @ b.tail) + d)
    bpy.ops.object.mode_set(mode="OBJECT")
    for bn in rig["no_skin"]:
        if bn in arm.data.bones:
            arm.data.bones[bn].use_deform = False

    if rig.get("weights") == "transfer":
        for g in old.vertex_groups:
            new.vertex_groups.new(name=g.name)
        select_only(new)
        dt = new.modifiers.new("weights", "DATA_TRANSFER")
        dt.object = old
        dt.use_vert_data = True
        dt.data_types_verts = {"VGROUP_WEIGHTS"}
        dt.vert_mapping = "POLYINTERP_NEAREST"
        dt.layers_vgroup_select_src = "ALL"
        dt.layers_vgroup_select_dst = "NAME"
        bpy.ops.object.modifier_apply(modifier="weights")
        weighted = len(old.vertex_groups)
        bpy.data.objects.remove(old)
        return _finish(name, rig, arm, new, weighted, out_path, (sx, sy, sz))
    # the skin: bone heat on a closed, smoothed copy, then copied onto the real mesh
    omw = old.matrix_world
    oldpts = [stretch(omw @ v.co) for v in old.data.vertices]
    oldw = [[(old.vertex_groups[g.group].name, g.weight) for g in v.groups if g.weight > 0.01] for v in old.data.vertices]
    bpy.data.objects.remove(old)
    select_only(new)
    bpy.ops.object.duplicate()
    proxy = bpy.context.active_object
    proxy.name = "proxy"
    rm = proxy.modifiers.new("close", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = (nhi.z - nlo.z) / 70.0
    sm = proxy.modifiers.new("soft", "SMOOTH")
    sm.iterations = 4
    bpy.ops.object.modifier_apply(modifier="close")
    bpy.ops.object.modifier_apply(modifier="soft")
    # only the body: the remesh leaves crumbs (whisker and fur tips) that bone heat cannot solve, and one unsolved
    # island used to leave the whole skin unweighted
    bm = bmesh.new()
    bm.from_mesh(proxy.data)
    seen, best = set(), []
    for v0 in bm.verts:
        if v0 in seen:
            continue
        isl, stack = [], [v0]
        seen.add(v0)
        while stack:
            v = stack.pop()
            isl.append(v)
            for e in v.link_edges:
                w = e.other_vert(v)
                if w not in seen:
                    seen.add(w)
                    stack.append(w)
        if len(isl) > len(best):
            best = isl
    keep = set(best)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v not in keep], context="VERTS")
    bm.to_mesh(proxy.data)
    bm.free()
    select_only(proxy, arm)
    proxy.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    weighted = len(proxy.vertex_groups)
    bare = [v.index for v in proxy.data.vertices if sum(g.weight for g in v.groups) < 0.01]
    if bare:  # where the heat found no answer: the nearest bone (its head-to-tail segment), wholly
        print("bone heat left", len(bare), "of", len(proxy.data.vertices), "bare: given to the nearest bone")
        segs = []
        for bb in arm.data.bones:
            if bb.use_deform and bb.name not in rig["no_skin"]:
                segs.append((bb.name, arm.matrix_world @ bb.head_local, arm.matrix_world @ bb.tail_local))

        def dist(p, a2, b2):
            ab = b2 - a2
            t = 0.0 if ab.length_squared < 1e-12 else max(0.0, min(1.0, (p - a2).dot(ab) / ab.length_squared))
            return (a2 + ab * t - p).length
        for vi in bare:
            co = proxy.matrix_world @ proxy.data.vertices[vi].co
            bn = min(segs, key=lambda sg: dist(co, sg[1], sg[2]))[0]
            g = proxy.vertex_groups.get(bn) or proxy.vertex_groups.new(name=bn)
            g.add([vi], 1.0, "REPLACE")
    select_only(new)
    for g in proxy.vertex_groups:
        new.vertex_groups.new(name=g.name)
    dt = new.modifiers.new("weights", "DATA_TRANSFER")
    dt.object = proxy
    dt.use_vert_data = True
    dt.data_types_verts = {"VGROUP_WEIGHTS"}
    dt.vert_mapping = "POLYINTERP_NEAREST"
    dt.layers_vgroup_select_src = "ALL"
    dt.layers_vgroup_select_dst = "NAME"
    bpy.ops.object.modifier_apply(modifier="weights")
    bpy.data.objects.remove(proxy)
    return _finish(name, rig, arm, new, weighted, out_path, (sx, sy, sz))


def _finish(name, rig, arm, new, weighted, out_path, st):
    for bn in rig.get("no_skin", []):  # a helper bone (IK, pole) must hold no skin, or it drags the paws about
        g = new.vertex_groups.get(bn)
        if g:
            new.vertex_groups.remove(g)
    new.parent = arm
    new.matrix_parent_inverse = arm.matrix_world.inverted()
    mod = new.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    # smooth shading for the cut-down mesh, the material named as the game expects
    for p in new.data.polygons:
        p.use_smooth = True
    if new.data.materials:
        new.data.materials[0].name = rig["material"]
    new.name = name.capitalize()
    print("fit", name, "tris", sum(len(p.vertices) - 2 for p in new.data.polygons), "groups", weighted,
          "stretch", [round(x, 3) for x in st], "clips", len(bpy.data.actions))

    select_only(arm)
    for o in bpy.context.scene.objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", use_selection=True,
                              export_animations=True, export_animation_mode="ACTIONS", export_apply=False,
                              export_force_sampling=True, export_yup=True)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    name, src = args[0], args[1]
    out = args[2] if len(args) > 2 else os.path.join(OUT, name + ".glb")
    fit(name, src, out)
