// Kitchen Rat — game.
// Sections: storage · utils · renderer · materials · permanent scene (nest, characters)
//           · level builder · navigation · state · input · menus · cutscenes · gameplay · render · loop
(function () {
'use strict';
const $ = id => document.getElementById(id);
const DESKTOP = !!(window.kitchenRat && window.kitchenRat.desktop);
if (DESKTOP) document.documentElement.classList.add('desktop');
if (!window.THREE) { $('mainTag').textContent = 'Could not load the 3D engine. Reload the page.'; return; }

// ================= STORAGE =================
const store = {
  get(k, d) { try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : d; } catch (e) { return d; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* storage unavailable */ } },
};
const DEFAULT_SETTINGS = { sens: 1, invertY: false, fov: 62, music: 70, sfx: 80, quality: 'high', hints: true };
const settings = Object.assign({}, DEFAULT_SETTINGS, store.get('kr_settings', {}));
let progress = Object.assign({ unlocked: 1, best: {} }, store.get('kr_progress', {}));
const saveSettings = () => store.set('kr_settings', settings);
const saveProgress = () => store.set('kr_progress', progress);

// ================= UTILS =================
const W = 960, H = 600, CELL = 20, GW = W / CELL, GH = H / CELL;
const STAR_AT = [10, 24, 40, 58, 80];
const hole = { x: 46, y: 574, r: 26 };
const nest = { x: 10, z: 612, w: 240, d: 170, cx: 120, cz: 705 };
const R = (x, y, w, h) => ({ x, y, w, h });
const inRect = (x, y, r, m = 0) => x > r.x - m && x < r.x + r.w + m && y > r.y - m && y < r.y + r.h + m;
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const lerp = (a, b, t) => a + (b - a) * t, clamp01 = t => clamp(t, 0, 1), ease = t => t * t * (3 - 2 * t);
const angDiff = (a, b) => { let d = b - a; while (d > Math.PI) d -= 2 * Math.PI; while (d < -Math.PI) d += 2 * Math.PI; return d; };
const center = o => [o.x + o.w / 2, o.y + o.h / 2];
const starStr = n => '★'.repeat(n) + '☆'.repeat(Math.max(0, 5 - n));
const hexRgb = h => { const n = parseInt(h.slice(1), 16); return [n >> 16 & 255, n >> 8 & 255, n & 255]; };
const rgbStr = (c, v = 0) => 'rgb(' + c.map(x => clamp(Math.round(x + v), 0, 255)).join(',') + ')';

// ================= RENDERER =================
const view = $('view'), stage = $('stage');
const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
view.appendChild(renderer.domElement);
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x0e1220);
scene.fog = new THREE.Fog(0x0e1220, 380, 1350);
const camera = new THREE.PerspectiveCamera(settings.fov, 1, 1, 3000);
let composer = null, bloomPass = null;
try {
  if (THREE.EffectComposer && THREE.UnrealBloomPass && THREE.ShaderPass) {
    composer = new THREE.EffectComposer(renderer);
    composer.addPass(new THREE.RenderPass(scene, camera));
    bloomPass = new THREE.UnrealBloomPass(new THREE.Vector2(512, 512), 0.45, 0.45, 0.86);
    composer.addPass(bloomPass);
    const grade = new THREE.ShaderPass({
      uniforms: { tDiffuse: { value: null }, uTime: { value: 0 } },
      vertexShader: 'varying vec2 vUv;void main(){vUv=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}',
      fragmentShader: 'uniform sampler2D tDiffuse;uniform float uTime;varying vec2 vUv;float h(vec2 p){return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);}' +
        'void main(){vec3 c=texture2D(tDiffuse,vUv).rgb;float l=dot(c,vec3(.299,.587,.114));' +
        'c=mix(c*vec3(.9,.97,1.14),c*vec3(1.07,1.01,.9),smoothstep(.2,.8,l));c=(c-.5)*1.07+.52;' +
        'vec2 d=vUv-.5;c*=clamp(1.-dot(d,d)*1.3,0.,1.);c+=(h(vUv*vec2(1733.,977.)+fract(uTime))-.5)*.03;gl_FragColor=vec4(c,1.);}',
    });
    composer.addPass(grade); composer.grade = grade;
  }
} catch (e) { composer = null; }
let useComposer = !!composer;

// ================= MATERIALS & HELPERS =================
const gradTex = (() => { const d = new Uint8Array([90, 90, 90, 255, 165, 165, 165, 255, 255, 255, 255, 255]); const t = new THREE.DataTexture(d, 3, 1, THREE.RGBAFormat); t.minFilter = t.magFilter = THREE.NearestFilter; t.needsUpdate = true; return t; })();
const T = (c, o = {}) => new THREE.MeshToonMaterial(Object.assign({ color: c, gradientMap: gradTex }, o));
const TF = (c, o = {}) => T(c, Object.assign({ transparent: true }, o)); // fadeable
const outlineMat = new THREE.MeshBasicMaterial({ color: 0x0b0a12, side: THREE.BackSide });
function outline(mesh, t = 1.3) {
  mesh.geometry.computeBoundingBox(); const s = new THREE.Vector3(); mesh.geometry.boundingBox.getSize(s);
  const sx = Math.abs(s.x * mesh.scale.x), sy = Math.abs(s.y * mesh.scale.y), sz = Math.abs(s.z * mesh.scale.z);
  const k = (v) => v < 0.01 ? 1 : (v + 2 * t) / v;
  const o = new THREE.Mesh(mesh.geometry, outlineMat); o.scale.set(k(sx), k(sy), k(sz)); o.userData.isOutline = true;
  mesh.add(o); return mesh;
}
function canvasTex(w, h, draw, rep) { const c = document.createElement('canvas'); c.width = w; c.height = h; draw(c.getContext('2d'), w, h); const t = new THREE.CanvasTexture(c); if (rep) { t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(rep[0], rep[1]); } return t; }
const glowTex = canvasTex(64, 64, (g, w, h) => { const r = g.createRadialGradient(32, 32, 0, 32, 32, 32); r.addColorStop(0, 'rgba(255,255,255,1)'); r.addColorStop(0.4, 'rgba(255,255,255,.5)'); r.addColorStop(1, 'rgba(255,255,255,0)'); g.fillStyle = r; g.fillRect(0, 0, w, h); });
const hideTex = canvasTex(128, 128, (g, w, h) => { g.fillStyle = 'rgba(255,255,255,.16)'; g.beginPath(); g.roundRect(10, 10, w - 20, h - 20, 18); g.fill(); g.setLineDash([12, 8]); g.lineWidth = 6; g.strokeStyle = 'rgba(255,255,255,.95)'; g.beginPath(); g.roundRect(10, 10, w - 20, h - 20, 18); g.stroke(); });
const softRect = canvasTex(128, 128, (g, w, h) => { g.filter = 'blur(14px)'; g.fillStyle = '#000'; g.fillRect(26, 26, w - 52, h - 52); });
const skyTex = canvasTex(256, 128, (g, w, h) => {
  const gr = g.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, '#1b2a52'); gr.addColorStop(1, '#3e5a8f'); g.fillStyle = gr; g.fillRect(0, 0, w, h);
  g.fillStyle = '#fff'; for (let i = 0; i < 40; i++) { g.globalAlpha = Math.random() * 0.8 + 0.2; g.fillRect(Math.random() * w, Math.random() * h * 0.8, 1.5, 1.5); } g.globalAlpha = 1;
  g.fillStyle = '#f4f1e1'; g.beginPath(); g.arc(190, 40, 18, 0, 7); g.fill(); g.fillStyle = 'rgba(244,241,225,.15)'; g.beginPath(); g.arc(190, 40, 30, 0, 7); g.fill();
});
const wood = T(0x8a5f3c), darkWood = T(0x63412a);

let PARENT = scene, camBlock = [], fadeables = [];
const add = m => { PARENT.add(m); return m; };
function box(w, h, d, mat, x, y, z, o = {}) {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat); m.position.set(x, y, z);
  m.castShadow = o.cast !== false; m.receiveShadow = true; add(m);
  if (o.block !== false) camBlock.push(m);
  if (o.line !== false) outline(m, o.t || 1.5);
  return m;
}
function cyl(r, h, mat, x, y, z, o = {}) {
  const m = new THREE.Mesh(new THREE.CylinderGeometry(o.r2 != null ? o.r2 : r, r, h, o.seg || 12), mat);
  m.position.set(x, y, z); m.castShadow = true; add(m);
  if (o.line !== false) outline(m, o.t || 1);
  return m;
}
function sprite(color, size, x, y, z, op = 0.8) {
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTex, color, transparent: true, opacity: op, depthWrite: false, blending: THREE.AdditiveBlending }));
  s.scale.set(size, size, 1); s.position.set(x, y, z); add(s); return s;
}

// ================= PERMANENT LIGHTS =================
const hemi = new THREE.HemisphereLight(0x7d8fc4, 0x2a2430, 0.75); scene.add(hemi);
const moon = new THREE.DirectionalLight(0xb4c4ee, 0.85);
moon.position.set(520, 360, -320); moon.target.position.set(520, 0, 330);
moon.castShadow = true; moon.shadow.mapSize.set(2048, 2048);
Object.assign(moon.shadow.camera, { left: -700, right: 700, top: 700, bottom: -700, near: 10, far: 1800 });
moon.shadow.bias = -0.0008; scene.add(moon, moon.target);
const holeLight = new THREE.PointLight(0xf2c14e, 0.7, 110, 2); holeLight.position.set(hole.x, 18, hole.y - 10); scene.add(holeLight);
const nestLight = new THREE.PointLight(0xffb070, 1.3, 300, 1.6); nestLight.position.set(nest.cx + 20, 45, nest.cz); scene.add(nestLight);
const roomLight = new THREE.PointLight(0xffe0b0, 0, 1000, 1.1); roomLight.position.set(480, 205, 300); scene.add(roomLight);
const hallLight = new THREE.PointLight(0xffc890, 0, 260, 1.5); scene.add(hallLight);
const lampBulbMat = new THREE.MeshBasicMaterial({ color: 0x4a4436 });

// ================= NEST (same every night) =================
{
  const hm = new THREE.Mesh(new THREE.CircleGeometry(20, 24, 0, Math.PI), new THREE.MeshBasicMaterial({ color: 0x050506 })); hm.position.set(hole.x, 0.2, H - 0.5); hm.rotation.y = Math.PI; scene.add(hm);
  const hm2 = new THREE.Mesh(new THREE.CircleGeometry(20, 24, 0, Math.PI), new THREE.MeshBasicMaterial({ color: 0x050506 })); hm2.position.set(hole.x, 0.2, H + 10.5); scene.add(hm2);
  const ring = new THREE.Mesh(new THREE.RingGeometry(hole.r + 3, hole.r + 6, 40), new THREE.MeshBasicMaterial({ color: 0xf2c14e, transparent: true, opacity: 0.5 })); ring.rotation.x = -Math.PI / 2; ring.position.set(hole.x, 0.4, hole.y); scene.add(ring);
  const earth = T(0x4a3326), soil = T(0x5c4130);
  const nf = new THREE.Mesh(new THREE.PlaneGeometry(nest.w, nest.d), soil); nf.rotation.x = -Math.PI / 2; nf.position.set(nest.x + nest.w / 2, 0, nest.z + nest.d / 2); nf.receiveShadow = true; scene.add(nf);
  box(nest.w + 20, 90, 10, earth, nest.x + nest.w / 2, 45, nest.z + nest.d + 5, { line: false });
  box(10, 90, nest.d, earth, nest.x - 5, 45, nest.z + nest.d / 2, { line: false });
  box(10, 90, nest.d, earth, nest.x + nest.w + 5, 45, nest.z + nest.d / 2, { line: false });
  box(nest.w + 20, 10, nest.d + 10, earth, nest.x + nest.w / 2, 95, nest.z + nest.d / 2, { line: false });
  const paper = [0xe6dcc8, 0xd2c4a8, 0xf0e8d6, 0xa9bfd6];
  for (let i = 0; i < 26; i++) {
    const a = Math.random() * Math.PI * 2, r = 20 + Math.random() * 34;
    const p = new THREE.Mesh(new THREE.BoxGeometry(10 + Math.random() * 12, 1.2, 3 + Math.random() * 3), T(paper[i % 4]));
    p.position.set(nest.cx + Math.cos(a) * r, 1 + Math.random() * 3, nest.cz + Math.sin(a) * r * 0.75); p.rotation.set(Math.random() * 0.4, Math.random() * 6, Math.random() * 0.4); p.receiveShadow = true; scene.add(p);
  }
  const bed = new THREE.Mesh(new THREE.SphereGeometry(1, 20, 12), T(0x9a7a60)); bed.scale.set(46, 5, 36); bed.position.set(nest.cx, 0, nest.cz); bed.receiveShadow = true; scene.add(bed);
  const sock = cyl(7, 40, T(0x6a82b6), nest.cx + 75, 7, nest.cz + 40); sock.rotation.z = Math.PI / 2; sock.rotation.y = 0.6;
  cyl(6, 4, T(0xc4483a), nest.cx - 80, 2, nest.cz + 30); cyl(5, 2, T(0xe6c06a), nest.cx + 60, 1, nest.cz - 45);
}
camBlock = [];

// ================= CHARACTERS =================
function makeRodent(furCol, s) {
  const g = new THREE.Group(), fur = T(furCol), belly = T(new THREE.Color(furCol).lerp(new THREE.Color(0xf1e4da), 0.55)), pink = T(0xd9999a);
  const body = new THREE.Mesh(new THREE.SphereGeometry(1, 18, 14), fur); body.scale.set(11 * s, 6.5 * s, 7 * s); body.position.y = 7 * s; body.castShadow = true; g.add(body); outline(body, 1.1 * s);
  const bel = new THREE.Mesh(new THREE.SphereGeometry(1, 14, 10), belly); bel.scale.set(0.8, 0.62, 0.8); bel.position.set(0.12, -0.38, 0); body.add(bel);
  const headG = new THREE.Group(); headG.position.set(10 * s, 8 * s, 0); g.add(headG);
  const head = new THREE.Mesh(new THREE.SphereGeometry(1, 16, 12), fur); head.scale.set(7 * s, 4.6 * s, 4.6 * s); head.castShadow = true; headG.add(head); outline(head, 1 * s);
  const cheek = new THREE.Mesh(new THREE.SphereGeometry(1, 12, 8), belly); cheek.scale.set(4 * s, 2.6 * s, 3.6 * s); cheek.position.set(3 * s, -1.6 * s, 0); headG.add(cheek);
  const eyes = [];
  [-1, 1].forEach(k => {
    const e = new THREE.Mesh(new THREE.SphereGeometry(1, 12, 8), pink); e.scale.set(1 * s, 3.4 * s, 3.4 * s); e.position.set(-3 * s, 4.2 * s, k * 4 * s); e.rotation.x = k * 0.25; headG.add(e); outline(e, 0.6 * s);
    const inner = new THREE.Mesh(new THREE.SphereGeometry(1, 10, 6), T(0xf2b9bd)); inner.scale.set(0.5, 0.7, 0.7); inner.position.x = 0.5; e.add(inner);
    const eye = new THREE.Mesh(new THREE.SphereGeometry(1.15 * s, 10, 8), new THREE.MeshBasicMaterial({ color: 0x0a0a0a })); eye.position.set(3 * s, 1.6 * s, k * 2.7 * s); headG.add(eye); eyes.push(eye);
    const hl = new THREE.Mesh(new THREE.SphereGeometry(0.38, 6, 4), new THREE.MeshBasicMaterial({ color: 0xffffff })); hl.position.set(0.7, 0.45, k * -0.2); eye.add(hl);
  });
  const nose = new THREE.Mesh(new THREE.SphereGeometry(1.4 * s, 8, 6), T(0xf09aa8)); nose.position.set(7 * s, 0, 0); headG.add(nose);
  { const pts = []; [-1, 1].forEach(k => { for (let i = 0; i < 3; i++) pts.push(6 * s, -0.2 * s, k * 1.4 * s, 10.5 * s, (-0.9 + i * 0.9) * s, k * (5.5 + i * 0.4) * s); });
    const wg = new THREE.BufferGeometry(); wg.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3)); headG.add(new THREE.LineSegments(wg, new THREE.LineBasicMaterial({ color: 0xe9e2da, transparent: true, opacity: 0.8 }))); }
  const feet = []; [[5, 4.5], [5, -4.5], [-5, 5], [-5, -5]].forEach(([x, z]) => { const f = new THREE.Mesh(new THREE.SphereGeometry(1, 8, 6), pink); f.scale.set(2.2 * s, 1.1 * s, 1.6 * s); f.position.set(x * s, 1 * s, z * s); f.userData.by = 1 * s; g.add(f); feet.push(f); });
  const tailPivot = new THREE.Group(); tailPivot.position.set(-10 * s, 5 * s, 0); g.add(tailPivot);
  const tail = []; let par = tailPivot; const L5 = 5.2 * s;
  for (let i = 0; i < 5; i++) {
    const r0 = (1.6 - i * 0.25) * s, r1 = (1.6 - (i + 1) * 0.25) * s;
    const seg = new THREE.Mesh(new THREE.CylinderGeometry(r0, r1, L5 * 1.25, 8), pink); seg.rotation.z = Math.PI / 2; seg.position.x = -L5 / 2; par.add(seg);
    const nx = new THREE.Group(); nx.position.x = -L5; nx.rotation.z = 0.07; par.add(nx); tail.push(nx); par = nx;
  }
  const mouth = new THREE.Group(); mouth.position.set(18 * s, 6 * s, 0); g.add(mouth);
  g.userData = { tailPivot, tail, mouth, body, headG, eyes, feet, s }; scene.add(g); return g;
}
function wagTail(u, ph, amp) { u.tailPivot.rotation.y = Math.sin(ph) * amp * 0.6; u.tail.forEach((t, i) => t.rotation.y = Math.sin(ph - (i + 1) * 0.8) * amp * 0.45); }
function makeCat() {
  const g = new THREE.Group(), orange = T(0xe8913f), stripe = T(0xb8682a), cream = T(0xf3dcc0);
  const bodyG = new THREE.Group(); g.add(bodyG);
  const body = new THREE.Mesh(new THREE.SphereGeometry(1, 18, 14), orange); body.scale.set(24, 13, 13); body.position.y = 22; body.castShadow = true; bodyG.add(body); outline(body, 1.6);
  [-10, 0, 10].forEach(x => { const s = new THREE.Mesh(new THREE.TorusGeometry(12.6, 1.5, 6, 20, Math.PI), stripe); s.position.set(x, 24, 0); s.rotation.y = Math.PI / 2; bodyG.add(s); });
  const chest = new THREE.Mesh(new THREE.SphereGeometry(1, 14, 10), cream); chest.scale.set(9, 9, 9.5); chest.position.set(16, 19, 0); bodyG.add(chest);
  const headG = new THREE.Group(); headG.position.set(24, 32, 0); bodyG.add(headG);
  const head = new THREE.Mesh(new THREE.SphereGeometry(10, 16, 12), orange); head.castShadow = true; headG.add(head); outline(head, 1.4);
  const muzzle = new THREE.Mesh(new THREE.SphereGeometry(5, 12, 8), cream); muzzle.scale.set(1, 0.8, 1.3); muzzle.position.set(7, -3, 0); headG.add(muzzle);
  const cnose = new THREE.Mesh(new THREE.SphereGeometry(1.8, 8, 6), T(0xe88a9a)); cnose.position.set(11.6, -1, 0); headG.add(cnose);
  { const pts = []; [-1, 1].forEach(k => { for (let i = 0; i < 3; i++) pts.push(10, -3, k * 3, 15, -4.5 + i * 1.6, k * (12 + i)); }); const wg = new THREE.BufferGeometry(); wg.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3)); headG.add(new THREE.LineSegments(wg, new THREE.LineBasicMaterial({ color: 0xf6efe4 }))); }
  [-1, 1].forEach(s => { const ear = new THREE.Mesh(new THREE.ConeGeometry(4, 9, 4), orange); ear.position.set(-2, 10, s * 6); ear.castShadow = true; headG.add(ear); outline(ear, 1); });
  const eyeM = new THREE.MeshBasicMaterial({ color: 0x9be06a }), eyeMeshes = [];
  [-1, 1].forEach(s => { const e = new THREE.Mesh(new THREE.SphereGeometry(2.2, 10, 8), eyeM); e.position.set(8, 2, s * 4); headG.add(e); eyeMeshes.push(e); const pu = new THREE.Mesh(new THREE.BoxGeometry(0.6, 3, 1.1), new THREE.MeshBasicMaterial({ color: 0x101010 })); pu.position.set(10.15, 2, s * 4); headG.add(pu); eyeMeshes.push(pu); });
  const legs = []; [[14, 7], [14, -7], [-14, 7], [-14, -7]].forEach(([x, z]) => { const l = new THREE.Mesh(new THREE.CylinderGeometry(3, 3, 14, 8), orange); l.position.set(x, 7, z); l.castShadow = true; bodyG.add(l); outline(l, 1); const paw = new THREE.Mesh(new THREE.SphereGeometry(3.6, 8, 6), cream); paw.scale.set(1.3, 0.7, 1); paw.position.set(1.5, -6.5, 0); l.add(paw); legs.push(l); });
  const tailPivot = new THREE.Group(); tailPivot.position.set(-22, 26, 0); bodyG.add(tailPivot);
  const ctail = []; { let par = tailPivot; const L7 = 7; for (let i = 0; i < 5; i++) { const r0 = 3 - i * 0.3, r1 = 3 - (i + 1) * 0.3; const seg = new THREE.Mesh(new THREE.CylinderGeometry(r0, r1, L7, 8), i === 4 ? cream : i % 2 ? stripe : orange); seg.rotation.z = Math.PI / 2; seg.position.x = -L7 / 2; seg.castShadow = true; par.add(seg); outline(seg, 0.8); const nx = new THREE.Group(); nx.position.x = -L7; nx.rotation.z = -0.32; par.add(nx); ctail.push(nx); par = nx; } }
  tailPivot.rotation.z = -0.5;
  g.userData = { eyeM, eyeMeshes, legs, tailPivot, ctail, bodyG, headG, body }; scene.add(g); return g;
}
function makeHuman() {
  const g = new THREE.Group(), paj = T(0x5b7fb8), paj2 = T(0x4a6aa0), skin = T(0xe8b896), hair = T(0x4a3426), slip = T(0xa35a7a);
  const bodyG = new THREE.Group(); g.add(bodyG);
  const legs = [];
  [-10, 10].forEach(z => { const piv = new THREE.Group(); piv.position.set(0, 88, z); bodyG.add(piv);
    const l = new THREE.Mesh(new THREE.CylinderGeometry(7.5, 6.5, 84, 10), paj2); l.position.y = -42; l.castShadow = true; piv.add(l); outline(l, 1.4);
    const sl = new THREE.Mesh(new THREE.BoxGeometry(26, 7, 12), slip); sl.position.set(5, -84, 0); sl.castShadow = true; piv.add(sl); outline(sl, 1); legs.push(piv); });
  const torso = new THREE.Mesh(new THREE.BoxGeometry(28, 64, 44), paj); torso.position.y = 120; torso.castShadow = true; bodyG.add(torso); outline(torso, 1.6);
  for (let i = 0; i < 3; i++) { const st = new THREE.Mesh(new THREE.BoxGeometry(28.6, 3, 44.6), T(0xe8ecf4)); st.position.y = 100 + i * 18; bodyG.add(st); }
  const head = new THREE.Mesh(new THREE.SphereGeometry(13, 16, 12), skin); head.position.set(2, 166, 0); head.castShadow = true; bodyG.add(head); outline(head, 1.4);
  const hr = new THREE.Mesh(new THREE.SphereGeometry(13.8, 16, 10, 0, Math.PI * 2, 0, Math.PI / 2), hair); hr.position.set(-1, 167, 0); hr.rotation.z = 0.3; bodyG.add(hr);
  const nose = new THREE.Mesh(new THREE.SphereGeometry(2.6, 8, 6), skin); nose.position.set(15, 164, 0); bodyG.add(nose);
  [-5, 5].forEach(z => { const e = new THREE.Mesh(new THREE.SphereGeometry(1.6, 8, 6), new THREE.MeshBasicMaterial({ color: 0x111111 })); e.position.set(13, 169, z); bodyG.add(e); });
  const mkArm = z => { const piv = new THREE.Group(); piv.position.set(0, 148, z); bodyG.add(piv); const a = new THREE.Mesh(new THREE.CylinderGeometry(5, 4.5, 56, 8), paj); a.position.y = -28; a.castShadow = true; piv.add(a); outline(a, 1.2); const hd = new THREE.Mesh(new THREE.SphereGeometry(5, 8, 6), skin); hd.position.y = -58; piv.add(hd); return piv; };
  const armL = mkArm(-26), armR = mkArm(26);
  const fl = new THREE.Mesh(new THREE.CylinderGeometry(3.5, 3, 16, 10), T(0x2c2f3a)); fl.position.y = -64; armR.add(fl);
  const lens = new THREE.Mesh(new THREE.CircleGeometry(3.4, 12), new THREE.MeshBasicMaterial({ color: 0xfff2c0 })); lens.position.y = -72.2; lens.rotation.x = Math.PI / 2; armR.add(lens);
  const spot = new THREE.SpotLight(0xfff0c8, 0, 560, 0.45, 0.5, 1); spot.position.y = -72; armR.add(spot); const tgt = new THREE.Object3D(); tgt.position.y = -400; armR.add(tgt); spot.target = tgt;
  g.userData = { legs, armL, armR, spot, bodyG }; scene.add(g); return g;
}
function makeVacuum() {
  const g = new THREE.Group();
  const body = new THREE.Mesh(new THREE.CylinderGeometry(17, 17, 8, 28), T(0x2a2d36)); body.position.y = 5; body.castShadow = true; g.add(body); outline(body, 1);
  const top = new THREE.Mesh(new THREE.CylinderGeometry(12, 12, 1.2, 24), T(0x4a4f5e)); top.position.y = 9.4; g.add(top);
  const bump = new THREE.Mesh(new THREE.CylinderGeometry(17.6, 17.6, 4, 28, 1, true, -Math.PI / 2.2, Math.PI / 1.1), T(0x8a8f9e, { side: THREE.DoubleSide })); bump.position.y = 4; bump.rotation.y = Math.PI / 2; g.add(bump);
  const ledM = new THREE.MeshBasicMaterial({ color: 0x6ee07a }); const led = new THREE.Mesh(new THREE.SphereGeometry(1.6, 8, 6), ledM); led.position.set(9, 10, 0); g.add(led);
  g.userData = { ledM }; g.visible = false; scene.add(g); return g;
}
const ratMesh = makeRodent(0x8f8580, 1), catMesh = makeCat(), humanMesh = makeHuman(), vacMesh = makeVacuum();
humanMesh.visible = false;
const pupSpots = [[-18, -14, 0.3], [-26, 8, -0.6], [-6, 20, -1.6], [8, -20, 1.2]];
const pups = pupSpots.map(([dx, dz, a], i) => { const m = makeRodent([0xc4aaa6, 0xb09f9b, 0xd0b8b2, 0xa7978f][i], 0.55); return { m, bx: nest.cx + dx, bz: nest.cz + dz, a, ph: i * 1.7 }; });

