# Kitchen Rat: design notes

## Pitch

You are a mother rat. Your pups are starving in a nest behind the kitchen wall. Every night you sneak
out, steal food and carry it home before dawn. The house is huge from a rat's point of view, and the
people who live in it slowly figure out they have a rat problem.

Inspirations: **Stray** (small animal, readable traversal, jump prompts), **GTA** (wanted stars that
escalate the response), **Untitled Goose Game** (a domestic space as a playground).

## Design pillars

1. **Always readable.** The player should never wander around wondering what to do. Clear goals,
   highlighted interactables, jump prompts, scent trails. No pixel hunting in open areas.
2. **Greed vs. safety.** Every extra piece of cheese raises the heat. The interesting choice is
   whether to grab one more or lie low.
3. **Rat senses.** Smell is the signature mechanic: it pulls you toward cheese, and it is also how
   you tell real cheese from traps and poison.
4. **Cozy stakes.** The pups give the stealth a warm reason. Feeding them is the reward.

## Core loop (one night)

1. Wake up in the nest, pups ask for food (cutscene).
2. Enter the kitchen, use smell to find food, jump up onto furniture to reach cheese.
3. Avoid the cat and, later, the owner. Hide under furniture, distract by knocking things over.
4. Carry food back to the hole (max 3 weight: crumb = 1, cheese = 2).
5. Repeat until 20 food is delivered (win) or dawn comes / you get caught 3 times (lose).

## Wanted level

Heat = **evidence** (permanent, from thefts) + **alarm** (temporary, decays when unseen).

| Heat source | Amount |
|---|---|
| Steal a crumb / a cheese | +3 / +9 evidence |
| Seen by the cat | +4 alarm per second |
| Seen by the owner | +12 alarm per second |
| Running, loud drop, knocking things over | +0.5 / +2 / +7 alarm |
| Getting caught | +10 alarm |

Alarm decays after 4 s out of sight (5/s), faster in the nest (14/s).

Stars are reached at heat 10 / 24 / 40 / 58 / 80. Each night has an ordered list of threats; the
n-th star unlocks the n-th threat. Stars beyond the list make everyone faster ("High alert").

| Threat | What happens |
|---|---|
| cat | The cat starts asleep in its bed. Noise nearby or the first star wakes it. It can't climb, so it waits below |
| owner | Footsteps, the door opens, the light comes on. Patrols with a flashlight, sees onto tables, chases, whacks with a slipper. Leaves if stars drop for 8 s |
| traps | 3 mousetraps placed near furniture (2 more at 5 stars). They smell like cheese; sniffing reveals them |
| poison | One cheese turns poisonous; new cheese has a 45% chance. Different scent color. Delivering it costs 4 food |
| vacuum | A robot vacuum roams everywhere, including under furniture, eats floor crumbs and beeps loudly when it bumps you |

## Nights

20 nights in four acts of five (full plan: the "Kitchen Rat — план до релиза в Steam" doc).

| Act | Nights | Theme |
|---|---|---|
| 1 · Silence | 1–5 | Moving quietly. Only the cat. 1 empty kitchen, 2 sleeping cat, 3 prowling cat, 4 sniffing out hidden food, 5 distractions |
| 2 · The Owner | 6–10 | The owner, lamps and flashlight, paths inside the walls, the laundry room, a storm |
| 3 · Traps | 11–15 | Mousetraps, sticky traps, the kids' room, a party, poison |
| 4 · Siege | 16–20 | Robot vacuum, a dog that follows your scent, sealed cracks, the whole floor, moving out |

Playable now: nights 1–3. Target length per night in the final game: 15–20 minutes.

### Noise and the sleeping cat

| Action | Heard within | Sleep lost at point-blank |
|---|---|---|
| Sneak (Ctrl / C) | silent | 0 |
| Walk | 95 | 0.10 every 0.45 s |
| Run | 210 | 0.30 every 0.35 s |
| Bump into furniture while running | 170 | 0.45 |
| Jump down from higher than 50 | 160 | 0.55 |
| Knock something off a table | 460 | 0.90 |

Sleep drops with distance (linear to zero at the edge) and faster with each wanted star. After 2.5 s of
quiet it recovers 0.045 per second. Below 0.6 the cat stirs, below 0.3 it lifts its head and looks
toward the last noise: if it sees the rat, it wakes. At 0 it wakes and prowls for the rest of the night.

## Sound

All audio is synthesized in `game/js/audio.js`. Each night has its own key, tempo and chord loop. Two
extra layers fade in on top: a "wanted" layer (ticking hats and a pulsing bass) that follows the star
count, and chase drums while the cat or the owner is chasing you.

## Controls

See the main README.

## Roadmap

### Now (HTML prototype)
- [x] Third-person camera with mouse look
- [x] Jumping between floor, chairs, stool, table, counters (Stray-style prompts)
- [x] Cat with A* pathfinding, random wandering, vision cone, hearing, chase, guarding below
- [x] Cheese scent, sniff trail, poison and trap detection
- [x] Wanted stars with mousetraps, the owner, poison
- [x] Intro and outro cutscenes with the pups
- [x] Desktop app (Electron) and CI builds
- [x] Five nights in four rooms with escalating threats
- [x] Synthesized adaptive music and sound effects
- [x] Main menu, night select, pause, results, settings; saved progress

### Next
- [ ] Pups grow between nights and ask for different food
- [ ] Traversal paths between rooms (inside walls, pipes) as short linear levels
- [ ] Gamepad support
- [ ] More owner behaviour: sets traps where you were last seen, calls for help at 5 stars

### Godot version
- [x] Port every mechanic, all 20 nights, menus, sound and music
- [ ] Steamworks (GodotSteam): achievements, cloud saves
- [ ] Steam page and Next Fest demo
