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
//
// cat:     'away' (not in the room), 'sleep' (asleep, noise wakes it), 'awake' (prowls from the start)
// catSense multiplies how far the awake cat sees and hears (1 = normal)
// wanted:  show wanted stars. Stars make the house sharper; threats[] adds a new danger per star
// food:    { spots: [[type, x, y], ...] placed by hand (height comes from the furniture under it),
//            random: { crumb, cheese } extra random pieces, refill: keep at least this many, 0 = no refill }
// openFood: food is always visible. Otherwise it shows up only close by or after sniffing.
// goals:   the three goals of the night: 'fed' + two of 'early', 'nocatch', 'sleep', 'unseen'
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

  const livingPal = { fog: 0x10141a, sky: 0x8a9ab8, ground: 0x2e2620, hemi: 0.74, moon: 0.7, floor: 'wood', floorA: '#5a4232', wall: 'damask', wallA: '#3c5655', wallB: '#466361', trim: 0x2e2622, ceil: 0x26282e };
  const livingFurniture = [
    { t: 'bookcase', x: 0, y: 0, w: 60, h: 190 },
    { t: 'tvStand', x: 330, y: 0, w: 300, h: 55 },
    { t: 'sofa', x: 300, y: 330, w: 360, h: 110, face: 'n', color: 0x6a5a8f },
    { t: 'coffeeTable', x: 380, y: 200, w: 200, h: 80, plate: true },
    { t: 'armchair', x: 720, y: 330, w: 96, h: 96, face: 'n', color: 0x9a5a48 },
    { t: 'sideTable', x: 840, y: 350, w: 50, h: 50, ht: 62 },
    { t: 'lamp', x: 860, y: 470, w: 26, h: 26 },
    { t: 'plant', x: 892, y: 16, w: 52, h: 52 },
    { t: 'fireplace', x: 0, y: 250, w: 46, h: 150 },
    { t: 'ottoman', x: 150, y: 150, w: 50, h: 50 },
  ];
  const livingCracks = [{ wall: 's', x: 600 }, { wall: 'w', y: 470 }, { wall: 'e', y: 540 }];
  const livingKnocks = [
    { kind: 'vase', x: 865, y: 375, to: [908, 382] },
    { kind: 'book', x: 352, y: 26, to: [352, 82] },
    { kind: 'cup', x: 550, y: 230, to: [598, 302] },
  ];

  window.THREATS = {
    cat: { name: 'the cat', label: 'The cat is awake', banner: 'The cat woke up', tip: 'It can’t climb after you, but it will wait below. Hide in a green spot to lose it' },
    owner: { name: 'the owner', label: 'The owner is up', banner: 'The owner woke up', tip: 'With a flashlight he can spot you even on tables. Hide under furniture or in a crack' },
    traps: { name: 'mousetraps', label: 'Mousetraps on the floor', banner: 'Mousetraps!', tip: 'The owner set traps. They smell like cheese too, so sniff first (hold E)' },
    poison: { name: 'poison', label: 'Poison in the cheese', banner: 'Poisoned cheese', tip: 'Poisoned cheese smells green. Sniff before you grab' },
    vacuum: { name: 'a robot vacuum', label: 'Robot vacuum on patrol', banner: 'Robot vacuum!', tip: 'It roams everywhere, even under furniture, and beeps loudly when it bumps into you' },
  };

  window.GOALS = {
    fed: 'Feed the pups',
    early: 'Finish before 1:00 AM',
    nocatch: 'Never get caught',
    sleep: 'Don’t wake the cat',
    unseen: 'Never get chased',
  };

  window.LEVELS = [
    {
      id: 'kitchen', name: 'The Kitchen', act: 1, goal: 8, night: 300,
      cat: 'away', wanted: false, threats: [], openFood: true, tutorial: true,
      food: { spots: [], random: { crumb: 12, cheese: 4 }, refill: 10 },
      goals: ['fed', 'early', 'nocatch'],
      blurb: 'Everyone is asleep. Food is everywhere.',
      teaser: 'The living room. The cat sleeps there, so you’ll have to be quiet.',
      intro: { pups: ['Mom, we’re hungry!', 'Squeak!', 'We want cheese!'], mom: 'Everyone is asleep, even the cat is out. Food is everywhere tonight. Let’s grab it.' },
      start: { title: 'Bring 8 food to the nest', sub: 'Nobody is around tonight. Learn the ropes and grab what you can.' },
      pal: { fog: 0x0e1220, sky: 0x7d8fc4, ground: 0x2a2430, hemi: 0.8, moon: 0.9, floor: 'tile', floorA: '#3b4058', floorB: '#4a5070', wall: 'stripes', wallA: '#4b5272', wallB: '#545c80', trim: 0x3a2e30, ceil: 0x22263a },
      lamp: 'shade', window: { x: 410, w: 220 }, door: 320,
      catBed: [470, 545], bowl: [770, 215], dock: [900, 430],
      lights: [{ x: 900, y: 560, h: 60, c: 0xffa860, i: 1.0, r: 520 }],
      decor: 'kitchen', furn: kitchenFurniture, knocks: kitchenKnocks, cracks: kitchenCracks,
      music: { root: 57, minor: false, bpm: 70, prog: [[0, 'M'], [-5, 'M'], [-3, 'm'], [-7, 'M']] },
    },
    {
      id: 'living', name: 'The Sleeping Cat', act: 1, goal: 12, night: 300,
      cat: 'sleep', catSense: 1, wanted: true, threats: [], openFood: true,
      food: {
        spots: [
          ['cheese', 440, 246], ['crumb', 472, 228], ['crumb', 506, 262],   // the plate on the coffee table
          ['cheese', 688, 476],                                             // fell behind the sofa
          ['crumb', 340, 308], ['crumb', 430, 312], ['crumb', 548, 310],   // crumbs in front of the sofa
          ['cheese', 560, 28],                                              // on the TV stand
          ['crumb', 262, 548], ['crumb', 165, 455],                         // right next to the cat bed
          ['crumb', 80, 150], ['crumb', 760, 250], ['crumb', 900, 250],
        ],
        random: { crumb: 0, cheese: 0 }, refill: 0,
      },
      goals: ['fed', 'sleep', 'nocatch'],
      blurb: 'The cat is asleep. Running and loud landings wake it up.',
      teaser: 'Same room, but the cat is up and prowling now.',
      intro: { pups: ['Mom, can we have chips?', 'Squeak!', 'We’re sooo hungry!'], mom: 'Snacks all over the living room… and the cat is asleep right by our hole. Quiet now, slow and quiet.' },
      start: { title: 'Bring 12 food. Don’t wake the cat', sub: 'Running and jumping down make noise. Hold Ctrl (or press C) to sneak.' },
      starTip: 'The cat sleeps lighter now',
      pal: livingPal, lamp: 'shade', window: { x: 680, w: 200 }, door: 240,
      catBed: [215, 500], dock: [900, 330], lights: [], decor: 'living',
      furn: livingFurniture, cracks: livingCracks, knocks: livingKnocks,
      music: { root: 55, minor: false, bpm: 66, prog: [[0, 'M'], [-3, 'm'], [-7, 'M'], [-5, 'M']] },
    },
    {
      id: 'living2', name: 'The Prowling Cat', act: 1, goal: 12, night: 300,
      cat: 'awake', catSense: 1.15, catStart: [700, 180], wanted: true, threats: [], openFood: true,
      food: {
        spots: [
          ['cheese', 420, 28],                         // TV stand
          ['cheese', 520, 252],                        // coffee table
          ['cheese', 175, 175],                        // ottoman
          ['cheese', 770, 470],                        // behind the armchair
          ['crumb', 90, 120], ['crumb', 270, 300], ['crumb', 700, 300], ['crumb', 880, 200],
          ['crumb', 620, 560], ['crumb', 360, 480], ['crumb', 900, 450], ['crumb', 230, 80],
        ],
        random: { crumb: 0, cheese: 0 }, refill: 0,
      },
      goals: ['fed', 'unseen', 'nocatch'],
      blurb: 'The cat is awake and watching. Stay out of its sight.',
      teaser: 'More nights are on the way.',
      intro: { pups: ['Mom, the cat was meowing all day!', 'Squeak…', 'Be careful!'], mom: 'The cat didn’t sleep after last night. It’s walking around now. I’ll stay in the shadows and hide when it looks my way.' },
      start: { title: 'Bring 12 food. The cat is awake', sub: 'Watch its sight cone. Hide under furniture or in a crack when it comes close.' },
      starTip: 'The cat is faster and sharper now',
      pal: Object.assign({}, livingPal, { hemi: 0.7, moon: 0.62 }), lamp: 'shade', window: { x: 680, w: 200 }, door: 240,
      catBed: [215, 500], dock: [900, 330], lights: [], decor: 'living',
      furn: livingFurniture, cracks: livingCracks, knocks: livingKnocks,
      music: { root: 53, minor: true, bpm: 72, prog: [[0, 'm'], [-4, 'M'], [-7, 'm'], [-5, 'M']] },
    },
  ];

  // The full game will have 20 nights. Nights past the playable ones are listed as "in development".
  window.PLANNED = [
    ['The Pantry', 'Food is hidden. Stand up and sniff it out.'],
    ['The Kitchen, Again', 'Knock things over to lure the cat away.'],
    ['A Glass of Water', 'The owner comes down for a drink.'],
    ['The Flashlight', 'The owner patrols with a flashlight.'],
    ['Dinner Leftovers', 'Paths inside the walls.'],
    ['The Laundry Room', 'The cat eats at night. Time it right.'],
    ['The Storm', 'Thunder hides your noise. Lightning shows you.'],
    ['Mousetraps', 'Sniff to tell cheese from a trap.'],
    ['Sticky Traps', 'Get stuck and you make a racket.'],
    ['The Kids’ Room', 'Squeaky toys all over the floor.'],
    ['The Party', 'Guests stayed the night.'],
    ['Poison', 'Green scent means poison.'],
    ['The Robot Vacuum', 'It eats the crumbs before you do.'],
    ['The Dog', 'It follows your scent.'],
    ['The Basement', 'The cracks are sealed. Find a new way.'],
    ['The Whole Floor', 'Every room, every danger.'],
    ['Moving Out', 'Lead the pups out of the house.'],
  ];
  window.TOTAL_NIGHTS = window.LEVELS.length + window.PLANNED.length;

  window.MENU_MUSIC = { root: 57, minor: true, bpm: 64, prog: [[0, 'm'], [-4, 'M'], [-9, 'M'], [-2, 'M']] };
})();