// vision cones (cat and flashlight) drawn as floor decals
function makeCone(n, color, op, additive) {
  const geo = new THREE.BufferGeometry(), pos = new Float32Array((n + 2) * 3);
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  const idx = []; for (let i = 1; i <= n; i++) idx.push(0, i + 1, i); geo.setIndex(idx);
  const mat = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: op, depthWrite: false, side: THREE.DoubleSide, blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending });
  const mesh = new THREE.Mesh(geo, mat); mesh.frustumCulled = false; scene.add(mesh);
  return { n, geo, pos, mat, mesh };
}
const catCone = makeCone(28, 0xdcdceb, 0.14), lightCone = makeCone(24, 0xfff0c0, 0.14, true);
function updateCone(c, x, y, a, half, range) {
  c.pos[0] = x; c.pos[1] = 0.7; c.pos[2] = y;
  for (let i = 0; i <= c.n; i++) {
    const t = a - half + 2 * half * i / c.n; let r = range;
    for (let d = 10; d <= range; d += 10) { const px = x + Math.cos(t) * d, py = y + Math.sin(t) * d; if (L.losRects.some(s => s.ht > 30 && inRect(px, py, s))) { r = d; break; } }
    c.pos[(i + 1) * 3] = x + Math.cos(t) * r; c.pos[(i + 1) * 3 + 1] = 0.7; c.pos[(i + 1) * 3 + 2] = y + Math.sin(t) * r;
  }
  c.geo.attributes.position.needsUpdate = true; c.geo.computeBoundingSphere();
}

const marker = new THREE.Mesh(new THREE.RingGeometry(7, 10, 32), new THREE.MeshBasicMaterial({ color: 0xf2c14e, transparent: true, opacity: 0.9, depthWrite: false, side: THREE.DoubleSide }));
marker.rotation.x = -Math.PI / 2; marker.visible = false; scene.add(marker);

// food
const crumbGeo = new THREE.SphereGeometry(3.5, 8, 6), crumbMat = T(0xe3c08e, { emissive: 0x3a2a12 });
const cheeseGeo = new THREE.CylinderGeometry(10, 10, 8, 8, 1, false, 0, Math.PI / 3), cheeseMat = T(0xf7c64e, { emissive: 0x8a6214 });
const poisonMat = T(0xd6d45a, { emissive: 0x2e4a10 });
function itemMesh(type, poison) { const m = new THREE.Mesh(type === 'cheese' ? cheeseGeo : crumbGeo, poison ? poisonMat : type === 'cheese' ? cheeseMat : crumbMat); m.castShadow = true; outline(m, type === 'cheese' ? 1 : 0.6); scene.add(m); return m; }
const scentMat = new THREE.SpriteMaterial({ map: glowTex, color: 0xf2d36a, transparent: true, opacity: 0.5, depthWrite: false, blending: THREE.AdditiveBlending });
function makeWisps(col) { const arr = []; for (let i = 0; i < 5; i++) { const s = new THREE.Sprite(scentMat.clone()); if (col) s.material.color.set(col); s.scale.set(7, 7, 1); scene.add(s); arr.push({ s, ph: i / 5 }); } return arr; }
const trapBaseM = T(0xd2ab72), metalM = T(0xbfc6d2);
function makeTrap(x, y) {
  const g = new THREE.Group();
  const base = new THREE.Mesh(new THREE.BoxGeometry(26, 3, 14), trapBaseM); base.position.y = 1.5; base.castShadow = true; g.add(base); outline(base, 0.8);
  const bar = new THREE.Group(); bar.position.set(-1, 3.5, 0); g.add(bar);
  const b1 = new THREE.Mesh(new THREE.BoxGeometry(1.4, 1.4, 12), metalM); b1.position.x = -10; bar.add(b1);
  const b2 = new THREE.Mesh(new THREE.BoxGeometry(10, 1.2, 1.2), metalM); b2.position.set(-5, 0, -5.5); bar.add(b2);
  const b3 = b2.clone(); b3.position.z = 5.5; bar.add(b3);
  const spring = new THREE.Mesh(new THREE.TorusGeometry(2, 0.6, 6, 12), metalM); spring.position.set(-1, 4, 0); g.add(spring);
  const bait = new THREE.Mesh(cheeseGeo, cheeseMat); bait.scale.setScalar(0.45); bait.position.set(7, 3.5, 0); g.add(bait);
  const warn = new THREE.Mesh(new THREE.RingGeometry(16, 19, 32), new THREE.MeshBasicMaterial({ color: 0xe8664a, transparent: true, opacity: 0.85, depthWrite: false, side: THREE.DoubleSide })); warn.rotation.x = -Math.PI / 2; warn.position.y = 0.6; warn.visible = false; g.add(warn);
  g.position.set(x, 0, y); g.rotation.y = Math.random() * 6; scene.add(g);
  return { x, y, h: 0, type: 'trap', id: Math.random(), mesh: g, bar, bait, warn, sprung: false, reveal: 0, wisps: makeWisps() };
}
const rings = [], trail = [];
// sniffing: thin streams of scent particles flowing from food to the rat's nose
const STREAM_N = 70;
function makeStream() {
  const geo = new THREE.BufferGeometry(), pos = new Float32Array(STREAM_N * 3), alpha = new Float32Array(STREAM_N);
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3)); geo.setAttribute('alpha', new THREE.BufferAttribute(alpha, 1));
  const mat = new THREE.ShaderMaterial({
    uniforms: { map: { value: glowTex }, color: { value: new THREE.Color(0xf2d36a) }, opacity: { value: 0 } },
    vertexShader: 'attribute float alpha;varying float vA;void main(){vA=alpha;vec4 mv=modelViewMatrix*vec4(position,1.);gl_PointSize=3.4*(300./-mv.z);gl_Position=projectionMatrix*mv;}',
    fragmentShader: 'uniform sampler2D map;uniform vec3 color;uniform float opacity;varying float vA;void main(){float a=texture2D(map,gl_PointCoord).a;gl_FragColor=vec4(color*1.4,a*vA*opacity);}',
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
  });
  const pts = new THREE.Points(geo, mat); pts.frustumCulled = false; pts.visible = false; scene.add(pts);
  return { geo, pos, alpha, mat, pts, op: 0, it: null };
}
const streams = [makeStream(), makeStream(), makeStream()];
function addRing(x, z, big, k = 1) { const m = new THREE.Mesh(new THREE.RingGeometry(0.92, 1, 48), new THREE.MeshBasicMaterial({ color: big ? 0xf2c14e : 0xece6da, transparent: true, opacity: k < 1 ? 0.35 : 0.6, depthWrite: false })); m.rotation.x = -Math.PI / 2; m.position.set(x, 1, z); scene.add(m); rings.push({ m, r: 4, t: big ? 1 : 0.6, sp: (big ? 420 : 220) * k, k }); }

// ================= LEVEL BUILDER =================
let world = null, L = null, fid = 0;
function solid(o, ht) { L.solids.push({ x: o.x, y: o.y, w: o.w, h: o.h, ht }); }
function hideR(o, kind, land) { const r = { x: o.x, y: o.y, w: o.w, h: o.h, kind, land: !!land }; L.hides.push(r); return r; }
function surf(id, h, rects, food = true) { let s = L.surfaces.find(q => q.id === id); if (!s) { s = { id, h, rects: [], food }; L.surfaces.push(s); } s.rects.push(...rects); return s; }
function fadeGroup(rect, meshes) { L.fades.push({ rect, meshes, op: 1 }); }
const shade = (c, f) => new THREE.Color(c).multiplyScalar(f).getHex();

const B = {
  counter(o) { const ht = o.ht || 92, [cx, cz] = center(o); solid(o, ht); surf('counter', ht, [o.join ? R(o.x, o.y - 16, o.w, o.h + 16) : R(o.x, o.y, o.w, o.h)]);
    box(o.w, ht - 4, o.h, T(0x6b5446), cx, (ht - 4) / 2, cz); box(o.w + 4, 4, o.h + 4, T(0xb7a68f), cx, ht - 2, cz); },
  fridge(o) { const [cx, cz] = center(o); solid(o, 180);
    box(o.w, 180, o.h, T(0xdfe3ea), cx, 90, cz); box(4, 50, 4, T(0x9ca3b0), o.x + 18, 110, o.y + o.h + 2, { block: false });
    box(o.w - 10, 1.5, 1, T(0x9ca3b0), cx, 120, o.y + o.h + 0.6, { block: false, line: false }); box(14, 14, 2, T(0xe8664a), o.x + 60, 150, o.y + o.h + 1, { block: false, t: 0.8 }); },
  island(o) { const [cx, cz] = center(o); solid(o, 92); surf('island' + (fid++), 92, [R(o.x, o.y, o.w, o.h)]);
    box(o.w, 88, o.h, T(0x5a463a), cx, 44, cz); box(o.w + 6, 4, o.h + 6, T(0xb7a68f), cx, 90, cz);
    const bowl = new THREE.Mesh(new THREE.SphereGeometry(16, 20, 12, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2), T(0xe9e2d0)); bowl.position.set(cx - 40, 108, cz); bowl.castShadow = true; add(bowl); outline(bowl, 1); },
  box(o) { const ht = o.ht || 44, [cx, cz] = center(o); solid(o, ht); surf('box' + (fid++), ht, [R(o.x, o.y, o.w, o.h)]);
    box(o.w, ht, o.h, T(0xb08a5a), cx, ht / 2, cz); box(o.w + 1, 3, Math.min(10, o.h * 0.25), T(0xd8c49a), cx, ht - 0.5, cz, { block: false, line: false }); },
  crate(o) { const ht = o.ht || 40, [cx, cz] = center(o); solid(o, ht); surf('crate' + (fid++), ht, [R(o.x, o.y, o.w, o.h)]);
    box(o.w, ht, o.h, T(0x9a7448), cx, ht / 2, cz); const sl = T(0x6e5232);
    for (let k = 1; k < ht / 20; k++) { box(o.w + 0.6, 1.6, 0.6, sl, cx, k * 20, o.y + o.h + 0.3, { block: false, line: false }); box(0.6, 1.6, o.h + 0.6, sl, o.x + o.w + 0.3, k * 20, cz, { block: false, line: false }); } },
  table(o) { const ht = o.ht || 79, [cx, cz] = center(o), low = ht < 70, tw = o.top || 0x8a5f3c;
    hideR(o, 'table', true); surf('table' + (fid++), ht, [R(o.x, o.y, o.w, o.h)]);
    const ms = [], mt = low ? TF(tw) : T(tw), ml = low ? TF(0x3a2a20) : darkWood;
    ms.push(box(o.w, 5, o.h, mt, cx, ht - 2.5, cz, { block: !low }));
    const inset = Math.min(10, o.w * 0.08); [[inset, inset], [o.w - inset, inset], [inset, o.h - inset], [o.w - inset, o.h - inset]].forEach(([a, b]) => ms.push(cyl(3, ht - 5, ml, o.x + a, (ht - 5) / 2, o.y + b)));
    if (o.cloth) {
      if (o.dining) {
        box(o.w + 8, 1.2, o.h + 8, T(o.cloth), cx, ht + 0.6, cz, { block: false, line: false });
        box(o.w * 0.9, 1.4, 30, T(0xa83a3a), cx, ht + 1.3, cz, { block: false, line: false });
        [[-110, -45], [0, -45], [110, -45], [-110, 45], [0, 45], [110, 45]].forEach(([dx, dz]) => cyl(14, 1.6, T(0xf4f0e6), cx + dx, ht + 1.6, cz + dz, { seg: 24, t: 0.6 }));
        const flames = []; [-55, 55].forEach(dx => { cyl(3, 20, T(0xf2ead8), cx + dx, ht + 11, cz, { t: 0.5 }); flames.push(sprite(0xffb050, 9, cx + dx, ht + 24, cz, 0.9)); });
        const lt = new THREE.PointLight(0xffb060, 0.45, 300, 1.8); lt.position.set(cx, ht + 60, cz); add(lt); L.flickers.push({ type: 'fire', light: lt, base: 0.45, sprites: flames });
      } else box(90, 1, o.h + 6, T(o.cloth), cx - 30, ht + 0.5, cz, { block: false, line: false });
    }
    if (o.plate) cyl(15, 2, T(0xe9e2d0), o.x + 60, ht + 1, o.y + 50, { r2: 12, seg: 24 });
    if (low) fadeGroup(R(o.x, o.y, o.w, o.h), ms); },
  coffeeTable(o) { B.table(Object.assign({}, o, { ht: 45, top: 0x4a3428 })); },
  bench(o) { B.table(Object.assign({}, o, { ht: 80, top: 0x8a6a48 })); const [cx, cz] = center(o); box(26, 10, 14, T(0x5a6470), o.x + 24, 85, cz - 20, { block: false }); box(40, 4, 8, T(0xb08a5a), cx + 30, 82, cz + 20, { block: false }); },
  chair(o) { const r = R(o.x, o.y, 32, 32), cx = o.x + 16, cz = o.y + 16; hideR(r, 'chair', false); surf('chair' + (fid++), 47, [r]);
    box(32, 4, 32, wood, cx, 45, cz); [[3, 3], [29, 3], [3, 29], [29, 29]].forEach(([a, b]) => cyl(1.8, 43, darkWood, o.x + a, 21.5, o.y + b, { t: 0.7 }));
    const bm = TF(0x63412a); let b;
    if (o.back === 'w') b = box(3, 40, 32, bm, o.x + 2, 67, cz, { block: false });
    else if (o.back === 'e') b = box(3, 40, 32, bm, o.x + 30, 67, cz, { block: false });
    else if (o.back === 'n') b = box(32, 40, 3, bm, cx, 67, o.y + 2, { block: false });
    else b = box(32, 40, 3, bm, cx, 67, o.y + 30, { block: false });
    fadeables.push(b); },
  stool(o) { const r = R(o.x, o.y, 36, 36), cx = o.x + 18, cz = o.y + 18; hideR(r, 'stool', false); surf('stool' + (fid++), 52, [r]);
    cyl(18, 4, T(0x6c8fa0), cx, 50, cz, { seg: 20 }); [[6, 6], [30, 6], [6, 30], [30, 30]].forEach(([a, b]) => cyl(1.8, 48, darkWood, o.x + a, 24, o.y + b, { t: 0.7 })); },
  lowShelf(o) { const [cx, cz] = center(o); hideR(o, 'shelf', false); surf('shelf' + (fid++), 27, [R(o.x, o.y, o.w, o.h)]);
    const ms = [box(o.w, 4, o.h, TF(0x9b7c4c), cx, 25, cz, { block: false })]; [[4, 4], [o.w - 4, 4], [4, o.h - 4], [o.w - 4, o.h - 4]].forEach(([a, b]) => ms.push(cyl(2, 23, TF(0x63412a), o.x + a, 11.5, o.y + b, { t: 0.7 })));
    fadeGroup(R(o.x, o.y, o.w, o.h), ms); },
  sofa(o, armW = 16, cushions) { const face = o.face || 's', back = 26, legH = 14, col = o.color || 0x6a5a8f, [cx, cz] = center(o);
    hideR(o, 'sofa', false); L.blockers.push({ x: o.x, y: o.y, w: o.w, h: o.h, ht: 76 });
    const backR = face === 'n' ? R(o.x, o.y + o.h - back, o.w, back) : R(o.x, o.y, o.w, back);
    const seatR = face === 'n' ? R(o.x + armW, o.y, o.w - 2 * armW, o.h - back) : R(o.x + armW, o.y + back, o.w - 2 * armW, o.h - back);
    const id = 'sofa' + (fid++); surf(id + 's', 40, [seatR]); surf(id + 'b', 76, [backR]);
    const fab = TF(col), fab2 = TF(shade(col, 0.82)), legM = TF(0x2a1e18), ms = [];
    [[6, 6], [o.w - 6, 6], [6, o.h - 6], [o.w - 6, o.h - 6]].forEach(([a, b]) => ms.push(cyl(2.5, legH, legM, o.x + a, legH / 2, o.y + b, { line: false })));
    ms.push(box(o.w, 16, o.h, fab2, cx, legH + 8, cz, { block: false }));
    const n = cushions || Math.max(2, Math.round(seatR.w / 90)); for (let i = 0; i < n; i++) { const w = seatR.w / n; ms.push(box(w - 3, 10, seatR.h - 2, fab, seatR.x + w * (i + 0.5), 35, seatR.y + seatR.h / 2, { block: false })); }
    ms.push(box(backR.w, 46, backR.h, fab2, backR.x + backR.w / 2, 53, backR.y + backR.h / 2, { block: false }));
    [o.x + armW / 2, o.x + o.w - armW / 2].forEach(ax => ms.push(box(armW, 26, o.h, fab2, ax, 43, cz, { block: false })));
    fadeGroup(R(o.x, o.y, o.w, o.h), ms); },
  armchair(o) { B.sofa(o, 14, 1); },
  tvStand(o) { const [cx, cz] = center(o); solid(o, 55); surf('tv' + (fid++), 55, [R(o.x, o.y, o.w * 0.28, o.h), R(o.x + o.w * 0.72, o.y, o.w * 0.28, o.h)]);
    box(o.w, 51, o.h, T(0x3a2c26), cx, 25.5, cz); box(o.w + 4, 4, o.h + 4, T(0x5a4436), cx, 53, cz);
    [1, 2].forEach(k => box(1.5, 40, 0.6, T(0x22180f), o.x + o.w * k / 3, 26, o.y + o.h + 0.4, { block: false, line: false }));
    const tw = o.w * 0.42, th = tw * 0.58; box(tw, th, 5, T(0x111216), cx, 63 + th / 2, o.y + 14); box(30, 6, 16, T(0x111216), cx, 58, o.y + 14, { line: false });
    const scr = new THREE.MeshBasicMaterial({ color: 0x5a7ac8 }); const sp = new THREE.Mesh(new THREE.PlaneGeometry(tw - 8, th - 8), scr); sp.position.set(cx, 63 + th / 2, o.y + 16.7); add(sp);
    const lt = new THREE.PointLight(0x8fb4ff, 1.1, 460, 1.5); lt.position.set(cx, 90, o.y + 70); add(lt);
    L.flickers.push({ type: 'tv', light: lt, mat: scr, base: 1.1, t: 0 }); },
  bookcase(o) { const [cx, cz] = center(o); solid(o, 190); box(o.w, 190, o.h, T(0x3e2c22), cx, 95, cz);
    const cols = [0xa83a3a, 0x3a6aa8, 0xd8b04a, 0x4a8a5a, 0x7a4a8a, 0xe0d8c8, 0x2a3a5a];
    for (let k = 0; k < 4; k++) { const y = 14 + k * 44; box(3, 3, o.h - 6, T(0x5a4030), o.x + o.w + 0.5, y, cz, { block: false, line: false });
      let z = o.y + 6; while (z < o.y + o.h - 12) { const th = 5 + Math.random() * 6, hh = 22 + Math.random() * 12; box(4, hh, th, T(cols[Math.floor(Math.random() * cols.length)]), o.x + o.w + 1, y + hh / 2 + 1.5, z + th / 2, { block: false, line: false, cast: false }); z += th + 0.8; } } },
  fireplace(o) { const [cx, cz] = center(o); solid(o, 110); box(o.w, 108, o.h, T(0x7a4a3a), cx, 54, cz); box(o.w + 14, 6, o.h + 24, T(0x5a3e30), o.x + (o.w + 14) / 2, 111, cz);
    const op = new THREE.Mesh(new THREE.PlaneGeometry(o.h * 0.5, 52), new THREE.MeshBasicMaterial({ color: 0x120a08 })); op.position.set(o.x + o.w + 0.4, 30, cz); op.rotation.y = Math.PI / 2; add(op);
    [-10, 10].forEach(dz => { const lg = cyl(3.5, 30, T(0x5a3a22), o.x + o.w + 5, 5, cz + dz, { line: false }); lg.rotation.x = Math.PI / 2; lg.rotation.z = dz * 0.02; });
    const sprites = [0, 1, 2, 3].map(i => sprite(i % 2 ? 0xffc050 : 0xff7a2a, 14 + i * 3, o.x + o.w + 6, 14 + i * 4, cz + (i - 1.5) * 8, 0.85));
    const lt = new THREE.PointLight(0xff8a3a, 1.4, 420, 1.6); lt.position.set(o.x + o.w + 30, 40, cz); add(lt);
    L.flickers.push({ type: 'fire', light: lt, base: 1.4, sprites }); L.crackle = { x: o.x + o.w + 10, y: cz }; },
  sideTable(o) { const ht = o.ht || 60, [cx, cz] = center(o); solid(o, ht); surf('side' + (fid++), ht, [R(o.x, o.y, o.w, o.h)]);
    cyl(o.w / 2, 3, T(0x6a4a30), cx, ht - 1.5, cz, { seg: 20 }); cyl(3, ht - 3, T(0x4a3020), cx, (ht - 3) / 2, cz); cyl(12, 2, T(0x4a3020), cx, 1, cz, { line: false }); },
  lamp(o) { const [cx, cz] = center(o); solid(o, 160);
    cyl(11, 3, T(0x2a2a30), cx, 1.5, cz, { line: false }); cyl(1.5, 150, T(0x2a2a30), cx, 76, cz, { line: false });
    const sh = new THREE.Mesh(new THREE.ConeGeometry(17, 22, 20, 1, true), T(0xe8d4a8, { side: THREE.DoubleSide })); sh.position.set(cx, 152, cz); add(sh); outline(sh, 0.8);
    sprite(0xffd090, 40, cx, 142, cz, 0.5); const lt = new THREE.PointLight(0xffc27a, 0.85, 380, 1.6); lt.position.set(cx, 138, cz); add(lt); },
  plant(o) { const [cx, cz] = center(o); solid(o, 40); cyl(o.w / 2.4, 28, T(0xc06a46), cx, 14, cz, { r2: o.w / 2.1 });
    const lm = [T(0x5e9a5a), T(0x4a8048)]; for (let i = 0; i < 9; i++) { const a = i * 0.7, lf = new THREE.Mesh(new THREE.ConeGeometry(5, 34 + (i % 3) * 8, 5), lm[i % 2]); lf.position.set(cx + Math.cos(a) * 6, 46, cz + Math.sin(a) * 6); lf.rotation.set(Math.sin(a) * 0.55, 0, -Math.cos(a) * 0.55); lf.castShadow = true; add(lf); outline(lf, 0.6); } },
  washer(o) { const [cx, cz] = center(o); solid(o, 85); surf('washer' + (fid++), 85, [R(o.x, o.y, o.w, o.h)]);
    box(o.w, 85, o.h, T(o.dryer ? 0xd2d6de : 0xeef0f4), cx, 42.5, cz);
    const ring = new THREE.Mesh(new THREE.TorusGeometry(20, 3, 8, 24), T(0x9aa0aa)); ring.position.set(cx, 38, o.y + o.h + 1.5); add(ring);
    const gl = new THREE.Mesh(new THREE.CircleGeometry(18, 24), new THREE.MeshBasicMaterial({ color: o.dryer ? 0x2a2a34 : 0x2a3a5a })); gl.position.set(cx, 38, o.y + o.h + 0.8); add(gl);
    box(o.w - 8, 10, 1, T(0xb8bec8), cx, 76, o.y + o.h + 0.6, { block: false, line: false }); cyl(3, 2, T(0x5a6070), cx + 28, 76, o.y + o.h + 1.5, { line: false }).rotation.x = Math.PI / 2; },
  basket(o) { const ht = o.ht || 45, [cx, cz] = center(o); solid(o, ht); surf('basket' + (fid++), ht, [R(o.x, o.y, o.w, o.h)]);
    cyl(Math.min(o.w, o.h) / 2, ht, T(0xb08a5a), cx, ht / 2, cz, { seg: 16 }); [0xc95b4a, 0x6a8ab6, 0xe6dcc8].forEach((c, i) => { const m = new THREE.Mesh(new THREE.SphereGeometry(9, 10, 8), T(c)); m.scale.y = 0.4; m.position.set(cx + (i - 1) * 8, ht + 1, cz + (i % 2 ? 4 : -4)); add(m); }); },
  cans(o) { const ht = o.ht || 30, [cx, cz] = center(o); solid(o, ht); surf('cans' + (fid++), ht, [R(o.x, o.y, o.w, o.h)]);
    [[-11, -11, 0xc95b4a], [11, -11, 0x4a8a5a], [-11, 11, 0xd8b04a], [11, 11, 0x3a6aa8]].forEach(([dx, dz, c]) => cyl(10, ht, T(c), cx + dx, ht / 2, cz + dz)); },
  shelfUnit(o) { const [cx, cz] = center(o); solid(o, 160); const fr = T(0x7a7f88);
    [[2, 2], [o.w - 2, 2], [2, o.h - 2], [o.w - 2, o.h - 2]].forEach(([a, b]) => cyl(2, 160, fr, o.x + a, 80, o.y + b, { line: false }));
    const jc = [0xd8b04a, 0xc95b4a, 0x9ab86a, 0xe6dcc8, 0x8a5a3a];
    [4, 52, 104, 156].forEach((y, k) => { box(o.w, 3, o.h, T(0x9a9fa8), cx, y, cz, { block: k === 3 });
      if (k < 3) for (let x = o.x + 14; x < o.x + o.w - 10; x += 22 + Math.random() * 10) { const jh = 18 + Math.random() * 14; cyl(7, jh, T(jc[Math.floor(Math.random() * jc.length)]), x, y + 1.5 + jh / 2, cz + (Math.random() - 0.5) * 16, { t: 0.6 }); } }); },
  boiler(o) { const [cx, cz] = center(o); solid(o, 200); cyl(Math.min(o.w, o.h) / 2, 190, T(0xc8ccd2), cx, 95, cz, { seg: 20 });
    cyl(4, 70, T(0x8a6a4a), cx - 15, 225, cz, { line: false }); cyl(4, 70, T(0x8a6a4a), cx + 15, 225, cz, { line: false });
    sprite(0xff8a3a, 14, cx - 30, 40, cz, 0.9); const lt = new THREE.PointLight(0xff8a3a, 0.9, 300, 1.8); lt.position.set(cx - 50, 40, cz); add(lt);
    L.flickers.push({ type: 'fire', light: lt, base: 0.9, sprites: [] }); },
  sideboard(o) { const [cx, cz] = center(o); solid(o, 85); surf('sideboard' + (fid++), 85, [R(o.x, o.y, o.w, o.h)]);
    box(o.w, 81, o.h, T(0x4a3024), cx, 40.5, cz); box(o.w + 6, 4, o.h + 6, T(0x6a4434), cx, 83, cz);
    for (let i = 1; i < 4; i++) box(1.5, 70, 0.6, T(0x22140c), o.x + o.w * i / 4, 40, o.y + o.h + 0.4, { block: false, line: false });
    for (let i = 0; i < 4; i++) { const k = new THREE.Mesh(new THREE.SphereGeometry(2, 8, 6), T(0xd8c49a)); k.position.set(o.x + o.w * (i + 0.5) / 4, 60, o.y + o.h + 1.5); add(k); } },
  cabinetTall(o) { const [cx, cz] = center(o); solid(o, 200); box(o.w, 200, o.h, T(0x4a3024), cx, 100, cz);
    const gl = new THREE.Mesh(new THREE.PlaneGeometry(o.h - 16, 150), new THREE.MeshBasicMaterial({ color: 0x9ab0c8, transparent: true, opacity: 0.25 })); gl.position.set(o.x + o.w + 0.5, 110, cz); gl.rotation.y = Math.PI / 2; add(gl);
    for (let k = 0; k < 3; k++) for (let i = 0; i < 4; i++) { const p = new THREE.Mesh(new THREE.CircleGeometry(12, 20), T(0xf4f0e6)); p.position.set(o.x + o.w - 6, 60 + k * 48, o.y + 30 + i * 48); p.rotation.y = Math.PI / 2; add(p); } },
  ottoman(o) { const [cx, cz] = center(o); solid(o, 40); surf('ottoman' + (fid++), 40, [R(o.x, o.y, o.w, o.h)]);
    box(o.w, 32, o.h, T(0x7a4a5a), cx, 24, cz); [[5, 5], [o.w - 5, 5], [5, o.h - 5], [o.w - 5, o.h - 5]].forEach(([a, b]) => cyl(2.5, 8, darkWood, o.x + a, 4, o.y + b, { line: false })); },
  barCart(o) { const ht = 62, [cx, cz] = center(o); solid(o, ht); surf('cart' + (fid++), ht, [R(o.x, o.y, o.w, o.h)]);
    const br = T(0xc9a35a); [[3, 3], [o.w - 3, 3], [3, o.h - 3], [o.w - 3, o.h - 3]].forEach(([a, b]) => cyl(1.5, ht, br, o.x + a, ht / 2, o.y + b, { line: false }));
    box(o.w, 2, o.h, T(0x3a3030), cx, ht - 1, cz); box(o.w, 2, o.h, T(0x3a3030), cx, 26, cz);
    [0x3a6a3a, 0x8a3a3a].forEach((c, i) => { cyl(4, 22, T(c), cx - 14 + i * 22, 38, cz, { t: 0.6 }); }); },
};

