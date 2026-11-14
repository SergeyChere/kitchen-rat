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
import math
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


def keep_largest_island(proxy):
    """Only the body: the remesh leaves crumbs (whisker and hair tips, a party hat) that bone heat cannot solve,
    and one unsolved island leaves the whole skin unweighted."""
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


def copy_weights(src, dst):
    """Each vertex of dst takes the weights of the nearest vertex of src (both in world space)."""
    from mathutils.kdtree import KDTree
    kd = KDTree(len(src.data.vertices))
    mw = src.matrix_world
    for v in src.data.vertices:
        kd.insert(mw @ v.co, v.index)
    kd.balance()
    names = [g.name for g in src.vertex_groups]
    groups = {n: (dst.vertex_groups.get(n) or dst.vertex_groups.new(name=n)) for n in names}
    dmw = dst.matrix_world
    for v in dst.data.vertices:
        _, j, _ = kd.find(dmw @ v.co)
        for g in src.data.vertices[j].groups:
            if g.weight > 0.001:
                groups[names[g.group]].add([v.index], g.weight, "REPLACE")


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
    legd = {}
    for key, chain in rig["legs"].items():
        # the whole leg moved onto its paw, every bone by the same step: a bone's direction must not change, or the
        # clips (which turn bones from their rest) bend the leg somewhere else and tear the paw off
        foot = arm.matrix_world @ eb[rig["feet"][key]].head
        d = np_[key] - foot
        d.z = 0.0
        legd[key] = d
        for bn in chain:
            b = eb[bn]
            b.head = to_local @ ((arm.matrix_world @ b.head) + d)
            b.tail = to_local @ ((arm.matrix_world @ b.tail) + d)
    bpy.ops.object.mode_set(mode="OBJECT")
    for bn in rig["no_skin"]:
        if bn in arm.data.bones:
            arm.data.bones[bn].use_deform = False

    if rig.get("weights") == "transfer":
        # the old skin's hand-made weights fit these clips best: the old skin, stretched like the skeleton and
        # each leg's skin moved with its leg, gives every new vertex the weights of its nearest old one
        gname = {g.index: g.name for g in old.vertex_groups}
        leg_of = {bn: key for key, chain in rig["legs"].items() for bn in chain}
        omw = old.matrix_world
        oinv = omw.inverted()
        for v in old.data.vertices:
            off = Vector()
            for g in v.groups:
                key = leg_of.get(gname[g.group])
                if key:
                    off += legd[key] * g.weight
            v.co = oinv @ ((omw @ v.co) + off)
        old.data.update()
        copy_weights(old, new)
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
    keep_largest_island(proxy)
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
    copy_weights(proxy, new)
    # whiskers: thin and far from the closed copy, they took the weights of whatever lay nearest (a paw) and
    # trailed after it; anything that far out in front of the neck rides the head
    from mathutils.bvhtree import BVHTree
    tree = BVHTree.FromObject(proxy, bpy.context.evaluated_depsgraph_get())
    hb = arm.data.bones[rig["head"]]
    head_y = (arm.matrix_world @ hb.head_local).y
    reach = (nhi.z - nlo.z) * 0.03
    hg = new.vertex_groups.get(rig["head"]) or new.vertex_groups.new(name=rig["head"])
    moved = 0
    # …and a thin tail the closed copy lost goes to the nearest tail (or other) bone, not the rump beside it
    segs = [(bb.name, arm.matrix_world @ bb.head_local, arm.matrix_world @ bb.tail_local) for bb in arm.data.bones
            if bb.use_deform and bb.name not in rig["no_skin"]]

    def seg_d(p, a2, b2):
        ab = b2 - a2
        t = 0.0 if ab.length_squared < 1e-12 else max(0.0, min(1.0, (p - a2).dot(ab) / ab.length_squared))
        return (a2 + ab * t - p).length
    back = max((proxy.matrix_world @ v.co).y for v in proxy.data.vertices)
    for v in new.data.vertices:
        co = new.matrix_world @ v.co
        if co.y > back - reach:  # past the end of the closed copy: the thin tail
            bn = min(segs, key=lambda sg: seg_d(co, sg[1], sg[2]))[0]
        elif co.y <= head_y + reach:
            hit = tree.find_nearest(proxy.matrix_world.inverted() @ co)
            if hit[0] is None or hit[3] < reach:
                continue
            bn = rig["head"]
        else:
            continue
        for g in list(v.groups):
            new.vertex_groups[g.group].remove([v.index])
        (new.vertex_groups.get(bn) or new.vertex_groups.new(name=bn)).add([v.index], 1.0, "REPLACE")
        moved += 1
    print("whisker bits on the head:", moved)
    # the tail lies along the floor between the back paws: the heat lent its skin to the paws, and running, the
    # tail dragged a web of skin after them. Behind the back paws on the middle line, only tail and rump bones.
    tails = [bb.name for bb in arm.data.bones if bb.name.lower().startswith("tail") or bb.name in ("Back", "Hips", "Bone.004", "Bone.005", "Bone.006", "Bone.007")]
    if tails:
        back_paw_y = max(np_["BL"].y, np_["BR"].y)
        L = nhi.y - nlo.y
        names = {g.index: g.name for g in new.vertex_groups}
        tsegs = [sg for sg in segs if sg[0] in tails]
        for v in new.data.vertices:
            co = new.matrix_world @ v.co
            if co.y < back_paw_y + L * 0.03 or abs(co.x) > L * 0.045:
                continue
            ws = [(names[g.group], g.weight) for g in v.groups if g.weight > 0]
            keep = [(n2, w) for n2, w in ws if n2 in tails]
            if len(keep) == len(ws):
                continue
            for n2, _ in ws:
                new.vertex_groups[n2].remove([v.index])
            if not keep and tsegs:
                keep = [(min(tsegs, key=lambda sg: seg_d(co, sg[1], sg[2]))[0], 1.0)]
            tot = sum(w for _, w in keep) or 1.0
            for n2, w in keep:
                (new.vertex_groups.get(n2) or new.vertex_groups.new(name=n2)).add([v.index], w / tot, "REPLACE")
    bpy.data.objects.remove(proxy)
    return _finish(name, rig, arm, new, weighted, out_path, (sx, sy, sz))


