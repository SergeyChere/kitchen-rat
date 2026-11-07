"""Turn the free animated characters (CC0, art/library/characters/ via tools/fetch_models.sh) into the game's
characters: real-world size, facing the game's forward axis, and with the animation clips the game asks for
("walk", "sneak", "sleep", "jump_up"…). Missing clips are made from the ones the model has: a stretch of a clip,
slower or faster, reversed, held on one frame, and/or with bones pushed into a new pose (a cat sits by lowering its
hips: the IK legs fold by themselves). Everything is baked, so constraints end up in the keys.

  python tools/blender/import_characters.py <download folder>          (Blender's Python, bpy)
  → godot/assets/models/characters/{rat_mother,rat_pup,cat,dog,owner,kid,guest}.glb

Each model is scaled on a root node, so the toon outline in level_builder.gd is sized from the node scale.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

src_dir = sys.argv[-1]
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.environ.get("OUTDIR") or os.path.join(REPO, "godot", "assets", "models", "characters")
QS = "trebeljahr_quaternius-showcase/public/glb/"
QP = "beep2bleep_FreeAssetsByKenneyNLandQuaternius/FreeModels by Quaternius[Patreon]/Characters and Animals/"

UP = Vector((0, 0, 1))
FWD = Vector((0, -1, 0))  # after the turn every model looks along Blender -Y (glTF +Z)
SIDE = Vector((1, 0, 0))  # pitch axis: + tips the nose down… depending on the bone; see the poses below


def k(bone, t=0.0, down=0.0, fwd=0.0, pitch=0.0, yaw=0.0, roll=0.0):
    """A pose key: at t (0…1 of the clip) move `bone` down / forward (fractions of the model's height) and turn it
    (degrees; pitch about the side axis, yaw about up, roll about forward)."""
    return (bone, t, down, fwd, pitch, yaw, roll)


def hold(*keys):
    """The same pose at the start and the end."""
    out = []
    for key in keys:
        out.append(key)
        out.append((key[0], 1.0) + key[2:])
    return out


# ---------- the characters ----------
RAT_SLEEP = hold(k("Body", down=0.22), k("Head", pitch=25), k("Neck", pitch=15))
RAT_SNEAK = hold(k("Body", down=0.14))
# standing up on the hind legs to sniff: the body tips nose-up and rises, the front paws come off the floor
REAR = hold(k("Body", down=-0.25, fwd=-0.25, pitch=-55), k("Tail1", pitch=50), k("FrontFoot.L", down=-0.75, fwd=-0.55), k("FrontFoot.R", down=-0.75, fwd=-0.55))
RAT = {
    "idle": ("Idle",), "walk": ("Walk",), "carry_walk": ("Walk", 0.9), "run": ("Run",),
    "sneak": ("Walk", 0.6, None, None, False, RAT_SNEAK),
    "drag": ("Walk", 0.5, None, None, True, hold(k("Body", down=0.08))),
    "eat": ("Attack", 0.45), "gnaw": ("Attack", 1.3), "stuck": ("Attack", 0.4),
    "sniff": ("Idle", 1.0, 0, 30, False, REAR + [k("Head", 0, pitch=-10), k("Head", 0.3, pitch=-25, yaw=15),
                                              k("Head", 0.6, pitch=-25, yaw=-15), k("Head", 1, pitch=-10)]),
    "jump_up": ("Jump", 1.0, 0, 9), "jump_down": ("Jump", 1.0, 9, 14), "land": ("Jump", 1.0, 14, 20),
    "sleep": ("Idle", 1.0, 0, 2, False, RAT_SLEEP),
    "wake_up": ("Idle", 1.0, 0, 16, False, [k("Body", 0, down=0.22), k("Head", 0, pitch=25), k("Body", 1), k("Head", 1)]),
}
PUP = dict(RAT)
PUP.update({
    "freeze": ("Idle", 1.0, 0, 2, False, hold(k("Body", down=0.1), k("Head", pitch=-10))),
    "play": ("Jump",), "rear": ("Jump", 0.7, 0, 9), "squeak": ("Attack", 0.8),
})

CAT_SIT = hold(k("Bone", down=0.08, pitch=-10))
CAT_SLEEP = hold(k("Bone", down=0.36), k("Bone.001", down=0.0, pitch=10), k("Bone.003", pitch=30), k("Bone.004", pitch=70))
CAT = {
    "walk": ("Walking",), "run": ("Walking", 2.2), "carry_pup": ("Walking", 0.8),
    "pounce": ("Walking", 3.0, 0, 20, False, [k("Bone", 0, down=0.12), k("Bone", 0.5, down=-0.08), k("Bone", 1)]),
    "idle_sit": ("Idle", 1.0, None, None, False, CAT_SIT),
    "look_around": ("Idle", 1.0, None, None, False, CAT_SIT[:2] + [k("Bone.003", 0), k("Bone.003", 0.3, yaw=40),
                                                                     k("Bone.003", 0.7, yaw=-40), k("Bone.003", 1)]),
    "meow": ("Idle", 1.0, 0, 20, False, CAT_SIT[:2] + [k("Bone.003", 0), k("Bone.003", 0.4, pitch=-25), k("Bone.003", 1)]),
    "eat": ("Idle", 1.6, None, None, False, hold(k("Bone.003", pitch=40), k("Bone.001", pitch=8))),
    "groom": ("Idle", 1.0, None, None, False, CAT_SIT[:2] + [k("Bone.003", 0, pitch=30, yaw=30), k("Bone.003", 0.5, pitch=40, yaw=40),
                                                              k("Bone.003", 1, pitch=30, yaw=30)]),
    "sleep": ("Idle", 0.5, None, None, False, CAT_SLEEP),
    "stir": ("Idle", 1.0, 0, 30, False, CAT_SLEEP[:4] + [k("Bone.003", 0, pitch=30), k("Bone.003", 0.5, pitch=10, yaw=15), k("Bone.003", 1, pitch=30)]),
    "head_up": ("Idle", 1.0, 0, 20, False, CAT_SLEEP[:4] + [k("Bone.003", 0, pitch=30), k("Bone.003", 1, pitch=-10)]),
    "wake_up": ("Idle", 1.0, 0, 24, False, [k("Bone", 0, down=0.36), k("Bone.001", 0, pitch=10), k("Bone.003", 0, pitch=30),
                                           k("Bone", 1), k("Bone.001", 1), k("Bone.003", 1)]),
}

DOG = {
    "idle": ("Idle",), "walk": ("Walk",), "run": ("Gallop",), "bark": ("Attack", 1.0),
    "play": ("Jump_ToIdle",), "sit": ("Idle_2_HeadLow",), "sniff_ground": ("Eating", 1.2),
    "sleep": ("Death", 1.0, 24, 25, False, hold(k("Body", down=-0.12))),
    "wake_up": ("Death", 1.2, None, None, True, hold(k("Body", down=-0.12))),
}

OWNER_CROUCH = hold(k("Hips", down=0.22), k("Torso", pitch=35), k("Head", pitch=10))
OWNER = {
    "idle": ("Idle",), "walk": ("Walk",), "run": ("Run",), "swat": ("Punch", 1.0),
    "look_around": ("Idle", 1.0, 0, 60, False, [k("Head", 0), k("Head", 0.3, yaw=45), k("Head", 0.7, yaw=-45), k("Head", 1)]),
    "flashlight_sweep": ("Idle", 1.0, 0, 80, False, [k("Torso", 0), k("Torso", 0.3, yaw=30), k("Torso", 0.7, yaw=-30), k("Torso", 1)]
                         + hold(k("UpperArm.R", pitch=-70))),
    "crouch_look": ("Idle", 1.0, 0, 40, False, [k("Hips", 0), k("Torso", 0), k("Hips", 0.5, down=0.22), k("Torso", 0.5, pitch=35),
                                               k("Head", 0.5, pitch=15), k("Hips", 1, down=0.22), k("Torso", 1, pitch=35), k("Head", 1, pitch=15)]),
    "place_trap": ("Idle", 1.0, 0, 40, False, OWNER_CROUCH + [k("UpperArm.R", 0), k("UpperArm.R", 0.6, pitch=-45), k("UpperArm.R", 1)]),
    "drink": ("Idle", 1.0, 0, 50, False, [k("UpperArm.R", 0), k("LowerArm.R", 0), k("Head", 0), k("UpperArm.R", 0.3, pitch=-40),
                                         k("LowerArm.R", 0.3, pitch=-110), k("Head", 0.5, pitch=-25), k("UpperArm.R", 0.7, pitch=-40),
                                         k("LowerArm.R", 0.7, pitch=-110), k("UpperArm.R", 1), k("LowerArm.R", 1), k("Head", 1)]),
    "yawn": ("Idle", 1.0, 0, 50, False, [k("Head", 0), k("Head", 0.5, pitch=-30), k("Head", 1)]),
}

LIE = ("Death", 1.0, 49, 50)  # Quaternius people fall on their back: head behind, feet ahead (like the old models)
SIT = [k("Abdomen", pitch=-45), k("Torso", pitch=-40), k("Head", pitch=-10)]


def sit_up(t0=0.0, t1=0.35):
    out = []
    for key in SIT:
        out += [(key[0], 0.0) + (0, 0, 0, 0, 0), (key[0], t0 + 0.001) + (0, 0, 0, 0, 0), (key[0], t1) + key[2:], (key[0], 1.0) + key[2:]]
    return out


SLEEPER = {
    "idle": ("Idle",), "walk": ("Walk",), "run": ("Run",),
    "sleep_bed": LIE, "sleep_floor": LIE,
    "toss": LIE[:3] + (40, False, [k("Torso", 0), k("Torso", 0.5, roll=25, pitch=10), k("Torso", 1)]),
    "sit_up": LIE[:3] + (70, False, sit_up()),
    "sit_up_scream": LIE[:3] + (50, False, sit_up(0.0, 0.2) + [k("UpperArm.L", 0), k("UpperArm.R", 0), k("UpperArm.L", 0.3, pitch=-120),
                                                              k("UpperArm.R", 0.3, pitch=-120), k("UpperArm.L", 1, pitch=-120), k("UpperArm.R", 1, pitch=-120)]),
    "sit_bed": LIE[:3] + (50, False, hold(*SIT)),
    "stand_up": ("Death", 1.5, None, None, True), "excited": ("Clapping",), "climb": ("Jump",),
}

# How the rat looks: small black bead eyes, a shorter snout, a pink nose and whiskers; her own small ears; fur colour.
# (RATSTYLE picks a variant to compare; "main" is the game's.)
RAT_STYLES = {
    "main": {"eye": 0.055, "shine": False, "ear": 0.0, "nose": 0.07, "snout": 0.7, "head": 1.0,
             "fur": (0.2, 0.13, 0.09), "pup_fur": (0.3, 0.21, 0.15)},
    "shine": {"eye": 0.055, "shine": True, "ear": 0.0, "nose": 0.07, "snout": 0.7, "head": 1.0,
              "fur": (0.2, 0.13, 0.09), "pup_fur": (0.3, 0.21, 0.15)},
}
RAT_STYLE = RAT_STYLES[os.environ.get("RATSTYLE", "main")]

CHARS = [
    # out, source, turn (deg about up), height (m, of the source model's bounding box), clips, new colours (linear)
    ("rat_mother", QS + "easy_enemies_pack/Rat.glb", 0, 0.165, RAT, {"Grey": RAT_STYLE["fur"]}, RAT_STYLE),
    ("rat_pup", QS + "easy_enemies_pack/Rat.glb", 0, 0.095, PUP, {"Grey": RAT_STYLE["pup_fur"]}, RAT_STYLE),
    ("cat", QP + "Animal Pack Vol.2 - Jul 2017/Blends/Cat.blend", -90, 0.53, CAT, {"Grey": (0.7, 0.28, 0.06)}),
    ("dog", QS + "animals_pack/ShibaInu.glb", 0, 0.70, DOG, {}),
    ("owner", QP + "Animated Men Characters - Feb 2019/Blends/Male_Casual.blend", 0, 1.78, OWNER,
     {"Shirt": (0.08, 0.14, 0.4), "Pants": (0.12, 0.1, 0.08)}),
    ("kid", QP + "Animated Men Characters - Feb 2019/Blends/Male_LongSleeve.blend", 0, 1.35, SLEEPER,
     {"Shirt": (0.05, 0.12, 0.45), "Pants": (0.04, 0.06, 0.2)}),
    ("guest", QP + "Animated Women Characters - Feb 2019/Blend/Female_Casual.blend", 0, 1.68, SLEEPER, {}),
]


# ---------- helpers ----------

def load(path):
    if path.endswith(".blend"):
        bpy.ops.wm.open_mainfile(filepath=path)
    else:
        bpy.ops.wm.read_homefile(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=path)
    for o in list(bpy.data.objects):
        if o.type in ("CAMERA", "LIGHT") or o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o)


def fix_materials(recolor):
    """Old Quaternius files use Diffuse BSDF nodes, which glTF doesn't know: rebuild as Principled."""
    for m in bpy.data.materials:
        col = tuple(m.diffuse_color)
        if m.use_nodes:
            out = next((n for n in m.node_tree.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output), None)
            sn = out.inputs[0].links[0].from_node if out and out.inputs[0].links else None
            if sn is not None and "Color" in sn.inputs:
                col = tuple(sn.inputs["Color"].default_value)
            elif sn is not None and "Base Color" in sn.inputs:
                if sn.inputs["Base Color"].links and m.name not in recolor:
                    continue  # textured: keep as is
                col = tuple(sn.inputs["Base Color"].default_value)
        if m.name in recolor:
            col = tuple(recolor[m.name]) + (1.0,)
        m.use_nodes = True
        nt = m.node_tree
        nt.nodes.clear()
        b = nt.nodes.new("ShaderNodeBsdfPrincipled")
        b.inputs["Base Color"].default_value = col
        b.inputs["Roughness"].default_value = 0.8
        o = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(b.outputs[0], o.inputs[0])


def bounds():
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for o in bpy.context.scene.objects:
        if o.type == "MESH" and o.visible_get():
            for v in o.bound_box:
                w = o.matrix_world @ Vector(v)
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
    return lo, hi


def find_action(name):
    for a in bpy.data.actions:
        if a.name == name or a.name.split("|")[-1] in (name, "Rat_" + name, "Man_" + name, "Female_" + name):
            return a
    raise KeyError(name)


def to_local(arm, bone, v):
    m = (arm.matrix_world.to_3x3() @ arm.data.bones[bone].matrix_local.to_3x3()).inverted()
    return m @ v


def pose_action(arm, keys, length, height, turn, scales=None):
    """An action with the pose offsets (keyed location / rotation per bone), blended on top with COMBINE;
    scales: {bone: factor} held over the whole clip (a bigger head)."""
    act = bpy.data.actions.new("pose_tmp")
    arm.animation_data.action = act
    for bone, f in (scales or {}).items():
        pb = arm.pose.bones[bone]
        pb.scale = (f, f, f)
        pb.keyframe_insert("scale", frame=1)
        pb.keyframe_insert("scale", frame=length)
        pb.scale = (1, 1, 1)
    rot = Quaternion(UP, math.radians(turn))  # the source model's own axes (before the turn on the root)
    fwd = rot.inverted() @ FWD
    side = rot.inverted() @ SIDE
    for bone, t, down, fw, pitch, yaw, roll in keys or []:
        pb = arm.pose.bones[bone]
        pb.rotation_mode = "QUATERNION"
        frame = 1 + t * (length - 1)
        pb.location = to_local(arm, bone, (-UP * down + fwd * fw) * height)
        q = Quaternion()
        for axis, deg in ((side, pitch), (UP, yaw), (fwd, roll)):
            if deg:
                q = Quaternion(to_local(arm, bone, axis).normalized(), math.radians(deg)) @ q
        pb.rotation_quaternion = q
        pb.keyframe_insert("location", frame=frame)
        pb.keyframe_insert("rotation_quaternion", frame=frame)
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.scale = (1, 1, 1)
    return act


def make_clip(arm, name, spec, height, turn, scales=None):
    src, speed, a, b, rev, keys = tuple(spec) + (1.0, None, None, False, None)[len(spec) - 1:]
    sa = find_action(src)
    fa, fb = sa.frame_range
    a = fa if a is None else a
    b = fb if b is None else b
    if b - a < 1:
        b = a + 1
    ad = arm.animation_data_create()
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    ad.action = None
    tr = ad.nla_tracks.new()
    st = tr.strips.new(name, 1, sa)
    st.action_frame_start = a
    st.action_frame_end = b
    st.scale = 1.0 / speed
    st.use_reverse = rev
    st.extrapolation = "HOLD"
    length = max(2, int(round((b - a) / speed)) + 1)
    if keys or scales:
        pa = pose_action(arm, keys, length, height, turn, scales)
        tr2 = ad.nla_tracks.new()
        st2 = tr2.strips.new("pose", 1, pa)
        st2.blend_type = "COMBINE"
        st2.extrapolation = "HOLD"
    bpy.context.view_layer.objects.active = arm
    for o in bpy.context.scene.objects:
        o.select_set(o == arm)
    bpy.ops.nla.bake(frame_start=1, frame_end=length, only_selected=False, visual_keying=True,
                     clear_constraints=False, use_current_action=False, bake_types={"POSE"})
    act = ad.action
    act.name = name
    act.use_fake_user = True
    ad.action = None
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    return act


def _mat(name, col, rough=0.6):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = tuple(col) + (1.0,)
    b.inputs["Roughness"].default_value = rough
    return m


def _add(kind, loc, scale, mat, parts, rot=(0, 0, 0)):
    if kind == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, location=loc)
    else:
        bpy.ops.mesh.primitive_cylinder_add(vertices=16, location=loc)
    o = bpy.context.active_object
    o.scale = scale
    o.rotation_euler = rot
    bpy.ops.object.shade_smooth()
    o.data.materials.append(mat)
    parts.append(o)
    return o