function floorTexture(p) {
  if (p.floor === 'wood') return canvasTex(512, 512, g => {
    const base = hexRgb(p.floorA);
    for (let r = 0; r < 8; r++) { let x = -((r * 97) % 200); while (x < 512) { const len = 180 + Math.random() * 200, v = (Math.random() - 0.5) * 22; g.fillStyle = rgbStr(base, v); g.fillRect(x, r * 64, len, 64);
      for (let k = 0; k < 6; k++) { g.strokeStyle = 'rgba(0,0,0,' + (0.05 + Math.random() * 0.07) + ')'; g.lineWidth = 1; g.beginPath(); const yy = r * 64 + 6 + Math.random() * 52; g.moveTo(x, yy); g.bezierCurveTo(x + len * 0.3, yy + 4, x + len * 0.6, yy - 4, x + len, yy); g.stroke(); }
      g.fillStyle = 'rgba(0,0,0,.45)'; g.fillRect(x, r * 64, 3, 64); x += len; } g.fillStyle = 'rgba(0,0,0,.5)'; g.fillRect(0, r * 64, 512, 3); }
  }, [W / 256, H / 256]);
  if (p.floor === 'concrete') return canvasTex(512, 512, g => {
    const base = hexRgb(p.floorA); g.fillStyle = rgbStr(base); g.fillRect(0, 0, 512, 512);
    for (let i = 0; i < 3000; i++) { g.fillStyle = 'rgba(' + (Math.random() < 0.5 ? '0,0,0' : '255,255,255') + ',' + Math.random() * 0.06 + ')'; g.fillRect(Math.random() * 512, Math.random() * 512, 2 + Math.random() * 3, 2 + Math.random() * 3); }
    g.strokeStyle = 'rgba(0,0,0,.35)'; g.lineWidth = 3; g.strokeRect(0, 0, 512, 512);
    g.strokeStyle = 'rgba(0,0,0,.25)'; g.lineWidth = 1.5; g.beginPath(); let x = 100, y = 0; g.moveTo(x, y); while (y < 512) { x += (Math.random() - 0.5) * 40; y += 20 + Math.random() * 30; g.lineTo(x, y); } g.stroke();
  }, [W / 256, H / 256]);
  return canvasTex(512, 512, g => {
    const A = hexRgb(p.floorA), Bc = hexRgb(p.floorB || p.floorA);
    for (let y = 0; y < 4; y++) for (let x = 0; x < 4; x++) { const v = (Math.random() - 0.5) * 10; g.fillStyle = rgbStr((x + y) % 2 ? A : Bc, v); g.fillRect(x * 128, y * 128, 128, 128);
      for (let k = 0; k < 40; k++) { g.fillStyle = 'rgba(255,255,255,' + Math.random() * 0.035 + ')'; g.fillRect(x * 128 + Math.random() * 128, y * 128 + Math.random() * 128, 2, 2); } }
    g.strokeStyle = 'rgba(12,12,24,.55)'; g.lineWidth = 4; for (let i = 0; i <= 4; i++) { g.beginPath(); g.moveTo(i * 128, 0); g.lineTo(i * 128, 512); g.moveTo(0, i * 128); g.lineTo(512, i * 128); g.stroke(); }
  }, [W / 192, H / 192]);
}
function wallTexture(p) {
  const A = p.wallA, Bc = p.wallB;
  if (p.wall === 'brick') return canvasTex(256, 128, (g, w, h) => {
    g.fillStyle = Bc; g.fillRect(0, 0, w, h); const base = hexRgb(A);
    for (let r = 0; r < 4; r++) for (let c = -1; c < 5; c++) { const x = c * 64 + (r % 2 ? 32 : 0); g.fillStyle = rgbStr(base, (Math.random() - 0.5) * 30); g.fillRect(x + 2, r * 32 + 2, 60, 28); }
  }, [10, 6]);
  if (p.wall === 'damask') return canvasTex(128, 128, (g, w, h) => {
    g.fillStyle = A; g.fillRect(0, 0, w, h); g.fillStyle = Bc;
    const dia = (x, y, s) => { g.beginPath(); g.moveTo(x, y - s); g.lineTo(x + s * 0.7, y); g.lineTo(x, y + s); g.lineTo(x - s * 0.7, y); g.closePath(); g.fill(); };
    dia(32, 32, 18); dia(96, 96, 18); g.fillStyle = 'rgba(255,255,255,.05)'; dia(96, 32, 8); dia(32, 96, 8);
  }, [14, 3]);
  if (p.wall === 'panel') return canvasTex(128, 256, (g, w, h) => {
    g.fillStyle = A; g.fillRect(0, 0, w, h * 0.6); g.fillStyle = 'rgba(255,255,255,.04)'; g.fillRect(0, 0, w / 2, h * 0.6);
    g.fillStyle = Bc; g.fillRect(0, h * 0.6, w, h * 0.4); g.strokeStyle = 'rgba(255,255,255,.08)'; g.lineWidth = 2; g.strokeRect(12, h * 0.64, w - 24, h * 0.32);
    g.fillStyle = 'rgba(0,0,0,.4)'; g.fillRect(0, h * 0.6 - 4, w, 6);
  }, [12, 1]);
  return canvasTex(128, 128, (g, w, h) => { g.fillStyle = A; g.fillRect(0, 0, w, h); g.fillStyle = Bc; g.fillRect(0, 0, w / 2, h); g.fillStyle = 'rgba(255,255,255,.06)'; for (let i = 0; i < 4; i++) { g.beginPath(); g.arc(w * 0.75, i * 32 + 16, 5, 0, 7); g.fill(); } }, [12, 3]);
}
function buildShell(d) {
  const p = d.pal;
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(W, H), T(0xffffff, { map: floorTexture(p) }));
  floor.rotation.x = -Math.PI / 2; floor.position.set(W / 2, 0, H / 2); floor.receiveShadow = true; add(floor);
  const wt = wallTexture(p), wt2 = wt.clone(); wt2.needsUpdate = true; wt2.repeat.set(wt.repeat.x * H / W, wt.repeat.y);
  const wm = T(0xffffff, { map: wt }), wm2 = T(0xffffff, { map: wt2 });
  box(W + 20, 260, 10, wm, W / 2, 130, -5, { line: false, cast: false });
  box(W + 20, 260, 10, wm, W / 2, 130, H + 5, { line: false });
  box(10, 260, H, wm2, -5, 130, H / 2, { line: false }); box(10, 260, H, wm2, W + 5, 130, H / 2, { line: false });
  const bm = T(p.trim);
  box(W, 12, 3, bm, W / 2, 6, H - 1.5, { block: false, line: false }); box(3, 12, H, bm, 1.5, 6, H / 2, { block: false, line: false }); box(3, 12, H, bm, W - 1.5, 6, H / 2, { block: false, line: false });
  const ceil = new THREE.Mesh(new THREE.PlaneGeometry(W + 20, H + 20), T(p.ceil)); ceil.rotation.x = Math.PI / 2; ceil.position.set(W / 2, 262, H / 2); add(ceil);
  const mold = T(shade(p.ceil, 1.6)); box(W, 8, 8, mold, W / 2, 256, 4, { block: false, line: false }); box(8, 8, H, mold, 4, 256, H / 2, { block: false, line: false }); box(8, 8, H, mold, W - 4, 256, H / 2, { block: false, line: false }); box(W, 8, 8, mold, W / 2, 256, H - 4, { block: false, line: false });
  // ceiling lamp
  const cx = 480, cz = 300;
  if (d.lamp === 'bulb') { cyl(0.6, 56, T(0x1a1a22), cx, 234, cz, { line: false }); cyl(3, 8, T(0x3a3a40), cx, 204, cz, { line: false }); const b = new THREE.Mesh(new THREE.SphereGeometry(6, 12, 10), lampBulbMat); b.position.set(cx, 196, cz); add(b); }
  else if (d.lamp === 'chandelier') { cyl(0.8, 36, T(0x8a6a3a), cx, 244, cz, { line: false }); const rg = new THREE.Mesh(new THREE.TorusGeometry(34, 1.6, 8, 32), T(0xc9a35a)); rg.rotation.x = Math.PI / 2; rg.position.set(cx, 224, cz); add(rg);
    for (let i = 0; i < 6; i++) { const a = i / 6 * Math.PI * 2, b = new THREE.Mesh(new THREE.SphereGeometry(4, 10, 8), lampBulbMat); b.position.set(cx + Math.cos(a) * 34, 229, cz + Math.sin(a) * 34); add(b); } }
  else { cyl(0.6, 26, T(0x1a1a22), cx, 249, cz, { line: false }); const sh = new THREE.Mesh(new THREE.ConeGeometry(26, 20, 28, 1, true), T(0xd9c39a, { side: THREE.DoubleSide })); sh.position.set(cx, 226, cz); add(sh); outline(sh, 1); const b = new THREE.Mesh(new THREE.SphereGeometry(7, 12, 10), lampBulbMat); b.position.set(cx, 214, cz); add(b); }
}
function buildWindow(w) {
  const cx = w.x + w.w / 2, cy = w.y || 170, ww = w.w, wh = w.h || 110;
  const win = new THREE.Mesh(new THREE.PlaneGeometry(ww, wh), new THREE.MeshBasicMaterial({ map: skyTex })); win.position.set(cx, cy, 0.5); add(win);
  const fr = T(0x2a2e40);
  box(4, wh, 3, fr, cx, cy, 1.5, { block: false, line: false }); box(ww, 4, 3, fr, cx, cy, 1.5, { block: false, line: false });
  box(ww + 16, 8, 6, fr, cx, cy + wh / 2 + 4, 2, { block: false, line: false }); box(ww + 16, 10, 10, fr, cx, cy - wh / 2 - 5, 4, { block: false, line: false });
  const top = cy + wh / 2, bot = cy - wh / 2, x0 = cx - ww / 2, x1 = cx + ww / 2, sp = ww * 0.05;
  const v = [[x0, top, 1], [x1, top, 1], [x1, bot, 1], [x0, bot, 1], [x0 - sp, 1, 250], [x1 + sp, 1, 250], [x1 + sp * 2, 1, 430], [x0 - sp * 2, 1, 430]];
  const pos = new Float32Array([0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5, 2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7].flatMap(i => v[i]));
  const bg = new THREE.BufferGeometry(); bg.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  add(new THREE.Mesh(bg, new THREE.MeshBasicMaterial({ color: 0x8fa6dd, transparent: true, opacity: 0.045, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide })));
  const pool = new THREE.Mesh(new THREE.PlaneGeometry(ww + 80, 220), new THREE.MeshBasicMaterial({ map: glowTex, color: 0x7d93cf, transparent: true, opacity: 0.35, blending: THREE.AdditiveBlending, depthWrite: false }));
  pool.rotation.x = -Math.PI / 2; pool.position.set(cx, 0.8, 340); add(pool);
  const N = Math.round(260 * ww / 220), dp = new Float32Array(N * 3), seeds = [];
  for (let i = 0; i < N; i++) { const t = Math.random(); const x = lerp(x0 + 10, x1 - 10, Math.random()), y = lerp(top, 8, t), z = lerp(10, 400, t) + (Math.random() - 0.5) * 60; dp.set([x, y, z], i * 3); seeds.push([x, y, z, Math.random() * 6]); }
  const dg = new THREE.BufferGeometry(); dg.setAttribute('position', new THREE.BufferAttribute(dp, 3));
  add(new THREE.Points(dg, new THREE.PointsMaterial({ color: 0xdfe6ff, size: 2.2, map: glowTex, transparent: true, opacity: 0.7, depthWrite: false, blending: THREE.AdditiveBlending })));
  L.dust = { dg, dp, seeds };
  moon.position.set(cx, 360, -320); moon.target.position.set(cx, 0, 330);
}
function buildDoor(y) {
  const pv = new THREE.Group(); pv.position.set(957, 0, y - 45); add(pv); L.doorPivot = pv;
  const dp = new THREE.Mesh(new THREE.PlaneGeometry(90, 200), new THREE.MeshBasicMaterial({ color: 0x2a1d16 })); dp.position.set(959.4, 100, y); dp.rotation.y = -Math.PI / 2; add(dp);
  const fr = T(0x2a2e40); box(6, 206, 6, fr, 957, 103, y - 48, { block: false, line: false }); box(6, 206, 6, fr, 957, 103, y + 48, { block: false, line: false }); box(6, 6, 102, fr, 957, 203, y, { block: false, line: false });
  const panel = new THREE.Mesh(new THREE.BoxGeometry(4, 198, 88), T(0x8a6a4e)); panel.position.set(0, 99, 44); panel.castShadow = true; pv.add(panel); outline(panel, 1.2);
  const knob = new THREE.Mesh(new THREE.SphereGeometry(3, 8, 6), T(0xd8c49a)); knob.position.set(-3, 95, 78); pv.add(knob);
  hallLight.position.set(925, 140, y);
}
function curtains(w) {
  const cx = w.x + w.w / 2, cy = w.y || 170, wh = w.h || 110;
  const ct = canvasTex(64, 64, g => { for (let x = 0; x < 64; x++) { const v = Math.sin(x / 64 * Math.PI * 6) * 0.5 + 0.5; g.fillStyle = 'rgb(' + (140 + v * 40) + ',' + (70 + v * 22) + ',' + (78 + v * 24) + ')'; g.fillRect(x, 0, 1, 64); } });
  const cm = T(0xffffff, { map: ct }), hgt = wh + 50;
  box(34, hgt, 5, cm, w.x - 22, cy + 2, 8, { block: false, line: false }); box(34, hgt, 5, cm, w.x + w.w + 22, cy + 2, 8, { block: false, line: false });
  const rod = cyl(1.6, w.w + 90, T(0x2a2e40), cx, cy + hgt / 2 + 4, 10, { line: false }); rod.rotation.z = Math.PI / 2;
}
function rug(x, y, w, h, base, border) {
  const t = canvasTex(256, 192, (g, cw, ch) => { g.fillStyle = base; g.fillRect(0, 0, cw, ch); g.strokeStyle = border; g.lineWidth = 6; g.strokeRect(14, 14, cw - 28, ch - 28); g.lineWidth = 2; g.strokeRect(26, 26, cw - 52, ch - 52);
    g.fillStyle = 'rgba(255,255,255,.08)'; for (let i = 0; i < 5; i++) { g.beginPath(); g.moveTo(cw / 2, 40 + i * 24); g.lineTo(cw / 2 + 30, 52 + i * 24); g.lineTo(cw / 2, 64 + i * 24); g.lineTo(cw / 2 - 30, 52 + i * 24); g.fill(); } });
  const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), T(0xffffff, { map: t })); m.rotation.x = -Math.PI / 2; m.position.set(x, 0.35, y); m.receiveShadow = true; add(m);
}
function wallArt(wall, pos, y, w, h, draw) {
  const t = canvasTex(128, Math.round(128 * h / w), draw), m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ map: t }));
  const fr = T(0x3a2a1a);
  if (wall === 'n') { m.position.set(pos, y, 1.2); add(m); box(w + 8, h + 8, 2, fr, pos, y, 0.4, { block: false, line: false }); }
  else { m.position.set(W - 1.2, y, pos); m.rotation.y = -Math.PI / 2; add(m); box(2, h + 8, w + 8, fr, W - 0.4, y, pos, { block: false, line: false }); }
}
const DECOR = {
  kitchen(d) {
    const cabM = T(0x6f5a4c), lineM = T(0x2e241d), knobM = T(0xd8c49a);
    const cab = (x0, x1) => { const w = x1 - x0; box(w, 74, 34, cabM, x0 + w / 2, 190, 17); const n = Math.max(1, Math.round(w / 64)); for (let i = 1; i < n; i++) box(1.6, 70, 0.6, lineM, x0 + i * w / n, 190, 34.4, { block: false, line: false }); for (let i = 0; i < n; i++) { const k = new THREE.Mesh(new THREE.SphereGeometry(2.2, 8, 6), knobM); k.position.set(x0 + (i + 0.5) * w / n + (i % 2 ? -11 : 11), 162, 35); add(k); } };
    cab(0, 392); cab(648, 830);
    const tile = canvasTex(128, 128, (g, w, h) => { g.fillStyle = '#8f9cb8'; g.fillRect(0, 0, w, h); g.strokeStyle = '#5d6887'; g.lineWidth = 3; for (let i = 0; i <= 4; i++) { g.beginPath(); g.moveTo(i * 32, 0); g.lineTo(i * 32, h); g.moveTo(0, i * 32); g.lineTo(w, i * 32); g.stroke(); } });
    [[0, 392], [648, 830]].forEach(([a, b]) => { const t = tile.clone(); t.needsUpdate = true; t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set((b - a) / 48, 1.2); const m = new THREE.Mesh(new THREE.PlaneGeometry(b - a, 58), T(0xffffff, { map: t })); m.position.set((a + b) / 2, 123, 0.7); add(m); });
    curtains(d.window);
    const potM = T(0xc06a46), lm = [T(0x5e9a5a), T(0x4a8048)];
    [[452, 0], [596, 1]].forEach(([x, v]) => { cyl(6, 10, potM, x, 121, 8, { r2: 7.5 }); for (let i = 0; i < 5; i++) { const lf = new THREE.Mesh(new THREE.ConeGeometry(2.6, 16 + v * 6, 5), lm[i % 2]); lf.position.set(x + Math.cos(i * 1.26) * 3, 134 + v * 2, 8 + Math.sin(i * 1.26) * 3); lf.rotation.set(Math.sin(i * 1.26) * 0.5, 0, -Math.cos(i * 1.26) * 0.5); add(lf); outline(lf, 0.6); } });
    box(90, 2, 44, T(0xa3abb6), 305, 93, 36, { block: false, t: 0.8 }); box(120, 3, 52, T(0x22232b), 620, 93.5, 36, { block: false, t: 0.8 });
    [[595, 24], [645, 24], [595, 48], [645, 48]].forEach(([x, z]) => { const r = new THREE.Mesh(new THREE.TorusGeometry(9, 1.4, 6, 20), T(0x3a3b46)); r.rotation.x = Math.PI / 2; r.position.set(x, 95.5, z); add(r); });
    const kM = T(0x4f9a96), k = new THREE.Mesh(new THREE.SphereGeometry(12, 16, 12), kM); k.scale.y = 0.85; k.position.set(645, 106, 48); k.castShadow = true; add(k); outline(k, 1);
    const spt = cyl(2, 14, kM, 656, 108, 48, { line: false }); spt.rotation.z = -1.0;
    box(30, 20, 18, T(0xd5dae2), 150, 103, 30); box(48, 2.5, 30, T(0xc9a06c), 226, 94.5, 42, { block: false });
    const art = (fn, x, y, w, h) => { const t = canvasTex(128, 160, fn); const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ map: t })); m.position.set(x, y, 182.7); add(m); };
    art((g, w, h) => { g.fillStyle = '#f4f0e6'; g.fillRect(0, 0, w, h); g.fillStyle = '#f2c14e'; g.beginPath(); g.arc(98, 30, 18, 0, 7); g.fill(); g.fillStyle = '#e8664a'; g.fillRect(28, 80, 60, 50); g.fillStyle = '#8a4a2a'; g.beginPath(); g.moveTo(20, 82); g.lineTo(58, 46); g.lineTo(96, 82); g.fill(); g.fillStyle = '#5e9a5a'; g.fillRect(0, 130, w, 30); }, 866, 140, 26, 32);
    art((g, w, h) => { g.fillStyle = '#eef3f8'; g.fillRect(0, 0, w, h); g.strokeStyle = '#e08c3e'; g.lineWidth = 8; g.beginPath(); g.arc(64, 90, 34, 0, 7); g.stroke(); g.beginPath(); g.moveTo(40, 62); g.lineTo(46, 36); g.lineTo(58, 58); g.moveTo(70, 58); g.lineTo(82, 36); g.lineTo(88, 62); g.stroke(); g.fillStyle = '#333'; g.fillRect(50, 84, 6, 6); g.fillRect(72, 84, 6, 6); }, 918, 118, 24, 30);
    const clk = new THREE.Group(); clk.position.set(957, 188, 470); clk.rotation.y = -Math.PI / 2; add(clk);
    clk.add(new THREE.Mesh(new THREE.CircleGeometry(22, 32), T(0xf4f0e6))); clk.add(new THREE.Mesh(new THREE.TorusGeometry(22, 2.4, 8, 32), T(0x2a2e40)));
    for (let i = 0; i < 12; i++) { const tk = new THREE.Mesh(new THREE.BoxGeometry(1.2, i % 3 ? 3 : 5, 0.5), new THREE.MeshBasicMaterial({ color: 0x2a2e40 })); const a = i / 12 * Math.PI * 2; tk.position.set(Math.sin(a) * 18, Math.cos(a) * 18, 0.4); tk.rotation.z = -a; clk.add(tk); }
    const hand = (len, wd) => { const pv = new THREE.Group(); pv.position.z = 0.8; clk.add(pv); const hm = new THREE.Mesh(new THREE.BoxGeometry(wd, len, 0.5), new THREE.MeshBasicMaterial({ color: 0x1a1c26 })); hm.position.y = len / 2 - 2; pv.add(hm); return pv; };
    L.clock = { h: hand(12, 2.4), m: hand(17, 1.6) };
    const nl = new THREE.Mesh(new THREE.BoxGeometry(2, 8, 6), new THREE.MeshBasicMaterial({ color: 0xffd9a0 })); nl.position.set(958, 40, 560); add(nl);
    rug(722, 446, 270, 200, '#7a2f3a', '#e6cf9e');
    if (d.bowl) { cyl(16, 6, T(0xc4483a), d.bowl[0], 3, d.bowl[1], { r2: 13, seg: 20 }); cyl(12, 1, T(0x8a6a3a), d.bowl[0], 6.2, d.bowl[1], { line: false }); }
  },
  living(d) {
    rug(480, 280, 440, 250, '#2f4f5a', '#d8c49a'); curtains(d.window);
    wallArt('n', 190, 165, 90, 64, (g, w, h) => { const gr = g.createLinearGradient(0, 0, 0, h); gr.addColorStop(0, '#f0b070'); gr.addColorStop(1, '#5a7aa8'); g.fillStyle = gr; g.fillRect(0, 0, w, h); g.fillStyle = '#2a3a4a'; g.beginPath(); g.moveTo(0, h); g.lineTo(40, h * 0.5); g.lineTo(70, h * 0.75); g.lineTo(100, h * 0.4); g.lineTo(w, h); g.fill(); });
    wallArt('e', 390, 170, 70, 90, (g, w, h) => { g.fillStyle = '#e8dcc8'; g.fillRect(0, 0, w, h); g.fillStyle = '#c95b4a'; g.beginPath(); g.arc(w / 2, h * 0.45, w * 0.28, 0, 7); g.fill(); g.fillStyle = '#4a8a5a'; g.fillRect(w * 0.47, h * 0.6, w * 0.06, h * 0.3); });
  },
  pantry() {
    const pm = T(0x8a8f98); const p1 = cyl(4, W, pm, W / 2, 240, 30, { line: false }); p1.rotation.z = Math.PI / 2; const p2 = cyl(3, W, T(0x9a6a4a), W / 2, 230, 50, { line: false }); p2.rotation.z = Math.PI / 2;
    cyl(3, 30, pm, 600, 245, 30, { line: false });
    [[30, 300], [40, 450]].forEach(([x, y]) => { const s = new THREE.Mesh(new THREE.SphereGeometry(1, 12, 10), T(0xb89a6a)); s.scale.set(22, 26, 18); s.position.set(x - 10, 18, y); s.castShadow = true; add(s); outline(s, 1); });
  },
  dining(d) {
    rug(480, 280, 420, 260, '#5a1f2a', '#d8b46a'); curtains(d.window);
    wallArt('n', 190, 165, 110, 76, (g, w, h) => { g.fillStyle = '#2a3a2a'; g.fillRect(0, 0, w, h); g.fillStyle = '#d8b04a'; for (let i = 0; i < 5; i++) { g.beginPath(); g.arc(20 + i * 22, h * 0.6, 8, 0, 7); g.fill(); } g.fillStyle = '#e8dcc8'; g.fillRect(10, h * 0.7, w - 20, 6); });
    wallArt('e', 480, 160, 64, 84, (g, w, h) => { g.fillStyle = '#1a1a2a'; g.fillRect(0, 0, w, h); g.fillStyle = '#e6c88a'; g.beginPath(); g.ellipse(w / 2, h * 0.42, w * 0.22, h * 0.26, 0, 0, 7); g.fill(); g.fillStyle = '#5a2a2a'; g.fillRect(w * 0.3, h * 0.68, w * 0.4, h * 0.3); });
  },
};
const KNOCK_INFO = {
  cup: { word: 'the cup', text: 'Clink!', snd: 'clink' }, glass: { word: 'the glass', text: 'Clink!', snd: 'clink' },
  vase: { word: 'the vase', text: 'Crash!', snd: 'crash' }, jar: { word: 'the jar', text: 'Bang!', snd: 'bang' },
  bottle: { word: 'the bottle', text: 'Bang!', snd: 'bang' }, apple: { word: 'the apple', text: 'Thud!', snd: 'thud' },
  book: { word: 'the book', text: 'Thud!', snd: 'thud' }, can: { word: 'the can', text: 'Clang!', snd: 'bang' },
};
function knockMesh(kind) {
  const g = new THREE.Group(), P = PARENT; PARENT = g;
  if (kind === 'cup') { cyl(5, 9, T(0xf0ece2), 0, 4.5, 0, { r2: 6 }); const h = new THREE.Mesh(new THREE.TorusGeometry(3, 1, 6, 12), T(0xf0ece2)); h.position.set(6.5, 5, 0); g.add(h); }
  else if (kind === 'jar') { cyl(6, 14, T(0x7fb0a8), 0, 7, 0); cyl(6.5, 3, T(0xc4483a), 0, 15, 0); }
  else if (kind === 'apple') { const a = new THREE.Mesh(new THREE.SphereGeometry(8, 16, 12), T(0xc93b2e)); a.position.y = 8; a.castShadow = true; outline(a, 1); g.add(a); cyl(0.8, 5, T(0x5a3a1a), 0, 17, 0, { line: false }); }
  else if (kind === 'vase') { cyl(5, 22, T(0x4a7ab8), 0, 11, 0, { r2: 3.5, seg: 14 }); const f = new THREE.Mesh(new THREE.SphereGeometry(4, 8, 6), T(0xe8664a)); f.position.y = 26; g.add(f); }
  else if (kind === 'book') { box(16, 4, 22, T(0xa83a3a), 0, 2, 0, { block: false }); box(15, 3.5, 21, T(0x3a6aa8), 1, 5.5, 0, { block: false }); }
  else if (kind === 'glass') { cyl(4, 12, T(0xcfe0ee, { transparent: true, opacity: 0.6 }), 0, 6, 0, { r2: 5 }); cyl(4.6, 3, T(0x8a2a3a), 0, 3, 0, { line: false }); }
  else if (kind === 'bottle') { cyl(5, 18, T(0x3a6a3a), 0, 9, 0); cyl(1.8, 8, T(0x3a6a3a), 0, 22, 0); }
  else { cyl(5, 12, T(0xc0c4cc), 0, 6, 0); cyl(5.1, 6, T(0xc95b4a), 0, 6, 0, { line: false }); }
  PARENT = P; add(g); return g;
}
function surfaceAt(x, y) { let best = null; for (const s of L.surfaces) if (s.h > 0 && s.rects.some(r => inRect(x, y, r)) && (!best || s.h > best.h)) best = s; return best; }

