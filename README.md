# Kitchen Rat

A stealth game about a mother rat who sneaks into a human kitchen at night to feed her hungry pups.
Every theft leaves evidence, and the house fights back GTA-style: the more you steal, the higher your
wanted level, from a wary cat to mousetraps, the owner with a flashlight, and poisoned cheese.

![icon](build/icon.png)

## Play it

### On your computer (desktop app)

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
| Windows | `npm run dist:win` | `KitchenRat-Setup-x.y.z.exe` and a portable `.exe` |
| macOS | `npm run dist:mac` | `.dmg` |
| Linux | `npm run dist:linux` | `.AppImage` |

Build each platform on that platform. You can also let GitHub do it: every push to `main` runs the
**Build desktop app** workflow, and its run page has the Windows, macOS and Linux builds as downloads.
Pushing a tag like `v0.1.0` also attaches them to a GitHub Release.

### In a browser

Open `game/index.html` directly. Everything it needs is in `game/vendor/`, so it works offline.

## Controls

| Action | Key |
|---|---|
| Move | `WASD` / arrow keys |
| Camera | Mouse (click the game to capture the cursor) |
| Jump onto furniture | `Space` when the yellow ring shows |
| Sniff (find cheese, spot poison and traps) | `E` or right mouse button |
| Knock something off a table (distraction) | `F` |
| Run (noisy) | `Shift` |
| Pause / release the cursor | `Esc` |
| Fullscreen (desktop app) | `F11` |
| Developer tools (desktop app) | `Ctrl+Shift+I` |

## Project layout

```
game/            The game itself: one HTML file (three.js r128) plus vendored libraries and fonts
  index.html
  vendor/
electron/        Desktop shell: window, fullscreen, quit button bridge
build/icon.png   App icon (used by the window and the installers)
unity/           Unity port in progress (C#). Behind the HTML version, see unity/README.md
docs/            Game design notes and roadmap
.github/         CI that builds the desktop app for Windows, macOS and Linux
```

The HTML version is where new gameplay ideas get tried first. Features that stick get ported to
Unity, which is the long-term engine for the Steam release.

## Быстрый старт (RU)

1. Установи [Node.js](https://nodejs.org) 20+.
2. `npm install`, затем `npm start`: игра откроется в отдельном окне.
3. Установщик для Windows: `npm run dist:win` (на Windows), файл появится в папке `dist/`.
   Или открой вкладку **Actions** на GitHub, выбери последний запуск **Build desktop app** и скачай готовый `.exe`.

## Credits

- 3D engine: [three.js](https://threejs.org) r128 (MIT), in `game/vendor/three/`
- Fonts: Fredoka and Rubik (SIL Open Font License), in `game/vendor/fonts/`
