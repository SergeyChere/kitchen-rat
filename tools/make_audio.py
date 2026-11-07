#!/usr/bin/env python3
"""Render Kitchen Rat's sounds and music for the Godot version.

The prototype (game/js/audio.js) synthesizes everything live with the Web Audio API. This script runs the same recipes
offline with numpy and writes:
  godot/assets/sounds/<name>.wav           one-shot effects (and two seamless loops: the vacuum hum and rain)
  godot/assets/music/<key>_<layer>.ogg     per-night music loops, one prog cycle (8 bars) long, three layers that
                                           play in sync: base (pads, bass, plucks), tension (the "wanted" ticking
                                           hats and pulsing bass) and chase (drums and arpeggio)
<key> is made from the night's music definition (godot/data/nights/*.json "music"), see music_key().

Run:  python3 tools/make_audio.py      (needs numpy, scipy and ffmpeg)
"""
import glob
import json
import os
import subprocess
import tempfile
import wave

import numpy as np
from scipy.signal import lfilter, lfilter_zi

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SND_DIR = os.path.join(REPO, 'godot', 'assets', 'sounds')
MUS_DIR = os.path.join(REPO, 'godot', 'assets', 'music')
SR = 32000
rng = np.random.default_rng(7)


# ---------- building blocks (audio.js: env, tone, noise) ----------

def env_curve(n, a, peak, d, sr):
    """Exponential attack from silence to peak over a seconds, then exponential decay over d."""
    t = np.arange(n) / sr
    peak = max(peak, 0.0002)
    out = np.empty(n)
    att = t < a
    out[att] = 0.0001 * (peak / 0.0001) ** (t[att] / max(a, 1e-6))
    dec = ~att
    out[dec] = peak * (0.0001 / peak) ** np.clip((t[dec] - a) / max(d, 1e-6), 0, 1)
    out[t > a + d] = 0.0
    return out


def freq_curve(n, f0, ramps, sr):
    """f0 then ramps: list of (time, value, 'exp'|'lin'), like AudioParam automation."""
    t = np.arange(n) / sr
    f = np.full(n, float(f0))
    t0, v0 = 0.0, float(f0)
    for (t1, v1, kind) in ramps:
        seg = (t >= t0) & (t < t1)
        k = (t[seg] - t0) / max(t1 - t0, 1e-6)
        f[seg] = v0 * (v1 / v0) ** k if kind == 'exp' else v0 + (v1 - v0) * k
        f[t >= t1] = v1
        t0, v0 = t1, v1
    return f


def osc(kind, f, sr):
    ph = np.cumsum(f / sr)
    ph -= np.floor(ph)
    if kind == 'sine':
        return np.sin(2 * np.pi * ph)
    if kind == 'square':
        return np.where(ph < 0.5, 1.0, -1.0) * 0.7
    if kind == 'sawtooth':
        return (2 * ph - 1) * 0.8
    return 1 - 4 * np.abs(ph - 0.5)  # triangle


def biquad(kind, f, q, sr):
    w = 2 * np.pi * min(f, sr * 0.45) / sr
    c, s = np.cos(w), np.sin(w)
    al = s / (2 * q)
    if kind == 'lowpass':
        b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
    elif kind == 'highpass':
        b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
    else:  # bandpass, constant 0 dB peak (Web Audio's bandpass)
        b = [al, 0, -al]
    a = [1 + al, -2 * c, 1 - al]
    return np.array(b) / a[0], np.array(a) / a[0]


def filt(x, kind, f, q, sr, f_curve=None):
    """Biquad filter; with f_curve (per-sample cutoff) it's updated every 64 samples."""
    if f_curve is None:
        b, a = biquad(kind, f, q, sr)
        return lfilter(b, a, x)
    out = np.empty_like(x)
    zi = None
    for i in range(0, len(x), 64):
        b, a = biquad(kind, float(f_curve[i]), q, sr)
        if zi is None:
            zi = lfilter_zi(b, a) * 0
        out[i:i + 64], zi = lfilter(b, a, x[i:i + 64], zi=zi)
    return out