function disposeWorld() {
  if (!world) return; scene.remove(world);
  world.traverse(o => { if (o.geometry && o.geometry !== cheeseGeo && o.geometry !== crumbGeo) o.geometry.dispose(); });
}
function buildLevel(i) {
  disposeWorld();
  world = new THREE.Group(); scene.add(world); PARENT = world; camBlock = []; fadeables = [];
  const d = LEVELS[i];
  L = { i, d, solids: [], hides: [], blockers: [], surfaces: [{ id: 'floor', h: 0, rects: [] }], fades: [], flickers: [], knocks: [], door: d.door, crackle: null, clock: null, dust: null, doorPivot: null };
  const p = d.pal;
  scene.background.set(p.fog); scene.fog.color.set(p.fog); hemi.color.set(p.sky); hemi.groundColor.set(p.ground); hemi.intensity = p.hemi; moon.intensity = p.moon;
  buildShell(d);
  d.furn.forEach(f => B[f.t](f));
  buildDoor(d.door);
  if (d.window) buildWindow(d.window);
  if (DECOR[d.decor]) DECOR[d.decor](d);
  // cat bed
  cyl(28, 6, T(0x7a6a9a), d.catBed[0], 3, d.catBed[1], { seg: 24 }); const rim = new THREE.Mesh(new THREE.TorusGeometry(28, 5, 8, 24), T(0x5a4a7a)); rim.rotation.x = Math.PI / 2; rim.position.set(d.catBed[0], 6, d.catBed[1]); add(rim);
  // lights
  (d.lights || []).forEach(l => { const lt = new THREE.PointLight(l.c, l.i, l.r, 2); lt.position.set(l.x, l.h, l.y); add(lt); });
  // soft contact shadows
  const cs = (r, op) => { const m = new THREE.Mesh(new THREE.PlaneGeometry(r.w * 1.45 + 20, r.h * 1.45 + 20), new THREE.MeshBasicMaterial({ map: softRect, transparent: true, opacity: op, depthWrite: false })); m.rotation.x = -Math.PI / 2; m.position.set(r.x + r.w / 2, 0.55, r.y + r.h / 2); add(m); };
  L.solids.forEach(r => cs(r, 0.5)); L.hides.forEach(r => cs(r, r.kind === 'table' ? 0.35 : 0.3));
  // knockables
  (d.knocks || []).forEach(k => { const s = surfaceAt(k.x, k.y); if (!s) return; const info = KNOCK_INFO[k.kind]; L.knocks.push({ kind: k.kind, x: k.x, y: k.y, to: k.to, h: s.h, surf: s.id, word: info.word, text: info.text, snd: info.snd, done: false, fall: null, mesh: knockMesh(k.kind) }); });
  // cracks: small gaps at the bottom of the walls the rat can squeeze into
  (d.cracks || []).forEach(c => {
    const sz = 28, r = c.wall === 's' ? R(c.x - 20, H - sz, 40, sz) : c.wall === 'w' ? R(0, c.y - 20, sz, 40) : c.wall === 'e' ? R(W - sz, c.y - 20, sz, 40) : R(c.x - 20, 0, 40, sz);
    L.hides.push({ x: r.x, y: r.y, w: r.w, h: r.h, kind: 'crack', land: true });
    const hm = new THREE.Mesh(new THREE.CircleGeometry(13, 20, 0, Math.PI), new THREE.MeshBasicMaterial({ color: 0x050506 }));
    if (c.wall === 's') { hm.position.set(c.x, 0.2, H - 3.2); hm.rotation.y = Math.PI; }
    else if (c.wall === 'w') { hm.position.set(3.2, 0.2, c.y); hm.rotation.y = Math.PI / 2; }
    else if (c.wall === 'e') { hm.position.set(W - 3.2, 0.2, c.y); hm.rotation.y = -Math.PI / 2; }
    else hm.position.set(c.x, 0.2, 0.8);
    add(hm);
  });
  // floor outlines that show where the rat can hide; they brighten as she gets closer
  L.marks = L.hides.map(r => { const m = new THREE.Mesh(new THREE.PlaneGeometry(r.w + 10, r.h + 10), new THREE.MeshBasicMaterial({ map: hideTex, color: 0x9be06a, transparent: true, opacity: 0, depthWrite: false, blending: THREE.AdditiveBlending })); m.rotation.x = -Math.PI / 2; m.position.set(r.x + r.w / 2, 0.75, r.y + r.h / 2); m.visible = false; add(m); return { m, r }; });
  L.losRects = [...L.solids, ...L.blockers];
  L.catBlock = [...L.solids, ...L.hides];
  L.grid = makeGrid([...L.solids, ...L.hides], 17);
  L.gridV = makeGrid(L.solids, 18);
  L.highSurf = L.surfaces.filter(s => s.h >= 25 && s.food !== false);
  PARENT = scene;
  applyQualityShadows(true);
}

// ================= NAVIGATION (A* on a 20 cm grid) =================
function makeGrid(rects, m) { const g = new Uint8Array(GW * GH); for (let gy = 0; gy < GH; gy++) for (let gx = 0; gx < GW; gx++) { const x = (gx + 0.5) * CELL, y = (gy + 0.5) * CELL; g[gy * GW + gx] = (x < 18 || x > W - 18 || y < 18 || y > H - 18 || rects.some(r => inRect(x, y, r, m))) ? 1 : 0; } return g; }
const cellOf = (x, y) => [clamp(Math.floor(x / CELL), 0, GW - 1), clamp(Math.floor(y / CELL), 0, GH - 1)];
const blockedAt = (g, x, y) => { const [gx, gy] = cellOf(x, y); return g[gy * GW + gx] === 1; };
function nearestFree(g, gx, gy) {
  if (!g[gy * GW + gx]) return [gx, gy];
  const seen = new Uint8Array(GW * GH), q = [[gx, gy]]; seen[gy * GW + gx] = 1;
  while (q.length) { const [x, y] = q.shift(); for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) { const nx = x + dx, ny = y + dy; if (nx < 0 || ny < 0 || nx >= GW || ny >= GH) continue; const k = ny * GW + nx; if (seen[k]) continue; seen[k] = 1; if (!g[k]) return [nx, ny]; q.push([nx, ny]); } }
  return [gx, gy];
}
const freePoint = (g, x, y) => { const c = nearestFree(g, ...cellOf(x, y)); return [(c[0] + 0.5) * CELL, (c[1] + 0.5) * CELL]; };
function clearLine(g, ax, ay, bx, by) { const d = Math.hypot(bx - ax, by - ay), n = Math.ceil(d / 6); for (let i = 1; i <= n; i++) { const t = i / n; if (blockedAt(g, ax + (bx - ax) * t, ay + (by - ay) * t)) return false; } return true; }
function astar(g, sx, sy, tx, ty) {
  const [ax, ay] = nearestFree(g, ...cellOf(sx, sy)), [bx, by] = nearestFree(g, ...cellOf(tx, ty));
  const N = GW * GH, cost = new Float32Array(N).fill(1e9), came = new Int32Array(N).fill(-1), closed = new Uint8Array(N);
  const start = ay * GW + ax, goal = by * GW + bx, open = [start]; cost[start] = 0;
  const hf = k => Math.hypot(k % GW - bx, Math.floor(k / GW) - by);
  while (open.length) {
    let bi = 0, bf = 1e9; for (let i = 0; i < open.length; i++) { const f = cost[open[i]] + hf(open[i]); if (f < bf) { bf = f; bi = i; } }
    const cur = open[bi]; open.splice(bi, 1); if (cur === goal) break; if (closed[cur]) continue; closed[cur] = 1;
    const cx = cur % GW, cy = Math.floor(cur / GW);
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { if (!dx && !dy) continue;
      const nx = cx + dx, ny = cy + dy; if (nx < 0 || ny < 0 || nx >= GW || ny >= GH) continue; const k = ny * GW + nx; if (g[k] || closed[k]) continue;
      if (dx && dy && (g[cy * GW + nx] || g[ny * GW + cx])) continue;
      const nc = cost[cur] + (dx && dy ? 1.414 : 1); if (nc < cost[k]) { cost[k] = nc; came[k] = cur; open.push(k); } }
  }
  if (came[goal] < 0 && goal !== start) return [];
  const cells = []; for (let k = goal; k !== start && k >= 0; k = came[k]) cells.push([(k % GW + 0.5) * CELL, (Math.floor(k / GW) + 0.5) * CELL]);
  cells.reverse(); if (!blockedAt(g, tx, ty) && cells.length) cells[cells.length - 1] = [tx, ty];
  const out = []; let cx = sx, cy = sy, i = 0;
  while (i < cells.length) { let j = cells.length - 1; while (j > i && !clearLine(g, cx, cy, cells[j][0], cells[j][1])) j--; out.push(cells[j]); cx = cells[j][0]; cy = cells[j][1]; i = j + 1; }
  return out;
}
function randomFree(g, minDist, fx, fy) { for (let t = 0; t < 200; t++) { const gx = Math.floor(Math.random() * GW), gy = Math.floor(Math.random() * GH); if (g[gy * GW + gx]) continue; const x = (gx + 0.5) * CELL, y = (gy + 0.5) * CELL; if (Math.hypot(x - fx, y - fy) >= minDist) return [x, y]; } return [480, 200]; }
function resolve(e, rects) {
  for (const r of rects) { const cx = clamp(e.x, r.x, r.x + r.w), cy = clamp(e.y, r.y, r.y + r.h); let dx = e.x - cx, dy = e.y - cy, d = Math.hypot(dx, dy); if (d < e.r) { if (d === 0) { dx = 0; dy = -1; d = 1; } e.x = cx + dx / d * e.r; e.y = cy + dy / d * e.r; } }
  e.x = clamp(e.x, e.r, W - e.r); e.y = clamp(e.y, e.r, H - e.r);
}
function moveFloor(e, vx, vy, dt, rects) { e.x += vx * dt; resolve(e, rects); e.y += vy * dt; resolve(e, rects); }
function follow(e, speed, dt, rects) {
  if (!e.path.length) return false;
  const p = e.path[0], dx = p[0] - e.x, dy = p[1] - e.y, d = Math.hypot(dx, dy);
  if (d < 6) { e.path.shift(); return e.path.length > 0; }
  e.a += angDiff(e.a, Math.atan2(dy, dx)) * Math.min(1, dt * 7);
  const st = Math.min(speed * dt, d), px = e.x, py = e.y;
  e.x += dx / d * st; e.y += dy / d * st; resolve(e, rects);
  e.speed = Math.hypot(e.x - px, e.y - py) / dt; return true;
}
function los(ax, ay, bx, by, th = 0) { const d = Math.hypot(bx - ax, by - ay), n = Math.ceil(d / 8); for (let i = 1; i < n; i++) { const t = i / n, x = ax + (bx - ax) * t, y = ay + (by - ay) * t; for (const s of L.losRects) if (s.ht > th + 4 && inRect(x, y, s)) return false; } return true; }
const onSurf = (s, x, y, m = 0) => s.rects.some(r => x > r.x + m && x < r.x + r.w - m && y > r.y + m && y < r.y + r.h - m);
const floorFree = (x, y, r) => x > r && x < W - r && y > r && y < H - r && !L.solids.some(s => inRect(x, y, s, r));
const S = id => L.surfaces.find(s => s.id === id);