def clean_sides(new, arm):
    """A vertex on the left takes nothing from a right-hand bone and the other way round (heat bleeds between
    legs set close together, and a paw then trails a shard after the other paw)."""
    side_of = {}
    for b in arm.data.bones:
        h = arm.matrix_world @ b.head_local
        if b.name.endswith((".L", ".R")) and abs(h.x) > 1e-4:
            side_of[b.name] = 1 if h.x > 0 else -1
    if not side_of:
        return
    names = {g.index: g.name for g in new.vertex_groups}
    width = max(abs((new.matrix_world @ v.co).x) for v in new.data.vertices)
    for v in new.data.vertices:
        x = (new.matrix_world @ v.co).x
        if abs(x) < width * 0.08:
            continue
        sd = 1 if x > 0 else -1
        bad = [g for g in v.groups if side_of.get(names[g.group], sd) != sd and g.weight > 0]
        if not bad:
            continue
        good = [(names[g.group], g.weight) for g in v.groups if g not in bad and g.weight > 0]
        for g in [names[g.group] for g in bad]:
            new.vertex_groups[g].remove([v.index])
        tot = sum(w for _, w in good)
        if tot > 0:
            for n2, w in good:
                new.vertex_groups[n2].add([v.index], w / tot, "REPLACE")


def _finish(name, rig, arm, new, weighted, out_path, st):
    clean_sides(new, arm)
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




# ---------------------------------------------------------------------------------------------------------------
# People. The game's people (Quaternius) stand in a T-pose; a Meshy person stands in an A-pose (arms hanging at
# about 45°). The skeleton is fitted to the new body with its arms lowered to the mesh's, the skin weighted by
# bone heat, then the arms raised back to the T-pose with the skin following — and that pose made the rest, so
# every bone is back in its old direction and the clips work unchanged.
HUMAN_ARMS = {"L": ["UpperArm.L", "LowerArm.L", "Palm.L", "MiddleHand.L", "Fingers.L", "Thumb1.L", "Thumb2.L"],
              "R": ["UpperArm.R", "LowerArm.R", "Palm.R", "MiddleHand.R", "Fingers.R", "Thumb1.R", "Thumb2.R"]}
HUMAN_NO_SKIN = ["Bone", "Foot.L", "Foot.R", "PoleTarget.L", "PoleTarget.R"]


