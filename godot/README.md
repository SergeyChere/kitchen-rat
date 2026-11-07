# Kitchen Rat: Godot 4 version

This is the main version of the game from now on. The three.js prototype in `game/` is the design
reference. The Unity port in `unity/` is frozen.

## Get a build without installing anything

Every push to `main` that touches `godot/` builds the game on GitHub:

1. Open **Actions → Build Godot game** and pick the latest green run.
2. Under **Artifacts**, download `KitchenRat-Godot`.
3. Unzip it. Then unzip `KitchenRat-Windows.zip` (or Linux/Mac) and run `KitchenRat.exe`.

When a release is published, the same zips are attached to it automatically.

## Open the project

1. Download [Godot 4.7.2](https://godotengine.org/download) (standard, not .NET). It's a single exe and needs no install.
2. Run Godot → **Import** → choose `godot/project.godot`.
3. Press **F5** to play.

## Controls

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Move | WASD / arrows | Left stick |
| Camera | Mouse | Right stick |
| Run | Shift | Right trigger / L3 |
| Sneak (hold / toggle) | Ctrl / C | LB |
| Jump (aims at the nearest surface) | Space | A |
| Sniff | E / right mouse | Y |
| Push / knock over | F | X |
| Pause | Esc | Start |
| Restart night | R | |
| Back to menu (from pause or end screen) | M | Back |

Food is picked up by walking into it. Bring it to the nest to drop it off.

## What works now

- Nights 1, 5, 6, 14 and 16 are playable. They all take place in the kitchen. The other rooms come next.
- The rat can walk, run, sneak, do aimed jumps onto chairs, the table and counters, carry food to the nest, and hide.
- Noise and the wanted level. Lives. The sniff trail.
- The cat AI: sleeps, wakes, patrols, chases, loses a hidden rat.
- The owner AI: comes in at set times, turns on the light, goes to the sink or fridge, uses a flashlight, leaves.
- Traps, knockable items, night tasks.

## Run the automated checks

```bash
godot --headless --path godot -- --night=kitchen --auto --test=walk
godot --headless --path godot -- --night=kitchen2 --auto --test=cat
godot --headless --path godot -- --night=water --auto --test=owner
```

## Where things come from

- `assets/models/*.glb` is made by `tools/blender/*.py`. Run it with Blender's Python.
- `data/nights/*.json` is made by `node tools/export_nights.mjs` from the prototype's night definitions.
- The level is built in code at runtime by `scripts/level_builder.gd`.