// ================= STATE =================
let state = 'menu', phase = '', scene_t = 0, clock = 0;
let rat, cat, human, vac, items = [], traps = [], pile = [], msgs = [];
let fed = 0, lives = 3, nightT = 0, evidence = 0, alarm = 0, unseenT = 0, stars = 0, maxStars = 0, levelDone = new Set(), lastStarsShown = -1;
let lightOn = false, humanSees = false, catSees = false, vacSees = false, ratHidden = false;
let camYaw = -Math.PI / 4, camPitch = 0.38, camDist = 82;
let jumpCand = null, knockCand = null, smell = 0, smellTarget = null, sniffCd = 0, refillT = 0, sniffTargets = [], mouseR = false, touchSniff = false;
const tut = { picked: false, delivered: false, cheese: false, sniffed: false, hideT: 0 };
let graceT = 0, run = { catWoke: false, chased: false }, crouchToggle = false, noiseLvl = 0, bumpT = 0, crouchAmt = 0;
let bannerTimer = 0, lastPauseT = 0, runLevel = 0;
const hasWanted = () => !!(L.d.wanted || L.d.threats.length);
const threatStar = t => { const i = L.d.threats.indexOf(t); return i < 0 ? 99 : i + 1; };
const DOOR = () => ({ x: 935, y: L.door });

function clearRun() {
  items.forEach(it => { scene.remove(it.mesh); it.wisps && it.wisps.forEach(w => scene.remove(w.s)); });
  if (rat) rat.carry.forEach(it => ratMesh.userData.mouth.remove(it.mesh));
  traps.forEach(t => { scene.remove(t.mesh); t.wisps && t.wisps.forEach(w => scene.remove(w.s)); });
  pile.forEach(m => scene.remove(m)); trail.forEach(p => scene.remove(p.s)); rings.forEach(r => scene.remove(r.m));
  msgs.forEach(m => m.el.remove());
  items = []; traps = []; pile = []; msgs = []; trail.length = 0; rings.length = 0;
}
function resetRun() {
  clearRun();
  fed = 0; lives = 3; nightT = 0; evidence = 0; alarm = 0; unseenT = 0; stars = 0; maxStars = 0; levelDone = new Set(); lastStarsShown = -1;
  lightOn = false; humanSees = false; catSees = false; refillT = 0;
  rat = { x: nest.cx + 30, y: nest.cz - 5, h: 0, surf: 'floor', r: 9, a: 0, carry: [], step: 0, noiseT: 0, stepT: 0, inNest: true, jump: null, sniffing: false, sniffHold: 0, sniffMin: 0, sniffSnd: 0, retarget: 0, stand: 0, smelled: new Set() };
  sniffTargets = []; streams.forEach(st => { st.op = 0; st.it = null; st.pts.visible = false; }); Object.assign(tut, { picked: false, delivered: false, cheese: false, sniffed: false, crouched: false, hideT: 0 }); crouchToggle = false;
  const bed = L.d.catBed;
  cat = { x: bed[0], y: bed[1], r: 17, a: Math.PI * 0.8, mode: 'sleep', alert: 0, lostT: 0, lastX: 0, lastY: 0, searchT: 0, watchT: 0, idleT: 0, sit: 1, path: [], repath: 0, speed: 0, step: 0, meowT: 0, zzzT: 1, sleep: 1, calmT: 0, stage: 0, peek: 0 };
  const cs = L.d.cat || (L.d.threats.includes('cat') ? 'sleep' : 'away');
  if (cs === 'away') cat.mode = 'away';
  else if (cs === 'awake') { Object.assign(cat, { mode: 'idle', idleT: 2.5, sit: 1, sleep: 0 }); if (L.d.catStart) { cat.x = L.d.catStart[0]; cat.y = L.d.catStart[1]; cat.a = -Math.PI / 2; } }
  graceT = 0;
  run = { catWoke: cs === 'awake', chased: false };
  human = { mode: 'away', x: DOOR().x, y: DOOR().y, a: Math.PI, path: [], r: 20, t: 0, t2: 0, step: 0, speed: 0, seeT: 0, lostT: 0, lowT: 0, sweep: 0, known: false, lastX: 0, lastY: 0, repath: 0, stepD: 0 };
  vac = { on: false, x: L.d.dock[0], y: L.d.dock[1], a: Math.PI, r: 17, path: [], speed: 0, bumpT: 0 };
  L.knocks.forEach(k => { k.done = false; k.fall = null; });
  const fd = foodDef();
  fd.spots.forEach(([type, x, y]) => placeItem(type, x, y));
  for (let i = 0; i < fd.random.crumb; i++) spawnItem('crumb');
  for (let i = 0; i < fd.random.cheese; i++) spawnItem('cheese');
  updHud();
}
function foodDef() {
  const f = L.d.food || {}, open = !!L.d.openFood;
  return { spots: f.spots || [], random: f.random || { crumb: open ? 12 : 4, cheese: open ? 4 : 3 }, refill: f.refill != null ? f.refill : open ? 10 : 5 };
}
function placeItem(type, x, y) {
  const s = surfaceAt(x, y), cheese = type === 'cheese';
  items.push({ x, y, h: s ? s.h : 0, surf: s ? s.id : 'floor', type, poison: false, w: cheese ? 2 : 1, v: cheese ? 5 : 1, rot: Math.random() * 6, mesh: itemMesh(type, false), wisps: cheese ? makeWisps(0) : null, id: Math.random() });
}
function spawnKitchen() { Object.assign(rat, { x: hole.x + 22, y: hole.y - 22, h: 0, surf: 'floor', a: -Math.PI / 4, inNest: false, jump: null }); camYaw = -Math.PI / 4; camPitch = 0.38; }
function spawnItem(type) {
  if (!type) type = Math.random() < 0.3 ? 'cheese' : 'crumb';
  const high = type === 'cheese' ? Math.random() < (L.d.openFood ? 0.45 : 0.8) : Math.random() < 0.25;
  for (let t = 0; t < 200; t++) {
    let x, y, h = 0, surfId = 'floor';
    if (high && L.highSurf.length) { const s = L.highSurf[Math.floor(Math.random() * L.highSurf.length)], r = s.rects[Math.floor(Math.random() * s.rects.length)];
      if (r.w < 28 || r.h < 28) continue; x = r.x + 14 + Math.random() * (r.w - 28); y = r.y + 14 + Math.random() * (r.h - 28); h = s.h; surfId = s.id;
      const top = surfaceAt(x, y); if (top && top.h > h) continue; }
    else { x = 90 + Math.random() * 840; y = 90 + Math.random() * 490; if (Math.hypot(x - hole.x, y - hole.y) < 120 || !floorFree(x, y, 14)) continue; }
    if (L.knocks.some(k => Math.hypot(k.x - x, k.y - y) < 24) || items.some(it => Math.hypot(it.x - x, it.y - y) < 24)) continue;
    const cheese = type === 'cheese', poison = cheese && stars >= threatStar('poison') && Math.random() < 0.45;
    items.push({ x, y, h, surf: surfId, type, poison, w: cheese ? 2 : 1, v: cheese ? 5 : 1, rot: Math.random() * 6, mesh: itemMesh(type, poison), wisps: cheese ? makeWisps(poison ? 0x8fe060 : 0) : null, id: Math.random() });
    return;
  }
}
const carryW = () => rat.carry.reduce((s, i) => s + i.w, 0);
function fmtClock(t = nightT) { const mins = 23 * 60 + Math.floor(t / L.d.night * 360), h = Math.floor(mins / 60) % 24; return (h % 12 || 12) + ':' + String(mins % 60).padStart(2, '0') + (h < 12 ? ' AM' : ' PM'); }
function updHud() {
  $('fed').textContent = Math.min(fed, L.d.goal) + ' / ' + L.d.goal; $('carry').textContent = (rat ? carryW() : 0) + ' / 3';
  $('lives').textContent = '♥'.repeat(Math.max(0, lives)) + '♡'.repeat(Math.max(0, 3 - lives)); $('clock').textContent = fmtClock(); $('starsHud').textContent = starStr(stars);
}
function say(text, x, z, y, col, size = 22) { const el = document.createElement('div'); el.className = 'tag'; el.textContent = text; el.style.color = col; el.style.fontSize = size + 'px'; $('tags').appendChild(el); msgs.push({ el, x, z, y, t: 1.4, rise: 20 }); }
function bubble(text, x, z, y, dur = 2) { const el = document.createElement('div'); el.className = 'bubble'; el.textContent = text; $('tags').appendChild(el); msgs.push({ el, x, z, y, t: dur, rise: 4 }); }
function banner(t, s, dur = 3) { $('bannerT').textContent = t; $('bannerS').textContent = s || ''; $('banner').style.opacity = 1; bannerTimer = dur; }
const fade = on => $('fade').style.opacity = on ? 1 : 0;
const bars = on => stage.classList.toggle('on', on);

// ================= INPUT =================
const keys = {}, pressed = {};
const cvs = renderer.domElement;
let locked = false, hadLock = false, usingTouch = false;
function requestLock() { if (usingTouch || state !== 'play') return; try { const p = cvs.requestPointerLock && cvs.requestPointerLock(); if (p && p.catch) p.catch(() => {}); } catch (e) { /* not allowed right now */ } }
function releaseLock() { if (document.pointerLockElement) document.exitPointerLock(); }
document.addEventListener('pointerlockchange', () => { locked = document.pointerLockElement === cvs; if (!locked && hadLock && state === 'play') { lastPauseT = performance.now(); pause(); } hadLock = locked; });
document.addEventListener('mousemove', e => {
  if (!(locked && state === 'play')) return;
  const k = 0.0026 * settings.sens; camYaw += e.movementX * k; camPitch = clamp(camPitch + (settings.invertY ? -1 : 1) * e.movementY * k, -0.05, 1.25);
});
function firstGesture() { Snd.init(); applySettings(); if (state === 'menu' && !firstGesture.done) Music.play(MENU_MUSIC, true); firstGesture.done = true; }
addEventListener('pointerdown', firstGesture); addEventListener('keydown', firstGesture);
addEventListener('keydown', e => {
  if (!keys[e.code]) pressed[e.code] = true; keys[e.code] = true;
  if (e.code === 'Escape') {
    if (performance.now() - lastPauseT < 350) return;
    if (!$('pSettings').hidden) closeSettings();
    else if (!$('pLevels').hidden) showPanel('pMain');
    else if (state === 'pause') resume();
    else if (state === 'play') pause();
  }
  if (e.code === 'KeyP') { if (state === 'play') pause(); else if (state === 'pause') resume(); }
  if (state === 'intro' && (e.code === 'Space' || e.code === 'Enter')) skipIntro();
  if ((state === 'play' || state === 'intro') && ['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space'].includes(e.code)) e.preventDefault();
});
addEventListener('keyup', e => keys[e.code] = false);
cvs.addEventListener('contextmenu', e => e.preventDefault());
let joy = null, look = null, drag = null, touchRun = false;
cvs.addEventListener('pointerdown', e => {
  const b = cvs.getBoundingClientRect();
  if (e.pointerType === 'mouse') { if (e.button === 2) { mouseR = true; return; } if (state === 'play' && !locked) { requestLock(); drag = { id: e.pointerId, x: e.clientX, y: e.clientY }; } return; }
  usingTouch = true;
  if (e.clientX - b.left < b.width / 2 && !joy) joy = { id: e.pointerId, sx: e.clientX, sy: e.clientY, x: e.clientX, y: e.clientY };
  else look = { id: e.pointerId, x: e.clientX, y: e.clientY };
  cvs.setPointerCapture(e.pointerId);
});
cvs.addEventListener('pointermove', e => {
  if (joy && e.pointerId === joy.id) { joy.x = e.clientX; joy.y = e.clientY; }
  const lk = look && e.pointerId === look.id ? look : (drag && e.pointerId === drag.id && !locked ? drag : null);
  if (lk && state === 'play') { camYaw += (e.clientX - lk.x) * 0.006 * settings.sens; camPitch = clamp(camPitch + (settings.invertY ? -1 : 1) * (e.clientY - lk.y) * 0.004 * settings.sens, -0.05, 1.25); lk.x = e.clientX; lk.y = e.clientY; }
});
const endP = e => { if (joy && e.pointerId === joy.id) joy = null; if (look && e.pointerId === look.id) look = null; if (drag && e.pointerId === drag.id) drag = null; };
cvs.addEventListener('pointerup', endP); addEventListener('pointerup', e => { if (e.button === 2) mouseR = false; }); cvs.addEventListener('pointercancel', endP);
const tbtn = (id, fn) => { const b = $(id); b.addEventListener('pointerdown', e => { e.preventDefault(); fn(true); }); ['pointerup', 'pointercancel', 'pointerleave'].forEach(t => b.addEventListener(t, () => fn(false))); };
tbtn('tJump', d => { if (d) pressed.Space = true; }); tbtn('tSniff', d => touchSniff = d); tbtn('tAct', d => { if (d) pressed.KeyF = true; }); tbtn('tRun', d => touchRun = d);
addEventListener('blur', () => { if (state === 'play') pause(); });

// ================= MENUS & SETTINGS =================
const PANELS = ['pMain', 'pLevels', 'pSettings', 'pPause', 'pResult'];
let settingsReturn = 'pMain';
function showPanel(id) {
  PANELS.forEach(p => $(p).hidden = p !== id); $('overlay').hidden = !id;
  if (id) { const b = $(id).querySelector('button:not([hidden]):not(:disabled)'); if (b) b.focus({ preventScroll: true }); }
}
function hudForPlay(on) { $('stats').hidden = !on; $('statWanted').hidden = !L || !hasWanted(); $('hudTitle').textContent = on && L ? 'Night ' + (L.i + 1) + ' · ' + L.d.name : 'Kitchen Rat'; }
function goMenu() {
  state = 'menu'; releaseLock(); bars(false); fade(false); $('skip').hidden = true; $('touch').hidden = true; hudForPlay(false);
  Snd.hum(0); Music.play(MENU_MUSIC, true); Music.duck(false);
  const next = Math.min(progress.unlocked, LEVELS.length) - 1;
  if (!L || L.i !== next) { buildLevel(next); resetRun(); }
  $('mPlay').textContent = progress.unlocked > 1 ? (progress.unlocked > LEVELS.length ? 'Play again' : 'Continue · Night ' + progress.unlocked) : 'Play';
  showPanel('pMain');
}
function renderLevels() {
  const list = $('levelList'); list.innerHTML = '';
  const ACTS = ['Act 1 · Silence', 'Act 2 · The Owner', 'Act 3 · Traps', 'Act 4 · Siege'];
  for (let i = 0; i < TOTAL_NIGHTS; i++) {
    if (i % 5 === 0) { const h = document.createElement('div'); h.className = 'act'; h.textContent = ACTS[i / 5]; list.appendChild(h); }
    const d = LEVELS[i], p = d ? null : PLANNED[i - LEVELS.length];
    const b = document.createElement('button'); b.className = 'lvl' + (d ? '' : ' soon'); b.type = 'button';
    const locked = !d || i + 1 > progress.unlocked, best = d && progress.best[d.id];
    b.innerHTML = '<span class="n">Night ' + (i + 1) + '</span><span class="t"></span><span class="d"></span>' + (best ? '<span class="b"></span>' : '');
    b.querySelector('.t').textContent = d ? d.name : p[0];
    b.querySelector('.d').textContent = !d ? p[1] + ' In development.' : locked ? 'Finish night ' + i + ' to unlock' : 'Bring ' + d.goal + ' food. ' + (d.blurb || '');
    if (best) b.querySelector('.b').textContent = 'Goals ' + (best.goals || 1) + ' / ' + (d.goals || ['fed']).length + ' · best ' + best.clock;
    b.disabled = locked; if (d) b.addEventListener('click', () => { Snd.fx.click(); startLevel(i); });
    list.appendChild(b);
  }
}
function openSettings(from) { settingsReturn = from; $('stResetMsg').hidden = true; resetArm = 0; $('stReset').textContent = 'Reset progress'; showPanel('pSettings'); }
function closeSettings() { saveSettings(); showPanel(settingsReturn); }
let resetArm = 0;
$('stReset').addEventListener('click', () => {
  if (performance.now() - resetArm < 4000) { progress = { unlocked: 1, best: {} }; saveProgress(); $('stReset').textContent = 'Reset progress'; $('stResetMsg').textContent = 'Progress reset. All nights except the first are locked again.'; $('stResetMsg').hidden = false; resetArm = 0; return; }
  resetArm = performance.now(); $('stReset').textContent = 'Click again to erase progress';
});
function bindSettings() {
  [['sSens', 'sens', v => (+v).toFixed(2) + '×'], ['sFov', 'fov', v => v + '°'], ['sMusic', 'music', v => v + '%'], ['sSfx', 'sfx', v => v + '%']].forEach(([id, key, fmt]) => {
    const el = $(id), out = $('o' + id.slice(1)); el.value = settings[key]; out.textContent = fmt(settings[key]);
    el.addEventListener('input', () => { settings[key] = +el.value; out.textContent = fmt(el.value); applySettings(); saveSettings(); });
  });
  $('sInvert').checked = settings.invertY; $('sInvert').addEventListener('change', () => { settings.invertY = $('sInvert').checked; saveSettings(); });
  $('sHints').checked = settings.hints; $('sHints').addEventListener('change', () => { settings.hints = $('sHints').checked; saveSettings(); });
  $('sQuality').value = settings.quality; $('sQuality').addEventListener('change', () => { settings.quality = $('sQuality').value; saveSettings(); applyQuality(); });
  $('settingsForm').addEventListener('submit', e => e.preventDefault());
}
function applySettings() { camera.fov = settings.fov; camera.updateProjectionMatrix(); Snd.setVolumes(settings.music / 100, settings.sfx / 100); }
function applyQualityShadows(force) {
  const sh = settings.quality !== 'low';
  if (force || renderer.shadowMap.enabled !== sh) {
    renderer.shadowMap.enabled = sh; moon.castShadow = sh;
    scene.traverse(o => { if (o.material) (Array.isArray(o.material) ? o.material : [o.material]).forEach(m => m.needsUpdate = true); });
  }
}
function applyQuality() {
  const q = settings.quality;
  if (moon.shadow.map) { moon.shadow.map.dispose(); moon.shadow.map = null; }
  moon.shadow.mapSize.set(q === 'high' ? 2048 : 1024, q === 'high' ? 2048 : 1024);
  useComposer = !!composer && q !== 'low'; if (bloomPass) bloomPass.enabled = q === 'high';
  applyQualityShadows(false); resize();
}
$('mPlay').addEventListener('click', () => { Snd.fx.click(); startLevel(Math.min(progress.unlocked, LEVELS.length) - 1); });
$('mLevels').addEventListener('click', () => { Snd.fx.click(); renderLevels(); showPanel('pLevels'); });
$('mSettings').addEventListener('click', () => { Snd.fx.click(); openSettings('pMain'); });
$('mQuit').hidden = !DESKTOP; $('mQuit').addEventListener('click', () => window.kitchenRat && window.kitchenRat.quit());
$('lvBack').addEventListener('click', () => showPanel('pMain'));
$('stBack').addEventListener('click', () => { Snd.fx.click(); closeSettings(); });
$('pResume').addEventListener('click', () => resume());
$('pSettingsBtn').addEventListener('click', () => openSettings('pPause'));
$('pRestart').addEventListener('click', () => startLevel(L.i));
$('pMenu').addEventListener('click', () => goMenu());
$('resNext').addEventListener('click', () => startLevel(L.i + 1));
$('resRetry').addEventListener('click', () => startLevel(L.i));
$('resMenu').addEventListener('click', () => goMenu());
$('skip').addEventListener('click', () => skipIntro());

function pause() { if (state !== 'play') return; state = 'pause'; releaseLock(); Music.duck(true); Snd.hum(0); $('pauseText').textContent = 'Night ' + (L.i + 1) + ' · ' + L.d.name + '. The pups are waiting.'; showPanel('pPause'); }
function resume() { if (state !== 'pause') return; state = 'play'; showPanel(null); Music.duck(false); requestLock(); }

