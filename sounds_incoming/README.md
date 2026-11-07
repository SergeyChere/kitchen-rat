# Your own sounds

Put each sound in a folder named after it: `sounds_incoming/<name>/`, 1–6 takes (variants) per folder, any format
(wav, mp3, ogg, flac). Then run `python3 tools/import_sounds.py` — it trims silence, makes them mono, evens out
the level and writes them into the game, replacing the free version of that sound. The files in this folder are
not committed (only this README), because they are licensed to you, not to the public.

Short one-shots: under 1–1.5 s, dry (no long reverb, no music). Loops (`*_loop`): 10–60 s, steady, no fades.

## 1. Most needed (the game still uses a synthesized sound)

| Folder | What it is in the game | Search for |
|---|---|---|
| `purr` | the cat purring when calm / fed | cat purr close |
| `squeak` | Mom rat's squeak (pups use it pitched up) | mouse squeak, rat squeak |
| `sniff` | Mom sniffs for food (key F) | small animal sniff, sniffing |
| `bell` | the bell on the cat's collar, every few steps | cat collar bell, small bell jingle |
| `beep` | robot vacuum beeps (start, bump, error) | robot vacuum beep, appliance beep |
| `hum_loop` | robot vacuum driving (loop) | robot vacuum loop, roomba |
| `tv` | TV turning on, voices/static | tv turn on, tv static, tv chatter |
| `crackle` | fireplace pops | fireplace crackle, fire pop |
| `squeaky` | dog's squeaky toy on the floor | squeaky toy, dog toy squeak |
| `buzz` | stepping on a power cord / the running washer | electric buzz, appliance hum short |
| `musicbox` | a music box on the floor, stepped on | music box short, toy music box |
| `cheese` | grabbing cheese | (UI) reward pickup, cute collect |
| `pickup` | picking up a crumb | (UI) small pop, pickup |
| `deliver` | food delivered to the nest | (UI) success, coin, collect |
| `poison` | green cheese delivered | (UI) negative, sick, gross |
| `caught` | caught by the cat/owner/dog | (UI) hit, fail stinger |
| `win` | night won | win jingle short |
| `lose` | night lost | lose jingle short |
| `star_up` | the "wanted" star goes up, achievement | alert rise, whoosh up |

## 2. Better versions (a free recording is used now, a nicer one would help)

| Folder | What | Search for |
|---|---|---|
| `meow`, `meow_q`, `meow_angry` | cat: normal, questioning, angry hiss/yowl | cat meow / cat trill / cat hiss |
| `bark` | the dog | dog bark medium |
| `snore` | owner / dog sleeping | snore |
| `gnaw` | gnawing through a box or a wire | rodent gnaw, chewing cardboard |
| `crunch` | eating, stepping on grain | crunch small |
| `step` | rat's tiny steps | small footsteps, paws |
| `stomp` | the owner's footsteps | footsteps wood floor slippers |
| `door`, `light_switch`, `creak` | door open/close, switch, floor creak | |
| `crash`, `clink`, `bang`, `thud` | glass breaking, glass/plate tap, pot falling, heavy thing falling | |
| `snap` | mousetrap snapping | mousetrap snap |
| `whack` | the owner's slipper hit | slap, whack |
| `splash`, `crinkle`, `scratch`, `scrape` | puddle, plastic bag, claws on fabric, sliding on wood | |
| `thunder` | storm nights | thunder close |
| `land`, `land_big`, `jump` | rat lands / big fall / jump swish | |
| `click`, `task`, `fail` | menu click, task done, task failed | UI click, success chime |

## 3. Loops (room ambience)

| Folder | What |
|---|---|
| `rain_loop` | rain on the window (storm nights) |
| `fridge_loop` | fridge hum |
| `clock_loop` | wall clock ticking |
| `boiler_loop` | boiler / water heater |
| `drip_loop` | dripping tap |
