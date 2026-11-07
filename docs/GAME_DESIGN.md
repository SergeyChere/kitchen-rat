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

| # | Room | Goal | Night length | Threat order |
|---|---|---|---|---|
| 1 | Kitchen | 10 | 4:00 | cat |
| 2 | Living room | 14 | 4:30 | cat, owner |
| 3 | Pantry | 16 | 4:45 | cat, owner, traps |
| 4 | Dining room | 18 | 5:00 | cat, owner, traps, poison |
| 5 | Kitchen, again | 22 | 5:00 | cat, owner, traps, poison, vacuum |

Rooms are 960 × 600 and built from furniture pieces in `game/js/levels.js`. Any surface at most 57
higher than the current one can be jumped to, so tall pieces need a step (chair → table, crates in a
staircase, armchair → side table).

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

### Unity port
- [ ] Port jumping and surfaces
- [ ] Port scent, sniff and items
- [ ] Port wanted level, traps, owner, poison
- [ ] Toon shader with outlines, bloom, color grading (URP)
- [ ] Steamworks.NET: achievements, cloud saves
- [ ] Steam page and Next Fest demo