// ================= CUTSCENES =================
const introPath = [[nest.cx + 30, nest.cz - 5], [nest.cx - 10, nest.cz - 55], [hole.x + 4, nest.z + 14], [hole.x, nest.z - 4]];
let cues = [], walkSeg = 0;
function startLevel(i) {
  Snd.init(); applySettings();
  runLevel = i; buildLevel(i); resetRun(); hudForPlay(false); showPanel(null);
  state = 'intro'; scene_t = 0; phase = 'sleep'; bars(true); $('skip').hidden = false; $('touch').hidden = true;
  Object.assign(rat, { x: nest.cx + 30, y: nest.cz - 5, h: 0, a: Math.PI * 0.85, inNest: true });
  const it = L.d.intro;
  cues = [[0.7, 0, it.pups[0]], [1.5, 1, it.pups[1]], [2.3, 3, it.pups[2]]].map(c => ({ t: c[0], fn: () => { const p = pups[c[1]]; bubble(c[2], p.bx, p.bz, 20, 1.8); Snd.fx.squeak(1.4 + Math.random() * 0.2, 0.12); } }));
  cues.push({ t: 3.6, fn: () => bubble(it.mom, rat.x, rat.y, 30, 3) });
  camera.position.set(nest.cx + 90, 45, nest.cz + 70); fade(false);
  Music.play(L.d.music);
  banner('Night ' + (i + 1) + ' · ' + L.d.name, '', 2.6);
}
function skipIntro() { if (state !== 'intro' || phase === 'leave') return; phase = 'leave'; scene_t = 0; fade(true); }
function beginPlay() {
  spawnKitchen(); state = 'play'; phase = ''; bars(false); $('skip').hidden = true; $('touch').hidden = !usingTouch;
  msgs.forEach(m => m.el.remove()); msgs = []; hudForPlay(true); updHud();
  camera.position.set(rat.x - 60, 50, rat.y + 60); fade(false);
  const danger = L.d.threats.map(t => THREATS[t].name).join(' → ');
  if (L.d.start) banner(L.d.start.title, L.d.start.sub, 5.5);
  else if (L.d.threats.length) banner('Bring ' + L.d.goal + ' food before dawn', (L.d.openFood ? '' : 'Food is hidden: hold E to sniff it out. ') + 'Tonight: ' + danger, 5);
  else banner('Bring ' + L.d.goal + ' food before dawn', 'Everyone is asleep and food is everywhere. Grab what you can!', 4.5);
  requestLock();
}
function intro(dt) {
  scene_t += dt; cues = cues.filter(c => { if (scene_t >= c.t) { c.fn(); return false; } return true; });
  const ud = ratMesh.userData;
  if (phase === 'sleep') { if (scene_t > 3.4) { phase = 'wake'; scene_t = 3.4; } }
  else if (phase === 'wake') { if (scene_t > 6.2) { phase = 'walk'; walkSeg = 0; } }
  else if (phase === 'walk') {
    const tgt = introPath[walkSeg + 1];
    if (tgt) { const dx = tgt[0] - rat.x, dy = tgt[1] - rat.y, d = Math.hypot(dx, dy); if (d < 4) walkSeg++; else { rat.a += angDiff(rat.a, Math.atan2(dy, dx)) * Math.min(1, dt * 8); rat.x += dx / d * 80 * dt; rat.y += dy / d * 80 * dt; rat.step += dt * 12; } }
    else { phase = 'leave'; scene_t = 0; fade(true); }
  } else if (phase === 'leave') { if (scene_t > 0.55) beginPlay(); }
  const wake = phase === 'sleep' ? 0 : phase === 'wake' ? ease(clamp01((scene_t - 3.4) / 1.2)) : 1;
  ud.body.scale.set(lerp(12.5, 11, wake), lerp(5, 6.5, wake), lerp(8.5, 7, wake));
  ud.body.position.y = lerp(5, 7, wake) + (phase === 'sleep' ? Math.sin(scene_t * 2) * 0.4 : 0);
  ud.headG.position.y = lerp(5, 8, wake); ud.headG.rotation.z = lerp(-0.25, 0, wake);
  ud.eyes.forEach(e => e.scale.y = wake < 0.5 ? 0.15 : 1);
  if (phase === 'wake') rat.a += angDiff(rat.a, Math.PI * 0.75 + Math.sin(scene_t * 3) * 0.3) * dt * 3;
  if (phase === 'sleep' || phase === 'wake') {
    const a = 0.5 + scene_t * 0.09, r = lerp(95, 70, clamp01(scene_t / 5));
    camera.position.lerp(new THREE.Vector3(nest.cx + 15 + Math.cos(a) * r, lerp(50, 32, clamp01(scene_t / 5)), nest.cz + Math.sin(a) * r * 0.7), Math.min(1, dt * 3)); camera.lookAt(nest.cx + 5, 8, nest.cz);
  } else followCam(dt, rat.a, 0.4);
}
function startOutro() { state = 'outro'; phase = 'in'; scene_t = 0; fade(true); bars(true); releaseLock(); $('touch').hidden = true; Snd.hum(0); hudForPlay(false); Snd.fx.win(); Music.set(0, false); }
function outro(dt) {
  scene_t += dt;
  if (phase === 'in' && scene_t > 0.55) {
    phase = 'eat'; scene_t = 0;
    Object.assign(rat, { x: nest.cx + 38, y: nest.cz - 12, h: 0, a: Math.PI, inNest: true, jump: null });
    camera.position.set(nest.cx + 80, 40, nest.cz + 60); msgs.forEach(m => m.el.remove()); msgs = []; fade(false);
    cues = [[0.6, 0, 'Nom!'], [1.3, 2, 'Thanks, Mom!'], [2.1, 1, 'Cheeese!'], [3, 3, 'I’m full!']].map(c => ({ t: c[0], fn: () => { const p = pups[c[1]]; bubble(c[2], p.bx, p.bz, 20, 1.8); Snd.fx.squeak(1.45, 0.1); } }));
  }
  if (phase === 'eat') {
    cues = cues.filter(c => { if (scene_t >= c.t) { c.fn(); return false; } return true; });
    const a = 0.4 + scene_t * 0.12;
    camera.position.lerp(new THREE.Vector3(nest.cx + 10 + Math.cos(a) * 80, 36, nest.cz + Math.sin(a) * 60), Math.min(1, dt * 2.5)); camera.lookAt(nest.cx + 10, 6, nest.cz);
    if (scene_t > 4.6) finishNight(true);
  }
}
function finishNight(won, title, text) {
  state = 'result'; phase = 'done'; bars(false); releaseLock(); $('touch').hidden = true; Snd.hum(0); hudForPlay(false);
  const id = L.d.id, last = L.i === LEVELS.length - 1;
  const goals = nightGoals(won);
  if (won) {
    progress.unlocked = Math.max(progress.unlocked, L.i + 2);
    const prev = progress.best[id], t = Math.round(nightT), got = goals.filter(g => g.ok).length;
    if (!prev || t < prev.time) progress.best[id] = { time: t, clock: fmtClock(), stars: Math.min(maxStars, prev ? prev.stars : 5), goals: Math.max(got, prev && prev.goals || 0) };
    else { prev.stars = Math.min(prev.stars, maxStars); prev.goals = Math.max(prev.goals || 0, got); }
    saveProgress();
    $('resTitle').textContent = 'Night ' + (L.i + 1) + ' complete';
    $('resText').textContent = last ? 'The pups are fed. That’s every night built so far: nights ' + (LEVELS.length + 1) + '–' + TOTAL_NIGHTS + ' are on the way.' : 'The pups are fed. Tomorrow night: ' + (L.d.teaser || LEVELS[L.i + 1].name);
    $('resNext').hidden = last; $('resRetry').textContent = 'Replay night';
  } else {
    Snd.fx.lose(); Music.set(0, false);
    $('resTitle').textContent = title; $('resText').textContent = text;
    $('resNext').hidden = true; $('resRetry').textContent = 'Try again';
  }
  $('resGoals').innerHTML = '';
  goals.forEach(g => { const li = document.createElement('li'); li.className = g.ok ? 'ok' : 'no'; li.innerHTML = '<i></i><span></span>'; li.querySelector('i').textContent = g.ok ? '✔' : '✖'; li.querySelector('span').textContent = g.label; $('resGoals').appendChild(li); });
  $('resStats').innerHTML = '';
  [[won ? fmtClock() : fmtClock(), won ? 'Finished at' : 'Time'], [Math.min(fed, L.d.goal) + ' / ' + L.d.goal, 'Food'], [String(3 - Math.max(lives, 0)), 'Lives lost'], [starStr(maxStars), 'Top wanted']].forEach(([v, k]) => { const dv = document.createElement('div'); dv.innerHTML = '<b></b><span></span>'; dv.querySelector('b').textContent = v; dv.querySelector('span').textContent = k; $('resStats').appendChild(dv); });
  showPanel('pResult');
}
function lose(title, text) { finishNight(false, title, text); }
function nightGoals(won) {
  const ids = L.d.goals || ['fed'];
  const check = { fed: won, early: won && nightT / L.d.night * 360 < 120, nocatch: lives === 3, sleep: !run.catWoke, unseen: !run.chased };
  return ids.map(id => ({ id, label: GOALS[id], ok: !!check[id] && (id === 'fed' || won) }));
}

// ================= GAMEPLAY =================
// A noise at (x, y) heard within `radius`. `amt` is how much it disturbs a sleeping cat at point-blank range
// (1 = wakes it instantly). Quiet footsteps (radius < 100) don't raise the wanted level.
function noise(x, y, radius, label, big, amt) {
  if (amt == null) amt = big ? 0.9 : radius > 150 ? 0.3 : 0.4;
  addRing(x, y, big, radius < 100 ? 0.35 : 1);
  alarm += big ? 7 : radius > 150 ? 0.5 : radius > 100 ? 2 : 0;
  if (label) say(label, x, y, 24, '#f2c14e', 20);
  if ((human.mode === 'patrol' || human.mode === 'look') && Math.hypot(human.x - x, human.y - y) < (big ? 700 : 320)) { human.mode = 'patrol'; human.path = astar(L.grid, human.x, human.y, x, y); human.lastX = x; human.lastY = y; human.known = true; }
  if (cat.mode === 'away') return;
  const dc = Math.hypot(cat.x - x, cat.y - y);
  if (cat.mode === 'sleep') {
    if (dc >= radius) return;
    cat.sleep -= amt * (1 - dc / radius) * (1 + stars * 0.25); cat.calmT = 2.5; cat.lastX = x; cat.lastY = y;
    if (cat.sleep <= 0) wakeCat(x, y);
    return;
  }
  const hear = radius * (L.d.catSense || 1);
  if (dc < hear && cat.mode !== 'chase' && cat.mode !== 'watch') {
    cat.mode = 'investigate'; cat.lastX = x; cat.lastY = y; cat.alert = Math.max(cat.alert, radius < 100 ? 0.25 : 0.4); cat.path = astar(L.grid, cat.x, cat.y, x, y); cat.sit = 0;
    if (big || cat.meowT <= 0) { cat.meowT = 2; bubble(big ? 'Meow?' : '?', cat.x, cat.y, 50, 1.2); if (big) Snd.fx.meow('q'); }
  }
}
function wakeCat(x, y) {
  if (cat.mode !== 'sleep') return;
  cat.mode = 'search'; cat.searchT = 1.8; cat.sit = 0.6; cat.sleep = 0; alarm += 4;
  if (x != null) cat.a = Math.atan2(y - cat.y, x - cat.x);
  bubble('MRRAW?!', cat.x, cat.y, 46, 1.6); Snd.fx.meow('q');
  if (state === 'play' && !run.catWoke && L.d.cat === 'sleep') banner('You woke the cat!', 'Now it prowls the room. Stay out of its sight and hide in green spots.', 4.5);
  run.catWoke = true;
}
function findJump() {
  if (rat.jump) return null;
  const cur = S(rat.surf), fx = Math.cos(camYaw), fz = Math.sin(camYaw);
  let best = null, bestScore = 1e9;
  const consider = (s, px, py) => { const dx = px - rat.x, dy = py - rat.y, d = Math.hypot(dx, dy); if (d > 74) return; const dot = d > 1 ? (dx * fx + dy * fz) / d : 1; if (d > 10 && dot < 0.42) return; const score = d * (1.8 - dot) - (s.h < cur.h ? s.h * 0.4 : 0); if (score < bestScore) { bestScore = score; best = { s, x: px, y: py, d }; } };
  for (const s of L.surfaces) {
    if (s.id === rat.surf) continue;
    if (s.h > cur.h) {
      if (s.h - cur.h > 57) continue;
      if (cur.id === 'floor' && s.rects.some(r => inRect(rat.x, rat.y, r))) continue;
      for (const r of s.rects) { const px = clamp(rat.x, r.x + 10, r.x + r.w - 10), py = clamp(rat.y, r.y + 10, r.y + r.h - 10); const top = surfaceAt(px, py); if (top && top.h > s.h) continue; consider(s, px, py); }
    } else {
      const px = rat.x + fx * 46, py = rat.y + fz * 46;
      if (onSurf(cur, px, py, -4)) continue;
      if (s.id === 'floor') { if (!floorFree(px, py, 12) || L.hides.some(r => !r.land && inRect(px, py, r, 4))) continue; }
      else if (!onSurf(s, px, py, 6)) continue;
      const top = surfaceAt(px, py); if (s.id !== 'floor' && top && top.h > s.h) continue;
      consider(s, px, py);
    }
  }
  return best;
}
function doJump(c) { const d = Math.hypot(c.x - rat.x, c.y - rat.y); rat.jump = { fx: rat.x, fy: rat.y, fh: rat.h, tx: c.x, ty: c.y, th: c.s.h, surf: c.s.id, t: 0, dur: 0.34 + d / 420, arc: 14 + Math.max(0, c.s.h - rat.h) * 0.35 }; if (d > 2) rat.a = Math.atan2(c.y - rat.y, c.x - rat.x); Snd.fx.jump(); }
function nearestCheese(withTraps) {
  let best = null, bd = 1e9;
  for (const it of withTraps ? [...items, ...traps.filter(t => !t.sprung)] : items) { if (it.type === 'crumb') continue; const d = Math.hypot(it.x - rat.x, it.y - rat.y) + Math.abs(it.h - rat.h) * 0.6; if (d < bd) { bd = d; best = it; } }
  if (!best) for (const it of items) { const d = Math.hypot(it.x - rat.x, it.y - rat.y); if (d < bd) { bd = d; best = it; } }
  return best ? { it: best, d: bd } : null;
}
function updateSniff(dt) {
  const want = (keys.KeyE || mouseR || touchSniff) && !rat.jump;
  if (want && !rat.sniffing) {
    rat.sniffing = true; rat.sniffHold = 0; rat.sniffMin = 1.0; rat.sniffSnd = 0.4; rat.retarget = 0; tut.sniffed = true; Snd.fx.sniff();
    for (const t of traps) if (!t.sprung && Math.hypot(t.x - rat.x, t.y - rat.y) < 260) { t.reveal = 6; say('Trap!', t.x, t.y, 26, '#e8664a', 18); }
  }
  if (!rat.sniffing) return;
  rat.sniffHold += dt; rat.sniffMin -= dt; rat.sniffSnd -= dt; rat.retarget -= dt;
  if (rat.sniffSnd <= 0) { rat.sniffSnd = 0.75; Snd.fx.sniff(); }
  if (rat.sniffHold > 0.35 && rat.retarget <= 0) { rat.retarget = 0.5; pickScentTargets(); }
  if (!want && rat.sniffMin <= 0) rat.sniffing = false;
}
function pickScentTargets() {
  const first = rat.sniffHold < 0.9;
  const cand = items.map(it => ({ it, d: Math.hypot(it.x - rat.x, it.y - rat.y) + Math.abs(it.h - rat.h) * 0.6 - (it.type === 'cheese' ? 120 : 0) })).filter(c => c.d < 900);
  cand.sort((a, b) => a.d - b.d);
  sniffTargets = cand.slice(0, 3).map(c => c.it);
  sniffTargets.forEach(it => it.reveal = Math.max(it.reveal || 0, 7));
  if (!first) return;
  if (!sniffTargets.length) { bubble('I can’t smell anything…', rat.x, rat.y, rat.h + 34, 1.5); return; }
  const it = sniffTargets[0], rel = angDiff(camYaw, Math.atan2(it.y - rat.y, it.x - rat.x)), ar = Math.abs(rel);
  const dir = ar < 0.5 ? 'ahead' : ar > 2.6 ? 'behind' : rel > 0 ? 'to the right' : 'to the left';
  const up = it.h > rat.h + 20 ? ', up high' : it.h < rat.h - 20 ? ', down low' : '';
  const what = it.poison ? 'Ew, poisoned cheese' : it.type === 'cheese' ? 'Cheese' : 'Crumbs';
  bubble(what + ' ' + dir + up + ' · ' + (Math.round(Math.hypot(it.x - rat.x, it.y - rat.y) / 10) / 10) + ' m', rat.x, rat.y, rat.h + 34, 2.2);
}
function caught(text, x, y, yy, sfx) {
  lives--; Snd.fx[sfx || 'caught'](); if (sfx) Snd.fx.caught();
  rat.carry.forEach(it => { ratMesh.userData.mouth.remove(it.mesh); scene.add(it.mesh); const p = { x: rat.x + (Math.random() - 0.5) * 30, y: rat.y + (Math.random() - 0.5) * 30, r: 8 }; resolve(p, L.solids); Object.assign(it, { x: p.x, y: p.y, h: 0, surf: 'floor' }); if (it.type === 'cheese') it.wisps = makeWisps(it.poison ? 0x8fe060 : 0); items.push(it); });
  rat.carry = []; say(text, x, y, yy, '#e8664a');
  spawnKitchen(); graceT = 3;
  if (cat.mode !== 'sleep' && cat.mode !== 'away') { const t = randomFree(L.grid, 380, hole.x, hole.y); Object.assign(cat, { mode: 'wander', alert: 0, path: astar(L.grid, cat.x, cat.y, t[0], t[1]), sit: 0 }); bubble('Hmph.', cat.x, cat.y, 50, 1.2); }
  alarm += 10; updHud();
  if (lives <= 0) lose('You got caught', 'The pups got ' + fed + ' of ' + L.d.goal + ' and are waiting for Mom. Top wanted level: ' + starStr(maxStars) + '.');
}
function makePoison(it) { it.poison = true; it.mesh.material = poisonMat; if (it.wisps) it.wisps.forEach(w => w.s.material.color.set(0x8fe060)); }
function placeTraps(n) {
  let placed = 0;
  for (let t = 0; t < 500 && placed < n; t++) {
    const [x, y] = randomFree(L.grid, 0, 0, 0);
    if (Math.hypot(x - hole.x, y - hole.y) < 150 || Math.hypot(x - rat.x, y - rat.y) < 90 || Math.hypot(x - DOOR().x, y - DOOR().y) < 70) continue;
    if (traps.some(q => Math.hypot(q.x - x, q.y - y) < 100)) continue;
    if (!L.catBlock.some(r => inRect(x, y, r, 45)) && Math.random() < 0.7) continue;
    traps.push(makeTrap(x + (Math.random() - 0.5) * 8, y + (Math.random() - 0.5) * 8)); placed++;
  }
}
function triggerThreat(t) {
  if (t === 'cat') wakeCat();
  if (t === 'traps') placeTraps(3);
  if (t === 'poison') { const c = items.filter(i => i.type === 'cheese' && !i.poison); if (c.length) makePoison(c[Math.floor(Math.random() * c.length)]); spawnItem('cheese'); }
  if (t === 'vacuum') { vac.on = true; vac.x = L.d.dock[0]; vac.y = L.d.dock[1]; vac.path = []; Snd.fx.beep(); bubble('Beep boop!', vac.x, vac.y, 30, 1.6); }
}
function onStars(ns, os) {
  for (let s = os + 1; s <= ns; s++) {
    if (levelDone.has(s)) continue; levelDone.add(s); Snd.fx.starUp(s);
    const t = L.d.threats[s - 1];
    if (t) { triggerThreat(t); banner('★'.repeat(s) + ' ' + THREATS[t].banner, THREATS[t].tip, 5); }
    else if (!L.d.threats.length) banner('★'.repeat(s) + ' The house is restless', L.d.starTip || 'Everyone is faster and sharper now', 3.5);
    else { banner('★'.repeat(s) + ' High alert', 'Everyone in the house is faster and sharper now', 4.5); if (L.d.threats.includes('traps') && s === 5) placeTraps(2); }
  }
}
function update(dt) {
  nightT += dt;
  if (nightT >= L.d.night) { updHud(); lose('Dawn', 'The owners are waking up. The pups got ' + fed + ' of ' + L.d.goal + '. Top wanted level: ' + starStr(maxStars) + '. There is always tomorrow night.'); return; }
  sniffCd = Math.max(0, sniffCd - dt); graceT = Math.max(0, graceT - dt);
  // --- rat ---
  if (rat.jump) {
    const j = rat.jump; j.t += dt / j.dur; const t = clamp01(j.t);
    rat.x = lerp(j.fx, j.tx, t); rat.y = lerp(j.fy, j.ty, t); rat.h = lerp(j.fh, j.th, t) + Math.sin(Math.PI * t) * j.arc;
    if (j.t >= 1) { rat.h = j.th; rat.surf = j.surf; const drop = j.fh - j.th; rat.jump = null; Snd.fx.land(drop > 50);
      if (rat.surf === 'floor') { const e = { x: rat.x, y: rat.y, r: rat.r }; resolve(e, L.solids); rat.x = e.x; rat.y = e.y; if (drop > 50) noise(rat.x, rat.y, 160, 'Thud', false, 0.55); } }
  } else {
    let fwd = (keys.KeyW || keys.ArrowUp ? 1 : 0) - (keys.KeyS || keys.ArrowDown ? 1 : 0);
    let str = (keys.KeyD || keys.ArrowRight ? 1 : 0) - (keys.KeyA || keys.ArrowLeft ? 1 : 0);
    if (joy) { const dx = joy.x - joy.sx, dy = joy.y - joy.sy, d = Math.hypot(dx, dy); if (d > 8) { str = dx / Math.max(d, 45); fwd = -dy / Math.max(d, 45); } }
    const fx = Math.cos(camYaw), fz = Math.sin(camYaw);
    let mx = fx * fwd - fz * str, mz = fz * fwd + fx * str; const ml = Math.hypot(mx, mz); if (ml > 1) { mx /= ml; mz /= ml; }
    if (pressed.KeyC) crouchToggle = !crouchToggle;
    const moving = ml > 0.1 && !rat.sniffing;
    const crouching = (keys.ControlLeft || keys.ControlRight || crouchToggle) && !(keys.ShiftLeft || keys.ShiftRight || touchRun);
    const sprinting = (keys.ShiftLeft || keys.ShiftRight || touchRun) && moving;
    rat.crouch = crouching; if (crouching && moving) tut.crouched = true;
    const spd = moving ? (sprinting ? 195 : crouching ? 62 : 120) * (1 - 0.13 * carryW()) : 0;
    const px = rat.x, py = rat.y;
    if (rat.surf === 'floor') moveFloor(rat, mx * spd, mz * spd, dt, L.solids);
    else { const s = S(rat.surf), nx = rat.x + mx * spd * dt; if (onSurf(s, nx, rat.y, 4)) rat.x = nx; const ny = rat.y + mz * spd * dt; if (onSurf(s, rat.x, ny, 4)) rat.y = ny; }
    if (moving) { rat.a += angDiff(rat.a, Math.atan2(mz, mx)) * Math.min(1, dt * 14); rat.step += dt * spd * 0.15; rat.stepT -= dt; if (rat.stepT <= 0) { rat.stepT = sprinting ? 0.12 : crouching ? 0.32 : 0.2; Snd.fx.step(sprinting ? 0.05 : crouching ? 0.005 : 0.015); } }
    // footsteps: running is loud, walking is quiet (only heard up close), sneaking is silent
    noiseLvl = !moving ? 0 : sprinting ? 3 : crouching ? 0 : 1;
    rat.noiseT -= dt;
    if (sprinting && rat.noiseT <= 0) { rat.noiseT = 0.35; noise(rat.x, rat.y, 210, null, false, 0.3); }
    else if (noiseLvl === 1 && rat.surf === 'floor' && rat.noiseT <= 0) { rat.noiseT = 0.45; noise(rat.x, rat.y, 95, null, false, 0.1); }
    // running into furniture makes a thump
    bumpT -= dt;
    if (sprinting && rat.surf === 'floor' && bumpT <= 0 && Math.hypot(rat.x - px, rat.y - py) < spd * dt * 0.35) { bumpT = 0.9; Snd.fx.land(false); noise(rat.x, rat.y, 170, 'Thump!', false, 0.45); }
  }
  ratHidden = rat.surf === 'floor' && !rat.jump && (L.hides.some(h => inRect(rat.x, rat.y, h)) || Math.hypot(rat.x - hole.x, rat.y - hole.y) < hole.r);
  // --- actions ---
  jumpCand = findJump(); knockCand = null;
  if (!rat.jump) for (const k of L.knocks) { if (k.done || k.surf !== rat.surf) continue; if (Math.hypot(k.x - rat.x, k.y - rat.y) < 30) { knockCand = k; break; } }
  if (pressed.Space && jumpCand) doJump(jumpCand);
  if (pressed.KeyF && knockCand) { knockCand.done = true; knockCand.fall = { t: 0 }; bubble('Hee hee', rat.x, rat.y, rat.h + 30, 1); }
  updateSniff(dt);
  // --- food ---
  if (!rat.jump) for (let i = items.length - 1; i >= 0; i--) { const it = items[i];
    if (Math.abs(it.h - rat.h) < 10 && Math.hypot(it.x - rat.x, it.y - rat.y) < 17 && carryW() + it.w <= 3) {
      rat.carry.push(it); items.splice(i, 1); ratMesh.userData.mouth.add(it.mesh); it.mesh.visible = true; it.mesh.scale.setScalar(1); tut.picked = true; if (it.type === 'cheese') tut.cheese = true; it.wisps && it.wisps.forEach(w => scene.remove(w.s)); it.wisps = null;
      if (!it.poison) evidence += it.type === 'cheese' ? 9 : 3; updHud();
      if (it.type === 'cheese') { bubble('Cheeese!', rat.x, rat.y, rat.h + 30, 1.2); Snd.fx.cheese(); } else Snd.fx.pickup();
    } }
  if (rat.carry.length && rat.surf === 'floor' && Math.hypot(rat.x - hole.x, rat.y - hole.y) < hole.r + 6) {
    const pz = rat.carry.filter(i => i.poison).length, v = rat.carry.reduce((s, i) => s + (i.poison ? 0 : i.v), 0); fed = Math.max(0, fed + v - pz * 4);
    rat.carry.forEach(it => { ratMesh.userData.mouth.remove(it.mesh); if (!it.poison) addToPile(it.type); });
    const hadCheese = rat.carry.some(i => i.type === 'cheese' && !i.poison); rat.carry = []; updHud(); tut.delivered = true; if (hadCheese) tut.cheese = true;
    if (fed >= L.d.goal) { startOutro(); return; }
    { const rf = foodDef().refill; while (rf && items.length < rf + 3) spawnItem(); }
    if (pz) { say('Poison! −' + pz * 4, hole.x, hole.y, 32, '#9be06a'); bubble('Ew! Tummy ache…', hole.x, hole.y + 8, 22, 2); Snd.fx.poison(); }
    else { say('+' + v, hole.x, hole.y, 32, '#f2c14e'); const left = L.d.goal - fed; bubble(hadCheese ? 'Cheese! Yay!' : left > 8 ? 'Squeak! More!' : left > 3 ? 'Almost full!' : 'Just a little more!', hole.x, hole.y + 8, 22, 1.8); Snd.fx.deliver(); }
  }
  refillT -= dt; if (refillT <= 0) { refillT = 3; const rf = foodDef().refill; if (rf && items.length < rf) spawnItem(); }
  // --- smell (desire) ---
  const nc = nearestCheese(true);
  smellTarget = nc && nc.it.type !== 'crumb' ? nc.it : null;
  smell = smellTarget ? clamp01(1 - nc.d / 520) : 0;
  if (smellTarget && nc.d < 240 && !rat.smelled.has(smellTarget.id)) { rat.smelled.add(smellTarget.id); bubble('I smell cheese!', rat.x, rat.y, rat.h + 30, 1.6); }
  // --- house ---
  updateCat(dt); if (state !== 'play') return;
  updateHuman(dt); if (state !== 'play') return;
  updateVacuum(dt);
  if (!rat.jump && rat.surf === 'floor') for (const t of traps) { if (t.sprung) continue; if (Math.hypot(t.x - rat.x, t.y - rat.y) < 12) { t.sprung = true; t.bait.visible = false; t.wisps && t.wisps.forEach(w => scene.remove(w.s)); t.wisps = null; caught('SNAP!', t.x, t.y, 26, 'snap'); break; } }
  if (state !== 'play') return;
  for (const k of L.knocks) if (k.fall && k.fall.t < 1) { k.fall.t += dt / 0.55; if (k.fall.t >= 1) { k.fall.t = 1; Snd.fx[k.snd](); noise(k.to[0], k.to[1], 460, k.text, true); } }
  if (L.crackle && Math.random() < dt * 7) Snd.fx.crackle(0.06 * clamp01(1 - Math.hypot(rat.x - L.crackle.x, rat.y - L.crackle.y) / 500));
  // --- wanted level ---
  if (catSees || humanSees) unseenT = 0; else unseenT += dt;
  const inHole = rat.surf === 'floor' && Math.hypot(rat.x - hole.x, rat.y - hole.y) < hole.r + 4;
  if (inHole && unseenT > 1) alarm -= dt * 14; else if (unseenT > 4) alarm -= dt * 5;
  alarm = clamp(alarm, 0, 60);
  { let ns = 0; if (hasWanted()) for (const t of STAR_AT) if (evidence + alarm >= t) ns++; if (ns > stars) onStars(ns, stars); if (ns !== stars) { stars = ns; updHud(); } maxStars = Math.max(maxStars, stars); }
  Music.set(stars / 4, cat.mode === 'chase' || human.mode === 'chase');
  rings.forEach(r => { r.r += dt * r.sp; r.t -= dt; r.m.scale.set(r.r, r.r, 1); r.m.material.opacity = Math.max(0, r.t) * (r.k < 1 ? 0.45 : 0.7); });
  for (let i = rings.length - 1; i >= 0; i--) if (rings[i].t <= 0) { scene.remove(rings[i].m); rings.splice(i, 1); }
  for (const k in pressed) delete pressed[k];
  if (Math.floor(nightT * 2) !== Math.floor((nightT - dt) * 2)) updHud();
}
function addToPile(type) { const m = itemMesh(type); const a = Math.random() * Math.PI * 2, r = Math.random() * 14; m.position.set(nest.cx + 10 + Math.cos(a) * r, 3 + pile.length * 0.15, nest.cz + Math.sin(a) * r); m.rotation.y = Math.random() * 6; pile.push(m); }