class Mix:
    """A buffer you schedule voices into (dry and reverb send), then render with the room reverb."""

    def __init__(self, seconds, sr=SR):
        self.sr = sr
        self.dry = np.zeros(int(seconds * sr) + 1)
        self.send = np.zeros_like(self.dry)

    def add(self, sig, t, send=0.0, gain=1.0):
        i = int(t * self.sr)
        if i >= len(self.dry):
            return
        n = min(len(sig), len(self.dry) - i)
        self.dry[i:i + n] += sig[:n] * gain
        if send:
            self.send[i:i + n] += sig[:n] * gain * send

    def tone(self, kind, f, t, dur, peak, a=0.005, send=0.0, ramps=(), gain=1.0):
        n = int((a + dur + 0.05) * self.sr)
        fc = freq_curve(n, f, ramps, self.sr)
        sig = osc(kind, fc, self.sr) * env_curve(n, a, peak, dur, self.sr)
        self.add(sig, t, send, gain)

    def noise(self, t, dur, peak, kind, f, q=1.0, a=0.002, send=0.0, ramps=(), gain=1.0):
        n = int((a + dur + 0.05) * self.sr)
        x = rng.uniform(-1, 1, n)
        fc = freq_curve(n, f, ramps, self.sr) if ramps else None
        sig = filt(x, kind, f, q, self.sr, fc) * env_curve(n, a, peak, dur, self.sr)
        self.add(sig, t, send, gain)

    def render(self, wet=0.3, ir_len=2.2, wrap=False):
        """Dry + reverb. wrap: the buffer is a loop, so tails past the end come back in at the start."""
        ir = reverb_ir(ir_len, self.sr)
        verb = fft_conv(self.send, ir) * wet
        out = np.zeros(len(self.dry) + len(ir))
        out[:len(self.dry)] += self.dry
        out[:len(verb)] += verb[:len(out)]
        if wrap:
            n = len(self.dry) - 1
            loop = out[:n].copy()
            tail = out[n:]
            for k in range(0, len(tail), n):
                seg = tail[k:k + n]
                loop[:len(seg)] += seg
            return loop
        return out


_irs = {}


def reverb_ir(seconds, sr):
    key = (seconds, sr)
    if key not in _irs:
        n = int(sr * seconds)
        i = np.arange(n)
        _irs[key] = np.random.default_rng(3).uniform(-1, 1, n) * (1 - i / n) ** 2.8 * 0.06
    return _irs[key]


def fft_conv(x, h):
    n = len(x) + len(h) - 1
    m = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(h, m), m)[:n]


def trim(x, sr, floor=0.0008):
    idx = np.nonzero(np.abs(x) > floor)[0]
    end = (idx[-1] + int(0.02 * sr)) if len(idx) else int(0.05 * sr)
    x = x[:min(end, len(x))].copy()
    fade = min(len(x), int(0.01 * sr))
    x[-fade:] *= np.linspace(1, 0, fade)
    return x


def write_wav(path, x, sr):
    pcm = (np.clip(x, -1, 1) * 32767).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def write_ogg(path, x, sr):
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
        tmp = f.name
    write_wav(tmp, x, sr)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', tmp, '-c:a', 'libvorbis', '-q:a', '2', path], check=True)
    os.remove(tmp)


# ---------- sound effects (audio.js fx) ----------

FX = {}


def fx(name, seconds=1.5):
    def deco(fn):
        FX[name] = (fn, seconds)
        return fn
    return deco


def squeak(m, t, pitch=1.0, vol=0.18):
    m.tone('sine', 2100 * pitch, t, 0.16, vol, 0.01, 0.2, [(0.05, 3200 * pitch, 'exp'), (0.15, 2400 * pitch, 'exp')])


