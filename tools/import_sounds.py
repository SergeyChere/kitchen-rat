#!/usr/bin/env python3
"""Import free (CC0) recorded sounds into the Godot project.

Takes recordings from the packs tools/fetch_sounds.sh downloads, trims silence, makes them mono, evens out their
level and writes godot/assets/sounds/real/<sound>_<n>.ogg. The game (sfx.gd) plays a recording when one exists for a
sound and falls back to the synthesized one (tools/make_audio.py) otherwise. Sources and licences:
godot/assets/sounds/real/CREDITS.md.

Run:  sh tools/fetch_sounds.sh /tmp/sounds && python3 tools/import_sounds.py /tmp/sounds
"""
import glob
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, 'godot', 'assets', 'sounds', 'real')
SR = 32000

KI = 'kenney-impact-sounds-for-godot/addons/kenney impact sounds/'
KU = 'kenney-interface-sounds/addons/kenney_interface_sounds/'
SK = 'sfx-kit/sounds/'
LV = 'lavenderdotpet_CC0-Public-Domain-Sounds/'

# game sound → recordings (glob patterns, relative to the download folder). Each match becomes a variant.
MAP = {
    'meow_q': [LV + 'Micro Pack - Cat Meows/Cat Meows - Tiny Tito.wav', LV + 'Micro Pack - Cat Meows/Cat Meows - Food Time 11.wav', LV + 'Micro Pack - Cat Meows/Cat Meows - Food Time 2.wav'],
    'meow': [LV + 'Micro Pack - Cat Meows/Cat Meows - Food Time %s.wav' % n for n in (7, 8, 16, 12, 4)],
    'meow_angry': [LV + 'Micro Pack - Cat Meows/Cat Meows - Trevor.wav', LV + 'Micro Pack - Cat Meows/Cat Meows - Food Time 13.wav', LV + 'Micro Pack - Cat Meows/Cat Meows - Food Time 10.wav'],
    'squeak': [LV + '80-CC0-creature-SFX/cute_%02d.ogg' % n for n in (4, 5, 6, 9)],
    'bark': [LV + '80-CC0-creature-SFX/barking_0*.ogg'],
    'snore': [LV + '80-CC0-creature-SFX/snore.ogg', LV + '80-CC0-creature-sfx-2/snore_02.ogg'],
    'gnaw': [LV + '80-CC0-creature-SFX/eat_0*.ogg'],
    'crunch': [LV + '80-CC0-creature-SFX/eat_02.ogg', LV + '80-CC0-creature-SFX/eat_04.ogg'],
    'crash': [LV + '100-CC0-SFX/glass_0*.ogg'],
    'clink': [KI + 'impact_glass_light_00*.ogg', KI + 'impact_plate_light_00*.ogg'],
    'bang': [KI + 'impact_metal_heavy_00*.ogg', KI + 'impact_tin_medium_00*.ogg'],
    'thud': [KI + 'impact_wood_heavy_00*.ogg', KI + 'impact_soft_heavy_00*.ogg'],
    'snap': [KI + 'impact_metal_light_00*.ogg'],
    'whack': [KI + 'impact_punch_heavy_00*.ogg'],
    'land': [KI + 'impact_soft_medium_00*.ogg'],
    'land_big': [KI + 'impact_soft_heavy_00*.ogg'],
    'step': [KI + 'footstep_carpet_00*.ogg'],
    'stomp': [KI + 'footstep_wood_00*.ogg'],
    'door': [LV + '100-CC0-SFX/door_01.ogg', LV + '100-CC0-SFX/door_02.ogg'],
    'light_switch': [LV + '100-CC0-SFX/switch_0*.ogg'],
    'crinkle': [LV + '100-CC0-SFX/paper_0*.ogg'],
    'creak': [LV + '100-CC0-wood-metal-SFX/wood_squeak_0*.ogg'],
    'splash': [LV + '100-CC0-SFX/splash_0*.ogg'],
    'thunder': [LV + '100-cc0-sfx-2/sfx100v2_thunder_01.ogg', SK + 'cinematic-hits/cinematic-thunder-big.wav'],
    'scratch': [SK + 'foley/foley-fabric-slide.wav'],
    'scrape': [SK + 'foley/foley-wood-slide.wav'],
    'jump': [SK + 'swishes-and-zips/swish-soft.wav'],
    'task': [SK + 'notifications/notification-success-chime.wav'],
    'fail': [SK + 'notifications/notification-failure-pluck.wav'],
    'click': [KU + 'click_00[1-3].wav'],
}
LOOPS = {'rain_loop': LV + '30-cc0-sfx-loops/rain.ogg'}