def add_face(arm, f):
    """A friendlier rat: big shiny eyes, round pink ears, a pink nose and whiskers. They are joined into the rat's
    mesh and skinned 100% to the head bone, so they move exactly like her snout.
    Positions are in the source model's units (Quaternius rat: snout toward -Y, nose tip at y -2.07)."""
    body = next(o for o in bpy.context.scene.objects if o.type == "MESH" and o.parent is not None and o.find_armature() == arm)
    eye = _mat("Eye", (0.01, 0.01, 0.012), 0.15)
    shine = _mat("EyeShine", (1, 1, 1), 0.2)
    pink = _mat("NosePink", (0.85, 0.36, 0.42), 0.5)
    inner = _mat("EarPink", (0.9, 0.55, 0.58), 0.7)
    fur = bpy.data.materials.get("Grey")
    wh = _mat("Whisker", (0.35, 0.33, 0.32), 0.6)
    parts = []
    # a shorter snout: everything ahead of the eyes is pulled back toward them
    k = f.get("snout", 1.0)
    y0 = -1.5
    mw = body.matrix_world
    inv = mw.inverted()
    for v in body.data.vertices:
        w = mw @ v.co
        if w.y < y0:
            w.y = y0 + (w.y - y0) * k
            v.co = inv @ w
    tip = y0 + (-2.07 - y0) * k  # where the nose tip is now
    er = f.get("eye", 0.12)
    for sx in (-1, 1):
        # eyes: small black beads on the sides of the head
        ey = y0 + (-1.58 - y0) * k
        c = Vector((sx * (0.22 + er * 0.3), ey, 1.47))
        _add("sphere", c, (er, er * 0.9, er), eye, parts)
        if f.get("shine", True):
            _add("sphere", c + Vector((sx * er * 0.45, -er * 0.55, er * 0.5)), (er * 0.32,) * 3, shine, parts)
        ear_r = f.get("ear", 0.0)
        if ear_r > 0.0:
            ec = Vector((sx * 0.3, -1.12, 1.6 + ear_r * 0.75))
            rot = (math.radians(80), 0.0, math.radians(sx * -25))
            _add("cyl", ec, (ear_r, ear_r, 0.03), fur, parts, rot)
            fwd = Matrix.Rotation(rot[2], 3, "Z") @ Vector((0, -0.035, 0))
            _add("cyl", ec + fwd, (ear_r * 0.72, ear_r * 0.72, 0.02), inner, parts, rot)
        for dz in (-0.12, 0.0, 0.12):  # whiskers fanning out from the snout
            a = Vector((sx * 0.1, tip + 0.17, 1.3))
            d = Vector((sx * 1.0, -0.15, dz)).normalized()
            L = f.get("whisker", 0.55)
            q = d.to_track_quat("Z", "Y")
            _add("cyl", a + d * L * 0.5, (0.006, 0.006, L * 0.5), wh, parts, q.to_euler())
    nr = f.get("nose", 0.075)
    _add("sphere", Vector((0, tip + 0.01, 1.34)), (nr, nr * 0.85, nr * 0.8), pink, parts)
    for o in parts:
        vg = o.vertex_groups.new(name="Head")
        vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()