def split_arms(new, nv, H, sh_z, hand):
    """The proxy fuses a hanging arm with the body where they touch, so the heat lets the arm drag the body's sides
    along (wings of shirt in the T-pose). Below the armpit, each height's slice of the body is split where the
    arm and the side part: a vertex inside belongs to the body (no arm weights), outside to the arm (only arm
    weights)."""
    arm_bones = set(sum(HUMAN_ARMS.values(), []))
    bins = 120
    edge = {}
    for side in (1, -1):
        last = None
        for i in range(bins):
            z0, z1 = H * i / bins, H * (i + 1) / bins
            xs = sorted(abs(p.x) for p in nv if z0 <= p.z < z1 and (p.x > 0) == (side > 0))
            e = None
            for a2, b2 in zip(xs, xs[1:]):
                if b2 - a2 > H * 0.008 and a2 > H * 0.03:
                    e = (a2 + b2) / 2
                    break
            edge[(side, i)] = e if e is not None else last
            if e is not None:
                last = e
    top = sh_z - H * 0.05
    bottom = min(hand["L"].z, hand["R"].z) - H * 0.03
    names = {g.index: g.name for g in new.vertex_groups}
    by = {g.name: g for g in new.vertex_groups}
    for v in new.data.vertices:
        p = new.matrix_world @ v.co
        if not (bottom < p.z < top):
            continue
        side = 1 if p.x > 0 else -1
        e = edge.get((side, min(bins - 1, int(p.z / H * bins))))
        if e is None:
            continue
        inside = abs(p.x) < e
        ws = [(names[g.group], g.weight) for g in v.groups if g.weight > 0.0]
        keep = [(n, w) for n, w in ws if (n not in arm_bones) == inside]
        if not keep:
            keep = [("Torso" if p.z > H * 0.62 else "Abdomen", 1.0)] if inside else [("LowerArm.L" if side > 0 else "LowerArm.R", 1.0)]
        tot = sum(w for _, w in keep)
        for n, _ in ws:
            by[n].remove([v.index])
        for n, w in keep:
            g = by.get(n) or new.vertex_groups.new(name=n)
            by[n] = g
            g.add([v.index], w / tot, "REPLACE")


def _fcurves(action):
    if hasattr(action, "fcurves") and len(action.fcurves):
        return list(action.fcurves)
    out = []
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for cb in strip.channelbags:
                out += list(cb.fcurves)
    return out


def lift_lying(arm, old_body_z):
    """The new body's hips sit at a different height from the old one's, and the clips move the hips by the same
    amount as before: lying down, the new person sank into the bed (or floated). Each frame is lifted by that
    difference in proportion to how far down the hips are (none standing, all of it lying)."""
    body = arm.data.bones["Body"]
    new_z = (arm.matrix_world @ body.head_local).z
    d = old_body_z - new_z
    if abs(d) < 0.005:
        return
    rest = (arm.matrix_world.to_3x3() @ body.matrix_local.to_3x3())  # local axes → world (with the scale)
    inv = rest.inverted()
    for act in bpy.data.actions:
        fcs = {fc.array_index: fc for fc in _fcurves(act) if fc.data_path == 'pose.bones["Body"].location'}
        if len(fcs) < 3:
            continue
        n = len(fcs[0].keyframe_points)
        if any(len(fcs[i].keyframe_points) != n for i in (1, 2)):
            continue
        for k in range(n):
            loc = Vector([fcs[i].keyframe_points[k].co[1] for i in range(3)])
            dz = (rest @ loc).z  # how far the hips moved down in the old clip
            f = max(0.0, min(1.0, -dz / (old_body_z * 0.55)))
            if f <= 0.0:
                continue
            loc += inv @ Vector((0.0, 0.0, d * f))
            for i in range(3):
                kp = fcs[i].keyframe_points[k]
                kp.co[1] = loc[i]
                kp.handle_left[1] = loc[i]
                kp.handle_right[1] = loc[i]
        for fc in fcs.values():
            fc.update()
    print("lying clips lifted by", round(d, 3))