def thud(m, t):
    m.tone('sine', 160, t, 0.3, 0.35, ramps=[(0.25, 55, 'exp')])
    m.noise(t, 0.12, 0.15, 'lowpass', 500)


def meow(m, kind):
    angry, q = kind == 'angry', kind == 'q'
    dur = 0.7 if angry else (0.45 if q else 0.55)
    base = 300 if angry else 440
    n = int((dur + 0.1) * m.sr)
    f = freq_curve(n, base * 0.8, [(dur * 0.4, base * (1.5 if q else 1.25), 'lin'), (dur, base * (1.75 if q else 0.85), 'lin')], m.sr)
    x = osc('sawtooth', f, m.sr)
    fc = freq_curve(n, 700, [(dur * 0.35, 1700, 'lin'), (dur, 900, 'lin')], m.sr)
    sig = filt(x, 'bandpass', 700, 4, m.sr, fc) * env_curve(n, 0.05, 0.4 if angry else 0.25, dur, m.sr) * 3.0
    m.add(sig, 0, 0.25)


fx('click', 0.3)(lambda m: m.tone('sine', 1300, 0, 0.04, 0.08))
fx('squeak', 0.6)(lambda m: squeak(m, 0))
fx('meow', 1.0)(lambda m: meow(m, ''))
fx('meow_q', 1.0)(lambda m: meow(m, 'q'))
fx('meow_angry', 1.2)(lambda m: meow(m, 'angry'))
fx('purr', 1.4)(lambda m: m.noise(0, 0.9, 0.2, 'lowpass', 180, 1, 0.2))
fx('snore', 1.8)(lambda m: (m.noise(0, 1.1, 0.25, 'lowpass', 260, 2, 0.35), m.tone('sawtooth', 70, 0, 1.0, 0.05, 0.3, ramps=[(0.5, 95, 'lin'), (1.0, 60, 'lin')])))


@fx('pickup', 0.6)
def _(m):
    m.tone('sine', 988, 0, 0.12, 0.12, 0.005, 0.2)
    m.tone('sine', 1319, 0.07, 0.2, 0.1, 0.005, 0.25)


@fx('cheese', 0.9)
def _(m):
    for i, f in enumerate([784, 988, 1175, 1568]):
        m.tone('triangle', f, i * 0.06, 0.25, 0.1, 0.005, 0.3)


@fx('deliver', 1.4)
def _(m):
    for i, f in enumerate([523, 659, 784, 1047]):
        m.tone('triangle', f, i * 0.08, 0.4, 0.11, 0.01, 0.35)
    squeak(m, 0.25, 1.35, 0.12)
    squeak(m, 0.37, 1.5, 0.1)


@fx('poison', 1.0)
def _(m):
    for i, f in enumerate([392, 370, 311]):
        m.tone('square', f, i * 0.12, 0.25, 0.05)


fx('jump', 0.4)(lambda m: m.noise(0, 0.16, 0.07, 'bandpass', 600, 2, ramps=[(0.15, 2600, 'exp')]))
fx('land', 0.3)(lambda m: m.tone('sine', 200, 0, 0.07, 0.08, ramps=[(0.12, 60, 'exp')]))
fx('land_big', 0.4)(lambda m: m.tone('sine', 150, 0, 0.16, 0.25, ramps=[(0.12, 60, 'exp')]))


@fx('sniff', 0.6)
def _(m):
    for i in range(3):
        m.noise(i * 0.13, 0.06, 0.08, 'highpass', 2500, 0.7, 0.01)


for k in range(3):
    fx('step%d' % k, 0.15)(lambda m: m.noise(0, 0.025, 0.06, 'bandpass', 3000 + rng.uniform(-400, 400), 1.5))


@fx('clink', 1.0)
def _(m):
    m.noise(0, 0.03, 0.2, 'highpass', 4000)
    for i, f in enumerate([1870, 2730, 3910, 5200]):
        m.tone('sine', f, 0, 0.5 - i * 0.08, 0.08, 0.002, 0.4)


