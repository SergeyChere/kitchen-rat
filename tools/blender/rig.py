"""Skeletons and keyframed animations for the characters.

Every part of a character is rigidly bound to one bone (weight 1.0), so the low-poly look stays crisp.
Animations are Blender Actions; the glTF exporter writes each one as a separate animation for Godot.
Rotations are Euler XYZ in degrees in the bone's local space:
  legs (vertical bones): X swings the leg forward/back
  spine/head/tail (horizontal bones along -Y): X pitches up/down, Z turns left/right
"""
import math

import bpy
from mathutils import Vector

from lib import CM, join, save, origin_bottom

FPS = 24


def build(name, bones):
    """bones: [(name, head_cm, tail_cm, parent)]"""
    data = bpy.data.armatures.new(name + '_rig')
    arm = bpy.data.objects.new(name + '_rig', data)
    bpy.context.collection.objects.link(arm)
    for ob in bpy.context.selected_objects:
        ob.select_set(False)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    for n, h, t, p in bones:
        eb = data.edit_bones.new(n)
        eb.head = Vector(h) * CM
        eb.tail = Vector(t) * CM
        eb.roll = 0
        if p:
            eb.parent = data.edit_bones[p]
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in arm.pose.bones:
        pb.rotation_mode = 'XYZ'
    return arm


def bind(arm, parts_by_bone, name, attach=None):
    """parts_by_bone: {bone: [mesh parts]}. attach: {bone: [(child_name, [parts])]} separate objects held by a bone."""
    parts = []
    for bone, ps in parts_by_bone.items():
        for p in ps:
            vg = p.vertex_groups.new(name=bone)
            vg.add(list(range(len(p.data.vertices))), 1.0, 'REPLACE')
            parts.append(p)
    mesh = join(parts, name)
    mesh.parent = arm
    md = mesh.modifiers.new('Armature', 'ARMATURE')
    md.object = arm
    for bone, items in (attach or {}).items():
        for cname, cps in items:
            c = join(cps, cname)
            mw = c.matrix_world.copy()
            c.parent = arm
            c.parent_type = 'BONE'
            c.parent_bone = bone
            bpy.context.view_layer.update()
            c.matrix_world = mw
    return mesh


def clip(arm, name, length, keys, loop=True):
    """keys: {frame: {bone: (rx, ry, rz) | {'r': (..), 'l': (x, y, z cm)}}}. Bones missing from a frame use 0.
    For looping clips the last frame repeats the first."""
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = act
    bones = set()
    for f in keys.values():
        bones.update(f.keys())
    frames = dict(keys)
    if loop and 0 in frames:
        frames[length] = frames[0]
    for fr in sorted(frames):
        for b in bones:
            pb = arm.pose.bones[b]
            v = frames[fr].get(b, (0, 0, 0))
            r, l = (v.get('r', (0, 0, 0)), v.get('l', (0, 0, 0))) if isinstance(v, dict) else (v, (0, 0, 0))
            pb.rotation_euler = [math.radians(a) for a in r]
            pb.location = [a * CM for a in l]
            pb.keyframe_insert('rotation_euler', frame=fr)
            pb.keyframe_insert('location', frame=fr)
    act.frame_range = (0, length)
    try:
        act.use_frame_range = True
        act.use_cyclic = loop
    except Exception:
        pass
    return act


def finish(arm, mesh, category, name):
    for pb in arm.pose.bones:
        pb.rotation_euler = (0, 0, 0)
        pb.location = (0, 0, 0)
    arm.animation_data.action = None
    bpy.context.scene.render.fps = FPS
    return save(category, name, [arm], anim=True)


def s(t):
    return math.sin(t * 2 * math.pi)
