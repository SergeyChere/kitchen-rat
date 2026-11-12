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

## Round 5 — the playtest list (2026-11-10)

Eleven points from the playtester, taken in order:

1. **Sneak speed** 0.4 → 0.68 m/s. At 0.4 sneaking was a trap nobody used;
   0.68 keeps it clearly slower than walking (0.9) but actually usable.
2. **Tasks.** Main = the goal ("Fill the nest") + the chain, as before.
   Side tasks (green) are now ALWAYS exactly two: the tracker keeps two
   open, tops the night's list up from a built-in pool if it ships fewer
   than six, and when one finishes or fails the next opens at once — and is
   ANNOUNCED (green "+ New side task" at the top of the panel) instead of
   silently materialising by the old "reveal after N steps" rule. Done or
   failed side tasks leave the list (they flash in the announcements).
3. **Kitchen wall paths** (nights 1 and 5) rebuilt to the requested graph,
   now a cycle, not the old complete graph: floor crack SW → up inside the
   wall to a COUNTERTOP exit → up to the CABINET TOPS → behind the FRIDGE
   (east wall) → down to the SE baseboard → back to the start. Plus: the
   table-side crack → straight into the NEST; and two plinth gaps under
   the island, north ↔ south. Cracks can now be elevated (data: h = the
   height she stands at, d = depth onto the surface) and can be plain
   floor holes; elevated cracks get a dark hole disc on the wall. Hiding
   works at elevated cracks (the cat waits below — WATCH mode exists for
   exactly this). And whoever was CHASING her when she dives in now goes
   to the entry crack and searches there (cat: SEARCH 3.2 s, pathing to
   the crack; the owner checks it too if he's near) while she exits
   elsewhere. Still teleports, not a crawlable interior — the wall runs
   are instant, as before; the light remark is answered at the nest (7).
4. **Moving things.** Kettle steams (world_fx puffs at the kettle's spot).
   The sleeping cat breathes (a ~3.4 s swell) and Zzz's as before. A
   garland on the living rooms' south wall: 17 coloured bulbs chasing,
   one real light breathing with them (flicker kind "garland"). The TV
   already flickered when on. The window curtains sway gently. The robot
   vacuum's LED already blinked (night 16). Still static: the cobweb
   (not added), the fireplace is light-flicker only, as before.
5. **Hide props.** Under the kitchen table: a storage box + the kid's
   backpack. Under the coffee table: a box. She now hides AMONG things.
6. **The door moves.** wall_door.glb's leaf is its own node, but hinged at
   its centre — the builder re-hangs it on a pivot at its edge, and the
   game swings it: it opens as the owner arrives (COMING, last 0.9 s) and
   while he's within 1.3 m of it coming or going, and eases shut behind
   him. The rat still can't slip out (the section's collision walls the
   doorway, and the owner at the door is the catch).
7. **The burrow.** The nest light was a bare omni floating mid-air; now it
   spills through the mouse hole (lamp just inside the hole, a warm glow
   disc on the hole), and the burrow got bedding mounds and an old cloth
   so it doesn't read as four flat boxes.
8. **Wall clocks show the night's time.** The model's hands are baked
   into one mesh, so the game now builds its own clock (rim, face, ticks,
   two hand pivots) at the spots the static clock used (kitchen east
   wall; living rooms via the picture-hanging spots). Hands follow the
   HUD clock exactly: 23:00 → 06:00 over the night.
9. **The sausage problem.** Cause found: while dragging, aimed jumps
   were forbidden ENTIRELY — at a table's edge Space did nothing and she
   wedged there. Down-jumps are now allowed while dragging (climbing UP
   with a mouthful stays barred). And when food falls (she's caught), it
   no longer drops straight down at the furniture's base: it scatters
   sideways in an arc to clear floor (Food.toss_scatter), keeping its
   proper scale.
10. **No more crumbs.** "Crumb" in night data now spawns a PIECE of real
    food — a cheese wedge, a pizza slice or a rusk chunk (deterministic
    per spot), worth 2, weighing 1. Small food generally sits bigger
    (world scales: pieces ~0.6–0.85 of models that were drawn larger,
    other small foods ×1.22, big ×1.12) so it reads as food, not specks.
    Task texts in the demo nights say "piece of food" now. Note: fed
    counts value, so pieces (2) fill the nest a bit faster than crumbs
    (1) did — goal numbers may want a nudge up after a playtest.
11. **The cat's eyes + models.** The cat's Eyes are a separate mesh in
    cat.glb (materials CatIris / Eye / EyeShine): in code they're now
    8% smaller, the iris is a true amber with a faint night emission,
    the eyeball near-black. All the game's models are already separate
    .glb files; a zip of the whole models/ tree accompanies this round
    for Blender work (the eyes are the "Eyes" node in characters/cat.glb;
    the door leaf is node "door" in rooms/wall_door.glb; the clock's
    hands are baked — that model is decorative now).

**Known issue (pre-existing, not from this round).** The night 2 walk test
(chair → dining table jump targets) fails — and fails identically on the
round-4 build, so it predates round 5 (likely older). The rat's target
scanner doesn't offer the chair in the living room. Worth its own look:
it smells like the same family as the sausage-at-the-edge problem.

## Round 6 — the user's eight points (2026-11-10)

1. **The heartbeat by the door, with no cat.** Root cause: the owner waits
   invisible at the door while AWAY / COMING, but his root node stays
   "visible" and GameFeel's proximity term counted him. He now counts only
   once `OwnerAI.in_room()`. Verified by reading the modes: the cat already
   hides its root when AWAY and is skipped while asleep — the owner was the
   only leak.
2. **The kitchen light stood on air.** The JSON candle (h≈60 in an empty
   corner) got a visible fixture in round 4 but nothing under it. Now a
   slim stand (pole + foot disc) carries any candle higher than 12 cm down
   to the floor.
3. **The moon shaft was a searchlight.** Albedo alpha 0.5 → 0.26, both in
   the builder and in the sky's per-frame cloud dimming; the untextured
   fallback went 0.13 → 0.07.
4. **The garland worked "so-so".** It was a dead-straight wire at the
   ceiling with a fast harsh chase. Now: two sagging swags (segmented wire
   on a cosine hang), bulbs on little sockets below the wire, a slower
   travelling wave (1.7 rad/s, cubic pulse, phase step 0.55), and the real
   light breathes with the same wave instead of its own unrelated sine.
5. **The climb was a rocket.** Rebuilt stage by stage, as specified:
   run-in and rear up → a real crouch (she loads, nose up the face) → a
   first spring up the face (front paws pull) → a hitch while the hind
   legs find the wall → the wall kick (she visibly shoves a touch AWAY
   from the face) → front paws over the edge and pull through → landing
   squash (already there). The rise is a keyframed curve (`Rat._keys`)
   with two impulses and a plateau between them; up/grab climbs take
   30% longer so the stages can be read.
6. **Sloppy holes.** The flat dark discs are gone. A hole is now an
   irregular seeded blob (a 10-point fan, radii 0.7–1.14 of nominal) with
   a chipped-plaster rim behind it — floor holes and wall holes both.
7. **No Python — and there will be no Python.** The texture generator was
   ported INTO the game: `texture_gen.gd` paints the same nine materials
   (+ the shaft gradient) in GDScript, seeded and tileable, at 256×256.
   `texture_lib.gd` resolves each texture in order — CDN pack, repo file,
   earlier-generated cache, paint-now-and-cache — and paints the full set
   on a background thread at boot, so the first night rarely pays for it.
   `tools/make_textures.py` stays as the offline reference variant.
8. **Textures on a CDN.** Heavy good textures never belonged in git
   anyway. `godot/cdn.json` holds one zip URL (a GitHub Release asset,
   tag `textures-v1`, on this repo); at boot the game fetches it once in
   the background into `user://textures/` and marks `.cdn_done`. Offline,
   a missing release, any failure — the painted textures take over
   silently; the game never waits for the network. To publish the pack:
   zip the maps flat (wood.png, wood_normal.png, ceramic_tile.png, …),
   create the release `textures-v1`, attach the zip as `textures.zip`.

**Testing.** Night 1 CI set: bugs 5, rules 4, physics 7, juice 13,
sink 5, under 1 — all pass. Hides pass on nights 1–5, walk on night 1,
cat on night 5, physics on nights 1 (7) and 5 (7). The physics "teeter"
check fails on nights 2–4 — verified PRE-EXISTING (fails identically on
the round-5 build): that check teleports her onto a kitchen table at
(700, 420), which only exists in the kitchen nights. Same family as the
known night-2 walk failure: the tester assumes kitchen geometry.

## Round 7 — the user's five points (2026-11-10)

1. **The door drifted (night 1).** Round 5's hinge math re-applied the
   leaf's own offset — its centre sits at (0, 1.06, −0.02) in the model —
   INSIDE the pivot, lifting the leaf ~1 m. The hinge now goes at the
   leaf's edge in parent space (through the leaf's own basis), the leaf
   sits at exactly (0.45, 0, 0) inside it, and the swing adds to the
   leaf's base yaw instead of overwriting it. A tester check ("the door
   leaf hangs at door height") guards it.
2. **A light for the pantry.** Night 4 had NO light sources of its own.
   A small wall lamp now hangs on the north wall by the washing machines
   (plate, green enamel shade, warm bulb, steady OmniLight, range 3.4).
3. **The garland's switching was invisible.** Round 6's wave kept every
   bulb lit and smeared the phase, so nothing visibly switched. Now a
   real chase: four groups in turn, bulbs mostly OFF between their beats
   (emission floor 0.1, pulse^6), so the alternation reads across the room.
4. **The climb, third rebuild — this time from the rig out.** Diagnosis
   (measured, not guessed): jump_up is a 0.42 s one-shot. It played at
   full speed, FINISHED, and froze in its end pose while the parametric
   path kept gliding — a statue on a wire. Its root-bone translation is
   ~zero (one key, −0.0005), so the other stack was the tilt: rounds 4–6
   pitched the whole model 66–80° around the floor-level origin ON TOP of
   the clip's own spine pitch — a slow backflip. Fixes: the clip is
   TIME-WARPED onto the climb's length (its crouch/launch/pull-over land
   with the path's stages; pole climbs play the run clip as a leg
   scramble); the model tilt is now just a lean (≤38°); the path's hitch
   became a small SLIP back (0.50 → 0.46) with the body pressed INTO the
   face, then the kick shoves her off it; the root pose offset is
   cancelled out of the model node each climb frame as a guard, and
   restored on every exit from the jump state.