CREDITS = """# Recorded sounds

All recordings here are public domain (CC0 1.0): free to use in a commercial game, no credit required.
They were picked, trimmed and levelled by `tools/import_sounds.py`.

| Pack | Author | Licence | Used for |
|---|---|---|---|
| [Impact Sounds](https://kenney.nl/assets/impact-sounds) via [Boyquotes/kenney-impact-sounds-for-godot](https://github.com/Boyquotes/kenney-impact-sounds-for-godot) | Kenney | CC0 | footsteps, things falling, glass, plates, the trap, the slipper |
| [Interface Sounds](https://kenney.nl/assets/interface-sounds) via [Calinou/kenney-interface-sounds](https://github.com/Calinou/kenney-interface-sounds) | Kenney | CC0 | menu clicks |
| [sfx-kit](https://github.com/wyzowl/sfx-kit) | Wyzowl | CC0 | thunder, fabric and wood slides, swish, task chimes |
| Micro Pack: Cat Meows, via [lavenderdotpet/CC0-Public-Domain-Sounds](https://github.com/lavenderdotpet/CC0-Public-Domain-Sounds) | Benjamin Burnes (abstractionmusic.com) | CC0 | the cat |
| 80 CC0 creature SFX, 100 CC0 SFX, 100 CC0 wood & metal SFX, 100 CC0 SFX 2, 30 CC0 SFX loops, via the same collection | rubberduck (OpenGameArt) | CC0 | squeaks, barking, snoring, gnawing, glass breaking, doors, switches, paper, creaks, splashes, rain |
"""


def load(path):
    raw = subprocess.run(['ffmpeg', '-loglevel', 'error', '-i', path, '-ac', '1', '-ar', str(SR), '-f', 'f32le', '-'], capture_output=True, check=True).stdout
    return np.frombuffer(raw, '<f4').astype(np.float64)


def clean(x):
    a = np.abs(x)
    if a.max() <= 0:
        return x
    idx = np.nonzero(a > a.max() * 0.02)[0]
    x = x[max(0, idx[0] - int(0.005 * SR)):idx[-1] + int(0.05 * SR)].copy()
    x -= x.mean()
    fade = min(len(x) // 4, int(0.01 * SR))
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x / np.abs(x).max() * 0.8


def write_ogg(path, x):
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
        tmp = f.name
    with wave.open(tmp, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype('<i2').tobytes())
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', tmp, '-c:a', 'libvorbis', '-q:a', '4', path], check=True)
    os.remove(tmp)


def main(src):
    os.makedirs(OUT, exist_ok=True)
    for f in glob.glob(os.path.join(OUT, '*.ogg')):
        os.remove(f)
    total = 0
    for name, pats in MAP.items():
        files = []
        for p in pats:
            files += sorted(glob.glob(os.path.join(src, p)))
        if not files:
            print('missing:', name)
            continue
        for i, f in enumerate(files[:6]):
            write_ogg(os.path.join(OUT, '%s_%d.ogg' % (name, i)), clean(load(f)))
            total += 1
    for name, p in LOOPS.items():
        x = load(os.path.join(src, p))
        ov = int(0.3 * SR)
        n = len(x) - ov
        y = x[:n].copy()
        k = np.linspace(0, 1, ov)
        y[:ov] = y[:ov] * k + x[n:n + ov] * (1 - k)
        write_ogg(os.path.join(OUT, name + '_0.ogg'), y / np.abs(y).max() * 0.8)
        total += 1
    with open(os.path.join(OUT, 'CREDITS.md'), 'w') as f:
        f.write(CREDITS)
    print('imported', total, 'recordings into', os.path.relpath(OUT, REPO))


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '/tmp/kitchen-rat-sounds')
