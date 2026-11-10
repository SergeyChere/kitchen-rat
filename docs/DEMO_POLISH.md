# Demo polish — branch notes

This branch works through the demo plan (nights 1–5) point by point. Nothing
here is merged to `main`; every change is meant to be reviewed and playtested
locally first. The generated PNG textures are *not* committed (they are
binary); run the generator once, see below.

## What changed

### 1. Rat physics and camera feel (`godot/scripts/rat.gd`, `follow_camera.gd`)
- `air_acceleration` 2.0 → 6.0. At 2.0 a hop could not be corrected in the
  air at all; 6.0 is ~40% of the ground acceleration, enough to steer a hop
  without turning it into a double jump.
- `floor_snap_length` 0.05 → 0.12. She used to un-stick from the floor and
  micro-fall when stepping off shelves and ledges.
- Camera: mouse and gamepad stick now move look *targets* (`_yaw_t`,
  `_pitch_t`) and `yaw`/`pitch` ease toward them (`SMOOTH = 18`, frame-rate
  independent). Raw mouse motion used to turn the view instantly, pixel for
  pixel, which felt twitchy. `snap()` sets both the view and the targets.

### 2. Named materials (`tools/make_textures.py`, `level_builder.gd`, `room_furniture.gd`)
- New `tools/make_textures.py` (same idea as `tools/make_audio.py`: no
  external assets, no licence questions). Run from the repo root:
  `python3 tools/make_textures.py` — writes 9 seamless 256×256 PNGs
  (wood, wood_dark, fabric, leather, ceramic_tile, metal_matte, cardboard,
  plastic, counter_stone) into `godot/assets/textures/`. Seeds are fixed;
  every run reproduces the same files, and the script checks its own tiling.
- New `LevelBuilder.mat_named(name, colour, tiling)`: uses the generated
  texture when it exists, falls back to the flat colour until then, so the
  game never breaks on a missing texture.
- First users: the kitchen wall shelves and the shelf over the window now
  take `mat_named("wood", …)` instead of a flat brown.
- Still to do here: sofa/armchair fabric and the rest of the furniture, and
  UV tiling from the box size so grain scale is constant across pieces.

### 3. Bugs
No specific bug list existed yet, so this branch fixes no invented bugs.
What it does instead: every change above is small and isolated, and the
headless checks in `godot/scripts/tester.gd` were run for this branch with
Godot 4.7.2 (after a `--import` pass, as in CI). All green:

- the CI set on night 1 — `bugs`, `rules`, `physics`, `juice`, `sink`,
  `under`: all PASS, no script errors;
