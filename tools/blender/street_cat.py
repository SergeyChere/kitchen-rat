"""The black street cat of the prologue, on a skeleton of its own (asked: "make it its own skeleton"): the house
cat's clips are made for a short, plump body and tore the thin, long-legged street cat apart. Here the bones are
placed from the street cat's own body (its paws, shoulders, hips, head and tail), the skin is weighted to them, and
its few clips are made by hand in code — a gallop, a walk, standing, a pounce and an angry yowl.

    python tools/blender/street_cat.py path/to/meshy_street_cat.glb

Writes godot/assets/models/characters/cat_street.glb.
"""
import bpy  # (first: the pip build of bpy makes bmesh importable)
import math
import os
import sys
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fit_meshy as fm  # noqa: E402

OUT = os.path.join(fm.OUT, "cat_street.glb")
HEIGHT = 0.40   # to the top of the head, as tall as the house cat
TRIS = 12000
FPS = 24


def build(src):
    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.ops.import_scene.gltf(filepath=src)
    new = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    for o in list(bpy.context.scene.objects):
        if o != new:
            bpy.data.objects.remove(o)
    new.parent = None
    fm.select_only(new)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    t0 = sum(len(p.vertices) - 2 for p in new.data.polygons)
    dec = new.modifiers.new("cut", "DECIMATE")
    dec.ratio = TRIS / t0
    dec.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier="cut")
    for m in new.data.materials:
        bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf:
            for inp in ["Metallic", "Roughness"]:
                for link in list(bsdf.inputs[inp].links):
                    m.node_tree.links.remove(link)
            bsdf.inputs["Metallic"].default_value = 0.0
            bsdf.inputs["Roughness"].default_value = 0.9
        m.name = "Main"
    for img in list(bpy.data.images):
        if img.users == 0:
            bpy.data.images.remove(img)
        elif img.size[0] > 1024:
            img.scale(1024, 1024)
    # size and place: nose toward -Y, paws on the floor, as tall as the house cat
    nv = fm.world_verts(new)
    lo, hi = fm.bbox(nv)
    k = HEIGHT / (hi.z - lo.z)
    new.scale = (k, k, k)
    bpy.ops.object.transform_apply(scale=True)
    nv = fm.world_verts(new)
    lo, hi = fm.bbox(nv)
    new.location = Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))
    bpy.ops.object.transform_apply(location=True)
    nv = fm.world_verts(new)
    lo, hi = fm.bbox(nv)
    H = hi.z
    paws = fm.paws(nv, lo.z, H)

    # landmarks
    front_y = (paws["FL"].y + paws["FR"].y) / 2
    back_y = (paws["BL"].y + paws["BR"].y) / 2

    def top_at(y, band=0.02):
        s = [p.z for p in nv if abs(p.y - y) < band and abs(p.x) < 0.03]
        return max(s) if s else H * 0.6

    def mid_at(y, band=0.02):
        s = [p.z for p in nv if abs(p.y - y) < band and abs(p.x) < 0.03]
        return (max(s) + min(s)) / 2 if s else H * 0.5

    shoulder_z = top_at(front_y) * 0.82
    hip_z = top_at(back_y) * 0.82
    nose_y = lo.y
    head_c = Vector((0, nose_y + (front_y - nose_y) * 0.45, mid_at(nose_y + (front_y - nose_y) * 0.45, 0.015)))
    neck_b = Vector((0, front_y - 0.01, shoulder_z + 0.02))
    # the tail: behind the hips, the farthest-back points, followed in four slices
    tail_pts = [p for p in nv if p.y > back_y + 0.03 and abs(p.x) < 0.03]
    tail_tip = max(tail_pts, key=lambda p: p.y) if tail_pts else Vector((0, hi.y, H * 0.3))
    tail_root = Vector((0, back_y + 0.02, hip_z + 0.02))

    def tail_at(f):
        y = tail_root.y + (tail_tip.y - tail_root.y) * f
        s = [p for p in tail_pts if abs(p.y - y) < 0.012]
        if not s:
            return tail_root.lerp(tail_tip, f)
        return Vector((0, y, sum(p.z for p in s) / len(s)))

    arm_data = bpy.data.armatures.new("StreetCatRig")
    arm = bpy.data.objects.new("StreetCat", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    fm.select_only(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def bone(name, h, t, parent=None, roll_to=Vector((0, 0, 1))):
        b = eb.new(name)
        b.head, b.tail = h, t
        b.align_roll(roll_to)
        if parent:
            b.parent = eb[parent]
        return b

    root = bone("Root", Vector((0, (front_y + back_y) / 2, 0)), Vector((0, (front_y + back_y) / 2 - 0.05, 0)))
    hips = bone("Hips", Vector((0, back_y, hip_z)), Vector((0, (front_y + back_y) / 2, (hip_z + shoulder_z) / 2)), "Root")
    chest = bone("Chest", hips.tail.copy(), Vector((0, front_y, shoulder_z)), "Hips")
    neck = bone("Neck", chest.tail.copy(), neck_b + Vector((0, -0.03, 0.04)), "Chest")
    bone("Head", neck.tail.copy(), Vector((0, nose_y + 0.01, head_c.z)), "Neck")
    prev = "Hips"
    last = tail_root
    for i in range(1, 6):
        p = tail_at(i / 5.0)
        bone("Tail%d" % i, last, p, prev)
        prev = "Tail%d" % i
        last = p
    # the legs: from the body (at the shoulder or hip) to the paw, with a knee two fifths of the way down; their
    # rolls set so a turn about the bone's own X swings the leg forward and back
    for key, top_z, parent in [("FL", shoulder_z, "Chest"), ("FR", shoulder_z, "Chest"), ("BL", hip_z, "Hips"), ("BR", hip_z, "Hips")]:
        pw = paws[key]
        top = Vector((pw.x * 0.8, pw.y + (0.0 if key[0] == "F" else -0.015), top_z * 0.92))
        knee = Vector((pw.x, pw.y + (0.006 if key[0] == "F" else 0.03), top.z * 0.45))
        foot = Vector((pw.x, pw.y, 0.012))
        bone("Up" + key, top, knee, parent, Vector((0, 1, 0)))
        bone("Low" + key, knee, foot, "Up" + key, Vector((0, 1, 0)))
        bone("Paw" + key, foot, foot + Vector((0, -0.03, 0)), "Low" + key, Vector((0, 0, 1)))
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.data.bones["Root"].use_deform = False

    # the skin: bone heat on a closed copy, crumbs dropped, bare spots to the nearest bone, sides kept apart
    fm.select_only(new)
    bpy.ops.object.duplicate()
    proxy = bpy.context.active_object
    rm = proxy.modifiers.new("close", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = H / 90.0
    bpy.ops.object.modifier_apply(modifier="close")
    fm.keep_largest_island(proxy)
    fm.select_only(proxy, arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    segs = [(b.name, arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local) for b in arm.data.bones if b.use_deform]

    def seg_d(p, a, b):
        ab = b - a
        t = 0.0 if ab.length_squared < 1e-12 else max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
        return (a + ab * t - p).length
    bare = [v for v in proxy.data.vertices if sum(g.weight for g in v.groups) < 0.01]
    for v in bare:
        co = proxy.matrix_world @ v.co
        bn = min(segs, key=lambda s: seg_d(co, s[1], s[2]))[0]
        (proxy.vertex_groups.get(bn) or proxy.vertex_groups.new(name=bn)).add([v.index], 1.0, "REPLACE")
    print("bone heat left", len(bare), "bare")
    fm.copy_weights(proxy, new)
    # thin bits the closed copy lost (whiskers, the tail's end, fur tufts): to their nearest bone, wholly
    from mathutils.bvhtree import BVHTree
    tree = BVHTree.FromObject(proxy, bpy.context.evaluated_depsgraph_get())
    inv = proxy.matrix_world.inverted()
    for v in new.data.vertices:
        co = new.matrix_world @ v.co
        hit = tree.find_nearest(inv @ co)
        if hit[0] is not None and hit[3] < H * 0.03:
            continue
        bn = min(segs, key=lambda s: seg_d(co, s[1], s[2]))[0]
        for g in list(v.groups):
            new.vertex_groups[g.group].remove([v.index])
        (new.vertex_groups.get(bn) or new.vertex_groups.new(name=bn)).add([v.index], 1.0, "REPLACE")
    bpy.data.objects.remove(proxy)
    side = {}
    for b in arm.data.bones:
        if b.name[-2:] in ("FL", "BL"):
            side[b.name] = 1
        elif b.name[-2:] in ("FR", "BR"):
            side[b.name] = -1
    names = {g.index: g.name for g in new.vertex_groups}
    for v in new.data.vertices:
        x = (new.matrix_world @ v.co).x
        if abs(x) < 0.01:
            continue
        sd = 1 if x > 0 else -1
        bad = [g for g in v.groups if side.get(names[g.group], sd) != sd]
        if bad:
            good = [(names[g.group], g.weight) for g in v.groups if g not in bad and g.weight > 0]
            for n in [names[g.group] for g in bad]:
                new.vertex_groups[n].remove([v.index])
            tot = sum(w for _, w in good)
            for n, w in good:
                new.vertex_groups[n].add([v.index], w / tot, "REPLACE")
    new.parent = arm
    new.matrix_parent_inverse = arm.matrix_world.inverted()
    mod = new.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    for p in new.data.polygons:
        p.use_smooth = True
    new.name = "CatStreet"
    return arm, new


# ---- the clips: sine-driven poses, keyed every frame ------------------------------------------------------------
def clip(arm, name, frames, pose_at):
    act = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = act
    for f in range(frames + 1):
        t = f / frames
        for pb in arm.pose.bones:
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = (0, 0, 0)
            pb.location = (0, 0, 0)
        pose_at(arm.pose.bones, t)
        for pb in arm.pose.bones:
            pb.keyframe_insert("rotation_euler", frame=f + 1)
            pb.keyframe_insert("location", frame=f + 1)
    act.use_fake_user = True
    # an NLA strip per clip, so the exporter writes each as its own animation
    tr = arm.animation_data.nla_tracks.new()
    tr.name = name
    tr.strips.new(name, 1, act)
    arm.animation_data.action = None
    return act


def legs(pb, t, stride, lift, phases):
    """Each leg swings forward and back about its own X; the knee folds as it comes forward (the paw lifts)."""
    for key, ph in phases.items():
        a = math.sin((t + ph) * math.tau)
        pb["Up" + key].rotation_euler.x = stride * a
        fold = max(0.0, math.cos((t + ph) * math.tau)) * lift
        pb["Low" + key].rotation_euler.x = (-fold if key[0] == "F" else fold) * 1.2
        pb["Paw" + key].rotation_euler.x = 0.3 * fold


def tail(pb, t, amp, up):
    for i in range(1, 6):
        b = pb["Tail%d" % i]
        b.rotation_euler.z = amp * math.sin((t - i * 0.08) * math.tau) * (0.4 + i * 0.15)
        b.rotation_euler.x = up / 5.0


def run_pose(pb, t):  # a gallop: the back legs together, then the front; the spine bunches and stretches
    legs(pb, t, 0.75, 0.9, {"BL": 0.0, "BR": 0.06, "FL": 0.45, "FR": 0.53})
    pb["Hips"].rotation_euler.x = 0.18 * math.sin(t * math.tau)
    pb["Chest"].rotation_euler.x = -0.22 * math.sin(t * math.tau)
    pb["Root"].location.y = 0.0  # (the Root moves nothing: the game moves the cat)
    pb["Hips"].location.z = 0.012 * abs(math.sin(t * math.tau))
    pb["Neck"].rotation_euler.x = 0.12 * math.sin(t * math.tau)
    pb["Head"].rotation_euler.x = -0.12 * math.sin(t * math.tau)
    tail(pb, t, 0.15, 0.4)


def walk_pose(pb, t):
    legs(pb, t, 0.35, 0.5, {"BL": 0.0, "FL": 0.25, "BR": 0.5, "FR": 0.75})
    pb["Hips"].rotation_euler.z = 0.05 * math.sin(t * math.tau)
    pb["Head"].rotation_euler.z = -0.04 * math.sin(t * math.tau)
    tail(pb, t, 0.2, 0.6)


def idle_pose(pb, t):
    pb["Chest"].rotation_euler.x = 0.02 * math.sin(t * math.tau)
    pb["Head"].rotation_euler.z = 0.25 * math.sin(t * math.tau)
    tail(pb, t, 0.25, 0.8)


def pounce_pose(pb, t):  # crouch, spring, land
    if t < 0.4:
        c = t / 0.4
        crouch = math.sin(c * math.pi * 0.5)
        for k in ("BL", "BR"):
            pb["Up" + k].rotation_euler.x = 0.6 * crouch
            pb["Low" + k].rotation_euler.x = 1.0 * crouch
        for k in ("FL", "FR"):
            pb["Up" + k].rotation_euler.x = -0.4 * crouch
            pb["Low" + k].rotation_euler.x = -0.6 * crouch
        pb["Hips"].location.z = -0.04 * crouch
        pb["Head"].rotation_euler.x = 0.2 * crouch
    else:
        s = (t - 0.4) / 0.6
        up = math.sin(s * math.pi)
        for k in ("FL", "FR"):
            pb["Up" + k].rotation_euler.x = -1.1 * up
        for k in ("BL", "BR"):
            pb["Up" + k].rotation_euler.x = -0.7 * up
        pb["Hips"].location.z = 0.06 * up
        pb["Chest"].rotation_euler.x = -0.3 * up
    tail(pb, t, 0.1, 1.2)


def yowl_pose(pb, t):  # back arched, head up, tail up
    a = math.sin(min(1.0, t * 3.0) * math.pi * 0.5)
    pb["Hips"].rotation_euler.x = -0.25 * a
    pb["Chest"].rotation_euler.x = 0.25 * a
    pb["Neck"].rotation_euler.x = 0.35 * a
    pb["Head"].rotation_euler.x = 0.3 * a + 0.05 * math.sin(t * math.tau * 4)
    tail(pb, t, 0.05, 1.6 * a)


def main(src):
    arm, me = build(src)
    clip(arm, "run", 12, run_pose)
    clip(arm, "walk", 24, walk_pose)
    clip(arm, "idle", 72, idle_pose)
    clip(arm, "pounce", 18, pounce_pose)
    clip(arm, "meow_angry", 36, yowl_pose)
    fm.select_only(arm, me)
    me.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_apply=False, export_force_sampling=True,
                              export_yup=True)
    print("street cat", OUT, "tris", sum(len(p.vertices) - 2 for p in me.data.polygons), "bones", len(arm.data.bones))


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    main(args[0])
