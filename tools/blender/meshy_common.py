"""What every Meshy model needs before the game can use it (shared by swap_prop.py and fit_meshy.py)."""
import bpy


def weld(me):
    """glTF splits the vertices along every seam of Meshy's texture mosaic (thousands of them): welded again, so
    the surface is one skin to cut down, to unwrap and to weigh to bones."""
    bpy.ops.object.select_all(action="DESELECT")
    me.select_set(True)
    bpy.context.view_layer.objects.active = me
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.00002)
    bpy.ops.object.mode_set(mode="OBJECT")


def rebake(lo, hi, tex):
    """Meshy's texture is a mosaic of thousands of tiny islands packed edge to edge: scaled down (or seen from afar,
    through the mipmaps) neighbours of other colours bleed into each other, and the model is speckled along every
    seam. So the cut-down model gets a new, plain unwrap (a few big islands with a margin round each) and the paint
    is baked across from the model as it came."""
    sc = bpy.context.scene
    bpy.ops.object.select_all(action="DESELECT")
    lo.select_set(True)
    bpy.context.view_layer.objects.active = lo
    while lo.data.uv_layers:
        lo.data.uv_layers.remove(lo.data.uv_layers[0])
    lo.data.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.006)
    bpy.ops.object.mode_set(mode="OBJECT")
    img = bpy.data.images.new("Paint", tex, tex, alpha=False)
    mat = bpy.data.materials.new("Paint")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = img
    nt.nodes.active = node
    lo.data.materials.clear()
    lo.data.materials.append(mat)
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 1
    sc.render.bake.use_selected_to_active = True
    sc.render.bake.margin = 12
    sc.render.bake.margin_type = "EXTEND"
    size = max(lo.dimensions)
    sc.render.bake.cage_extrusion = size * 0.02
    sc.render.bake.max_ray_distance = size * 0.06
    hi.select_set(True)
    lo.select_set(True)
    bpy.context.view_layer.objects.active = lo
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
    img.pack()
    nt.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 0.9
    bpy.data.objects.remove(hi)
    bpy.ops.object.select_all(action="DESELECT")
    lo.select_set(True)
    bpy.context.view_layer.objects.active = lo
