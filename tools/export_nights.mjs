// Export the 20 nights from game/js/levels.js to JSON files the Unity version reads
// (godot/data/nights/NN_id.json, and unity/Assets/Resources/Nights for the Unity version). Run after changing levels.js:  node tools/export_nights.mjs
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ctx = { window: {}, Math };
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(root, 'game/js/levels.js'), 'utf8'), ctx);
const LEVELS = ctx.window.LEVELS;
const outs = [path.join(root, 'godot/data/nights'), path.join(root, 'unity/Assets/Resources/Nights')];
for (const out of outs) {
  fs.mkdirSync(out, { recursive: true });
  for (const f of fs.readdirSync(out)) if (f.endsWith('.json')) fs.rmSync(path.join(out, f));
}
const out = outs[0];

const pair = v => (Array.isArray(v) ? [v[0], v[1]] : []);
const task = t => ({
  text: t.text, hint: t.hint || '', type: t.check[0], arg: t.check[1] == null ? '' : String(t.check[1]),
  n: typeof t.check[2] === 'number' ? t.check[2] : 0, reveal: t.reveal == null ? -1 : t.reveal,
});
const pick = (o, keys) => { const r = {}; for (const k of keys) if (o[k] !== undefined) r[k] = o[k]; return r; };

const index = [];
LEVELS.forEach((d, i) => {
  const open = !!d.openFood, f = d.food || {};
  const n = {
    number: i + 1, id: d.id, name: d.name, act: d.act, goal: d.goal, seconds: d.night,
    prologue: !!d.prologue, finale: !!d.finale,
    cat: d.cat || (d.threats.includes('cat') ? 'sleep' : 'away'),
    catSense: d.catSense || 1, sleepSense: d.sleepSense || 1, catBell: !!d.catBell, eatTime: d.eatTime || 40,
    catStart: pair(d.catStart), catBed: pair(d.catBed), bowl: pair(d.bowl), dock: pair(d.dock), exit: pair(d.exit),
    wanted: !!(d.wanted || d.threats.length), threats: d.threats, starTip: d.starTip || '',
    openFood: open, tvOff: !!d.tvOff, storm: !!d.storm, blackout: d.blackout || 0,
    pups: d.pups || [], pupAge: d.pupAge || 0, vacuumStart: !!d.vacuumStart, poisonStart: d.poisonStart || 0,
    door: d.door, lamp: d.lamp || '', decor: d.decor || '',
    window: d.window ? { x: d.window.x || 0, w: d.window.w || 0, y: d.window.y || 0, h: d.window.h || 0 } : { x: 0, w: 0, y: 0, h: 0 },
    teaser: d.teaser || '', blurb: d.blurb || '',
    startTitle: d.start ? d.start.title : '', startSub: d.start ? d.start.sub : '',
    introMom: d.intro ? d.intro.mom || '' : '', introPups: d.intro ? d.intro.pups || [] : [],
    pal: pick(d.pal, ['fog', 'sky', 'ground', 'hemi', 'moon', 'floor', 'floorA', 'floorB', 'wall', 'wallA', 'wallB', 'trim', 'ceil']),
    food: {
      spots: (f.spots || []).map(([type, x, y, o = {}]) => ({ type, x, y, tag: o.tag || '', hidden: !!o.hidden, floor: !!o.floor })),
      randomCrumb: f.random ? f.random.crumb : open ? 12 : 4, randomCheese: f.random ? f.random.cheese : open ? 4 : 3,
      refill: f.refill != null ? f.refill : open ? 10 : 5,
    },
    tasks: d.tasks ? {
      goal: d.tasks.goal, chain: d.tasks.chain.map(task), side: d.tasks.side.map(task), secret: (d.tasks.secret || []).map(task),
    } : { goal: 'Fill the nest', chain: [], side: [], secret: [] },
    owner: d.owner ? {
      type: d.owner.type, at: d.owner.at, stand: pair(d.owner.stand), face: d.owner.face || 0, stay: d.owner.stay || 14,
      light: d.owner.light !== false, route: (d.owner.route || []).map(([x, y]) => ({ x, y })),
    } : { type: '', at: [], stand: [], face: 0, stay: 0, light: true, route: [] },
    furn: d.furn.map(o => pick(o, ['t', 'x', 'y', 'w', 'h', 'ht', 'join', 'cloth', 'plate', 'back', 'face', 'color', 'dryer', 'dining'])),
    props: (d.props || []).map(o => pick(o, ['t', 'x', 'y', 'w', 'h', 'kind', 'r', 'surf', 'spawn', 'floor'])),
    knocks: (d.knocks || []).map(k => ({ kind: k.kind, x: k.x, y: k.y, toX: k.to[0], toY: k.to[1], trap: !!k.trap, group: k.group || '', spawn: k.spawn || '' })),
    cracks: (d.cracks || []).map(c => ({ wall: c.wall, x: c.x || 0, y: c.y || 0 })),
    secrets: (d.secrets || []).map(s => ({ kind: s.kind, x: s.x, y: s.y, floor: !!s.floor, always: !!s.always, label: s.label || '' })),
    trapSpots: (d.trapSpots || []).map(([x, y, o = {}]) => ({ x, y, hidden: !!o.hidden })),
    lights: (d.lights || []).map(l => pick(l, ['x', 'y', 'h', 'c', 'i', 'r'])),
    sleepers: (d.sleepers || []).map(s => pick(s, ['kind', 'x', 'y', 'bedH', 'face', 'sense'])),
    dog: d.dog ? [d.dog.x, d.dog.y] : [],
    zones: (d.zones || []).map(z => pick(z, ['id', 'x', 'y', 'w', 'h'])),
    tunnels: (d.tunnels || []).map(([a, b]) => ({ a, b })),
  };
  const file = String(i + 1).padStart(2, '0') + '_' + d.id + '.json';
  for (const o of outs) fs.writeFileSync(path.join(o, file), JSON.stringify(n, null, 1));
  index.push(file.replace('.json', ''));
});
for (const o of outs) fs.writeFileSync(path.join(o, 'index.txt'), index.join('\n') + '\n');
console.log('exported', index.length, 'nights to', path.relative(root, out));
