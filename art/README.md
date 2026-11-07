# Art

Placeholder low-poly models for the Unity version, generated from code with Blender (`tools/blender/`).
The FBX files live inside the Unity project, in **`unity/Assets/Art/`**; this folder keeps the previews and the list.
Replace any of them with hand-made models of the same name, size and origin — the game will pick them up.

| Folder in `unity/Assets/Art/` | What |
|---|---|
| `food/` | Food the rat carries home (crumb, cheese, sausage, pizza…) |
| `finds/` | Nest finds and secrets (button, thimble, sock, photo…) |
| `props/` | Small objects: mugs, traps (with moving `bar`/`door`), toys, noisy items |
| `characters/` | Rat mother, pup, cat, dog, owner, kid, guest, exterminator, robot vacuum — rigged, with animation clips |
| `furniture/` | Counters, fridge, tables, sofa, shelves, washer, beds… (doors/lids are separate children) |
| `rooms/` | Wall sections (plain, mouse hole, crack, window, door), lamps, rugs, nest, wall art, kitchen clutter; `rooms/textures/` — floor and wall textures |
| `art/reference/` (here) | Concept art the models follow: `characters_concept.png`, `props_concept.png`, `furniture_concept.png`, `rooms_concept.png`, `key_art.png` (the mother's goggles, scarf and backpack), `logo_icon.png` (the game icon) |
| `art/previews/` (here) | Contact sheets of every group and `characters_poses.png` with animation frames |

Full list with triangle counts: [MODELS.md](MODELS.md).

## Conventions
- FBX, metres (1 unit = 1 m), origin at the bottom centre, facing +Z in Unity (Blender −Y).
- Characters: one armature, every part rigidly bound to a bone; each Blender Action is a separate clip in Unity
  (`walk`, `run`, `sneak`, `sleep`…). Hand props (flashlight, glass, slipper, spray) are children of the hand bones.
- Rooms are 960 × 600 cm, 250 cm high; wall sections are 120 cm wide and snap side by side.

## Regenerate
```
pip install bpy pillow            # Blender as a Python module (Python 3.11+)
python tools/blender/run.py                        # everything
python tools/blender/run.py props characters       # only some groups: props characters furniture rooms
python tools/blender/preview.py                    # contact sheets
python tools/blender/preview_poses.py              # character poses
```
