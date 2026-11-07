# Character sources (.blend)

`rat_mother.blend` and `rat_pup.blend`: the game's rats as editable Blender files (Blender 4.2+), saved by
`tools/blender/import_characters.py` (run with `BLENDDIR=art/characters`). Each has the mesh (with the eyes, nose
and whiskers joined in and skinned to the `Head` bone), the armature `RatArmature`, and every animation the game
uses as an action: idle, walk, run, sneak, carry_walk, drag, sniff (standing up), eat, gnaw, stuck, jump_up,
jump_down, land, sleep, wake_up (pups also: freeze, play, rear, squeak).

The root empty (`rat_mother`) holds the size (scale 0.0731) and stands the model on the floor; leave it as is.

To put an edited rat into the game: File → Export → glTF 2.0, format glTF Binary (.glb), Include: Selected
Objects off, Animation on with mode "Actions", and save over `godot/assets/models/characters/rat_mother.glb`
(or `rat_pup.glb`). Keep the bone named `Head` (the food she carries is held at it) and the action names.

These two are now polished by hand (bigger ears, lighter fur, finer mesh), so `tools/blender/import_characters.py`
skips the rats (set REBUILD_RATS=1 to rebuild them from the free model, which would overwrite the hand edits).
After editing, export from the .blend as described above, or run:
`blender -b art/characters/rat_mother.blend --python-expr "import bpy; [o.select_set(True) for o in bpy.context.scene.objects]; bpy.ops.export_scene.gltf(filepath='godot/assets/models/characters/rat_mother.glb', export_format='GLB', use_selection=True, export_animation_mode='ACTIONS', export_force_sampling=True)"`
