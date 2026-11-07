# Kitchen Rat — Unity project

The Unity version of the game. The three.js prototype in `game/` is the reference for how everything should feel.

## Open it
1. Install **Unity 6 LTS** (6000.0.x) with Unity Hub. Any 6000.0 version works; the Hub may offer to convert, say yes.
2. Unity Hub → **Add → Add project from disk** → choose this `unity/` folder.
3. The first import takes a few minutes (154 models). When it is done the kitchen scene is **built automatically** and opened:
   `Assets/Scenes/Kitchen.unity`. If Unity asks to enable the new Input System backends, either answer works.
4. Press **Play**, click the game view.

Menu **Kitchen Rat → Build Kitchen Scene** rebuilds the scene from code at any time (after you change models or the layout).
**Kitchen Rat → Reimport Art** reapplies the import settings to all models.

## Controls
WASD move · mouse look · wheel zoom · Shift run · Ctrl or C sneak · Space jump (face a higher surface until the yellow ring
appears) · E or right mouse sniff · F push things off · Esc pause · R restart.

## What is in the skeleton (night 1, "The Kitchen")
- The kitchen from the prototype: counters, sink, fridge, island, table with chairs, stool, box, shelf, foil, bread box,
  the mouse hole in the south wall and the nest behind it with four pups.
- The rat: walk / run / sneak, aimed jumps onto chairs → table → counter, jumping down, sniffing with a scent trail, carrying
  up to 3 pieces, delivering them in the nest. Animations play from the clips in the FBX.
- Food: the night's fixed spots (the crumb by the table, the cheese on the plate, the hidden cheese by the bread box…) plus
  random crumbs and cheese. A cheese is worth 5, a crumb 1, the goal is 15.
- Noise: running is loud, foil crinkles unless you sneak, the mug on the table edge falls if you walk past it, F pushes the apple.
- Cracks in the walls to hide in.
- All 12 chain tasks of night 1, the 2 side tasks and the secret (the shiny button), shown bottom-left like in the prototype.
- Clock 23:00 → 06:00 (15 minutes), a win screen when the nest is full and "Dawn came" when time runs out.

Not yet: the cat and the owner, sound, menus and saving, nights 2–20.

## Layout
| Path | What |
|---|---|
| `Assets/Art/` | Generated models (`tools/blender/run.py` writes here) and room textures |
| `Assets/Scripts/Runtime/` | The game: `RatController`, `FollowCamera`, `GameManager` (rules + HUD), `TaskTracker`, `Nights` (night data), zones, food, knockables |
| `Assets/Scripts/Editor/` | `ArtImport` (import settings, toon materials), `KitchenBuilder` (builds the scene) |
| `Assets/Shaders/Toon.shader` | Flat banded shading like the prototype |
| `Legacy/RatKitchen/` | The first, primitive-shapes port (cat with a vision cone, hide zones). Outside `Assets`, so Unity ignores it; kept as a reference for porting the cat |

Night data is ported from `game/js/levels.js`: positions use the prototype's room coordinates in cm (x to the east,
y to the south, origin at the north-west corner) and `Nights.World()` converts them to Unity metres.

Commit the `.meta` files Unity creates next to the assets: they keep scene references stable between computers.
