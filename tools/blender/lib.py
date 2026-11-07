"""Shared helpers for generating Kitchen Rat models in Blender.

Units: every size passed to the helpers is in centimetres; the scene is in metres (1 unit = 1 m).
Axes: Blender is Z-up. Models face -Y (Blender's front view), which becomes +Z (forward) in Godot
with the glTF export below. Every model's origin is at the bottom centre.
"""
import math
import os

import bpy
import bmesh
from mathutils import Vector

CM = 0.01
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
GODOT = os.path.join(REPO, 'godot', 'assets', 'models')  # models go straight into the Godot project as .glb
ROOT = GODOT
DOCS = os.path.join(REPO, 'art')                      # previews and MODELS.md
_mats = {}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()


def mat(hexcol, rough=0.75, metal=0.0, alpha=1.0, emit=0.0, name=None):
    key = (hexcol, rough, metal, alpha, emit)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name or ('c%06x' % hexcol))
    m.use_nodes = True
    b = m.node_tree.nodes.get('Principled BSDF')
    r, g, bl = ((hexcol >> 16) & 255) / 255, ((hexcol >> 8) & 255) / 255, (hexcol & 255) / 255
    lin = lambda c: (c / 12.92) if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    col = (lin(r), lin(g), lin(bl), 1)
    b.inputs['Base Color'].default_value = col
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    if alpha < 1:
        b.inputs['Alpha'].default_value = alpha
        try:
            m.surface_render_method = 'BLENDED'
        except Exception:
            pass
    if emit > 0:
        b.inputs['Emission Color'].default_value = col
        b.inputs['Emission Strength'].default_value = emit
    m.diffuse_color = col
    _mats[key] = m
    return m


def _set(o, m, name):
    if m is not None:
        o.data.materials.clear()
        o.data.materials.append(m)
    o.name = name or o.name
    return o


def _apply(o):
    bpy.context.view_layer.objects.active = o
    for ob in bpy.context.selected_objects:
        ob.select_set(False)
    o.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return o


def box(sx, sy, sz, x=0, y=0, z=0, m=None, name='part', bevel=0.0, rot=(0, 0, 0)):
    """Box sx × sy × sz cm. (x, y) is the centre, z is the bottom."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x * CM, y * CM, (z + sz / 2) * CM))
    o = bpy.context.object
    o.scale = (sx * CM, sy * CM, sz * CM)
    o.rotation_euler = [math.radians(a) for a in rot]
    _apply(o)
    if bevel > 0:
        md = o.modifiers.new('bv', 'BEVEL')
        md.width = bevel * CM
        md.segments = 1
        md.limit_method = 'ANGLE'
        bpy.ops.object.modifier_apply(modifier=md.name)
    return _set(o, m, name)


def cyl(r, h, x=0, y=0, z=0, m=None, name='part', verts=12, r2=None, rot=(0, 0, 0)):
    """Cylinder (or cone when r2 is given) of radius r cm, height h cm, standing on z."""
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r * CM, depth=h * CM, location=(0, 0, 0))
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r * CM, radius2=r2 * CM, depth=h * CM, location=(0, 0, 0))
    o = bpy.context.object
    o.rotation_euler = [math.radians(a) for a in rot]
    _apply(o)
    # move so that the local bottom (before rotation: -h/2 on Z) sits at z
    o.location = (x * CM, y * CM, (z + h / 2) * CM) if rot == (0, 0, 0) else (x * CM, y * CM, z * CM)
    return _set(o, m, name)


def sphere(r, x=0, y=0, z=0, m=None, name='part', seg=12, rings=8, scale=(1, 1, 1)):
    """Sphere radius r cm with its centre at (x, y, z)."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=r * CM, location=(x * CM, y * CM, z * CM))
    o = bpy.context.object
    o.scale = scale
    _apply(o)
    return _set(o, m, name)


def ico(r, x=0, y=0, z=0, m=None, name='part', sub=1, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=r * CM, location=(x * CM, y * CM, z * CM))
    o = bpy.context.object
    o.scale = scale
    _apply(o)
    return _set(o, m, name)