5. **Toward It Takes Two, honestly.** The gap is bespoke modelled sets +
   per-asset painted textures + graded light; no single code change
   closes it. This round's step: the whole game is graded — ACES filmic
   tonemapping (was linear) and a whisper of glow, so candle cores,
   garland bulbs and moonlight roll off and bloom instead of clipping.
   The remaining road, in order: the CDN PBR pack (round 6, awaits the
   user's upload), denser set dressing per room, bespoke models.

**Testing.** Night 1 CI set all pass: bugs 6 (the new door check among
them), rules 4, physics 7, juice 13, sink 5, under 1. Physics night 5,
hides night 2, walk night 1, cat night 5 — pass. The bugs suite fails
3 checks on night 4 (mug/cheese props) — verified PRE-EXISTING on the
round-6 build: that suite is kitchen-specific and CI only runs it on
night 1.

## Round 8 — the user's seven points (2026-11-10)

1. **The climb: "too many steps on the wall".** Round 7 still read as
   running up the wall. The user's biomechanics: she should FOLD IN
   HALF midway, and the fold should be the impulse for the extra jump.
   Now, for climbs ≥ 0.45 m: spring → grab → the rise DIPS deep
   (0.52 → 0.40) while her pitch jackknifes to −26° (hindquarters swing
   up under her), the clip nearly freezes (she holds, no leg steps),
   the body squashes flat (scale y 0.78) — then ONE unfold: rise
   0.40 → 0.90 in a fifth of the climb, pitch whips back, body stretches
   (scale y 1.13). Low hop-ups (< 0.45 m) keep the simple spring — the
   short jump was approved as-is.
2. **The floor lamp by the garland, dimmed** — in living rooms only:
   energy 1.3 → 0.7, range 3.8 → 3.0. Other rooms untouched.
3. **A moving fire in the fireplace** — it was a flickering light
   behind a static model. Now 26 CPU flame particles rise over the
   logs, shrink and die, orange → ember-red, additively blended; the
   warm flicker light stays as their glow.
4. **Question answered (no code): the CDN does NOT need a merge.**
   Releases are independent of branches; the game reads the release
   URL from `godot/cdn.json`, which is already in this branch. Steps
   for the user are in the round-8 report. Loader now also accepts
   .jpg files in the pack (what the texture libraries actually ship).
5. **Grading for the whole game (asked).** On top of round 7's ACES +
   glow: every room KIND now grades differently — ambient tint and
   adjustment presets per kind (living/dining warm and softer, pantry
   cold and flat, kids sweeter, kitchens crisp) — plus a film overlay
   on the whole frame: soft vignette + a whisper of animated grain
   (skipped on the low quality setting).
6. **"She swims when just walking" — measured, and it's bad.** The
   stride tester (extended to the rat) says the rig's clips were
   authored ambling: walk feet travel 0.09 m/s at playback 1.0, sneak
   0.055, carry 0.08, run 0.63 — against body speeds of 0.9/0.68/1.9,
   the feet were moving at a TENTH of the ground speed. She wasn't
   walking, she was ice-skating. Gaits are now sped from her ACTUAL
   velocity against the measured clip speeds (WALK_CLIP & co in
   rat.gd), so stance feet travel with the ground. Footstep sounds are
   distance-based and unaffected.
7. **The owner enters at once.** COMING was a 2.4 s wait in the hall
   with the door opening at the end. Now 0.9 s, and the door starts
   swinging the moment he arrives — he steps straight in behind it.

**Testing.** Import clean. Night 1 CI set all pass; hides night 2
(living room: dimmed lamp, fireplace), physics night 5, walk night 1,
cat night 5 — all pass.

## Round 9 — the user's two remaining complaints (2026-11-10)

Verdict on round 8: the run is GOOD ("running is fine now"), the
garland, lamp, fire, grading and the owner's entry were accepted; two
things still bothered him.

1. **Slow walking: "her legs look short — slightly fewer steps."**
   The true stride rate (round 8) reads as a blur of tiny steps at slow
   gaits. The slow gaits (walk, sneak, carry) now run at 80% of the
   stride rate — slightly fewer steps, a whisper of slide traded back.
   The run keeps the exact measured rate, untouched.
2. **The high climb: TWO JUMPS, not a fold, not a run up the wall.**
   His recipe: take the approved low jump and chain two of them. For
   climbs ≥ 0.45 m she now hops to a grab point at 57% of the face,
   clings there a beat (body pressed to the face, settling 3% as she
   loads, the clip frozen — she holds), then pushes off the face and
   hops over the edge. The rise is two arcs with a plateau; squash &
   stretch follow the hops (stretch in each arc, compressed at the
   grab). The round-8 fold is gone. Low hop-ups unchanged.

**Testing.** Import clean; night 1 CI set all pass; walk night 1,
physics night 5, cat night 5 — pass.

The user is merging this branch into main himself and setting up the
CDN release (textures-v1); the branch is ready for that.

## Round 10 — the lighting pass (2026-11-10)

The user asked for ALL of the light found, audited and re-set on
cinematic schemes. Full audit first (it is short — the game has fewer
sources than it feels like):

- **Moon** (directional, from the north window, shadows on) — the KEY.
- **Environment ambient** — the FILL, flat and cool.
- **Kitchen**: one candle practical in the SE corner (omni, shadows
  on) + two warm under-cabinet spots over the counter run + the
  moon shaft sheets + the ceiling light (off until the owner comes).
- **Rooms**: fireplace omni, floor/table lamps, the TV's cool flicker
  omni, the garland's warm omni, dining candles, the pantry wall lamp.
- **The owner's flashlight** (spot, shadows on, swept by his patrol).
- **The nest**: one warm omni through the mouse hole. Plus emissives
  with no light of their own (garland bulbs, candle cores, TV screen)
  and one gameplay light (the green exit ring — left alone on purpose).

The scheme applied — classic three-point, translated to a night
interior: a cool KEY (the moon), a low complementary FILL, warm
PRACTICALS as accents, darkness preserved between pools.

1. **The fill is now SHAPED.** A second directional ("Moon fill",
   0.22, deep blue, no shadows) comes from over the camera's shoulder
   (south-east, high): south faces get gentle blue modelling, so the
   rat's silhouette separates from dark furniture instead of melting
   into it. Flat ambient drops a little (0.42 → 0.38) and drops more
   in warm-keyed rooms (living/dining ×0.78) so their fires own them.
2. **Every practical is now a POOL.** Omni attenuation was the
   default 1.0 everywhere — washes, not pools. Now: data practicals
   1.45, furniture practicals by kind (fire 1.35, steady 1.3, garland
   1.25, TV 1.15), the ceiling light 1.3, the nest 1.2. Light falls
   off; the dark between sources is back.
3. **The moon deepened**: colour (0.72, 0.8, 1.0), shadow opacity
   0.55 → 0.62. Orange-teal, the night-film standard: blue keys and
   fills against warm practicals.
4. **Cabinet spots**: warmer (1.0, 0.72, 0.42), cone 58° → 46°,
   energy 1.5 → 1.35, attenuation 1.15 — a defined pool on the
   counter where the food is.
5. **The flashlight has a BEAM now.** An additive cone hangs in the
   air under his spot (bright at the lamp, fresnel-edged, fading down
   its length), a child of the light so it sweeps and switches with
   it. Patrols read across the room before the pool lands anywhere.

**Testing.** Import clean (one naming slip in the beam code was
caught and fixed before this push). Night 1 CI set all pass; night 7
(the flashlight night) boots and runs; hides night 2 pass.

## Round 11 — the tall climb is deleted; the night-8 cloth (2026-11-10)

1. **"You can't make the high jump work — delete it."** Done, all of
   it: the staged wall climb (and its fold / two-jump successors), the
   leg climb (`_try_pole`/`_pole_pos`, which climbed table legs up to
   1.2 m), the per-hop squash windows and the clip-freeze that served
   them. What remains is the ONE approved spring, and the scanner's
   reach cap is now `max_jump_up = 0.54` — a taller face is simply
   never offered. High places are reached over other furniture, which
   the levels already teach (measured with a raycast probe, night 1:
   chair seat 0.41 → counter 0.92 is a 0.51 step, chair → table 0.38;
   night 4: crates 0.40 → 0.80 → 1.20 in 0.40 steps, box 0.50, tall
   box +0.42, basket 0.43 → washer 0.86, stool 0.52 → bench 0.80).
   Kept, deliberately: climbing DOWN an edge, catching an edge
   mid-fall, and climbing out of the sink — none of them is a way UP
   a tall face. One route is tight and worth a playtest look: the
   island (0.92) is reached from the kitchen-table chair nearest it
   (a 0.51 step across a ~0.6 m gap); if that feels finicky, the fix
   is a stool by the island — a level-design call for the user.
2. **Night 8's tablecloth** threw the ceiling light back like a
   mirror (the model's pale cloth). Dining tables now get a deep
   wine cloth (0.4, 0.12, 0.15) with the woven fabric texture,
   roughness 0.96 and specular nearly off — matte, and the dining
   room gains a colour.

**Testing.** Import clean; night 1 CI set all pass; walk night 1
pass (the auto-walker still routes over furniture); night 8 boots
clean; hides night 4 pass.

## Round 12 — dragging down, houseplants, real cheese, varied food (2026-11-10)

Playtest reports, three of them:

1. **"The chicken leg hung under the table while she tried to drag
   it off."** Hauling big food DOWN off a surface was the broken
   part of dragging: the climb-down refused outright while dragging,
   and the jump scanner only ever looked where she FACES — but a
   dragging rat walks backwards, so the drop she was backing toward
   was never scanned and never offered; she could only back blindly
   off the edge and fall with the leg. Now: descending an edge works
   while dragging (walk backwards off a table and she climbs down
   with the leg in her teeth), and while dragging the drop scan also
   covers the direction she is actually moving, so Space hops her
   down off the edge she is backing toward. Up-offers are suppressed
   while hauling (the dispatch barred them anyway; one could hide
   the drop behind her).
2. **More houseplants, swaying.** Dressed rooms now place TWO
   plants (plus the floor lamp) instead of one; the kitchen — which
   the dressing pass skips — gets its own in the SW corner; and
   every plant (data-placed ones too) registers into `Game.plants`
   and breathes in `_tick_props`: a slow two-axis tilt of a couple
   of degrees around its base rotation, each on its own phase, the
   way the curtains already sway.
3. **Cheese with a texture; food with variety.** The cheese model
   wore a flat plastic yellow; TextureGen now paints a "cheese"
   (warm marbled rind, eleven seeded holes, dark and shadowed at
   their hearts) plus a matching "cheese_normal" whose dips are the
   same holes, and `spawn_model_food` dresses every cheese-model
   food in it. The placed food on nights 1–5 was nearly all cheese
   and crumbs; the spots now mix cake, salami, pizza, potato, lard,
   sausage, cookie, biscuit and explicit pieces across the same
   positions and tags (night totals stay in their old range), a
   `plate: true` spot flag serves the food on a plate (builder
   spawns it, the food sits in it), a few pieces lie on the floor —
   one under the kitchen table — and random finds roll cookies and
   cake slices too, not just cheese.

**Testing.** Import clean; night 1 CI set all pass; walk night 1
pass; nights 2, 3, 4, 8 boot clean; hides nights 2 and 4, cat and
physics night 5 pass.


## Round 13 — the look pass toward It Takes Two (2026-11-12)

The target the user named is It Takes Two: not to match it, to move
toward it. Everything here stays on the Compatibility renderer (the
user's laptop does not start Forward+), and each item was pushed to
`main` as its own small commit.

1. **Kitchen.** The first room was the weakest: an ultramarine floor,
   a worktop clipped to white, a washed-out tablecloth, a black
   ceiling. Floor tiles are a muted slate with half-contrast detail,
   walls a warm white (they read blue in the night ambient), the
   island and cloth are textured, the ceiling glows faintly.
2. **Smooth characters.** Models arrive flat-shaded (four vertices
   per point). `LevelBuilder.smooth_mesh` averages normals per
   position (keeps creases), stores the rest position in CUSTOM0
   and is cached; `FLAT=1` shows the models as authored.
3. **Fur.** Shell fur, 14 layers, on materials named Grey/White of
   the rat, pups and cat: dense, jittered, combed back, lighter at
   the roots. Off on quality low and with `NOFUR=1`. The shader has
   its own `light()` — direct light at 0.74, and the glow along the
   edge needs the light to actually reach it.
4. **Ground shadows.** No SSAO in Compatibility, so every piece of
   furniture standing on the floor and every wall gets a soft
   painted contact shadow (`_ground_shadows`, `HIDE=ao` to compare).
5. **Warm against cold.** Every room: a glowing gap under the door,
   a warm wedge on the floor, a small spill light. Kitchens: a
   plug-in night-light by the mouse hole. `HIDE=warm` to compare.
   **Lesson:** Godot's omni lights follow an inverse-power law; a
   lamp 10 cm from a wall with a falloff of 1.5 gives that wall
   ~40× its energy. Both lamps now use a falloff of 0.6, a third of
   the energy and sit further from the surface.
6. **Depth of field.** `Dof` (scripts/dof.gd): a full-screen quad on
   the camera reading the screen and depth textures, 12 taps, far
   blur only. Setting "Depth of field (soft background)"; off on
   quality low; `HIDE=dof` to compare.
7. **A living rat.** A glint in each eye (a small white sphere on
   the Head bone), light on the edge of the coat.
8. **Main menu.** The night-1 kitchen is built behind the menu
   (`Game.backdrop`): no HUD, no rules; she stands in the moon
   patch near her door and sniffs the air now and then, a camera
   drifts past at floor height. The menu sits on the left; Nights,
   Achievements and Settings keep the room visible through a veil.
   Dev: `--via_menu`, `--no_backdrop`,
   `BACK="x,y,facex,facey,lift,side,r"`.

**Checked.** Night 1 CI set after every item; night start through
the menu (`--via_menu --test=bugs`); screenshots of the kitchen,
living rooms (nights 2, 3), pantry (4), kitchen night 5, the cat
and the rat up close, the mouse hole and the door.

**Not checked.** Pups and the owner up close; fur in motion; the
cost of fur + depth of field on the user's laptop (both can be
switched off: quality low, or the DOF checkbox).
