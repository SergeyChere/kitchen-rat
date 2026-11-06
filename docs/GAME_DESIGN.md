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

| Stars | Heat | Response |
|---|---|---|
| ★ | 10 | Cat gets faster and sees further |
| ★★ | 24 | Mousetraps appear (they smell like cheese) |
| ★★★ | 40 | Owner wakes up, turns on the light, patrols with a flashlight, can see onto tables |
| ★★★★ | 58 | Poisoned cheese appears (different smell, detectable by sniffing) |
| ★★★★★ | 80 | Rat hunt: the owner is faster and won't leave until stars drop |

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

### Next
- [ ] Sound: pup squeaks, footsteps, cat meows, tension music during chases
- [ ] Settings menu: graphics quality (bloom on/off), mouse sensitivity, invert Y, volume
- [ ] Save progress between nights; pups grow and ask for different food
- [ ] Night 2+: new rooms (living room, pantry, basement), each adding one mechanic
- [ ] Chapter 1 vertical slice: walls/pipes traversal path, kitchen heist, chase back to the nest

### Unity port
- [ ] Port jumping and surfaces
- [ ] Port scent, sniff and items
- [ ] Port wanted level, traps, owner, poison
- [ ] Toon shader with outlines, bloom, color grading (URP)
- [ ] Steamworks.NET: achievements, cloud saves
- [ ] Steam page and Next Fest demo
