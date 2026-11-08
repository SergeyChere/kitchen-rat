# Third-party code and assets

## GDQuest — Godot 4 3D third-person controller (code, MIT)

https://github.com/gdquest-demos/godot-4-3d-third-person-controller

Ideas and small pieces of code are ported into `godot/scripts/rat.gd` (velocity easing toward the wanted velocity,
dead stop under a small speed, turning toward the last clear input direction, a higher jump while the button is
held, the nudge off walls when stuck, walk/run picked by actual speed) and `godot/scripts/follow_camera.gd` (the
camera follows the ground height, eased, instead of the jumping body). None of GDQuest's art is used (their art is
CC-BY-NC-SA and not for commercial use).

MIT License

Copyright (c) 2023-present GDQuest

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of
the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Models and sounds

CC0 (public domain): see `art/library/README.md` and `godot/assets/sounds/real/CREDITS.md`.

## Kenney Starter Kit 3D Platformer (MIT)
https://github.com/KenneyNL/Starter-Kit-3D-Platformer — squash & stretch on jump/landing and dust particles
(rat.gd) follow its player script. Copyright (c) 2023 Kenney. MIT License. No art from the kit is used.

## Godot TPS demo (MIT code)
https://github.com/godotengine/tps-demo — turning on the spot, rate-limited turning and speed-matched walk/run
for the cat, owner and dog (agent.gd) follow its player/robot scripts. Copyright (c) Godot Engine contributors.
MIT License. None of its models, textures or sounds (CC-BY 3.0) are used.