def build(out, path, turn, height, clips, recolor, face=None):
    load(os.path.join(src_dir, path))
    fix_materials(recolor)
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    if arm.animation_data:
        arm.animation_data.action = None
    lo, hi = bounds()
    h = hi.z - lo.z
    if face:
        add_face(arm, face)
    scales = {"Head": face["head"]} if face and face.get("head", 1.0) != 1.0 else None
    source = set(bpy.data.actions)
    made = [make_clip(arm, n, spec, h, turn, scales) for n, spec in clips.items()]
    for a in source:
        bpy.data.actions.remove(a)
    for a in list(bpy.data.actions):
        if a not in made:
            bpy.data.actions.remove(a)
    # root node: turn and size; the model stands on the origin
    top = arm
    while top.parent:
        top = top.parent
    root = bpy.data.objects.new(out, None)
    bpy.context.scene.collection.objects.link(root)
    top.parent = root
    s = height / h
    root.rotation_euler = (0, 0, math.radians(turn))
    root.scale = (s, s, s)
    root.location = (0, 0, -lo.z * s)
    bpy.context.view_layer.update()
    for o in bpy.context.scene.objects:
        o.select_set(True)
    if os.environ.get("BLENDDIR"):  # also keep an editable .blend (rig, mesh, every game clip as an action)
        for a in bpy.data.actions:
            a.use_fake_user = True
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(os.environ["BLENDDIR"], out + ".blend"), copy=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, out + ".glb"), export_format="GLB", use_selection=True,
                              export_animations=True, export_animation_mode="ACTIONS", export_apply=False,
                              export_force_sampling=True, export_yup=True)
    print("built", out, len(made), "clips, scale %.4f" % s)


only = os.environ.get("ONLY", "")
for c in CHARS:
    if not only or c[0] in only.split(","):
        build(*c)
