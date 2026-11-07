// Kitchen Rat — level data.
// Each night is a 960 × 600 room (units ≈ cm, x to the east, y to the south).
// The mouse hole is always in the south-west corner at (46, 574); the nest is behind that wall.
// The owner comes in through a door on the east wall at y = door.
//
// furn: furniture pieces. The builder in game.js turns each into meshes and collision data:
//   solids   block movement and line of sight (ht = height)
//   hides    space under furniture: the rat is hidden there, the cat and owner cannot enter
//   surfaces things the rat can stand on; any surface ≤ 57 higher than the current one can be jumped to
// cracks: gaps at the bottom of a wall ('n', 's', 'w', 'e') the rat can squeeze into and hide.
// knocks: items the rat can push off a surface with F; "to" is where they land (must be free floor).
// threats: unlocked in order as wanted stars rise. 1st star → threats[0], 2nd → threats[1], ...
// openFood: food is visible everywhere. Otherwise food only shows up close or after sniffing.
(function () {
  'use strict';

  const kitchenFurniture = [
    { t: 'counter', x: 0, y: 0, w: 960, h: 72 },
    { t: 'counter', x: 0, y: 72, w: 72, h: 240, join: true },
    { t: 'fridge', x: 830, y: 72, w: 130, h: 110 },
    { t: 'island', x: 380, y: 250, w: 200, h: 90 },
    { t: 'box', x: 586, y: 262, w: 44, h: 44, ht: 44 },
    { t: 'table', x: 620, y: 380, w: 200, h: 130, cloth: 0xc95b4a, plate: true },
    { t: 'chair', x: 580, y: 404, back: 'w' },
    { t: 'chair', x: 580, y: 456, back: 'w' },
    { t: 'chair', x: 830, y: 430, back: 'e' },
    { t: 'lowShelf', x: 200, y: 300, w: 62, h: 50 },
    { t: 'stool', x: 84, y: 236 },
  ];
  const kitchenKnocks = [
    { kind: 'cup', x: 810, y: 392, to: [840, 370] },
    { kind: 'jar', x: 470, y: 60, to: [470, 102] },
    { kind: 'apple', x: 520, y: 330, to: [522, 364] },
  ];
  const kitchenCracks = [{ wall: 's', x: 330 }, { wall: 'w', y: 420 }, { wall: 'e', y: 230 }, { wall: 's', x: 760 }];

  window.THREATS = {
    cat: { name: 'the cat', label: 'The cat is awake', banner: 'The cat woke up', tip: 'It can’t climb after you, but it will wait below. Hide in a green spot to lose it' },
    owner: { name: 'the owner', label: 'The owner is up', banner: 'The owner woke up', tip: 'With a flashlight he can spot you even on tables. Hide under furniture or in a crack' },
    traps: { name: 'mousetraps', label: 'Mousetraps on the floor', banner: 'Mousetraps!', tip: 'The owner set traps. They smell like cheese too, so sniff first (hold E)' },
    poison: { name: 'poison', label: 'Poison in the cheese', banner: 'Poisoned cheese', tip: 'Poisoned cheese smells green. Sniff before you grab' },
    vacuum: { name: 'a robot vacuum', label: 'Robot vacuum on patrol', banner: 'Robot vacuum!', tip: 'It roams everywhere, even under furniture, and beeps loudly when it bumps into you' },
  };

  window.LEVELS = [
    {
      id: 'kitchen', name: 'The Kitchen', goal: 8, night: 300,
      threats: [], openFood: true, tutorial: true,
      intro: { pups: ['Mom, we’re hungry!', 'Squeak!', 'We want cheese!'], mom: 'Everyone is asleep, even the cat is out. Food is everywhere tonight. Let’s grab it.' },
      pal: { fog: 0x0e1220, sky: 0x7d8fc4, ground: 0x2a2430, hemi: 0.8, moon: 0.9, floor: 'tile', floorA: '#3b4058', floorB: '#4a5070', wall: 'stripes', wallA: '#4b5272', wallB: '#545c80', trim: 0x3a2e30, ceil: 0x22263a },
      lamp: 'shade', window: { x: 410, w: 220 }, door: 320,
      catBed: [470, 545], bowl: [770, 215], dock: [900, 430],
      lights: [{ x: 900, y: 560, h: 60, c: 0xffa860, i: 1.0, r: 520 }],
      decor: 'kitchen', furn: kitchenFurniture, knocks: kitchenKnocks, cracks: kitchenCracks,
      music: { root: 57, minor: false, bpm: 70, prog: [[0, 'M'], [-5, 'M'], [-3, 'm'], [-7, 'M']] },
    },
    {
      id: 'living', name: 'The Living Room', goal: 12, night: 270,
      threats: ['cat'],
      intro: { pups: ['Mom, can we have chips?', 'Squeak!', 'We’re sooo hungry!'], mom: 'The living room. A cat sleeps there, and the snacks are tucked away. I’ll have to sniff them out.' },
      pal: { fog: 0x10141a, sky: 0x8a9ab8, ground: 0x2e2620, hemi: 0.74, moon: 0.7, floor: 'wood', floorA: '#5a4232', wall: 'damask', wallA: '#3c5655', wallB: '#466361', trim: 0x2e2622, ceil: 0x26282e },
      lamp: 'shade', window: { x: 680, w: 200 }, door: 240,
      catBed: [215, 500], dock: [900, 330],
      lights: [],
      decor: 'living',
      furn: [
        { t: 'bookcase', x: 0, y: 0, w: 60, h: 190 },
        { t: 'tvStand', x: 330, y: 0, w: 300, h: 55 },
        { t: 'sofa', x: 300, y: 330, w: 360, h: 110, face: 'n', color: 0x6a5a8f },
        { t: 'coffeeTable', x: 380, y: 200, w: 200, h: 80 },
        { t: 'armchair', x: 720, y: 330, w: 96, h: 96, face: 'n', color: 0x9a5a48 },
        { t: 'sideTable', x: 840, y: 350, w: 50, h: 50, ht: 62 },
        { t: 'lamp', x: 860, y: 470, w: 26, h: 26 },
        { t: 'plant', x: 892, y: 16, w: 52, h: 52 },
        { t: 'fireplace', x: 0, y: 250, w: 46, h: 150 },
        { t: 'ottoman', x: 150, y: 150, w: 50, h: 50 },
      ],
      cracks: [{ wall: 's', x: 600 }, { wall: 'w', y: 470 }, { wall: 'e', y: 540 }],
      knocks: [
        { kind: 'vase', x: 865, y: 375, to: [908, 382] },
        { kind: 'book', x: 352, y: 26, to: [352, 82] },
        { kind: 'cup', x: 550, y: 230, to: [598, 302] },
      ],
      music: { root: 55, minor: false, bpm: 70, prog: [[0, 'M'], [-3, 'm'], [-7, 'M'], [-5, 'M']] },
    },
    {
      id: 'pantry', name: 'The Pantry', goal: 14, night: 285,
      threats: ['cat', 'owner'],
      intro: { pups: ['Mom, we heard footsteps last night…', 'Squeak?', 'Be careful!'], mom: 'The pantry downstairs. The owner sleeps lightly. If he wakes up, I hide.' },
      pal: { fog: 0x0c100f, sky: 0x6f8a7a, ground: 0x2a2620, hemi: 0.66, moon: 0.55, floor: 'concrete', floorA: '#3e4541', wall: 'brick', wallA: '#6a4636', wallB: '#3a2a24', trim: 0x2a2420, ceil: 0x1c1e1c },
      lamp: 'bulb', window: { x: 220, w: 120, y: 205, h: 60 }, door: 300,
      catBed: [300, 480], dock: [900, 380],
      lights: [],
      decor: 'pantry',
      furn: [
        { t: 'shelfUnit', x: 480, y: 0, w: 200, h: 50 },
        { t: 'washer', x: 830, y: 12, w: 90, h: 80 },
        { t: 'washer', x: 730, y: 12, w: 90, h: 80, dryer: true },
        { t: 'basket', x: 700, y: 120, w: 52, h: 44, ht: 45 },
        { t: 'box', x: 40, y: 40, w: 70, h: 60, ht: 50 },
        { t: 'box', x: 110, y: 22, w: 60, h: 50, ht: 92 },
        { t: 'crate', x: 200, y: 150, w: 60, h: 60, ht: 40 },
        { t: 'crate', x: 260, y: 150, w: 60, h: 60, ht: 80 },
        { t: 'crate', x: 320, y: 150, w: 60, h: 60, ht: 120 },
        { t: 'bench', x: 470, y: 320, w: 180, h: 90 },
        { t: 'stool', x: 420, y: 352 },
        { t: 'cans', x: 130, y: 340, w: 44, h: 44 },
        { t: 'lowShelf', x: 640, y: 500, w: 80, h: 50 },
        { t: 'boiler', x: 870, y: 470, w: 80, h: 110 },
      ],
      cracks: [{ wall: 'w', y: 250 }, { wall: 's', x: 500 }, { wall: 'e', y: 180 }, { wall: 's', x: 800 }],
      knocks: [
        { kind: 'can', x: 352, y: 170, to: [352, 238] },
        { kind: 'bottle', x: 630, y: 340, to: [668, 352] },
        { kind: 'jar', x: 790, y: 40, to: [792, 120] },
      ],
      music: { root: 52, minor: true, bpm: 80, prog: [[0, 'm'], [-4, 'M'], [-7, 'm'], [-5, 'M']] },
    },
    {
      id: 'dining', name: 'The Dining Room', goal: 16, night: 300,
      threats: ['cat', 'owner', 'traps'],
      intro: { pups: ['Mom, we smell a feast!', 'Squeak squeak!', 'Bring the fancy cheese!'], mom: 'They had guests tonight. Lots of leftovers… and the owner set traps. If it smells like cheese but looks wrong, it’s a trap.' },
      pal: { fog: 0x120e14, sky: 0x9a8ab0, ground: 0x2e2228, hemi: 0.72, moon: 0.75, floor: 'wood', floorA: '#4a3226', wall: 'panel', wallA: '#5c3a46', wallB: '#2e1f1a', trim: 0x2a1c18, ceil: 0x241c22 },
      lamp: 'chandelier', window: { x: 660, w: 200 }, door: 330,
      catBed: [200, 480], dock: [900, 440],
      lights: [],
      decor: 'dining',
      furn: [
        { t: 'table', x: 330, y: 200, w: 300, h: 160, cloth: 0xd8d0c0, dining: true },
        { t: 'chair', x: 370, y: 162, back: 'n' }, { t: 'chair', x: 464, y: 162, back: 'n' }, { t: 'chair', x: 558, y: 162, back: 'n' },
        { t: 'chair', x: 370, y: 366, back: 's' }, { t: 'chair', x: 464, y: 366, back: 's' }, { t: 'chair', x: 558, y: 366, back: 's' },
        { t: 'chair', x: 292, y: 264, back: 'w' }, { t: 'chair', x: 636, y: 264, back: 'e' },
        { t: 'sideboard', x: 360, y: 0, w: 260, h: 55 },
        { t: 'ottoman', x: 440, y: 82, w: 46, h: 46 },
        { t: 'cabinetTall', x: 0, y: 90, w: 56, h: 220 },
        { t: 'ottoman', x: 720, y: 150, w: 46, h: 46 },
        { t: 'barCart', x: 780, y: 140, w: 70, h: 52 },
        { t: 'plant', x: 892, y: 16, w: 52, h: 52 },
        { t: 'plant', x: 892, y: 530, w: 52, h: 52 },
      ],
      cracks: [{ wall: 'w', y: 400 }, { wall: 's', x: 650 }, { wall: 'e', y: 200 }],
      knocks: [
        { kind: 'glass', x: 612, y: 216, to: [655, 222] },
        { kind: 'vase', x: 392, y: 24, to: [392, 72] },
        { kind: 'bottle', x: 830, y: 160, to: [832, 214] },
      ],
      music: { root: 53, minor: false, bpm: 74, prog: [[0, 'M'], [-3, 'm'], [-7, 'M'], [-5, 'M']] },
    },
    {
      id: 'kitchen2', name: 'The Kitchen, Again', goal: 20, night: 300,
      threats: ['cat', 'owner', 'traps', 'poison', 'vacuum'],
      intro: { pups: ['Mom, they’re hunting you!', 'Squeak!', 'Please come back!'], mom: 'One last big haul. They’re ready for me now… and so am I.' },
      pal: { fog: 0x101426, sky: 0x8a8fd0, ground: 0x2a2436, hemi: 0.78, moon: 0.9, floor: 'tile', floorA: '#383c5c', floorB: '#474c76', wall: 'stripes', wallA: '#474e70', wallB: '#50587c', trim: 0x3a2e30, ceil: 0x20243a },
      lamp: 'shade', window: { x: 410, w: 220 }, door: 320,
      catBed: [470, 545], bowl: [770, 215], dock: [900, 430],
      lights: [{ x: 900, y: 560, h: 60, c: 0xffa860, i: 1.0, r: 520 }],
      decor: 'kitchen', furn: kitchenFurniture, knocks: kitchenKnocks, cracks: kitchenCracks,
      music: { root: 50, minor: true, bpm: 88, prog: [[0, 'm'], [-4, 'M'], [-9, 'M'], [-2, 'M']] },
    },
  ];

  window.MENU_MUSIC = { root: 57, minor: true, bpm: 64, prog: [[0, 'm'], [-4, 'M'], [-9, 'M'], [-2, 'M']] };
})();
