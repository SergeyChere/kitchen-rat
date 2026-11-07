# Kitchen Rat: Godot 4 version

This is the main version of the game from now on. The three.js prototype in `game/` is the design
reference.

## Get a build without installing anything

Every push to `main` that touches `godot/` builds the game on GitHub:

1. Open **Actions → Build Godot game** and pick the latest green run.
2. Under **Artifacts**, download `KitchenRat-Windows` (or `KitchenRat-Linux` / `KitchenRat-Mac`; `KitchenRat-Demo-…`
   is the demo).
3. Unzip it and run `KitchenRat.exe` (Mac: unzip the `KitchenRat.zip` inside).

When a release is published, the same zips are attached to it automatically. The artifact also has
`KitchenRat-Demo-*.zip`: the demo with Act 1 only (nights 1–5), for the Steam demo page and Next Fest.

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

The game runs like the prototype: main menu (Continue · Night N, Nights, Settings, Quit), a nest scene with the
pups before every night (the prologue before night 1 the first time), the night itself, a nest scene after a win,
and a results screen with Next night. Finishing a night opens the next one; progress and the best result on each
night are saved. Settings: mouse sensitivity, invert Y, field of view, music and sound volume, quality, fullscreen,
VSync, hints, Calm mode, reset progress. On screen: green outlines show hiding spots, a pale cone shows where the
cat looks, Zzz / ? / ! over the cat, the owner and the dog, noise rings, "Hidden / Unseen / The cat sees you!",
and an arrow to the nest while you carry food. Noisy things glint as you come close and the noise meter warns
"Careful: Clink" right by them; dust puffs when you land, sparkles when you grab food, moon dust by the window,
the ceiling light stutters when the owner switches it on.

Keys can be rebound (Settings → Controls), prompts and task hints switch to gamepad buttons when you play with a
gamepad, and there are window size and colour-blind (purple poison) options. 15 achievements (menu →
Achievements) are saved locally and sent to Steam when the game runs with the GodotSteam extension. Each room has
its own background: the fridge in the kitchen, the boiler and dripping water in the pantry, a ticking clock.

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

Sound and music: every effect from the prototype (squeaks, meows, the cat's bell, barking, the vacuum hum,
thunder and rain, traps, crashes, footsteps…) plays from where it happens in the room. Each night has its own music
with three layers that blend in as the house wakes up: calm, the "wanted" layer (ticking hats, pulsing bass) as
the stars go up, and drums when something is chasing you. Music and sound volume are in the menu.

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
- `assets/sounds/*.wav` and `assets/music/*.ogg` are made by `python3 tools/make_audio.py`. It renders the
  prototype's synthesizer recipes from `game/js/audio.js` offline, so there are no third-party sound files to license.
- `assets/sounds/real/*.ogg` are free CC0 recordings (meows, squeaks, bark, crashes, footsteps, door, rain…), fetched
  by `tools/fetch_sounds.sh` and cut by `python3 tools/import_sounds.py`; sources in `assets/sounds/real/CREDITS.md`.
  When a recording exists for a sound the game plays it, otherwise the synthesized one.
- `art/library/` holds 297 free CC0 Quaternius models (furniture, kitchen, food) as `.glb`, ready to swap in.