def fit_human(name, src, out_path, tris=16000):
    from mathutils import Matrix
    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(BASE, {"exterminator": "owner"}.get(name, name) + ".glb"))
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o)
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    if arm.animation_data:
        arm.animation_data.action = None
    old = next(o for o in bpy.context.scene.objects if o.type == "MESH" and o.find_armature() == arm)
    ohi = max(v.z for v in world_verts(old))
    bpy.data.objects.remove(old)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=src)
    new = next(o for o in bpy.data.objects if o not in before and o.type == "MESH")
    new.parent = None
    select_only(new)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    t0 = sum(len(p.vertices) - 2 for p in new.data.polygons)
    if t0 > tris:
        dec = new.modifiers.new("cut", "DECIMATE")
        dec.ratio = tris / t0
        dec.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier="cut")
    for m in new.data.materials:
        if m and m.use_nodes:
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
    # the same height as the old person, feet on the floor, facing -Y (Meshy faces -Y as the game does)
    nv = world_verts(new)
    lo, hi = bbox(nv)
    k = ohi / (hi.z - lo.z)
    new.scale = (k, k, k)
    bpy.ops.object.transform_apply(scale=True)
    nv = world_verts(new)
    lo, hi = bbox(nv)
    new.location = Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))
    bpy.ops.object.transform_apply(location=True)
    nv = world_verts(new)
    lo, hi = bbox(nv)
    H = hi.z

    def slice_(z0, z1, cond=lambda p: True):
        return [p for p in nv if z0 <= p.z < z1 and cond(p)]
    # landmarks: the crotch (the lowest height where the body is closed at the middle), the hands (the furthest
    # points out on each side), the shoulders (the widest the torso gets above the armpits), the neck (the narrowest
    # above the shoulders)
    crotch = next((z / 200.0 * H for z in range(40, 130) if len(slice_(z / 200.0 * H, (z + 1) / 200.0 * H, lambda p: abs(p.x) < H * 0.012)) > 3), H * 0.45)
    hand = {"L": max((p for p in nv if p.x > 0), key=lambda p: p.x), "R": min((p for p in nv if p.x < 0), key=lambda p: p.x)}
    wrist_z = (hand["L"].z + hand["R"].z) / 2

    def half_width(z):
        s = slice_(z - H * 0.01, z + H * 0.01, lambda p: abs(p.x) < (hand["L"].x * 0.55))
        return max((abs(p.x) for p in s), default=0.0)
    neck = min((z / 100.0 * H for z in range(70, 92)), key=lambda z: half_width(z) or 9)
    head_top = H
    # the old skeleton's joints, mapped height by height: floor → crotch → neck → top
    ob = {b.name: (arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local) for b in arm.data.bones}
    o_crotch = ob["UpperLeg.L"][0].z
    o_neck = ob["Neck"][0].z
    # the hips at the old skeleton's share of the height (the "closed at the middle" guess was fooled by robes and
    # wide pyjama legs, and put the hips at a quarter of the height)
    crotch = H * o_crotch / ohi

    def zmap(z):
        if z <= o_crotch:
            return z / o_crotch * crotch
        if z <= o_neck:
            return crotch + (z - o_crotch) / (o_neck - o_crotch) * (neck - crotch)
        return neck + (z - o_neck) / (ohi - o_neck) * (head_top - neck)
    # sideways: the legs under the middle of each leg, the shoulders at the torso's sides
    def leg_x(side):
        s = slice_(crotch * 0.45, crotch * 0.55, lambda p: (p.x > 0) == (side > 0))
        return sum(p.x for p in s) / max(len(s), 1)
    sh_z = zmap(ob["UpperArm.L"][0].z)
    torso_w = half_width(sh_z - H * 0.04)
    to_local = arm.matrix_world.inverted()
    select_only(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    old_frame = {b.name: (b.matrix.to_3x3().normalized(), b.length) for b in eb}  # each bone's own axes (with roll)
    for b in eb:
        b.use_connect = False
    o_leg = {1: ob["UpperLeg.L"][0].x, -1: ob["UpperLeg.R"][0].x}
    o_sh = {1: ob["UpperArm.L"][0].x, -1: ob["UpperArm.R"][0].x}
    n_leg = {1: leg_x(1), -1: leg_x(-1)}
    for b in eb:
        if any(b.name in ch for ch in HUMAN_ARMS.values()):
            continue
        h, t = ob[b.name]
        for which, p in [("head", h), ("tail", t)]:
            side = 1 if p.x > 0 else -1
            if p.z <= o_crotch * 1.05 or b.name.startswith(("UpperLeg", "LowerLeg", "Foot", "Pole")):
                x = p.x - o_leg[side] + n_leg[side]
            elif b.name.startswith("Shoulder"):
                x = p.x / abs(o_sh[side]) * torso_w * 0.8 if abs(o_sh[side]) > 1e-4 else p.x
            else:
                x = p.x * torso_w / max(abs(o_sh[1]), 1e-4) * 0.8
            q = Vector((x, p.y * k, zmap(p.z)))
            setattr(b, which, to_local @ q)
    # the arms: from the new shoulder, lowered to the mesh's angle and as long as the mesh's arm
    angles = {}
    for side, chain in HUMAN_ARMS.items():
        s = 1 if side == "L" else -1
        sh = arm.matrix_world @ eb["Shoulder." + side].tail
        o_root = ob[chain[0]][0]
        o_tip = ob["Fingers." + side][1]
        o_len = (o_tip - o_root).length
        n_len = (hand[side] - sh).length
        ang = math.atan2(sh.z - hand[side].z, abs(hand[side].x - sh.x))
        angles[side] = ang
        rot = Matrix.Rotation(ang * s, 3, "Y")  # about +Y, a positive turn takes +x down
        f = n_len / o_len
        for bn in chain:
            h, t = ob[bn]
            eb[bn].head = to_local @ (sh + rot @ ((h - o_root) * f))
            eb[bn].tail = to_local @ (sh + rot @ ((t - o_root) * f))
    bpy.ops.object.mode_set(mode="OBJECT")
    for bn in HUMAN_NO_SKIN:
        if bn in arm.data.bones:
            arm.data.bones[bn].use_deform = False
    # skin: bone heat on a closed copy (crumbs dropped), copied over
    select_only(new)
    bpy.ops.object.duplicate()
    proxy = bpy.context.active_object
    rm = proxy.modifiers.new("close", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = H / 160.0
    sm = proxy.modifiers.new("soft", "SMOOTH")
    sm.iterations = 3
    bpy.ops.object.modifier_apply(modifier="close")
    bpy.ops.object.modifier_apply(modifier="soft")
    keep_largest_island(proxy)
    select_only(proxy, arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    bare = [v.index for v in proxy.data.vertices if sum(g.weight for g in v.groups) < 0.01]
    if bare:
        print("bone heat left", len(bare), "of", len(proxy.data.vertices), "bare: given to the nearest bone")
        segs = [(bb.name, arm.matrix_world @ bb.head_local, arm.matrix_world @ bb.tail_local) for bb in arm.data.bones if bb.use_deform]

        def dist(p, a2, b2):
            ab = b2 - a2
            t = 0.0 if ab.length_squared < 1e-12 else max(0.0, min(1.0, (p - a2).dot(ab) / ab.length_squared))
            return (a2 + ab * t - p).length
        for vi in bare:
            co = proxy.matrix_world @ proxy.data.vertices[vi].co
            bn = min(segs, key=lambda sg: dist(co, sg[1], sg[2]))[0]
            (proxy.vertex_groups.get(bn) or proxy.vertex_groups.new(name=bn)).add([vi], 1.0, "REPLACE")
    copy_weights(proxy, new)
    # (split_arms: tried, its slice gaps misread the body — not used)
    bpy.data.objects.remove(proxy)
    # raise the arms back to the T-pose, skin and all, and make that the rest
    mod = new.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    select_only(arm)
    bpy.ops.object.mode_set(mode="POSE")
    for side, chain in HUMAN_ARMS.items():
        # the turn that takes the arm from the mesh's A-pose back to the old arm's direction, done in the
        # armature's own space: from the arm's direction now to its direction in the old skeleton
        pb = arm.pose.bones[chain[0]]
        to_arm = arm.matrix_world.inverted()
        now = (pb.tail - pb.head).normalized()
        o_h, o_t = ob[chain[0]]
        was = ((to_arm @ o_t) - (to_arm @ o_h)).normalized()
        q = now.rotation_difference(was).to_matrix().to_4x4()
        h = pb.head.copy()
        pb.matrix = Matrix.Translation(h) @ q @ Matrix.Translation(-h) @ pb.matrix
        bpy.context.view_layer.update()
    bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode="OBJECT")
    select_only(new)
    bpy.ops.object.modifier_apply(modifier="Armature")
    select_only(arm)
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    # every bone back to its old axes exactly (its direction and its roll) at its new place and length: the
    # clips turn bones about their own axes, so a bone whose roll moved would swing its arm the wrong way
    select_only(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    for b in arm.data.edit_bones:
        if b.name in old_frame:
            m3, _ = old_frame[b.name]
            ln = b.length
            mat = m3.to_4x4()
            mat.translation = b.head.copy()
            b.matrix = mat
            b.length = ln
    bpy.ops.object.mode_set(mode="OBJECT")
    for bn in HUMAN_NO_SKIN:
        g = new.vertex_groups.get(bn)
        if g:
            new.vertex_groups.remove(g)
    lift_lying(arm, ob["Body"][0].z)
    ua = arm.data.bones["UpperArm.L"]
    print("rest arm dir", tuple(round(x, 2) for x in (ua.tail_local - ua.head_local).normalized()))
    print("human", name, "height", round(H, 3), "crotch", round(crotch, 3), "neck", round(neck, 3),
          "arm angles", {s2: round(math.degrees(a2), 1) for s2, a2 in angles.items()})
    return _finish(name, {"material": "Main", "no_skin": []}, arm, new, len(new.vertex_groups), out_path, (k, k, k))


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    name, src = args[0], args[1]
    out = args[2] if len(args) > 2 else os.path.join(OUT, name + ".glb")
    (fit_human if name in ("owner", "kid", "guest", "exterminator") else fit)(name, src, out)