- `mech` on nights 1, 2, 3, 4, 5 and 8: the tunnel checks pass ("standing
  in a linked crack shows the prompt", "crawled through the wall to the
  other crack", "task flag: tunnel");
- `hides` on nights 2, 3, 4, 5, `walk` on night 1 and `cat` on night 5:
  all PASS.

### 4. Nights 1–5
- `docs/GAME_DESIGN.md` no longer claims only nights 1–3 are playable, and
  gamepad support is marked done (it shipped in the Godot version).
- The demo definition of done stands: a stranger finishes each night
  without hints, a night takes 8–12 minutes, no softlocks. Night 4's
  `sleepSense = 1.6` is still the steepest difficulty step in the demo and
  is deliberately *not* retuned in code here — it needs a playtest verdict
  first (does the cat find you too fast?).

### 5. Wall tunnels in the demo (`godot/data/nights/01–05`)
The tunnel system already existed (night 8) but the demo nights had cracks
with `"tunnels": []`. Pairs now link cracks across the room, following the
night-8 hub pattern where a room has three cracks:

| Night | Pairs (crack indexes) |
|---|---|
| 1 kitchen | 0↔2, 3↔1 |
| 2 living | 0↔1, 0↔2 |
| 3 living, prowling cat | 0↔1, 0↔2 |
| 4 pantry | 0↔2, 1↔2, 3↔0 |
| 5 kitchen again | 0↔2, 3↔1 |

- Night 2 teaches the mechanic: the task chain ends with "Crawl through a
  path inside the wall" (same `count`/`tunnel` task shape as night 8) and a
  side task "Use the wall paths 3 times". Night 1 already teaches hiding in
  a crack, so the first linked crack appears one night later, while the cat
  is still asleep — before night 3, where a tunnel is an escape, not a toy.
- Deliberately *not* in this branch (they change chase balance and need a
  playtest, not a guess): the 0.8–1.2 s crawl instead of an instant
  teleport, the cat guarding the exit crack when it saw her go in, and
  refusing an exit while an enemy is within ~1.5 m of it.

## How to check locally

```
git fetch && git checkout muse/demo-polish
python3 tools/make_textures.py        # generates the 9 textures
godot --headless --path godot --import   # once, so Godot imports the new PNGs
godot --headless --path godot -- --night=kitchen --auto --test=walk
godot --headless --path godot -- --night=living --auto --test=hides
```

(The PNGs are not in this branch — the push channel for it carries text
only — so the generator run above is a required first step, not optional.
Until it runs, `mat_named` quietly falls back to the old flat colours.)

Then play nights 1–3 and judge three things: does a hop onto the table feel
steerable, does the camera feel calm rather than twitchy, and in night 3 —
can you actually escape the cat through a wall path?

## Round 2 (same day, after the first look)

### Textures, properly (plan point 2)
`LevelBuilder.apply_texture(node, name, tint)` lays a generated texture over a placed model's toon
materials; `RoomFurniture.place()` gained a `tex` argument, tinted by the night's own `color` for the
piece when it has one (the tint is divided by the textures' average brightness, ~0.45, so a purple
sofa stays purple instead of going twice as dark). Wired up: sofa/armchair/ottoman → `fabric`,
cardboard boxes → `cardboard`, crate/workbench/coffee table/bookcase/side table/tv stand/sideboard →
`wood_dark` (shelf unit → `wood`), fridge → `metal_matte`, washer/dryer/laundry basket → `plastic`.
`mat_named()` materials now carry a `tile_m` meta (one tile ≈ 0.5 m) and `box()` duplicates them with
UV scaled by the box size, so the wood grain keeps its scale on any shelf. Kitchen floors (`pal.floor
== "tile"`, nights 1 and 5) use the real `ceramic_tile` texture instead of the placeholder
`floor_tile` pattern, tinted to the old floor's measured tone (0.30, 0.32, 0.45) so the night stays
exactly as dark. Everything still falls back silently when the PNGs are not generated yet.

Not done: kitchen counters/island keep their model materials — one texture over the whole section
would turn the cabinet fronts to stone too; they need per-surface work.

### Gravity (rat.gd)
`gravity` 12.0 → 18.0: she no longer floats on hops and falls. `hop_impulse` 1.7 → 2.08 and
`hop_hold_force` 6.0 → 9.0 scale with it, so the hop apex is unchanged (2.08²/(2·18) = 1.7²/(2·12));
the low-roof hop already derives from gravity. Aimed jumps are timed arcs and do not use gravity.

### More tunnels (nights 1–5 + game.gd)
The demo networks are now complete graphs: every crack links to every other crack (6 pairs in the
4-crack nights, 3 pairs in the 3-crack nights). Because a crack can now have several exits,
`use_tunnel()` chooses: farthest exit from whoever is chasing her (cat / owner / dog); with no chase
on, the first link as before. New helper `_tunnel_exits()`; `_tunnel_from()` keeps its contract.

### The chase feeling (game_feel.gd)
Stronger, and driven by the hunter's distance, as asked:
- danger is felt from 3.4 m out (was 2.2 m) with a steeper curve (power 1.5), so the last metre
  before a catch counts far more;
- a chase starts at 0.72 threat and rises to 1.0 as the hunter closes in (was a flat 1.0);
- threat rises faster (4.5/s) and the heartbeat starts earlier (0.08), beats faster at the top
  (0.34 s, was 0.42 s) and louder (−0.5 dB at full threat, was −3 dB);
- the red edge is stronger (0.85 base + 0.30 pulse, cap 1.0 — was 0.55 + 0.18, cap 0.8) and creeps
  further in from the edges (smoothstep starts at 0.28, was 0.38).

## Round 3 (same day, second look)

### The climb, not the lift (rat.gd)
Playtest verdict on round 1/2: jumping onto a table / island / countertop still read as taking
off. The problem was the hop phase of `_climb_pos`: horizontal and vertical progress ran together
on smoothsteps, so she glided diagonally up at a steady 70° pitch. Now the scramble is split the
way a real rat does it: horizontal movement waits (`smoothstep(0.45, 1, k)`) while the vertical
runs first (`smoothstep(0, 0.55, k)`) — she goes UP the face, paws over the edge, then pulls over
with a 3.5 cm overshoot and settle; `_climb_tilt` rolls the body from nose-up 70° through −18°
as the hindquarters come over instead of levelling out in mid-air. The whole climb is brisker
(`_dur` 0.42 + 0.5·dy, cap 0.8 s; was 0.55 + 0.9·dy, cap 1.1 s). Leg climbs (`_pole_pos`) got
little grip pulses instead of one smooth rise.

### No slow motion when spotted; the red throbs (game_feel.gd, tester.gd)
The `slowmo(0.3, 0.4)` on chase start is gone (the trap snap and being caught keep theirs). The
red edge now pulses with the heartbeat itself: each beat sets `_pulse = 1` and the vignette is
`0.68·threat + 0.45·pulse·threat`, decaying at 3.2/s — a swell on every beat, ebbing between.
GameFeel counts `beats`; the juice test now asserts *no* slow motion, a beating heart and the
red edge, instead of the old slow-mo check.

### Every surface finished on its own (level_builder.gd, tools/make_textures.py)
Materials stopped sharing the toon defaults: `SURFACE_PROPS` gives each named surface its own
roughness/metallic, applied in `mat_named()` and `apply_texture()` — ceramic tile 0.30 and
counter stone 0.27 roughness (the moon patch reads on them), metal 0.38/0.65 metallic, leather
0.55, plastic 0.50, wood 0.72–0.78, fabric 0.96, cardboard 0.92. The generator's textures each
grew their own detail: pores along the wood grain, worn patches over the fabric weave, pebbled
cells in the leather, glaze clouding + kiln speckles + irregular grout in the ceramic, fine
scratches in the brushed metal, flute bands under the cardboard, orange-peel in the plastic,
denser speckle and quartz flecks in the stone. All still tile (the built-in check passes) and
are byte-reproducible from the fixed seeds.

### A living sky (new: godot/scripts/window_sky.gd)
Every night with a window gets a sky outside the north wall: an unshaded moon with a halo,
three dark clouds drifting across it, and near-black branch silhouettes in the top corner
swaying on two sine waves (they cast shadows, so their movement can ghost through the light
patch). The clouds write `Game.moon_cloud` from how much of the moon they cover, and game.gd
multiplies the moonlight by it — the moon dims to ~22% under a cloud and comes back, disc,
halo and floor patch together.

### Light you can read (level_builder.gd, room_furniture.gd)
Two new secondary sources, both with a visible fixture: under-cabinet strip lights in the
kitchens (emissive strip + warm SpotLight, 1.5 energy, over each cabinet block, washing the
worktop) and a plug-in night light in the living rooms (amber emissive box by the TV wall +
steady OmniLight 0.65). The rooms now read as: cold moon from the window, warm practicals
inside — the It Takes Two rule that you always see what is lit by what.

## Round 4 — motivated light, ballistic climb, painted textures (2026-11-10)

Playtest verdict on round 3: the heartbeat is perfect; the new sources read,
but the room as a whole still has light from nowhere; the climb is still not
right; the surfaces are still not right. Reference, again: It Takes Two —
which means big readable shapes and motivated light, not more noise.

**Light.** The sourceless light was the ambient fill: it is cut by ~40% and
cooled (that is moon bounce, nothing more); everything else must now earn its
place. The night-JSON lights (kitchens 1/5, 6, 13, 14, 16) had NO fixture at
all — each now gets a little candle lantern at its own spot (dark base, a
glowing core in the light's colour). And the moon gets a visible path: two
translucent additive sheets run from the window along the moon's own
direction to the floor — a fake shaft, the oldest trick in stylised games —
and the window sky dims the sheets together with the moonlight when a cloud
crosses. The generator now also writes shaft.png (the shaft's alpha
gradient); without it the sheets fall back to a faint flat alpha.

**Climb.** The pattern animators use: anticipation, ballistic rise, squash.
The gathering phase is now a loaded crouch — she DIPS ~3 cm (and leans in to
76°) instead of creeping up; the scramble's rise is an ease-out cubic (fast
off the push, soft at the top — the shape gravity gives), not smoothstep's
slow start; the whole thing is snappier (0.42–0.66 s); and landing from a
climb squashes the model (1.12 / 0.78 / 1.08).

**Textures.** The generator moves from "noisy" to "painted": the wood board
is now visibly four planks (per-plank tone, dark seam, bevel highlight, nails
at the ends); ceramic tiles get a pillow bevel, swelling bright away from
the grout; the fabric weave is chunkier (20 threads) with slub lines; the
stone speckle is blended in instead of hard pixels; cardboard gets broad
soft stains; fine wood noise is reduced.

**Real CC0 textures (optional, better).** The procedural set is a floor, not
a ceiling. The material code now also picks up a hand-dropped normal map:
put a CC0 PBR set's colour map at `godot/assets/textures/<name>.png` (1K is
plenty) and its normal map at `<name>_normal.png`, and the game uses them —
no code change. Verified-free sources (CC0, commercial use, no attribution):
ambientCG (https://ambientcg.com/a/Tiles141 — glazed ceramic;
https://ambientcg.com/a/WoodFloor064 — plank floor;
https://ambientcg.com/a/Wood095 — bare wood;
https://ambientcg.com/a/Fabric081C — woven fabric) and Poly Haven
(https://polyhaven.com/a/patterned_slate_tiles and its wood/floor
categories). Note: re-running tools/make_textures.py overwrites <name>.png,
so keep the downloads somewhere safe.