@fx('crash', 1.2)
def _(m):
    m.noise(0, 0.5, 0.35, 'highpass', 2500, 0.5, 0.002, 0.4)
    for f in [2100, 3300, 4700]:
        m.tone('sine', f * rng.uniform(0.9, 1.1), 0, 0.4, 0.05)


fx('thud', 0.6)(lambda m: thud(m, 0))


@fx('bang', 1.0)
def _(m):
    thud(m, 0)
    m.noise(0, 0.4, 0.25, 'bandpass', 900, 0.8, 0.002, 0.3)


@fx('snap', 0.6)
def _(m):
    m.noise(0, 0.06, 0.6, 'highpass', 2000)
    m.tone('square', 1400, 0, 0.03, 0.2)
    thud(m, 0)


@fx('whack', 0.5)
def _(m):
    m.noise(0, 0.18, 0.6, 'lowpass', 1400)
    m.tone('sine', 130, 0, 0.2, 0.4, ramps=[(0.18, 55, 'exp')])


@fx('stomp', 0.4)
def _(m):
    m.tone('sine', 85, 0, 0.2, 0.3, ramps=[(0.18, 40, 'exp')])
    m.noise(0, 0.08, 0.12, 'lowpass', 300)


@fx('door', 1.3)
def _(m):
    n = int(1.1 * m.sr)
    f = freq_curve(n, 70, [(0.4, 110, 'lin'), (0.9, 80, 'lin')], m.sr)
    sig = filt(osc('sawtooth', f, m.sr), 'bandpass', 900, 9, m.sr) * env_curve(n, 0.1, 0.18, 0.85, m.sr) * 6.0
    m.add(sig, 0, 0.2)


@fx('light_switch', 0.2)
def _(m):
    m.noise(0, 0.015, 0.3, 'highpass', 3000)
    m.noise(0.05, 0.015, 0.2, 'highpass', 3000)


@fx('beep', 0.6)
def _(m):
    m.tone('square', 1760, 0, 0.08, 0.08)
    m.tone('square', 1760, 0.15, 0.08, 0.08)
    m.tone('square', 2350, 0.3, 0.12, 0.08)


@fx('star_up', 1.0)
def _(m):
    m.tone('sawtooth', 880, 0, 0.16, 0.12)
    m.tone('sawtooth', 622, 0.17, 0.3, 0.12)
    m.tone('sine', 70, 0, 0.6, 0.35, ramps=[(0.5, 40, 'exp')])


@fx('caught', 1.0)
def _(m):
    m.tone('triangle', 420, 0, 0.7, 0.2, ramps=[(0.65, 90, 'exp')])
    m.noise(0, 0.3, 0.15, 'lowpass', 700)


@fx('win', 2.0)
def _(m):
    for i, f in enumerate([523, 659, 784, 1047, 1319]):
        m.tone('triangle', f, i * 0.13, 0.7, 0.12, 0.01, 0.45)


@fx('lose', 2.0)
def _(m):
    for i, f in enumerate([440, 415, 392, 330]):
        m.tone('triangle', f, i * 0.22, 0.6, 0.12, 0.01, 0.4)


@fx('task', 1.0)
def _(m):
    for i, f in enumerate([659, 880, 1319]):
        m.tone('sine', f, i * 0.09, 0.35, 0.09, 0.005, 0.3)


@fx('fail', 0.7)
def _(m):
    m.tone('triangle', 330, 0, 0.25, 0.08)
    m.tone('triangle', 262, 0.12, 0.3, 0.08)


