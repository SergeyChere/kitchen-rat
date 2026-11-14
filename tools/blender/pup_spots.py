"""The four pups' marks (the player's idea, after a famous four brothers): each pup's coat texture with one coloured
mark painted on — Brave's eyes blue, Curious's eyes green, Shy's ear red, Greedy's tail orange.

    python tools/blender/pup_spots.py

Reads the game's pup model (godot/assets/models/characters/rat_pup.glb), finds the parts in its rest pose (the
eyes: the near-black texels on the front of the head; an ear: the top of the head on one side; the tail: behind
the rump on the middle line), and paints those triangles of the texture in the mark's colour. Writes
godot/assets/models/characters/pup_<kind>.png; Pup and the burrow swap the texture in.
"""
import bpy  # noqa: F401  (first: the pip build of bpy)
import os
from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CH = os.path.join(REPO, "godot", "assets", "models", "characters")

MARKS = {"brave": ("eyes", (40, 95, 225)), "curious": ("eyes", (40, 170, 70)),
         "shy": ("ear", (215, 40, 40)), "greedy": ("tail", (245, 130, 25))}


def main():
    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(CH, "rat_pup.glb"))
    me = next(o for o in bpy.context.scene.objects if o.type == "MESH" and o.find_armature())
    arm = me.find_armature()
    mw = me.matrix_world
    pts = [mw @ v.co for v in me.data.vertices]
    head = arm.matrix_world @ arm.data.bones["Head"].head_local
    tail1 = arm.matrix_world @ arm.data.bones["Tail1"].head_local
    zs = [p.z for p in pts]
    top = max(zs)
    img = me.data.materials[0].node_tree.nodes["Image Texture"].image if "Image Texture" in me.data.materials[0].node_tree.nodes \
        else next(n.image for n in me.data.materials[0].node_tree.nodes if n.type == "TEX_IMAGE" and "Image_0" in n.image.name)
    w, h = img.size
    px = list(img.pixels[:])
    base = Image.new("RGB", (w, h))
    base.putdata([(int(px[i] * 255), int(px[i + 1] * 255), int(px[i + 2] * 255)) for i in range(0, len(px), 4)])
    base = base.transpose(Image.FLIP_TOP_BOTTOM)  # Blender's pixels start at the bottom row
    uv = me.data.uv_layers.active.data

    def lum(c):
        return (c[0] * 0.3 + c[1] * 0.59 + c[2] * 0.11) / 255.0

    def tri_uv(poly):
        return [(uv[li].uv.x * (w - 1), (1.0 - uv[li].uv.y) * (h - 1)) for li in poly.loop_indices]

    def centre(poly):
        c = sum((pts[i] for i in poly.vertices), pts[0] * 0) / len(poly.vertices)
        return c

    for kind, (part, col) in MARKS.items():
        out = base.copy()
        mask = Image.new("L", (w, h), 0)
        md = ImageDraw.Draw(mask)
        for poly in me.data.polygons:
            c = centre(poly)
            q = tri_uv(poly)
            if part == "eyes":
                if c.y > head.y + 0.006 or c.z < head.z - 0.01:
                    continue
                cx, cy = sum(p[0] for p in q) / len(q), sum(p[1] for p in q) / len(q)
                if lum(base.getpixel((int(cx), int(cy)))) > 0.22:  # the eye is the near-black part of the face
                    continue
            elif part in ("ear", "tail"):
                # the ear and the tail are the pink parts: the right ear above the head, the tail behind the rump
                if part == "ear" and (c.x < 0.006 or c.z < head.z or c.y > head.y + 0.03):
                    continue
                if part == "tail" and (c.y < tail1.y - 0.004 or abs(c.x) > 0.02):
                    continue
                cx, cy = sum(p[0] for p in q) / len(q), sum(p[1] for p in q) / len(q)
                r, g, b = base.getpixel((int(cx), int(cy)))
                if not (r > g + 25 and r > b + 15):
                    continue
            md.polygon(q, fill=255)
        tint = Image.new("RGB", (w, h), col)
        if part == "eyes":  # an iris colour over the dark eye, its white highlight kept
            g = out.convert("L").point(lambda v: 255 if v < 150 else 0)
            m2 = Image.composite(mask, Image.new("L", (w, h), 0), g)
            out = Image.composite(Image.blend(out, tint, 0.8), out, m2)
        else:
            mult = Image.blend(out, tint, 0.75)
            out = Image.composite(mult, out, mask)
        path = os.path.join(CH, "pup_%s.png" % kind)
        out.save(path)
        print("wrote", path, "texels", sum(1 for v in mask.getdata() if v))


main()
