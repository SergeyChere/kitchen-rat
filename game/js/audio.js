// Kitchen Rat — sound.
// Everything is synthesized with the Web Audio API: no audio files, no licensing questions.
//   Snd    sound effects (Snd.fx.meow(), Snd.fx.snap(), ...)
//   Music  generative score per night. Music.set(tension, chase) blends in the
//          "wanted" layer (ticking hats, pulsing bass) and the chase drums.
(function () {
  'use strict';
  let ctx = null, master, musicBus, sfxBus, verbIn, noiseBuf, vols = { music: 0.7, sfx: 0.8 };

  function init() {
    if (ctx) { if (ctx.state === 'suspended') ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    ctx = new AC();
    master = ctx.createGain(); master.connect(ctx.destination);
    const comp = ctx.createDynamicsCompressor(); comp.threshold.value = -14; comp.ratio.value = 3;
    master.disconnect(); master.connect(comp); comp.connect(ctx.destination);
    musicBus = ctx.createGain(); musicBus.connect(master);
    sfxBus = ctx.createGain(); sfxBus.connect(master);
    // small room reverb from a decaying noise impulse
    const len = Math.floor(ctx.sampleRate * 2.2), ir = ctx.createBuffer(2, len, ctx.sampleRate);
    for (let c = 0; c < 2; c++) { const d = ir.getChannelData(c); for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 2.8); }
    const conv = ctx.createConvolver(); conv.buffer = ir;
    verbIn = ctx.createGain(); const wet = ctx.createGain(); wet.gain.value = 0.3;
    verbIn.connect(conv); conv.connect(wet); wet.connect(master);
    noiseBuf = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate);
    const nd = noiseBuf.getChannelData(0); for (let i = 0; i < nd.length; i++) nd[i] = Math.random() * 2 - 1;
    applyVolumes();
  }
  function setVolumes(music, sfx) { vols = { music, sfx }; applyVolumes(); }
  function applyVolumes() {
    if (!ctx) return;
    musicBus.gain.setTargetAtTime(Math.pow(vols.music, 1.6) * 0.6, ctx.currentTime, 0.05);
    sfxBus.gain.setTargetAtTime(Math.pow(vols.sfx, 1.4) * 0.9, ctx.currentTime, 0.05);
  }

  // ---------- building blocks ----------
  function env(g, t, a, peak, d) {
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(Math.max(peak, 0.0002), t + a);
    g.gain.exponentialRampToValueAtTime(0.0001, t + a + d);
  }
  function tone(type, f, t, dur, peak, dest, a, send) {
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.type = type; o.frequency.setValueAtTime(f, t);
    env(g, t, a || 0.005, peak, dur);
    o.connect(g); g.connect(dest || sfxBus);
    if (send) { const s = ctx.createGain(); s.gain.value = send; g.connect(s); s.connect(verbIn); }
    o.start(t); o.stop(t + (a || 0.005) + dur + 0.05);
    return o;
  }
  function noise(t, dur, peak, ftype, f, q, dest, a, send) {
    const s = ctx.createBufferSource(); s.buffer = noiseBuf;
    const fl = ctx.createBiquadFilter(); fl.type = ftype; fl.frequency.setValueAtTime(f, t); fl.Q.value = q || 1;
    const g = ctx.createGain(); env(g, t, a || 0.002, peak, dur);
    s.connect(fl); fl.connect(g); g.connect(dest || sfxBus);
    if (send) { const sg = ctx.createGain(); sg.gain.value = send; g.connect(sg); sg.connect(verbIn); }
    s.start(t, Math.random() * 1.5); s.stop(t + (a || 0.002) + dur + 0.05);
    return fl;
  }
  const ok = () => !!ctx && ctx.state !== 'closed';
  const now = () => ctx.currentTime;

  // ---------- sound effects ----------
  const fx = {
    click() { if (!ok()) return; tone('sine', 1300, now(), 0.04, 0.08); },
    squeak(pitch = 1, vol = 0.18) {
      if (!ok()) return; const t = now();
      const o = tone('sine', 2100 * pitch, t, 0.16, vol, null, 0.01, 0.2);
      o.frequency.exponentialRampToValueAtTime(3200 * pitch, t + 0.05);
      o.frequency.exponentialRampToValueAtTime(2400 * pitch, t + 0.15);
    },
    meow(kind) {
      if (!ok()) return; const t = now();
      const angry = kind === 'angry', q = kind === 'q', dur = angry ? 0.7 : q ? 0.45 : 0.55, base = angry ? 300 : 440;
      const o = ctx.createOscillator(); o.type = 'sawtooth';
      o.frequency.setValueAtTime(base * 0.8, t);
      o.frequency.linearRampToValueAtTime(base * (q ? 1.5 : 1.25), t + dur * 0.4);
      o.frequency.linearRampToValueAtTime(base * (q ? 1.75 : 0.85), t + dur);
      const bp = ctx.createBiquadFilter(); bp.type = 'bandpass'; bp.Q.value = 4;
      bp.frequency.setValueAtTime(700, t); bp.frequency.linearRampToValueAtTime(1700, t + dur * 0.35); bp.frequency.linearRampToValueAtTime(900, t + dur);
      const g = ctx.createGain(); env(g, t, 0.05, angry ? 0.4 : 0.25, dur);
      o.connect(bp); bp.connect(g); g.connect(sfxBus);
      const s = ctx.createGain(); s.gain.value = 0.25; g.connect(s); s.connect(verbIn);
      o.start(t); o.stop(t + dur + 0.1);
    },
    purr(vol = 0.06) { if (!ok()) return; const t = now(); noise(t, 0.9, vol, 'lowpass', 180, 1, null, 0.2); },
    pickup() { if (!ok()) return; const t = now(); tone('sine', 988, t, 0.12, 0.12, null, 0.005, 0.2); tone('sine', 1319, t + 0.07, 0.2, 0.1, null, 0.005, 0.25); },
    cheese() { if (!ok()) return; const t = now(); [784, 988, 1175, 1568].forEach((f, i) => tone('triangle', f, t + i * 0.06, 0.25, 0.1, null, 0.005, 0.3)); },
    deliver() {
      if (!ok()) return; const t = now();
      [523, 659, 784, 1047].forEach((f, i) => tone('triangle', f, t + i * 0.08, 0.4, 0.11, null, 0.01, 0.35));
      setTimeout(() => { fx.squeak(1.35, 0.12); setTimeout(() => fx.squeak(1.5, 0.1), 120); }, 250);
    },
    poison() { if (!ok()) return; const t = now(); [392, 370, 311].forEach((f, i) => tone('square', f, t + i * 0.12, 0.25, 0.05)); },
    jump() { if (!ok()) return; const t = now(); const fl = noise(t, 0.16, 0.07, 'bandpass', 600, 2); fl.frequency.exponentialRampToValueAtTime(2600, t + 0.15); },
    land(big) { if (!ok()) return; const t = now(); const o = tone('sine', big ? 150 : 200, t, big ? 0.16 : 0.07, big ? 0.25 : 0.08); o.frequency.exponentialRampToValueAtTime(60, t + 0.12); },
    sniff() { if (!ok()) return; const t = now(); for (let i = 0; i < 3; i++) noise(t + i * 0.13, 0.06, 0.08, 'highpass', 2500, 0.7, null, 0.01); },
    step(vol = 0.04) { if (!ok()) return; noise(now(), 0.025, vol, 'bandpass', 3200, 1.5); },
    clink() { if (!ok()) return; const t = now(); noise(t, 0.03, 0.2, 'highpass', 4000); [1870, 2730, 3910, 5200].forEach((f, i) => tone('sine', f, t, 0.5 - i * 0.08, 0.08, null, 0.002, 0.4)); },
    crash() { if (!ok()) return; const t = now(); noise(t, 0.5, 0.35, 'highpass', 2500, 0.5, null, 0.002, 0.4); [2100, 3300, 4700].forEach(f => tone('sine', f * (0.9 + Math.random() * 0.2), t, 0.4, 0.05)); },
    thud() { if (!ok()) return; const t = now(); const o = tone('sine', 160, t, 0.3, 0.35); o.frequency.exponentialRampToValueAtTime(55, t + 0.25); noise(t, 0.12, 0.15, 'lowpass', 500); },
    bang() { fx.thud(); if (!ok()) return; noise(now(), 0.4, 0.25, 'bandpass', 900, 0.8, null, 0.002, 0.3); },
    snap() { if (!ok()) return; const t = now(); noise(t, 0.06, 0.6, 'highpass', 2000); tone('square', 1400, t, 0.03, 0.2); fx.thud(); },
    whack() { if (!ok()) return; const t = now(); noise(t, 0.18, 0.6, 'lowpass', 1400); const o = tone('sine', 130, t, 0.2, 0.4); o.frequency.exponentialRampToValueAtTime(55, t + 0.18); },
    stomp(vol = 0.3) { if (!ok() || vol < 0.02) return; const t = now(); const o = tone('sine', 85, t, 0.2, vol); o.frequency.exponentialRampToValueAtTime(40, t + 0.18); noise(t, 0.08, vol * 0.4, 'lowpass', 300); },
    door() { if (!ok()) return; const t = now(); const o = ctx.createOscillator(); o.type = 'sawtooth'; o.frequency.setValueAtTime(70, t); o.frequency.linearRampToValueAtTime(110, t + 0.4); o.frequency.linearRampToValueAtTime(80, t + 0.9);
      const bp = ctx.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = 900; bp.Q.value = 9; const g = ctx.createGain(); env(g, t, 0.1, 0.18, 0.85); o.connect(bp); bp.connect(g); g.connect(sfxBus); o.start(t); o.stop(t + 1.1); },
    lightSwitch() { if (!ok()) return; const t = now(); noise(t, 0.015, 0.3, 'highpass', 3000); noise(t + 0.05, 0.015, 0.2, 'highpass', 3000); },
    beep() { if (!ok()) return; const t = now(); tone('square', 1760, t, 0.08, 0.08); tone('square', 1760, t + 0.15, 0.08, 0.08); tone('square', 2350, t + 0.3, 0.12, 0.08); },
    starUp(level) {
      if (!ok()) return; const t = now();
      const o1 = tone('sawtooth', 880, t, 0.16, 0.12); const o2 = tone('sawtooth', 622, t + 0.17, 0.3, 0.12);
      [o1, o2].forEach(o => o.detune.setValueAtTime(level * 30, t));
      const b = tone('sine', 70, t, 0.6, 0.35); b.frequency.exponentialRampToValueAtTime(40, t + 0.5);
    },
    caught() { if (!ok()) return; const t = now(); const o = tone('triangle', 420, t, 0.7, 0.2); o.frequency.exponentialRampToValueAtTime(90, t + 0.65); noise(t, 0.3, 0.15, 'lowpass', 700); },
    win() { if (!ok()) return; const t = now(); [523, 659, 784, 1047, 1319].forEach((f, i) => tone('triangle', f, t + i * 0.13, 0.7, 0.12, null, 0.01, 0.45)); },
    lose() { if (!ok()) return; const t = now(); [440, 415, 392, 330].forEach((f, i) => tone('triangle', f, t + i * 0.22, 0.6, 0.12, null, 0.01, 0.4)); },
    crackle(vol = 0.05) { if (!ok() || vol < 0.01) return; noise(now(), 0.03, vol, 'highpass', 1800 + Math.random() * 2000); },
  };

  // looping hum for the robot vacuum
  let humNodes = null;
  function hum(vol) {
    if (!ok()) return;
    if (!humNodes) {
      const s = ctx.createBufferSource(); s.buffer = noiseBuf; s.loop = true;
      const bp = ctx.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = 340; bp.Q.value = 2;
      const o = ctx.createOscillator(); o.type = 'triangle'; o.frequency.value = 118;
      const og = ctx.createGain(); og.gain.value = 0.3;
      const g = ctx.createGain(); g.gain.value = 0;
      s.connect(bp); bp.connect(g); o.connect(og); og.connect(g); g.connect(sfxBus);
      s.start(); o.start(); humNodes = { g };
    }
    humNodes.g.gain.setTargetAtTime(vol, ctx.currentTime, 0.15);
  }

  // ---------- music ----------
  const Music = (() => {
    let def = null, timer = null, step = 0, nextT = 0, mode = 'off';
    let mg, tg, cg, dly, dfb, menuDuck = 1;
    const midi = n => 440 * Math.pow(2, (n - 69) / 12);
    function setup() {
      mg = ctx.createGain(); mg.gain.value = 0; mg.connect(musicBus);
      const send = ctx.createGain(); send.gain.value = 0.4; mg.connect(send); send.connect(verbIn);
      tg = ctx.createGain(); tg.gain.value = 0; tg.connect(mg);
      cg = ctx.createGain(); cg.gain.value = 0; cg.connect(mg);
      dly = ctx.createDelay(1.5); dfb = ctx.createGain(); dfb.gain.value = 0.33;
      dly.connect(dfb); dfb.connect(dly); const dOut = ctx.createGain(); dOut.gain.value = 0.5; dly.connect(dOut); dOut.connect(mg);
    }
    function play(d, calm) {
      init(); if (!ok()) return;
      if (!mg) setup();
      def = d; mode = calm ? 'menu' : 'game';
      dly.delayTime.setValueAtTime(60 / d.bpm * 0.75, ctx.currentTime);
      mg.gain.cancelScheduledValues(ctx.currentTime);
      mg.gain.setTargetAtTime(calm ? 0.8 : 1, ctx.currentTime, 0.8);
      set(0, 0);
      if (!timer) { step = 0; nextT = ctx.currentTime + 0.1; timer = setInterval(tick, 40); }
    }
    function stop() { if (mg && ok()) mg.gain.setTargetAtTime(0, ctx.currentTime, 0.4); }
    function duck(on) { if (mg && ok()) mg.gain.setTargetAtTime(on ? 0.35 : (mode === 'menu' ? 0.8 : 1), ctx.currentTime, 0.2); }
    let lastT = -1, lastC = null;
    function set(tension, chase) {
      if (!tg || !ok()) return;
      tension = Math.round(Math.min(1, tension) * 20) / 20;
      if (tension === lastT && chase === lastC) return; lastT = tension; lastC = chase;
      tg.gain.setTargetAtTime(Math.min(1, tension) * 0.9, ctx.currentTime, 0.6);
      cg.gain.setTargetAtTime(chase ? 1 : 0, ctx.currentTime, chase ? 0.15 : 1.2);
    }
    function tick() {
      if (!ok() || !def) return;
      const spb = 60 / def.bpm / 4;
      while (nextT < ctx.currentTime + 0.2) { sched(step, nextT, spb); step++; nextT += spb; }
    }
    function chord(s) { const bar = Math.floor(s / 16); return def.prog[Math.floor(bar / 2) % def.prog.length]; }
    function sched(s, t, spb) {
      const [off, q] = chord(s), root = def.root + off;
      const third = root + (q === 'm' ? 3 : 4), fifth = root + 7, top = root + (q === 'm' ? 10 : 11);
      const inBar = s % 16, firstBar = Math.floor(s / 16) % 2 === 0;
      if (inBar === 0 && firstBar) [root, third, fifth, top].forEach(n => pad(midi(n), t, spb * 32));
      if (mode === 'game' && (inBar === 0 || inBar === 10)) bass(midi(root - 12), t);
      const scale = def.minor ? [0, 3, 5, 7, 10] : [0, 2, 4, 7, 9];
      if (inBar % 2 === 0 && Math.random() < (mode === 'menu' ? 0.28 : 0.36)) {
        const deg = scale[Math.floor(Math.random() * scale.length)] + (Math.random() < 0.3 ? 24 : 12);
        pluck(midi(def.root + deg), t, mode === 'menu' ? 0.06 : 0.07);
      }
      // wanted layer
      hat(t, inBar % 4 === 0 ? 0.035 : 0.018, tg);
      if (inBar % 2 === 0) pulse(midi(root - 12), t, spb * 1.6);
      // chase layer
      if (inBar === 0 || inBar === 8 || inBar === 11) kick(t);
      if (inBar === 4 || inBar === 12) snare(t);
      hat(t, 0.03, cg);
      if (inBar % 2 === 1) pluck(midi(root + 12 + [0, 7, 12, 7][(inBar >> 1) % 4]), t, 0.05, cg);
    }
    function pad(f, t, dur) {
      const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 900;
      const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(0.035, t + 1.6); g.gain.setValueAtTime(0.035, t + dur - 1.2); g.gain.linearRampToValueAtTime(0.0001, t + dur + 0.4);
      lp.connect(g); g.connect(mg);
      [['triangle', 0], ['sawtooth', 7]].forEach(([ty, det]) => { const o = ctx.createOscillator(); o.type = ty; o.frequency.value = f; o.detune.value = det; o.connect(lp); o.start(t); o.stop(t + dur + 0.5); });
    }
    function pluck(f, t, peak, dest) {
      const o = ctx.createOscillator(), g = ctx.createGain(); o.type = 'triangle'; o.frequency.value = f;
      env(g, t, 0.004, peak, 0.55); o.connect(g); g.connect(dest || mg); if (!dest) g.connect(dly);
      o.start(t); o.stop(t + 0.65);
    }
    function bass(f, t) { const o = ctx.createOscillator(), g = ctx.createGain(); o.type = 'sine'; o.frequency.value = f; env(g, t, 0.01, 0.12, 0.7); o.connect(g); g.connect(mg); o.start(t); o.stop(t + 0.8); }
    function hat(t, peak, dest) {
      const s = ctx.createBufferSource(); s.buffer = noiseBuf; const hp = ctx.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 7000;
      const g = ctx.createGain(); env(g, t, 0.001, peak, 0.035); s.connect(hp); hp.connect(g); g.connect(dest); s.start(t, Math.random()); s.stop(t + 0.06);
    }
    function pulse(f, t, dur) {
      const o = ctx.createOscillator(), lp = ctx.createBiquadFilter(), g = ctx.createGain(); o.type = 'sawtooth'; o.frequency.value = f;
      lp.type = 'lowpass'; lp.frequency.setValueAtTime(700, t); lp.frequency.exponentialRampToValueAtTime(180, t + dur);
      env(g, t, 0.005, 0.07, dur); o.connect(lp); lp.connect(g); g.connect(tg); o.start(t); o.stop(t + dur + 0.05);
    }
    function kick(t) { const o = ctx.createOscillator(), g = ctx.createGain(); o.frequency.setValueAtTime(140, t); o.frequency.exponentialRampToValueAtTime(42, t + 0.2); env(g, t, 0.002, 0.45, 0.25); o.connect(g); g.connect(cg); o.start(t); o.stop(t + 0.3); }
    function snare(t) {
      const s = ctx.createBufferSource(); s.buffer = noiseBuf; const bp = ctx.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = 1900; bp.Q.value = 0.7;
      const g = ctx.createGain(); env(g, t, 0.001, 0.22, 0.14); s.connect(bp); bp.connect(g); g.connect(cg); s.start(t, Math.random()); s.stop(t + 0.2);
      const o = ctx.createOscillator(), og = ctx.createGain(); o.frequency.value = 190; env(og, t, 0.001, 0.12, 0.08); o.connect(og); og.connect(cg); o.start(t); o.stop(t + 0.12);
    }
    return { play, stop, set, duck };
  })();

  window.Snd = { init, setVolumes, fx, hum, ready: ok };
  window.Music = Music;
})();
