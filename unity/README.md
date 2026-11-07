# Kitchen Rat — Unity project

The Unity version of the game. The three.js prototype in `game/` is the reference for how everything should feel.

## Open it
1. Install **Unity 6 LTS** (6000.0.x) with Unity Hub. Any 6000.0 version works; the Hub may offer to convert, say yes.
2. Unity Hub → **Add → Add project from disk** → choose this `unity/` folder.
3. The first import takes a few minutes (154 models). When it is done the scenes are **built automatically** and the first
   one opens: `Assets/Scenes/01_kitchen.unity`. If Unity asks to enable the new Input System backends, either answer works.
4. Press **Play**, click the game view. To try another night, open its scene from `Assets/Scenes`.

Menu **Kitchen Rat → Build Kitchen Nights** rebuilds the scenes from code at any time (after you change models or night data).
**Kitchen Rat → Reimport Art** reapplies the import settings to all models.
If you opened the first skeleton before, its `Assets/Scenes/Kitchen.unity` is deleted on the next build.

## Building the game
Unity no longer lets a free license build on GitHub, so build on your computer:

- **Windows**: close the project in Unity and double-click `tools\build_unity.bat`. You get `build\KitchenRat-Unity-Windows.zip`.
  `tools\build_unity.bat v0.9.0` also uploads it to that GitHub release (needs the `gh` CLI).
- **Mac**: `sh tools/build_unity.sh` (or `sh tools/build_unity.sh v0.9.0` to upload).
- Or in Unity: **File → Build Profiles → Build** (open the scenes once with Kitchen Rat → Build Kitchen Nights first).

If a build fails, the log is in `build/unity-build.log`.

## Controls
WASD move · mouse look · wheel zoom · Shift run · Ctrl or C sneak · Space jump (face a higher surface until the yellow ring
appears) · E or right mouse sniff · F push things off · Esc pause · R restart.

## Playable nights
The five nights that take place in the kitchen are built as scenes:

| Scene | Night | What to try |
|---|---|---|
| `01_kitchen` | 1 · The Kitchen | The tutorial: jumping, carrying, foil, cracks, sniffing, pushing things off |
| `05_kitchen2` | 5 · The Kitchen, Again | The cat is **awake** from the start; the fridge hum hides your steps; puddle, creaky board, bag |
| `06_water` | 6 · A Glass of Water | The cat sleeps; the **owner** comes for water three times and turns on the light |
| `14_party` | 14 · The Party | The owner comes at the first star; balloons and party poppers, bottles, confetti |
| `16_vacuum` | 16 · The Robot Vacuum | Sleeping cat, the owner at the first star (the vacuum and the pups are not ported yet) |

## Mechanics ported from the prototype
- **Rat**: walk / run / sneak, aimed jumps (yellow ring), jumping down, carrying by weight (crumb 1, cheese 2, big food 3 and
  dragged), delivering in the nest, sniffing (scent trails to the 3 nearest pieces, a hint with direction and distance,
  reveals hidden food and traps).
- **Noise**: running, walking on the floor (not inside a hum), bumping into furniture while running, landing from high up,
  falling objects, and every noisy prop of the prototype (foil, boards, bags, puddles, glasses, balloons, poppers…).
- **Hiding**: cracks and the space under the table, chairs and the shelf. The cat and the owner can't get in.
- **The cat**: away / asleep with a sleep meter (the Zzz bar) that noise drains, half-awake peeking, eating then going to bed,
  wandering, investigating noises, searching, chasing, waiting below when you are up high, catching. Navigates with A*
  on a 20 cm grid like the prototype.
- **The owner**: scheduled visits (a glass of water, flashlight patrols) or coming at his wanted star; turns on the light,
  patrols, hears noises, sees far and onto tables, chases, swats with a slipper, leaves.
- **Wanted level**: evidence (food taken) + alarm (noise, being seen); stars at 10/24/40/58/80 bring the night's threats
  (cat, owner, mousetraps, poisoned cheese) and make everyone sharper.
- **Mousetraps** (placed by the threat or by the night data, some hidden until sniffed; things falling on them disarm them),
  **poisoned cheese** (−4 if delivered), **3 lives**, the night clock, refill of food.
- **Tasks**: the prototype's task system for every night (chain, side, keep, secret; pick, deliver, surf, hide, knock, flag,
  count, pickN) with the flags the ported mechanics raise.

Not yet: the pups who come along, the dog, the robot vacuum, the sleeping kid and guests, sticky traps, the cage, the
exterminator's spray, the TV, the washer, the storm and blackout, tunnels; sound and music; menus and saving; the rooms of
the other 15 nights (step 3).

## Night data
All 20 nights live in `Assets/Resources/Nights/NN_id.json`, exported from the prototype's `game/js/levels.js`:

```
node tools/export_nights.mjs
```

Change a night in `levels.js` (or the JSON directly), export, and rebuild the scenes.

## Layout
| Path | What |
|---|---|
| `Assets/Art/` | Generated models (`tools/blender/run.py` writes here) and room textures |
| `Assets/Resources/Nights/` | The 20 nights as JSON (exported from `levels.js`) |
| `Assets/Scripts/Runtime/` | The game: `GameManager` (rules, noise, wanted level, HUD), `RatController`, `CatAI`, `OwnerAI`, `NavGrid` (A*), `TaskTracker`, `NightData`, zones (nest, hiding spots, noisy things, hum), food, traps, knockables, `FollowCamera` |
| `Assets/Scripts/Editor/` | `ArtImport` (import settings, toon materials), `KitchenBuilder` (builds the kitchen nights from the JSON) |
| `Assets/Shaders/Toon.shader` | Flat banded shading like the prototype |
| `Legacy/RatKitchen/` | The first, primitive-shapes port (cat with a vision cone, hide zones). Outside `Assets`, so Unity ignores it; kept as a reference for porting the cat |

Positions in the night data are the prototype's room coordinates in cm (x to the east, y to the south, origin at the
north-west corner); `Nights.World()` converts them to Unity metres.

Commit the `.meta` files Unity creates next to the assets: they keep scene references stable between computers.