const catRange = () => (cat.mode === 'idle' && cat.sit > 0.5 ? 150 + stars * 10 : 260 + stars * 15) * (L.d.catSense || 1);
function updateCat(dt) {
  const dx = rat.x - cat.x, dy = rat.y - cat.y, dist = Math.hypot(dx, dy);
  cat.speed = 0; cat.meowT -= dt;
  if (cat.mode === 'away') { catSees = false; return; }
  if (cat.mode === 'sleep') {
    catSees = false;
    // sleep meter: noise lowers it, quiet time slowly restores it
    cat.calmT -= dt; if (cat.calmT <= 0) cat.sleep = Math.min(1, cat.sleep + dt * 0.045);
    const stage = cat.sleep > 0.6 ? 0 : cat.sleep > 0.3 ? 1 : 2;
    if (stage > cat.stage) { bubble(stage === 1 ? 'Mrr…' : '…?', cat.x, cat.y, 44, 1.4); Snd.fx.purr(0.06); }
    cat.stage = stage;
    cat.peek = lerp(cat.peek, stage === 2 ? 1 : stage === 1 ? 0.35 : 0, Math.min(1, dt * 3));
    if (stage === 0) { cat.zzzT -= dt; if (cat.zzzT <= 0) { cat.zzzT = 3.2; Snd.fx.purr(0.05 * clamp01(1 - dist / 400)); } }
    // half awake, the cat lifts its head and looks toward the last noise: if it sees you, it wakes up
    if (stage === 2) {
      cat.a += angDiff(cat.a, Math.atan2(cat.lastY - cat.y, cat.lastX - cat.x)) * Math.min(1, dt * 2);
      const peekSees = !ratHidden && dist < 170 && Math.abs(angDiff(cat.a, Math.atan2(dy, dx))) < 0.8 && los(cat.x, cat.y, rat.x, rat.y, rat.h);
      if (peekSees) { wakeCat(rat.x, rat.y); cat.alert = 0.8; return; }
    }
    if (dist < 32 || stars >= threatStar('cat')) wakeCat(rat.x, rat.y);
    return;
  }
  const ratHigh = (rat.h >= 30 && !rat.jump) || (rat.jump && rat.jump.th >= 30);
  const range = catRange();
  const inCone = dist < range && Math.abs(angDiff(cat.a, Math.atan2(dy, dx))) < 0.62;
  catSees = graceT <= 0 && !ratHidden && (inCone || dist < 34) && los(cat.x, cat.y, rat.x, rat.y, rat.h);
  if (catSees) { cat.alert += dt * (1.3 + (1 - dist / 260) * 3); cat.lastX = rat.x; cat.lastY = rat.y; alarm += dt * 4; }
  else if (cat.mode !== 'chase' && cat.mode !== 'watch') cat.alert -= dt * 0.45;
  cat.alert = clamp01(cat.alert);
  if (cat.alert >= 1 && cat.mode !== 'chase' && cat.mode !== 'watch') { cat.mode = ratHigh ? 'watch' : 'chase'; cat.lostT = 0; cat.watchT = 4; cat.repath = 0; cat.sit = 0; alarm += 6; bubble(ratHigh ? 'Meow?!' : 'MEOW!', cat.x, cat.y, 52, 1.2); Snd.fx.meow(ratHigh ? 'q' : 'angry'); }
  else if (cat.alert > 0.35 && catSees && (cat.mode === 'wander' || cat.mode === 'idle')) { cat.mode = 'investigate'; cat.path = astar(L.grid, cat.x, cat.y, rat.x, rat.y); cat.sit = 0; }
  const mul = 1 + stars * 0.05;
  switch (cat.mode) {
    case 'chase':
      if (ratHigh && catSees) { cat.mode = 'watch'; cat.watchT = 4; cat.repath = 0; break; }
      if (catSees) cat.lostT = 0; else cat.lostT += dt;
      cat.repath -= dt; if (cat.repath <= 0) { cat.repath = 0.25; cat.path = astar(L.grid, cat.x, cat.y, catSees ? rat.x : cat.lastX, catSees ? rat.y : cat.lastY); }
      if (!follow(cat, 172 * mul, dt, L.catBlock) && catSees) cat.a += angDiff(cat.a, Math.atan2(dy, dx)) * Math.min(1, dt * 7);
      if (cat.lostT > 1.4) { cat.mode = 'search'; cat.searchT = 2.4; cat.alert = 0.6; }
      break;
    case 'watch': {
      cat.repath -= dt; if (cat.repath <= 0) { cat.repath = 0.5; const [px, py] = freePoint(L.grid, rat.x, rat.y); cat.path = astar(L.grid, cat.x, cat.y, px, py); }
      if (!follow(cat, 120, dt, L.catBlock)) { cat.a += angDiff(cat.a, Math.atan2(dy, dx)) * Math.min(1, dt * 5); if (cat.meowT <= 0 && catSees) { cat.meowT = 2.2; bubble(Math.random() < 0.5 ? 'Meow…' : 'Get down here!', cat.x, cat.y, 52, 1.4); Snd.fx.meow(); } }
      cat.watchT -= catSees ? dt * 0.35 : dt;
      if (!ratHigh && catSees && !ratHidden) { cat.mode = 'chase'; cat.lostT = 0; cat.repath = 0; }
      else if (cat.watchT <= 0) { cat.mode = 'wander'; cat.alert = 0.2; cat.path = []; bubble('Hmph.', cat.x, cat.y, 50, 1.2); }
      break; }
    case 'investigate': if (!follow(cat, 100 * mul, dt, L.catBlock)) { cat.mode = 'search'; cat.searchT = 1.8; } break;
    case 'search': cat.searchT -= dt; cat.a += dt * 2.2; cat.sit = Math.max(0, cat.sit - dt * 2); if (cat.searchT <= 0) { cat.mode = 'wander'; cat.alert = Math.min(cat.alert, 0.2); cat.path = []; } break;
    case 'idle':
      cat.idleT -= dt; cat.sit = cat.idleT > 1.2 ? Math.min(1, cat.sit + dt * 2) : Math.max(0, cat.sit - dt * 2);
      cat.a += Math.sin(nightT * 0.9) * dt * 0.6;
      if (cat.idleT <= 0) { cat.mode = 'wander'; cat.path = []; cat.sit = 0; }
      break;
    default: {
      if (!cat.path.length) {
        const r = Math.random(), home = L.d.bowl ? [L.d.bowl[0] + 24, L.d.bowl[1]] : [L.d.catBed[0] + 36, L.d.catBed[1]];
        const t = r < 0.22 ? home : randomFree(L.grid, 260, cat.x, cat.y);
        cat.path = astar(L.grid, cat.x, cat.y, t[0], t[1]); cat.goingHome = r < 0.22;
      }
      if (!follow(cat, 70 * (1 + stars * 0.08), dt, L.catBlock)) { cat.mode = 'idle'; cat.idleT = cat.goingHome ? 4 : 1.5 + Math.random() * 3.5; }
    }
  }
  if (cat.mode === 'chase') run.chased = true;
  cat.step += dt * cat.speed * 0.08;
  if (graceT <= 0 && !ratHidden && rat.h < 30 && !rat.jump && dist < cat.r + rat.r + 4) caught('Gotcha!', cat.x, cat.y, 58);
}
function updateHuman(dt) {
  const h = human; humanSees = false;
  const ownerStar = threatStar('owner'); if (ownerStar > 5) return;
  if (h.mode === 'away') { if (stars >= ownerStar) { h.mode = 'coming'; h.t = 2.4; bubble('Stomp… stomp… stomp…', DOOR().x - 30, DOOR().y, 120, 2.2); [0, 0.6, 1.2, 1.8].forEach(d => setTimeout(() => Snd.fx.stomp(0.12 + d * 0.06), d * 1000)); } return; }
  if (h.mode === 'coming') { h.t -= dt; if (h.t <= 0) { Object.assign(h, { mode: 'patrol', x: DOOR().x, y: DOOR().y, a: Math.PI, path: [], lostT: 0, seeT: 0, lowT: 0, t: 0 }); lightOn = true; Snd.fx.door(); setTimeout(() => Snd.fx.lightSwitch(), 500); bubble(stars >= 5 ? 'That’s it, rat, you’re done!' : 'Who’s rustling in here?!', h.x, h.y, 195, 2.4); } return; }
  h.t += dt; h.speed = 0;
  const dx = rat.x - h.x, dy = rat.y - h.y, dist = Math.hypot(dx, dy), look = h.a + h.sweep;
  const inCone = dist < 330 && Math.abs(angDiff(look, Math.atan2(dy, dx))) < 0.5;
  humanSees = h.mode !== 'leaving' && !ratHidden && (inCone || dist < 50) && los(h.x, h.y, rat.x, rat.y, 150);
  if (humanSees) { h.seeT += dt; h.lastX = rat.x; h.lastY = rat.y; h.known = true; alarm += dt * 12; } else h.seeT = Math.max(0, h.seeT - dt * 0.5);
  const mul = 1 + Math.max(0, stars - ownerStar) * 0.05;
  if (h.mode !== 'leaving' && h.mode !== 'chase' && h.seeT > 0.35) { h.mode = 'chase'; h.lostT = 0; h.repath = 0; alarm += 6; bubble(Math.random() < 0.5 ? 'Why, you little…!' : 'There you are!', h.x, h.y, 195, 1.6); }
  switch (h.mode) {
    case 'patrol':
      h.sweep = Math.sin(h.t * 1.3) * 0.55;
      if (!h.path.length) { let t;
        if (h.known && Math.random() < 0.55) t = freePoint(L.grid, clamp(h.lastX + (Math.random() - 0.5) * 220, 30, W - 30), clamp(h.lastY + (Math.random() - 0.5) * 220, 30, H - 30));
        else t = randomFree(L.grid, 200, h.x, h.y);
        h.path = astar(L.grid, h.x, h.y, t[0], t[1]); }
      if (!follow(h, 85 * mul, dt, L.catBlock)) { h.mode = 'look'; h.t2 = 1.6; h.path = []; }
      break;
    case 'look': h.t2 -= dt; h.sweep = Math.sin(h.t * 2.4) * 0.9; if (h.t2 <= 0) h.mode = 'patrol'; break;
    case 'chase': {
      h.sweep *= Math.max(0, 1 - dt * 5);
      if (humanSees) h.lostT = 0; else h.lostT += dt;
      h.repath -= dt; if (h.repath <= 0) { h.repath = 0.3; const [px, py] = freePoint(L.grid, humanSees ? rat.x : h.lastX, humanSees ? rat.y : h.lastY); h.path = astar(L.grid, h.x, h.y, px, py); }
      if (!follow(h, 150 * mul, dt, L.catBlock) && humanSees) h.a += angDiff(h.a, Math.atan2(dy, dx)) * Math.min(1, dt * 6);
      if (h.lostT > 2.2) { h.mode = 'look'; h.t2 = 2.5; h.path = []; bubble('Where did it go?..', h.x, h.y, 195, 1.8); }
      break; }
    case 'leaving':
      h.sweep *= 0.95;
      if (stars >= ownerStar) { h.mode = 'patrol'; h.path = []; break; }
      if (!follow(h, 95, dt, L.catBlock)) { h.mode = 'away'; lightOn = false; h.known = false; Snd.fx.door(); return; }
      break;
  }
  if (h.mode !== 'leaving' && h.mode !== 'chase') {
    if (stars < ownerStar) { h.lowT += dt; if (h.lowT > 8) { h.mode = 'leaving'; h.path = astar(L.grid, h.x, h.y, DOOR().x, DOOR().y); bubble('Must be nothing… Back to bed.', h.x, h.y, 195, 2); Snd.fx.lightSwitch(); } }
    else h.lowT = 0;
  }
  h.step += dt * h.speed * 0.06; h.stepD += dt * h.speed;
  if (h.stepD > 60) { h.stepD = 0; Snd.fx.stomp(0.32 * clamp01(1 - dist / 700)); }
  const reach = h.r + rat.r + (rat.h > 20 ? 32 : 10);
  if (h.mode !== 'leaving' && !ratHidden && !rat.jump && rat.h < 110 && dist < reach) { h.mode = 'look'; h.t2 = 2; h.path = []; h.seeT = 0; caught('WHACK! Slipper!', h.x, h.y, 200, 'whack'); }
}
function updateVacuum(dt) {
  if (!vac.on) { Snd.hum(0); return; }
  vac.speed = 0; vac.bumpT = Math.max(0, vac.bumpT - dt);
  if (!vac.path.length) { const t = Math.random() < 0.4 ? freePoint(L.gridV, rat.x + (Math.random() - 0.5) * 300, rat.y + (Math.random() - 0.5) * 300) : randomFree(L.gridV, 200, vac.x, vac.y); vac.path = astar(L.gridV, vac.x, vac.y, t[0], t[1]); }
  follow(vac, 58 + stars * 4, dt, L.solids);
  for (let i = items.length - 1; i >= 0; i--) { const it = items[i]; if (it.h === 0 && it.type === 'crumb' && Math.hypot(it.x - vac.x, it.y - vac.y) < vac.r + 4) { scene.remove(it.mesh); items.splice(i, 1); } }
  const d = Math.hypot(rat.x - vac.x, rat.y - vac.y);
  Snd.hum(0.1 * clamp01(1 - d / 520));
  if (vac.bumpT <= 0 && rat.surf === 'floor' && !rat.jump && d < vac.r + rat.r + 3) {
    vac.bumpT = 2.5; Snd.fx.beep();
    const nx = (rat.x - vac.x) / (d || 1), ny = (rat.y - vac.y) / (d || 1); rat.x += nx * 34; rat.y += ny * 34; resolve(rat, L.solids);
    noise(vac.x, vac.y, 650, 'BEEP BEEP!', true); vac.path = [];
  }
}

