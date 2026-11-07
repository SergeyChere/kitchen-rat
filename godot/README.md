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
| Push / knock over · hold to gnaw a bag open | F | X |
| Pups: wait / follow | Q | RB |
| Pup fetches the nearest food | R | D-pad up |
| Crawl through a linked crack | Space (standing in it) | A |
| Pause | Esc | Start |
| Restart night (paused or at the end) | R | |
| Back to menu (from pause or end screen) | M | Back |

Food is picked up by walking into it. Bring it to the nest to drop it off.

## What works now

All 20 nights are playable:

| Nights | Room | What's new |
|---|---|---|
| 1, 5, 6, 14, 16 | Kitchen | the cat, the owner going for water, party guests asleep on the floor, the robot vacuum |
| 2, 3, 10, 17, 20 | Living room | sofa and armchair to hide under, the TV remote, the storm and the blackout, the dog that follows your scent, the finale exit |
| 4, 7, 9, 12, 18 | Pantry / laundry / basement | bags to gnaw open, the flashlight patrol, the washing machine hum, sticky tape, the cage trap |
| 8, 11, 15 | Dining room | tunnels between linked cracks, mousetraps, poisoned cheese |
| 13 | Kids' room | the sleeping kid (wakes the cat when screaming), the backpack full of cookies |
| 19 | The whole floor | three rooms joined by doorways |

Pups come along from night 11. Each has a personality: Brave runs ahead for food, Greedy grabs anything (even
green cheese), Shy freezes at loud noises and warns about the cat, Curious sniffs out hidden food and secrets.
The cat, the dog or the owner can catch a pup. Walk up to it to rescue it.

Not yet in the Godot version: sound and music.

## Run the automated checks

```bash
godot --headless --path godot -- --night=kitchen --auto --test=walk
godot --headless --path godot -- --night=kitchen2 --auto --test=cat
godot --headless --path godot -- --night=water --auto --test=owner
godot --headless --path godot -- --night=dining --auto --test=mech    # the night's special mechanics
godot --headless --path godot -- --night=living --auto --test=hides   # every hiding spot fits the rat
```

## Where things come from

- `assets/models/*.glb` is made by `tools/blender/*.py`. Run it with Blender's Python.
- `data/nights/*.json` is made by `node tools/export_nights.mjs` from the prototype's night definitions.
- The level is built in code at runtime by `scripts/level_builder.gd`.
