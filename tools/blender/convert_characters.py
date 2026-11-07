"""Collect free animated characters (CC0) into art/library/characters/ as .glb, animations included.
Sources (download with tools/fetch_models.sh): Quaternius packs and Kenney Cube Pets.
  python tools/blender/convert_characters.py <download folder> art/library/characters   (Blender's Python, bpy)
"""
import os
import shutil
import sys

import bpy

src, dst = sys.argv[-2], sys.argv[-1]
QS = "trebeljahr_quaternius-showcase/public/glb/"
QP = "beep2bleep_FreeAssetsByKenneyNLandQuaternius/FreeModels by Quaternius[Patreon]/Characters and Animals/"
KC = "shorepine_kenney/3d/cube-pets/"

# out name → source file
LIST = {
    "Rat": QS + "easy_enemies_pack/Rat.glb",
    "Cat": QP + "Animal Pack Vol.2 - Jul 2017/Blends/Cat.blend",
    "Cat_Cube": KC + "animal-cat.glb",
    "Dog": QP + "Animal Pack Vol.2 - Jul 2017/Blends/Dog.blend",
    "Dog_Cube": KC + "animal-dog.glb",
    "ShibaInu": QS + "animals_pack/ShibaInu.glb",
    "Husky": QS + "animals_pack/Husky.glb",
    "Fox": QS + "animals_pack/Fox.glb",
    "Man_Casual": QP + "Animated Men Characters - Feb 2019/Blends/Male_Casual.blend",
    "Man_LongSleeve": QP + "Animated Men Characters - Feb 2019/Blends/Male_LongSleeve.blend",
    "Woman_Casual": QP + "Animated Women Characters - Feb 2019/Blend/Female_Casual.blend",
    "Woman_Dress": QP + "Animated Women Characters - Feb 2019/Blend/Female_Dress.blend",
}

def fix_materials():
    """Old Quaternius files use Diffuse BSDF nodes, which glTF doesn't know: rebuild as Principled with that colour."""
    for m in bpy.data.materials:
        col = tuple(m.diffuse_color)
        if m.use_nodes:
            out = next((n for n in m.node_tree.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output), None)
            src_n = out.inputs[0].links[0].from_node if out and out.inputs[0].links else None
            if src_n is not None and "Color" in src_n.inputs:
                col = tuple(src_n.inputs["Color"].default_value)
            elif src_n is not None and "Base Color" in src_n.inputs:
                col = tuple(src_n.inputs["Base Color"].default_value)
        m.use_nodes = True
        nt = m.node_tree
        nt.nodes.clear()
        b = nt.nodes.new("ShaderNodeBsdfPrincipled")
        b.inputs["Base Color"].default_value = col
        b.inputs["Roughness"].default_value = 0.8
        o = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(b.outputs[0], o.inputs[0])


os.makedirs(dst, exist_ok=True)
for name, rel in LIST.items():
    f = os.path.join(src, rel)
    out = os.path.join(dst, name + ".glb")
    if not os.path.exists(f):
        print("missing", rel)
        continue
    if f.endswith(".glb") and KC not in rel:  # Kenney files keep their texture next to them: re-export embedded
        shutil.copy(f, out)
        print("copied", name)
        continue
    if f.endswith(".blend"):
        bpy.ops.wm.open_mainfile(filepath=f)
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        (bpy.ops.import_scene.gltf if f.endswith(".glb") else bpy.ops.import_scene.fbx)(filepath=f)
    if not f.endswith(".glb"):
        fix_materials()
    for o in [o for o in bpy.data.objects if o.type in ("CAMERA", "LIGHT")]:
        bpy.data.objects.remove(o)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_animations=True,
                              export_animation_mode="ACTIONS", export_apply=False)
    print("converted", name, len(bpy.data.actions), "animations")