// ================= RENDER SYNC =================
const ray = new THREE.Raycaster(), tmpV = new THREE.Vector3();
function project(x, y, z) { tmpV.set(x, y, z).project(camera); const b = stage.getBoundingClientRect(); return { x: (tmpV.x + 1) / 2 * b.width, y: (1 - tmpV.y) / 2 * b.height, vis: tmpV.z < 1 && tmpV.z > -1 }; }
function followCam(dt, yaw, pitch) {
  const th = rat.h + 14, tgt = new THREE.Vector3(rat.x, th, rat.y);
  const want = new THREE.Vector3(rat.x - Math.cos(yaw) * camDist * Math.cos(pitch), th + 6 + camDist * Math.sin(pitch), rat.y - Math.sin(yaw) * camDist * Math.cos(pitch));
  const dir = want.clone().sub(tgt); const len = dir.length(); dir.normalize();
  ray.set(tgt, dir); ray.far = len; const hit = ray.intersectObjects(camBlock, false)[0];
  const camPos = hit ? tgt.clone().addScaledVector(dir, Math.max(9, hit.distance - 3)) : want;
  camera.position.lerp(camPos, Math.min(1, dt * 12)); camera.lookAt(rat.x, rat.h + 12, rat.y);
}
const catTag = document.createElement('div'); catTag.className = 'tag'; $('tags').appendChild(catTag);
function setFade(m, op) { if (!m.material) return; m.material.opacity = op; m.children.forEach(c => { if (c.userData.isOutline) c.visible = op > 0.9; }); }
function sync(dt) {
  clock += dt;
  const ud = ratMesh.userData, playing = state === 'play', inRun = state === 'play' || state === 'pause';
  ratMesh.position.set(rat.x, rat.h, rat.y); ratMesh.rotation.y = -rat.a;
  rat.stand = lerp(rat.stand || 0, rat.sniffing ? 1 : 0, Math.min(1, dt * 9)); const st = state === 'intro' ? 0 : rat.stand;
  wagTail(ud, rat.step + clock * 1.5, 0.5);
  ud.feet.forEach((f, i) => { f.position.y = f.userData.by + (i < 2 ? st * 10 : 0) + Math.max(0, Math.sin(rat.step * 2 + (i % 2 ? Math.PI : 0))) * 1.6 * (1 - st); if (i < 2) f.position.x = 5 - st * 3; });
  if (state !== 'intro') {
    crouchAmt = lerp(crouchAmt, rat.crouch && !rat.jump && !rat.sniffing ? 1 : 0, Math.min(1, dt * 10)); const cr = crouchAmt * (1 - st);
    ud.body.scale.set(11 + cr * 1.5, 6.5 - cr * 1.6, 7 + cr * 0.6); ud.body.position.set(-st * 3, 7 - cr * 2.2 + Math.abs(Math.sin(rat.step * 2)) * 1.2 * (1 - st) * (1 - cr * 0.7) + st * 7, 0);
    ud.body.rotation.z = st * 1.0 + (rat.jump ? 0.25 * Math.cos(Math.PI * clamp01(rat.jump.t)) : 0);
    ud.headG.position.set(lerp(10, 2.5, st) + cr * 1.5, lerp(8, 22, st) - cr * 2.5, 0); ud.eyes.forEach(e => e.scale.y = 1);
    let hy = 0; if (smellTarget && smell > 0.15 && playing) hy = clamp(angDiff(rat.a, Math.atan2(smellTarget.y - rat.y, smellTarget.x - rat.x)), -0.9, 0.9) * smell;
    ud.headG.rotation.y = lerp(ud.headG.rotation.y, -hy, Math.min(1, dt * 6)); ud.headG.rotation.z = st * 0.55 + Math.sin(clock * 18) * 0.06 * (st * 1.4 + smell * 0.6);
  }
  rat.carry.forEach((it, i) => { it.mesh.position.set(i * 3, 0, (i - (rat.carry.length - 1) / 2) * 6); it.mesh.rotation.set(0, it.rot, 0); });
  const eating = (state === 'outro' && phase === 'eat') || (state === 'result' && phase === 'done' && fed >= L.d.goal);
  pups.forEach((p, i) => { const pu = p.m.userData; let x = p.bx, z = p.bz, a = p.a;
    if (eating) { const ang = i / pups.length * Math.PI * 2; x = nest.cx + 10 + Math.cos(ang) * 17; z = nest.cz + Math.sin(ang) * 17; a = Math.atan2(nest.cz - z, nest.cx + 10 - x); pu.headG.rotation.z = -0.35 + Math.abs(Math.sin(clock * 9 + p.ph)) * 0.3; p.m.position.y = 0; }
    else { const hop = Math.abs(Math.sin(clock * 7 + p.ph)); p.m.position.y = hop > 0.75 ? (hop - 0.75) * 10 : 0; a += Math.sin(clock * 3 + p.ph) * 0.4; pu.headG.rotation.z = 0.25; }
    p.m.position.x = x; p.m.position.z = z; p.m.rotation.y = -a; wagTail(pu, clock * 6 + p.ph, 0.5); });
  const openFood = !L || !!L.d.openFood || state === 'menu';
  items.forEach(it => { const base = it.h + (it.type === 'cheese' ? 4 : 3.5);
    it.reveal = Math.max(0, (it.reveal || 0) - dt);
    const vis = openFood || it.reveal > 0 || Math.hypot(it.x - rat.x, it.y - rat.y) + Math.abs(it.h - rat.h) < 80;
    it.vis = lerp(it.vis == null ? (vis ? 1 : 0) : it.vis, vis ? 1 : 0, Math.min(1, dt * 6));
    it.mesh.visible = it.vis > 0.03; it.mesh.scale.setScalar(Math.max(0.001, it.vis));
    it.mesh.position.set(it.x, base + Math.sin(clock * 3 + it.rot) * 1.5, it.y); it.mesh.rotation.y = it.rot + clock * 0.8;
    if (it.wisps) it.wisps.forEach(w => { const u = (clock * 0.35 + w.ph) % 1; w.s.visible = it.vis > 0.03; w.s.position.set(it.x + Math.sin(clock * 2 + w.ph * 9) * 5 * u, base + 4 + u * 42, it.y + Math.cos(clock * 1.7 + w.ph * 7) * 5 * u); w.s.material.opacity = Math.sin(u * Math.PI) * 0.55 * it.vis; w.s.scale.setScalar(5 + u * 9); }); });
  { const active = rat.sniffing && rat.sniffHold > 0.35, reach = 8 + 4 * (1 - st);
    const nx = rat.x + Math.cos(rat.a) * reach, ny = rat.h + 10 + st * 13, nz = rat.y + Math.sin(rat.a) * reach;
    streams.forEach((sm, k) => {
      const it = sniffTargets[k], on = active && it && items.includes(it);
      if (on) sm.it = it; else if (sm.it && !items.includes(sm.it)) sm.op = Math.min(sm.op, 0.3);
      sm.op = lerp(sm.op, on ? 1 : 0, Math.min(1, dt * (on ? 3 : 1.6)));
      sm.pts.visible = sm.op > 0.02 && !!sm.it; if (!sm.pts.visible) return;
      sm.mat.uniforms.opacity.value = sm.op; sm.mat.uniforms.color.value.set(sm.it.poison ? 0x8fe060 : sm.it.type === 'cheese' ? 0xf2d36a : 0xe8d8b0);
      const ax = sm.it.x, ay = sm.it.h + 6, az = sm.it.y, dx = nx - ax, dz = nz - az, dl = Math.hypot(dx, dz) || 1, px = -dz / dl, pz = dx / dl, lift = 16 + dl * 0.07;
      for (let i = 0; i < STREAM_N; i++) {
        const u = (i / STREAM_N + clock * 0.32 + k * 0.17) % 1, env = Math.sin(u * Math.PI);
        const w = Math.sin(u * 14 + clock * 2.2 + k * 2) * 5 * env + Math.sin(u * 5 + clock * 1.3 + k) * 3 * env;
        sm.pos[i * 3] = lerp(ax, nx, u) + px * w; sm.pos[i * 3 + 1] = lerp(ay, ny, u) + env * lift + Math.sin(u * 9 + clock * 3) * 1.5; sm.pos[i * 3 + 2] = lerp(az, nz, u) + pz * w;
        sm.alpha[i] = Math.pow(env, 0.6) * (0.55 + 0.45 * Math.sin(i * 1.7 + clock * 5));
      }
      sm.geo.attributes.position.needsUpdate = true; sm.geo.attributes.alpha.needsUpdate = true;
    });
    if (!rat.sniffing && streams.every(sm => sm.op < 0.03)) sniffTargets = []; }
  for (const k of L.knocks) { const m = k.mesh;
    if (k.fall) { const t = clamp01(k.fall.t); m.position.set(lerp(k.x, k.to[0], t), lerp(k.h, 0, t * t) + Math.sin(Math.PI * t) * 12, lerp(k.y, k.to[1], t)); m.rotation.z = t * (k.kind === 'apple' ? 6 : 1.57); m.rotation.x = t * 0.8; }
    else { m.position.set(k.x, k.h, k.y); m.rotation.set(0, 0, 0); } }
  if (L.dust) { const D = L.dust; for (let i = 0; i < D.seeds.length; i++) { const s = D.seeds[i]; D.dp[i * 3] = s[0] + Math.sin(clock * 0.3 + s[3]) * 8; D.dp[i * 3 + 1] = s[1] + Math.sin(clock * 0.2 + s[3] * 2) * 6; D.dp[i * 3 + 2] = s[2] + Math.cos(clock * 0.25 + s[3]) * 8; } D.dg.attributes.position.needsUpdate = true; }
  L.flickers.forEach(f => {
    if (f.type === 'tv') { f.t -= dt; if (f.t <= 0) { f.t = 0.08 + Math.random() * 0.25; const k = 0.55 + Math.random() * 0.6; f.light.intensity = f.base * k; f.mat.color.setHSL(0.6 + Math.random() * 0.06, 0.5, 0.35 + k * 0.25); } }
    else { const k = 0.85 + Math.sin(clock * 13 + f.base) * 0.08 + Math.random() * 0.07; f.light.intensity = f.base * k; f.sprites.forEach((s, i) => s.scale.setScalar((12 + i * 3) * (0.9 + Math.random() * 0.2))); }
  });
  // cat
  const cu = catMesh.userData, sleeping = cat.mode === 'sleep'; catMesh.visible = cat.mode !== 'away';
  catMesh.position.set(cat.x, 0, cat.y); catMesh.rotation.y = -cat.a;
  cu.legs.forEach((l, i) => l.rotation.z = Math.sin(cat.step + (i % 2 ? Math.PI : 0)) * 0.5);
  cu.bodyG.position.y = sleeping ? -9 : -cat.sit * 6; cu.bodyG.rotation.z = sleeping ? 0.05 : cat.sit * 0.28;
  cu.headG.rotation.z = sleeping ? lerp(-0.6, 0.15, cat.peek) : cat.mode === 'watch' ? 0.35 : cat.sit * -0.2;
  cu.eyeMeshes.forEach(e => e.scale.y = sleeping ? (cat.peek > 0.7 ? 1 : 0.12 + cat.peek * 0.4) : 1);
  { const ph = clock * (cat.mode === 'watch' || cat.mode === 'chase' ? 7 : sleeping ? 0.6 : 2) + cat.step * 0.3; cu.tailPivot.rotation.y = sleeping ? 1.2 : Math.sin(ph) * 0.3; cu.ctail.forEach((t, i) => t.rotation.y = sleeping ? 0.35 : Math.sin(ph - (i + 1) * 0.7) * 0.28); }
  if (sleeping) cu.body.scale.y = 13 + Math.sin(clock * 2) * 0.6; else cu.body.scale.y = 13;
  cu.eyeM.color.set(cat.mode === 'chase' ? 0xffd84a : cat.mode === 'watch' ? 0xffb84a : 0x9be06a);
  catCone.mesh.visible = inRun && !sleeping && cat.mode !== 'away';
  if (catCone.mesh.visible) { updateCone(catCone, cat.x, cat.y, cat.a, 0.62, catRange()); catCone.mat.color.set(cat.mode === 'chase' ? 0xe8664a : cat.alert > 0.3 || cat.mode === 'watch' ? 0xf2c14e : 0xdcdceb); catCone.mat.opacity = cat.mode === 'chase' ? 0.24 : 0.14; }
  // owner
  { const h = human, hu = humanMesh.userData, vis = h.mode !== 'away' && h.mode !== 'coming'; humanMesh.visible = vis;
    if (vis) { humanMesh.position.set(h.x, 0, h.y); humanMesh.rotation.y = -h.a; const sw = Math.sin(h.step || 0); hu.legs[0].rotation.z = sw * 0.45; hu.legs[1].rotation.z = -sw * 0.45; hu.armL.rotation.z = -sw * 0.35; hu.armR.rotation.set(0, -(h.sweep || 0), 1.25); hu.bodyG.position.y = Math.abs(Math.cos(h.step || 0)) * 2; }
    hu.spot.intensity = lerp(hu.spot.intensity, vis ? 2.6 : 0, Math.min(1, dt * 4));
    lightCone.mesh.visible = vis && inRun;
    if (lightCone.mesh.visible) { const la = h.a + h.sweep; updateCone(lightCone, h.x + Math.cos(la) * 20, h.y + Math.sin(la) * 20, la, 0.5, 330); lightCone.mat.color.set(h.mode === 'chase' ? 0xffb48a : 0xfff0c0); }
    const open = h.mode !== 'away' && !(h.mode === 'coming' && h.t > 0.9);
    if (L.doorPivot) L.doorPivot.rotation.y = lerp(L.doorPivot.rotation.y, open ? -1.45 : 0, Math.min(1, dt * 4));
    roomLight.intensity = lerp(roomLight.intensity, lightOn ? 0.75 : 0, Math.min(1, dt * 3));
    const k = roomLight.intensity / 0.75; lampBulbMat.color.setRGB(lerp(0.29, 1, k), lerp(0.27, 0.95, k), lerp(0.21, 0.8, k));
    hallLight.intensity = lerp(hallLight.intensity, open ? 1.2 : 0, Math.min(1, dt * 3)); }
  // vacuum
  vacMesh.visible = vac.on; if (vac.on) { vacMesh.position.set(vac.x, 0, vac.y); vacMesh.rotation.y = -vac.a; vacMesh.userData.ledM.color.set(vac.bumpT > 1.5 ? 0xff4a3a : 0x6ee07a); }
  // traps
  for (const t of traps) { t.reveal = Math.max(0, t.reveal - dt); t.warn.visible = t.reveal > 0 && !t.sprung; t.bar.rotation.z = lerp(t.bar.rotation.z, t.sprung ? -Math.PI : 0, Math.min(1, dt * 25));
    if (t.wisps) t.wisps.forEach(w => { const u = (clock * 0.35 + w.ph) % 1; w.s.position.set(t.x + Math.sin(clock * 2 + w.ph * 9) * 5 * u, 8 + u * 42, t.y + Math.cos(clock * 1.7 + w.ph * 7) * 5 * u); w.s.material.opacity = Math.sin(u * Math.PI) * 0.55; w.s.scale.setScalar(5 + u * 9); w.s.material.color.set(t.reveal > 0 ? 0xe8664a : 0xf2d36a); }); }
  // kitchen clock
  if (L.clock) { const mins = 23 * 60 + (state === 'menu' ? clock * 2 : nightT / L.d.night * 360); L.clock.m.rotation.z = -(mins % 60) / 60 * Math.PI * 2; L.clock.h.rotation.z = -((mins / 60) % 12) / 12 * Math.PI * 2; }
  // fade furniture between the camera and the rat, and furniture the rat is under
  { const rp = new THREE.Vector3(rat.x, rat.h + 8, rat.y), cp = camera.position;
    for (const m of fadeables) { const ab = rp.clone().sub(cp), ap = m.position.clone().sub(cp), t = clamp01(ap.dot(ab) / ab.lengthSq()), close = cp.clone().addScaledVector(ab, t).distanceTo(m.position);
      const hide = inRun && t > 0 && t < 1 && close < 26; setFade(m, lerp(m.material.opacity, hide ? 0.18 : 1, Math.min(1, dt * 10))); }
    for (const f of L.fades) { const under = inRun && rat.surf === 'floor' && inRect(rat.x, rat.y, f.rect, 6); f.op = lerp(f.op, under ? 0.22 : 1, Math.min(1, dt * 8)); f.meshes.forEach(m => setFade(m, f.op)); } }
  if (L.marks) for (const mk of L.marks) { const r = mk.r, dx = Math.max(r.x - rat.x, 0, rat.x - r.x - r.w), dy = Math.max(r.y - rat.y, 0, rat.y - r.y - r.h), d = Math.hypot(dx, dy);
    const inside = d === 0 && rat.surf === 'floor' && !rat.jump;
    const target = !inRun ? 0 : inside ? 0.9 : 0.6 * clamp01(1 - (d - 15) / 230);
    mk.m.material.opacity = lerp(mk.m.material.opacity, target * (0.85 + Math.sin(clock * 3 + r.x) * 0.15), Math.min(1, dt * 6)); mk.m.visible = mk.m.material.opacity > 0.01; }
  holeLight.intensity = 0.65 + Math.sin(clock * 3) * 0.15; nestLight.intensity = 1.25 + Math.sin(clock * 1.7) * 0.08;
  // camera
  if (inRun || (state === 'result' && !rat.inNest)) followCam(dt, camYaw, camPitch);
  else if (state === 'menu') { const a = clock * 0.08; camera.position.set(480 + Math.cos(a) * 420, 190, 300 + Math.sin(a) * 260); camera.lookAt(480, 30, 320); }
  // prompts
  const pr = $('prompt'); marker.visible = false; pr.hidden = true;
  if (playing) {
    if (knockCand) { const p = project(knockCand.x, knockCand.h + 22, knockCand.y); if (p.vis) { pr.hidden = false; pr.style.left = p.x + 'px'; pr.style.top = p.y + 'px'; $('promptKey').textContent = 'F'; $('promptTxt').textContent = 'Knock over ' + knockCand.word; } }
    else if (jumpCand) { marker.visible = true; marker.position.set(jumpCand.x, jumpCand.s.h + 0.7, jumpCand.y); const sc = 1 + Math.sin(clock * 6) * 0.12; marker.scale.set(sc, sc, sc);
      const p = project(jumpCand.x, jumpCand.s.h + 14, jumpCand.y); if (p.vis) { pr.hidden = false; pr.style.left = p.x + 'px'; pr.style.top = p.y + 'px'; $('promptKey').textContent = usingTouch ? 'Jump' : 'Space'; $('promptTxt').textContent = jumpCand.s.h > rat.h ? 'Jump up' : 'Jump down'; } }
  }
  const cp2 = project(cat.x, sleeping ? 40 : 58, cat.y);
  if (inRun && cp2.vis && sleeping) {
    // sleep meter over the sleeping cat: Zzz + a bar that empties as you make noise
    catTag.hidden = false; catTag.style.left = cp2.x + 'px'; catTag.style.top = cp2.y + 'px'; catTag.style.fontSize = '16px';
    const col = cat.stage === 0 ? '#9fb4ff' : cat.stage === 1 ? '#f2c14e' : '#e8664a';
    catTag.style.color = col;
    catTag.innerHTML = '<span class="zz">' + (cat.stage === 0 ? 'Zzz' : cat.stage === 1 ? 'zz…' : '?!') + '</span><span class="sleepbar"><i style="width:' + Math.round(cat.sleep * 100) + '%;background:' + col + '"></i></span>';
  } else if (inRun && cp2.vis && cat.mode !== 'watch' && cat.mode !== 'away' && (cat.mode === 'chase' || cat.mode === 'investigate' || cat.mode === 'search' || cat.alert > 0.05)) {
    catTag.hidden = false; catTag.style.left = cp2.x + 'px'; catTag.style.top = cp2.y + 'px';
    if (cat.mode === 'chase') { catTag.textContent = '!'; catTag.style.color = '#e8664a'; catTag.style.fontSize = '30px'; }
    else if (cat.mode === 'investigate' || cat.mode === 'search') { catTag.textContent = '?'; catTag.style.color = '#f2c14e'; catTag.style.fontSize = '26px'; }
    else { catTag.textContent = '•'.repeat(Math.ceil(cat.alert * 5)); catTag.style.color = '#f2c14e'; catTag.style.fontSize = '18px'; }
  } else catTag.hidden = true;
  msgs.forEach(m => { m.t -= dt; m.y += dt * m.rise; const p = project(m.x, m.y, m.z); m.el.style.left = p.x + 'px'; m.el.style.top = p.y + 'px'; m.el.style.opacity = Math.min(1, m.t * 2); m.el.hidden = !p.vis; });
  for (let i = msgs.length - 1; i >= 0; i--) if (msgs[i].t <= 0) { msgs[i].el.remove(); msgs.splice(i, 1); }
  if (bannerTimer > 0) { bannerTimer -= dt; if (bannerTimer <= 0) $('banner').style.opacity = 0; }
  // HUD
  $('chips').hidden = !playing; $('wanted').hidden = !playing || !hasWanted();
  if (playing) {
    if (stars !== lastStarsShown) { lastStarsShown = stars; $('wStars').innerHTML = '★'.repeat(stars) + '<span class="off">' + '★'.repeat(5 - stars) + '</span>'; }
    let evS = 0; for (const t of STAR_AT) if (evidence >= t) evS++;
    const wv = $('wanted'); wv.classList.toggle('blink', alarm > 0.5 && unseenT > 4 && stars > evS); wv.classList.toggle('hot', human.mode === 'chase' || cat.mode === 'chase');
    const hm = human.mode, top = L.d.threats[Math.min(stars, L.d.threats.length) - 1];
    const catTxt = sleeping ? ['The cat is fast asleep', 'The cat is stirring…', 'The cat is half awake!'][cat.stage] : cat.mode === 'chase' ? 'The cat is chasing you!' : cat.mode === 'away' ? 'All quiet' : 'The cat is prowling';
    $('wText').textContent = !L.d.threats.length ? catTxt : hm === 'chase' ? 'The owner is chasing you!' : hm === 'leaving' ? 'The owner is going back to bed…' : hm === 'coming' ? 'Footsteps in the hall…' : hm !== 'away' ? 'The owner is in the room' : stars === 0 ? (sleeping ? 'All quiet, even the cat is asleep' : 'All quiet') : stars > L.d.threats.length ? 'High alert!' : THREATS[top].label;
    const chip = $('chip');
    if (ratHidden) { chip.textContent = 'Hidden'; chip.className = 'chip hidden-state'; }
    else if (humanSees) { chip.textContent = 'The owner sees you!'; chip.className = 'chip seen'; }
    else if (catSees && cat.mode === 'watch') { chip.textContent = 'The cat is waiting below'; chip.className = 'chip seen'; }
    else if (catSees) { chip.textContent = 'The cat sees you!'; chip.className = 'chip seen'; }
    else if (rat.h >= 30) { chip.textContent = hm !== 'away' && hm !== 'coming' ? 'Up high, but the owner can still reach you' : 'Up high: the cat can’t reach you'; chip.className = 'chip'; }
    else { chip.textContent = 'Unseen'; chip.className = 'chip'; }
    { const nc = $('noiseChip'); nc.hidden = cat.mode === 'away';
      const lvl = rat.jump ? 1 : noiseLvl, sneaking = rat.crouch && lvl === 0 && !rat.jump;
      nc.className = 'chip noise-' + lvl; $('noiseTxt').textContent = lvl === 3 ? 'Loud: running' : lvl === 1 ? 'Quiet: walking' : sneaking ? 'Silent: sneaking' : 'Silent';
      [...$('nMeter').children].forEach((el, i) => el.classList.toggle('on', i < lvl)); }
    const bars5 = Math.ceil(smell * 5); [...$('meter').children].forEach((el, i) => el.classList.toggle('on', i < bars5));
    let hint = '';
    if (L.d.tutorial) hint = tutorialHint(dt);
    else if (settings.hints) {
      if (cat.mode === 'chase' && !ratHidden) hint = 'Run to a green outline: under furniture or into a crack in the wall.';
      else if (rat.carry.length === 0 && smellTarget && smell > 0.45 && smellTarget.h > rat.h + 20) hint = 'Something smells good up high. Look for a place to jump: a yellow ring will appear.';
      else if (carryW() >= 3) hint = 'Mouth full. Take the loot to the nest.';
      else if (cat.mode === 'sleep' && cat.stage >= 1) hint = cat.stage === 2 ? 'The cat is half awake and looking around! Freeze or slip out of its sight.' : 'The cat is stirring. Stop making noise and it will settle back down.';
      else if (cat.mode === 'sleep' && nightT < 35 && !rat.crouch) hint = 'The cat is asleep. Near it, hold Ctrl (or press C) to sneak. Running, bumping into things and jumping down from tables make noise.';
      else if (L.d.cat === 'awake' && nightT < 30) hint = 'The cat is awake. The pale cone shows where it looks. Under furniture and in cracks (green outlines) it can’t reach you.';
      else if (!L.d.openFood && nightT < 40 && fed === 0 && !rat.carry.length) hint = 'Food is hidden tonight. Hold E to stand up and sniff: a thin trail of scent leads to it.';
    }
    const hEl = $('hint'); hEl.hidden = !hint; if (hint) hEl.textContent = hint;
    const hd = Math.hypot(hole.x - rat.x, hole.y - rat.y);
    $('home').hidden = !(rat.carry.length && hd > 60);
    $('homeI').style.transform = 'rotate(' + angDiff(camYaw, Math.atan2(hole.y - rat.y, hole.x - rat.x)) + 'rad)';
    $('homeTxt').textContent = 'to the pups · ' + (Math.round(hd / 10) / 10) + ' m' + (rat.h >= 30 ? ' · jump down first' : '');
  } else $('home').hidden = true;
  $('lockHint').hidden = !(playing && !locked && !usingTouch);
  $('cross').hidden = !(playing && locked);
}

function tutorialHint(dt) {
  if (!tut.picked) return 'Move with WASD and look around with the mouse. Walk over food to pick it up.';
  if (!tut.delivered) return rat.carry.length ? 'Carry it home: the glowing hole in the corner. You can hold up to 3 pieces.' : 'Pick up some food. You can carry up to 3 pieces at once.';
  if (!tut.cheese) return 'Cheese is worth 5. Some sits up high: face a chair or the counter and press Space when the yellow ring appears.';
  if (!tut.crouched) return 'Hold Ctrl (or press C) to sneak. It’s slow but silent. Tomorrow the cat is home, and you’ll need it.';
  if (!tut.sniffed) return 'Hold E (or the right mouse button) to stand up and sniff. Thin trails of scent lead to the nearest food.';
  if (tut.hideT < 10) { tut.hideT += dt; return 'Green outlines mark hiding spots: under furniture and cracks in the walls. They get brighter as you get close.'; }
  return '';
}

// ================= LOOP =================
function resize() { const b = stage.getBoundingClientRect(); const pr = settings.quality === 'high' ? Math.min(devicePixelRatio, 2) : settings.quality === 'medium' ? Math.min(devicePixelRatio, 1.5) : 1; renderer.setPixelRatio(pr); renderer.setSize(b.width, b.height, false); if (composer) { composer.setPixelRatio(Math.min(pr, 1.5)); composer.setSize(b.width, b.height); } camera.aspect = b.width / b.height; camera.updateProjectionMatrix(); }
new ResizeObserver(resize).observe(stage);
bindSettings(); applySettings(); applyQuality();
goMenu();
let last = performance.now();
function frame(now) {
  const dt = Math.min(0.05, (now - last) / 1000); last = now;
  if (state === 'play') update(dt);
  else { if (state === 'intro') intro(dt); else if (state === 'outro') outro(dt); for (const k in pressed) delete pressed[k]; }
  sync(dt);
  if (useComposer) { composer.grade.uniforms.uTime.value = clock; composer.render(dt); } else renderer.render(scene, camera);
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

// test hooks (used by automated checks; harmless in play)
window.__kr = {
  info: () => ({ state, level: L && L.i, stars, fed, lives, cat: cat && cat.mode, human: human && human.mode, vac: vac && vac.on, traps: traps.length, items: items.length, poison: items.filter(i => i.poison).length, rat: rat && [Math.round(rat.x), Math.round(rat.y), rat.h, rat.surf] }),
  start: i => startLevel(i), skip: () => skipIntro(), evidence: v => { evidence = v; },
  teleport: (x, y, h = 0, surf = 'floor', yaw) => { Object.assign(rat, { x, y, h, surf, jump: null }); if (yaw != null) camYaw = yaw; },
  preview: i => { buildLevel(i); resetRun(); state = 'menu'; showPanel(null); },
  win: () => { fed = L.d.goal; startOutro(); }, pause: () => pause(),
  cat: () => ({ mode: cat.mode, sleep: +cat.sleep.toFixed(3), stage: cat.stage, x: Math.round(cat.x), y: Math.round(cat.y), woke: run.catWoke, chased: run.chased }),
  items: () => items.map(it => [it.type, Math.round(it.x), Math.round(it.y), it.h, it.surf]),
  noiseLvl: () => noiseLvl, goals: () => nightGoals(true),
  feed: n => { fed = n; }, unlockAll: () => { progress.unlocked = LEVELS.length + 1; saveProgress(); },
};
})();