for k in range(2):
    @fx('crinkle%d' % k, 0.4)
    def _(m):
        for i in range(6):
            m.noise(i * 0.035 + rng.uniform(0, 0.02), 0.03, 0.12, 'highpass', 3000 + rng.uniform(0, 3000), 0.8)

    @fx('crunch%d' % k, 0.4)
    def _(m):
        for i in range(4):
            m.noise(i * 0.04 + rng.uniform(0, 0.02), 0.03, 0.12, 'bandpass', 1800, 1.2)

    @fx('gnaw%d' % k, 0.4)
    def _(m):
        for i in range(3):
            m.noise(i * 0.07, 0.05, 0.16, 'bandpass', 2800, 1.5)


@fx('musicbox', 2.6)
def _(m):
    for i, f in enumerate([1047, 1047, 1568, 1568, 1760, 1760, 1568]):
        m.tone('sine', f, i * 0.28, 0.3, 0.06, 0.005, 0.25)


@fx('scratch', 0.5)
def _(m):
    for i in range(5):
        m.noise(i * 0.05, 0.04, 0.14, 'bandpass', 2400 + i * 300, 2)


fx('squeaky', 0.5)(lambda m: m.tone('square', 1400, 0, 0.22, 0.09, ramps=[(0.08, 2300, 'exp'), (0.2, 1100, 'exp')]))
fx('creak', 0.7)(lambda m: m.tone('sawtooth', 140, 0, 0.45, 0.07, 0.05, ramps=[(0.2, 210, 'lin'), (0.42, 120, 'lin')]))


@fx('splash', 0.6)
def _(m):
    m.noise(0, 0.25, 0.18, 'bandpass', 1200, 0.7)
    m.noise(0.05, 0.15, 0.08, 'highpass', 3500)


@fx('tv', 2.0)
def _(m):
    m.noise(0, 1.6, 0.22, 'bandpass', 2000, 0.4)
    m.tone('square', 520, 0.1, 1.2, 0.05)
    m.tone('square', 660, 0.4, 1.0, 0.04)


@fx('buzz', 0.8)
def _(m):
    m.tone('sawtooth', 100, 0, 0.5, 0.06)
    m.noise(0, 0.4, 0.05, 'bandpass', 900, 3)


@fx('bell', 0.6)
def _(m):
    for i, f in enumerate([2637, 3520]):
        m.tone('sine', f, i * 0.03, 0.25, 0.05, 0.002, 0.2)


fx('scrape', 0.5)(lambda m: m.noise(0, 0.3, 0.08, 'bandpass', 700, 0.8))
for k in range(3):
    fx('crackle%d' % k, 0.1)(lambda m: m.noise(0, 0.03, 0.05, 'highpass', 1800 + rng.uniform(0, 2000)))


@fx('bark', 0.8)
def _(m):
    for j in range(2):
        t = j * 0.28
        n = int(0.2 * m.sr)
        f = freq_curve(n, 380, [(0.04, 520, 'exp'), (0.18, 260, 'exp')], m.sr)
        sig = filt(osc('sawtooth', f, m.sr), 'bandpass', 900, 2, m.sr) * env_curve(n, 0.01, 0.5, 0.15, m.sr)
        m.add(sig, t, 0.25)
        m.noise(t, 0.08, 0.15, 'bandpass', 1400, 1)


@fx('thunder', 3.5)
def _(m):
    m.noise(0, 2.6, 0.5, 'lowpass', 220, 0.8, 0.02, 0.5)
    m.noise(0.05, 0.4, 0.3, 'lowpass', 900, 0.7, 0.002, 0.4)
    m.tone('sine', 55, 0, 1.4, 0.3, 0.05, ramps=[(1.3, 35, 'exp')])


def make_loop(seconds, gen):
    """A seamless loop: render a bit longer and crossfade the overhang into the start."""
    n = int(seconds * SR)
    ov = int(0.25 * SR)
    x = gen(n + ov)
    out = x[:n].copy()
    k = np.linspace(0, 1, ov)
    out[:ov] = out[:ov] * k + x[n:n + ov] * (1 - k)
    return out


