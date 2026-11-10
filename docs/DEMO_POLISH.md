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
