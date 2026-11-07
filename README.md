# Kitchen Rat

A stealth game about a mother rat who sneaks into a different room of the house every night to feed
her hungry pups. Every theft leaves evidence, and the house fights back GTA-style: the more you steal,
the higher your wanted level, from a sleepy cat to the owner with a flashlight, mousetraps, poisoned
cheese and a robot vacuum.

![icon](build/icon.png)

## Download and play

The game is made in Godot 4. Every push to `main` builds it for Windows, Mac and Linux:

1. Open [Actions → Build Godot game](https://github.com/SergeyChere/kitchen-rat/actions/workflows/godot.yml) and click the newest green run.
2. Under **Artifacts**, download **KitchenRat-Windows** (or **KitchenRat-Mac** / **KitchenRat-Linux**). The
   `KitchenRat-Demo-…` downloads are the demo (nights 1–5).
3. Unzip it and run `KitchenRat.exe` (Mac: unzip `KitchenRat.zip` inside and open the app). If Windows shows
   "Windows protected your PC", click **More info → Run anyway**.

**Скачать и играть (RU):** открой [Actions → Build Godot game](https://github.com/SergeyChere/kitchen-rat/actions/workflows/godot.yml),
выбери последний зелёный запуск и внизу в **Artifacts** скачай **KitchenRat-Windows**. Распакуй и запусти `KitchenRat.exe`.
Если появится окно «Windows защитила ваш компьютер», нажми **Подробнее → Выполнить в любом случае**.

The old browser prototype (three.js) is still in `game/` for trying ideas; it is no longer built as a desktop app.

## For developers

> **The game is in Godot 4:** see [godot/README.md](godot/README.md). The rest of this section is about the
> browser prototype in `game/`.

### Run the prototype from source

You need [Node.js](https://nodejs.org) 20 or newer.

```bash
git clone https://github.com/SergeyChere/kitchen-rat.git
cd kitchen-rat
npm install
npm start
```

### Build an installer

| Platform | Command | Output in `dist/` |
|---|---|---|
| Windows | `npm run dist:win` | `KitchenRat-Windows.exe` (portable) and `KitchenRat-Setup.exe` (installer) |
| macOS | `npm run dist:mac` | `.dmg` |
| Linux | `npm run dist:linux` | `.AppImage` |

Build each platform on that platform (GitHub no longer builds the prototype).

### In a browser

Open `game/index.html` directly. Everything it needs is in `game/vendor/`, so it works offline.

## The nights

All 20 nights in four acts are playable. Graphics are still placeholders; real models come with the Godot version.

| Night | Room | Food | What's new |
|---|---|---|---|
| Prologue | The nest | | A stormy night, a nest behind the kitchen wall, four pups |
| 1 | The Kitchen | 15 | Nobody is home. 12 tasks teach everything: jumping, sneaking, hiding, sniffing, knocking things over. Traps: a mug on the table edge, crinkly foil |
| 2 | The Sleeping Cat | 12 | The cat sleeps by your hole. Its Zzz bar drains with noise. Traps: a plate that clinks, a sofa that scratches, a TV remote, a squeaky toy, a creaky floorboard |
| 3 | The Prowling Cat | 12 | The cat is awake. Listen for its bell, hide under the sofa and in cracks |
| 4 | The Pantry | 14 | Food is hidden: sniff it out. Gnaw open a grain sack, push a box off the stack. Cans that fall like dominoes, rustling bags |
| 5 | The Kitchen, Again | 16 | Knock things down to lure the cat away, then drag its sausage home. The fridge hum hides your steps |
| 6 | A Glass of Water | 14 | The owner comes down for water three times a night. Hide, then steal a cookie while he drinks |
| 7 | The Flashlight | 16 | Flashlight patrols through the pantry. Steal the spare battery and his flashlight starts dying |
| 8 | Dinner Leftovers | 16 | Paths inside the walls: hide in a crack, press Space to come out of another. Drag a chicken leg home |
| 9 | The Laundry Room | 16 | The cat eats, then naps. Start the washing machine to hide your steps |
| 10 | The Storm | 18 | Thunder hides every sound, lightning shows you. Then the power goes out |
| 11 | Mousetraps | 18 | Brave comes along (Q: wait/follow, R: fetch). Sniff out traps, drop things on them to spring them |
| 12 | Sticky Traps | 18 | Yellow tape holds you in place. Curious spots hidden things. Roll a potato home |
| 13 | The Kids’ Room | 18 | Don’t wake the kid. Squeaky toys, Lego, a music box, a night light. Shy freezes at loud noises but warns you of danger |
| 14 | The Party | 18 | Guests sleep over (snoring stops = waking up). Greedy runs for food. Steal the cake |
| 15 | Poison | 20 | Green scent means poison. Curious and Greedy both come along |
| 16 | The Robot Vacuum | 20 | It eats the crumbs and bumps into you. Drop things in its way, or sneak onto it and ride it. Brave and Shy come along |
| 17 | The Dog | 20 | It follows your scent for 30 seconds. Puddles and the litter box wash your trail away. A ball distracts it |
| 18 | The Basement | 22 | The cracks are sealed: find a way through the pipes. Cage traps guard the food |
| 19 | The Whole Floor | 24 | Dining room, living room and kitchen in one night. All four pups, every danger |
| 20 | Moving Out | | The finale: scout the way, spring the traps, lead all four pups out under the front door |

Tasks for the night show up one at a time in the bottom-left corner. Each night has three goals (for example "Don't wake the cat" or "Never get caught"). Finishing a
night unlocks the next one; progress and settings are saved automatically.

## Settings

Mouse sensitivity, invert Y, field of view, music and sound effect volume, graphics quality
(High: bloom and shadows, Medium: no bloom, Low: no post effects or shadows), and hints on/off.
Open them from the main menu or the pause menu.

## Controls

| Action | Key |
|---|---|
| Move | `WASD` / arrow keys |
| Camera | Mouse (click the game to capture the cursor) |
| Jump onto furniture | `Space` when the yellow ring shows |
| Sniff (find cheese, spot poison and traps) | `E` or right mouse button |
| Knock something off a table (distraction) | `F` |
| Run (loud) | `Shift` |
| Sneak (silent, slow) | hold `Ctrl` or press `C` |
| Pause / release the cursor | `Esc` |
| Fullscreen (desktop app) | `F11` |
| Developer tools (desktop app) | `Ctrl+Shift+I` |

## Project layout

```
game/            The game itself (three.js r128), runs offline
  index.html     Markup, styles and menus
  js/audio.js    Synthesized sound effects and adaptive music (Web Audio, no audio files)
  js/levels.js   The nights: furniture, food, cat, goals, palettes, music. Add a night here
  js/game.js     Room builder, rat, cat, owner, vacuum, wanted level, cutscenes, menus
  vendor/        three.js and fonts
electron/        Desktop shell: window, fullscreen, quit button bridge
build/icon.png   App icon (used by the window and the installers)
godot/           The Godot 4 game: all 20 nights, menus, sound and music, see godot/README.md
tools/blender/   Scripts that generate every model into godot/assets/models (Blender as a Python module)
tools/make_audio.py  Renders the sound effects and music for Godot
art/             Model previews and the list of models
docs/            Game design notes and roadmap
.github/         CI that builds the Godot game (and the demo) for Windows, macOS and Linux
```

The HTML version is where new gameplay ideas get tried first. Features that stick get ported to
Godot, which is the engine for the Steam release.

## Credits

- 3D engine: [three.js](https://threejs.org) r128 (MIT), in `game/vendor/three/`
- Fonts: Fredoka and Rubik (SIL Open Font License), in `game/vendor/fonts/`