def hum_loop(n):
    # the robot vacuum: band-passed noise plus a 118 Hz triangle (2 s holds whole cycles)
    t = np.arange(n) / SR
    return filt(rng.uniform(-1, 1, n), 'bandpass', 340, 2, SR) * 0.9 + osc('triangle', np.full(n, 118.0), SR) * 0.3 * 0.5


def rain_loop(n):
    x = rng.uniform(-1, 1, n)
    soft = filt(x, 'lowpass', 1800, 0.7, SR) * 0.5
    drops = np.zeros(n)
    for i in rng.integers(0, n, n // 300):
        drops[i] = rng.uniform(0.2, 0.7)
    drops = filt(drops, 'bandpass', 3500, 1.5, SR)
    return soft + drops * 0.8


def render_fx():
    os.makedirs(SND_DIR, exist_ok=True)
    for f in glob.glob(os.path.join(SND_DIR, '*.wav')):
        os.remove(f)
    gain = 1.6
    for name, (fn, secs) in FX.items():
        m = Mix(secs + 0.2)
        fn(m)
        x = trim(m.render(0.3), SR, 0.0008 * max(1e-6, np.abs(m.dry).max()) / 0.2)
        x = np.tanh(x * gain)
        write_wav(os.path.join(SND_DIR, name + '.wav'), x / max(1e-6, np.abs(x).max()) * 0.8, SR)  # loudness is set in sfx.gd
    for name, x in (('hum_loop', make_loop(2.0, hum_loop)), ('rain_loop', make_loop(4.0, rain_loop))):
        write_wav(os.path.join(SND_DIR, name + '.wav'), x / np.abs(x).max() * 0.8, SR)
    print('sounds:', len(FX) + 2, 'files in', os.path.relpath(SND_DIR, REPO))


# ---------- music (audio.js Music) ----------

MSR = 32000


def midi(n):
    return 440 * 2 ** ((n - 69) / 12)


def music_key(d):
    prog = ''.join('%+d%s' % (o, q) for o, q in d['prog'])
    return 'r%d%s%d_%s' % (d['root'], 'm' if d['minor'] else 'M', d['bpm'], prog.replace('+', 'p').replace('-', 'n'))


def render_music(d, menu=False):
    """Three layers, each exactly one prog cycle (4 chords × 2 bars = 8 bars) so they loop together."""
    spb = 60 / d['bpm'] / 4
    steps = 16 * 2 * len(d['prog'])
    secs = steps * spb
    base, tens, chase = Mix(secs, MSR), Mix(secs, MSR), Mix(secs, MSR)
    delay = Mix(secs, MSR)
    r = np.random.default_rng(d['root'] * 100 + d['bpm'])
    scale = [0, 3, 5, 7, 10] if d['minor'] else [0, 2, 4, 7, 9]

    def chord(s):
        return d['prog'][(s // 16 // 2) % len(d['prog'])]

    def pad(f, t, dur):
        n = int((dur + 0.6) * MSR)
        tt = np.arange(n) / MSR
        g = np.interp(tt, [0, 1.6, dur - 1.2, dur + 0.4], [0.0001, 0.035, 0.035, 0.0001])
        x = osc('triangle', np.full(n, f), MSR) + osc('sawtooth', np.full(n, f * 2 ** (7 / 1200)), MSR)
        base.add(filt(x, 'lowpass', 900, 0.7, MSR) * g, t, 0.4)

    def pluck(m, f, t, peak, to_delay=True):
        n = int(0.6 * MSR)
        sig = osc('triangle', np.full(n, f), MSR) * env_curve(n, 0.004, peak, 0.55, MSR)
        m.add(sig, t, 0.4)
        if to_delay:
            delay.add(sig, t)

    def hat(m, t, peak):
        n = int(0.06 * MSR)
        m.add(filt(r.uniform(-1, 1, n), 'highpass', 7000, 0.7, MSR) * env_curve(n, 0.001, peak, 0.035, MSR), t, 0.4)

    for s in range(steps):
        t = s * spb
        off, q = chord(s)
        root = d['root'] + off
        third, fifth, top = root + (3 if q == 'm' else 4), root + 7, root + (10 if q == 'm' else 11)
        in_bar, first_bar = s % 16, (s // 16) % 2 == 0
        if in_bar == 0 and first_bar:
            for nn in (root, third, fifth, top):
                pad(midi(nn), t, spb * 32)
        if not menu and in_bar in (0, 10):
            n = int(0.8 * MSR)
            base.add(osc('sine', np.full(n, midi(root - 12)), MSR) * env_curve(n, 0.01, 0.12, 0.7, MSR), t, 0.4)
        if in_bar % 2 == 0 and r.random() < (0.28 if menu else 0.36):
            deg = scale[r.integers(len(scale))] + (24 if r.random() < 0.3 else 12)
            pluck(base, midi(d['root'] + deg), t, 0.06 if menu else 0.07)
        if menu:
            continue
        # the wanted layer
        hat(tens, t, 0.035 if in_bar % 4 == 0 else 0.018)
        if in_bar % 2 == 0:
            dur = spb * 1.6
            n = int((dur + 0.05) * MSR)
            fc = freq_curve(n, 700, [(dur, 180, 'exp')], MSR)
            tens.add(filt(osc('sawtooth', np.full(n, midi(root - 12)), MSR), 'lowpass', 700, 0.7, MSR, fc) * env_curve(n, 0.005, 0.07, dur, MSR), t, 0.4)
        # the chase layer
        if in_bar in (0, 8, 11):
            chase.tone('sine', 140, t, 0.25, 0.45, 0.002, 0.4, [(0.2, 42, 'exp')])
        if in_bar in (4, 12):
            chase.noise(t, 0.14, 0.22, 'bandpass', 1900, 0.7, 0.001, 0.4)
            chase.tone('sine', 190, t, 0.08, 0.12, 0.001, 0.4)
        hat(chase, t, 0.03)
        if in_bar % 2 == 1:
            pluck(chase, midi(root + 12 + [0, 7, 12, 7][(in_bar >> 1) % 4]), t, 0.05, False)

    # the feedback delay on the plucks: 0.75 beat, feedback 0.33, out 0.5 (wrapped around the loop)
    dl = int(60 / d['bpm'] * 0.75 * MSR)
    src = delay.dry
    echo = np.zeros_like(src)
    tap = src.copy()
    for k in range(1, 8):
        tap = np.roll(tap, dl) * (0.33 if k > 1 else 1.0)
        echo += tap
    base.dry += echo * 0.5
    base.send += echo * 0.5 * 0.4
    return [m.render(0.3, 2.2, wrap=True) for m in (base, tens, chase)]


def render_all_music():
    os.makedirs(MUS_DIR, exist_ok=True)
    for f in glob.glob(os.path.join(MUS_DIR, '*.ogg')):
        os.remove(f)
    defs = {}
    for f in sorted(glob.glob(os.path.join(REPO, 'godot', 'data', 'nights', '*.json'))):
        d = json.load(open(f))['music']
        defs[music_key(d)] = (d, False)
    menu = json.load(open(os.path.join(REPO, 'godot', 'data', 'menu_music.json')))
    gain = 2.2
    for key, (d, _) in defs.items():
        for name, x in zip(('base', 'tension', 'chase'), render_music(d)):
            write_ogg(os.path.join(MUS_DIR, '%s_%s.ogg' % (key, name)), np.tanh(x * gain) * 0.5, MSR)
    base, _, _ = render_music(menu, menu=True)
    write_ogg(os.path.join(MUS_DIR, 'menu.ogg'), np.tanh(base * gain) * 0.5, MSR)
    print('music:', len(defs), 'night themes + menu in', os.path.relpath(MUS_DIR, REPO))


if __name__ == '__main__':
    render_fx()
    render_all_music()