def torus(R, r, x=0, y=0, z=0, m=None, name='part', seg=16, rseg=6, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=R * CM, minor_radius=r * CM, major_segments=seg, minor_segments=rseg, location=(x * CM, y * CM, z * CM))
    o = bpy.context.object
    o.rotation_euler = [math.radians(a) for a in rot]
    _apply(o)
    return _set(o, m, name)


def plane(sx, sy, x=0, y=0, z=0, m=None, name='part'):
    bpy.ops.mesh.primitive_plane_add(size=1, location=(x * CM, y * CM, z * CM))
    o = bpy.context.object
    o.scale = (sx * CM, sy * CM, 1)
    _apply(o)
    return _set(o, m, name)


def wedge(sx, sy, sz, x=0, y=0, z=0, m=None, name='part'):
    """Triangular prism (cheese wedge): right angle along -Y, thin edge at +Y."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    hx, hy = sx * CM / 2, sy * CM / 2
    zz = sz * CM
    vs = [bm.verts.new(v) for v in [(-hx, -hy, 0), (hx, -hy, 0), (0, hy, 0), (-hx, -hy, zz), (hx, -hy, zz), (0, hy, zz)]]
    for f in [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)]:
        bm.faces.new([vs[i] for i in f])
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.location = (x * CM, y * CM, z * CM)
    return _set(o, m, name)


def join(parts, name):
    """Join meshes into one object."""
    parts = [p for p in parts if p is not None]
    for ob in bpy.context.selected_objects:
        ob.select_set(False)
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    o = bpy.context.object
    o.name = name
    o.data.name = name
    return o


def origin_bottom(o):
    """Origin at the bottom centre of the bounding box, object placed at world origin."""
    bpy.context.view_layer.objects.active = o
    pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    pivot = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    bpy.context.scene.cursor.location = pivot
    for ob in bpy.context.selected_objects:
        ob.select_set(False)
    o.select_set(True)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    o.location = (0, 0, 0)
    return pivot


def flat(o):
    for p in o.data.polygons:
        p.use_smooth = False


def save(category, name, objs, anim=False):
    """Export the given objects (and their children) to godot/assets/models/<category>/<name>.glb."""
    for ob in bpy.context.selected_objects:
        ob.select_set(False)
    allo = []
    for o in objs:
        allo.append(o)
        allo.extend(o.children_recursive)
    for o in allo:
        o.select_set(True)
        if o.type == 'MESH':
            flat(o)
    bpy.context.view_layer.objects.active = objs[0]
    tris = sum(len(p.vertices) - 2 for o in allo if o.type == 'MESH' for p in o.data.polygons)
    gout = os.path.join(GODOT, category)
    os.makedirs(gout, exist_ok=True)
    path = os.path.join(gout, name + '.glb')
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True, export_yup=True,
        export_apply=False, export_animations=anim, export_animation_mode='ACTIONS', export_force_sampling=True,
        export_frame_range=False, export_def_bones=False, export_skins=True, export_lights=False, export_cameras=False)
    return path, tris


def model(category, name, parts, movable=None, anim=False):
    """Join parts into one mesh named <name>, put the origin at the bottom centre and export.
    movable: {child_name: [parts]} separate child objects (a trap's bar, a door) kept under the main one."""
    o = join(parts, name)
    pivot = origin_bottom(o)
    for cname, cparts in (movable or {}).items():
        c = join(cparts, cname)
        c.location = c.location - pivot
        bpy.context.view_layer.update()
        c.parent = o
    return save(category, name, [o], anim)


def seg(a, b, r1, r2=None, m=None, name='part', verts=8):
    """Tapered cylinder from point a to point b (cm)."""
    a, b = Vector(a) * CM, Vector(b) * CM
    d = b - a
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r1 * CM, depth=d.length)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1 * CM, radius2=r2 * CM, depth=d.length)
    o = bpy.context.object
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = d.to_track_quat('Z', 'Y')
    o.location = (a + b) / 2
    _apply(o)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return _set(o, m, name)
