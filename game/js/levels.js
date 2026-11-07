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

  const pantryFurniture = [
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
      ];
  const pantryCracks = [{ wall: 'w', y: 250 }, { wall: 's', x: 500 }, { wall: 'e', y: 180 }, { wall: 's', x: 800 }];

  const diningFurniture = [
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
      ];
  const diningPal = { fog: 0x120e14, sky: 0x9a8ab0, ground: 0x2e2228, hemi: 0.7, moon: 0.75, floor: 'wood', floorA: '#4a3226', wall: 'panel', wallA: '#5c3a46', wallB: '#2e1f1a', trim: 0x2a1c18, ceil: 0x241c22 };
  const diningCracks = [{ wall: 'w', y: 400 }, { wall: 's', x: 650 }, { wall: 'e', y: 200 }];

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
      id: 'kitchen', name: 'The Kitchen', act: 1, goal: 15, night: 900, prologue: true,
      cat: 'away', wanted: false, threats: [], openFood: true,
      food: {
        spots: [
          ['crumb', 585, 548, { tag: 'first' }],            // the first crumb, by the table
          ['cheese', 680, 432, { tag: 'plate' }],           // on the plate on the table
          ['cheese', 116, 30, { tag: 'bread', hidden: true }], // on the counter next to the bread box, only found by sniffing
          ['cheese', 232, 470],                             // just past the foil
        ],
        random: { crumb: 10, cheese: 3 }, refill: 8,
      },
      // Tasks: the chain is shown one step at a time in the bottom-left list. check = [type, arg]:
      //   pick <tag> · deliver [tag] · surf <id prefix> · hide crack · knock <kind> · flag <name> · keep <knock kind>
      tasks: {
        goal: 'Fill the nest',
        chain: [
          { text: 'Pick up the crumb by the table', hint: 'Walk over food to pick it up. Move with WASD, look around with the mouse.', check: ['pick', 'first'] },
          { text: 'Take it home to the nest', hint: 'The nest is the glowing hole in the corner. The arrow at the bottom of the screen shows the way.', check: ['deliver'] },
          { text: 'Jump onto a chair', hint: 'Walk up to a chair and face it. When the yellow ring appears, press Space.', check: ['surf', 'chair'] },
          { text: 'Climb from the chair onto the table', hint: 'From the chair, face the table and press Space when the ring appears.', check: ['surf', 'table'] },
          { text: 'Take the cheese from the plate', hint: 'A cheese is worth 5 crumbs. Careful: walk slowly past the mug on the edge.', check: ['pick', 'plate'] },
          { text: 'Bring the cheese home', hint: 'Walk to the edge of the table and press Space to jump down, then head for the nest.', check: ['deliver', 'plate'] },
          { text: 'Sneak across the foil without a sound', hint: 'Hold Ctrl or press C to sneak. Walking on foil makes it crinkle loudly.', check: ['flag', 'foilSneak'] },
          { text: 'Hide in a crack in the wall', hint: 'Cracks are dark gaps at the bottom of the walls. Green outlines mark every hiding spot.', check: ['hide', 'crack'] },
          { text: 'Stand up and sniff', hint: 'Hold E or the right mouse button. Thin trails of scent lead to the nearest food.', check: ['flag', 'sniffed'] },
          { text: 'Find the cheese hidden by the bread box', hint: 'The bread box is up on the counter. Climb the stool, jump to the counter and sniff there.', check: ['pick', 'bread'] },
          { text: 'Climb onto the kitchen island', hint: 'It’s too high to reach from the floor. Use the cardboard box next to it as a step.', check: ['surf', 'island'] },
          { text: 'Push the apple off the island', hint: 'Walk up to the apple and press F. Falling things make noise, and later you can use that to lure the cat away.', check: ['knock', 'apple'] },
        ],
        side: [
          { text: 'Leave the mug on the table', reveal: 3, check: ['keep', 'cup'] },
          { text: 'Carry 3 pieces home at once', reveal: 2, check: ['flag', 'full'] },
        ],
        secret: [{ text: 'Find the shiny button', check: ['flag', 'button'] }],
      },
      secrets: [{ kind: 'button', x: 895, y: 198 }],
      props: [{ t: 'foil', x: 150, y: 386, w: 160, h: 56 }, { t: 'breadbox', x: 140, y: 10, w: 56, h: 34 }],
      teaser: 'The living room. The cat sleeps there, so you’ll have to be quiet.',
      blurb: 'Your first night out. Nobody is home.',
      intro: { pups: ['Mom, we’re hungry!', 'Squeak!', 'We want cheese!'], mom: 'Everyone is asleep, even the cat is out. Food is everywhere tonight. A good night to learn the house.' },
      start: { title: 'Your first night out', sub: 'Nobody is home. Follow the tasks in the bottom-left corner.' },
      pal: { fog: 0x0e1220, sky: 0x7d8fc4, ground: 0x2a2430, hemi: 0.8, moon: 0.9, floor: 'tile', floorA: '#3b4058', floorB: '#4a5070', wall: 'stripes', wallA: '#4b5272', wallB: '#545c80', trim: 0x3a2e30, ceil: 0x22263a },
      lamp: 'shade', window: { x: 410, w: 220 }, door: 320,
      catBed: [470, 545], bowl: [770, 215], dock: [900, 430],
      lights: [{ x: 900, y: 560, h: 60, c: 0xffa860, i: 1.0, r: 520 }],
      decor: 'kitchen', furn: kitchenFurniture, cracks: kitchenCracks,
      knocks: [
        { kind: 'cup', x: 655, y: 398, to: [655, 362], trap: true },   // on the edge: walk past it and it falls
        { kind: 'jar', x: 470, y: 60, to: [470, 102] },
        { kind: 'apple', x: 520, y: 330, to: [522, 364] },
      ],
      music: { root: 57, minor: false, bpm: 70, prog: [[0, 'M'], [-5, 'M'], [-3, 'm'], [-7, 'M']] },
    },
    {
      id: 'living', name: 'The Sleeping Cat', act: 1, goal: 12, night: 720,
      cat: 'sleep', wanted: true, threats: [], openFood: true, tvOff: true,
      food: {
        spots: [
          ['cheese', 440, 246, { tag: 'plate' }], ['crumb', 472, 228], ['crumb', 506, 262],   // the plate on the coffee table
          ['cheese', 688, 476],                                                               // fell behind the sofa
          ['crumb', 340, 308, { tag: 'sofa1' }], ['crumb', 430, 312, { tag: 'sofa2' }], ['crumb', 548, 310, { tag: 'sofa3' }], ['crumb', 610, 306, { tag: 'sofa4' }],
          ['cheese', 560, 28, { tag: 'tv' }],                                                 // on the TV stand
          ['crumb', 262, 548, { tag: 'bed' }], ['crumb', 165, 455],                           // right next to the cat bed
          ['crumb', 80, 150], ['crumb', 760, 250], ['crumb', 900, 250], ['crumb', 880, 540],
        ],
        random: { crumb: 0, cheese: 0 }, refill: 0,
      },
      tasks: {
        goal: 'Fill the nest',
        chain: [
          { text: 'Sneak past the sleeping cat', hint: 'The cat sleeps right by our hole. Hold Ctrl (or press C) and sneak past. Watch the Zzz bar above it.', check: ['flag', 'passCat'] },
          { text: 'Take the cheese from the plate', hint: 'The plate is on the coffee table. Don’t land on it or run across it: it clinks.', check: ['pick', 'plate'] },
          { text: 'Carry the cheese home past the cat', hint: 'Sneak by the cat again. Running near it drains the Zzz bar fast.', check: ['deliver', 'plate'] },
          { text: 'Pick up 3 crumbs in front of the sofa', hint: 'Stay on the floor: jumping onto the sofa makes your claws scratch the fabric.', check: ['pickN', 'sofa', 3] },
          { text: 'Get the cheese from the TV stand', hint: 'Careful with the remote on the sofa. Step on it and the TV comes on.', check: ['pick', 'tv'] },
        ],
        side: [
          { text: 'Don’t wake the cat', check: ['keep', 'catWoke'] },
          { text: 'Grab the crumb right next to the cat bed', reveal: 1, check: ['pick', 'bed'] },
          { text: 'Find a soft sock for the nest', reveal: 3, check: ['flag', 'sock'] },
        ],
        secret: [{ text: 'Find the toy mouse', check: ['flag', 'toy'] }],
      },
      props: [
        { t: 'noisy', kind: 'plate', x: 440, y: 250, r: 16 },
        { t: 'noisy', kind: 'sofa', surf: 'sofa', x: 300, y: 330, w: 516, h: 110 },
        { t: 'noisy', kind: 'remote', x: 560, y: 372 },
        { t: 'noisy', kind: 'squeaky', x: 252, y: 452 },
        { t: 'noisy', kind: 'board', x: 52, y: 408, w: 120, h: 18 },
      ],
      secrets: [{ kind: 'sock', x: 768, y: 400, floor: true, always: true }, { kind: 'toy', x: 70, y: 226, floor: true }],
      blurb: 'The cat is asleep. Running and loud landings wake it up.',
      teaser: 'Same room, but the cat is up and prowling now.',
      intro: { pups: ['Mom, can we have chips?', 'Squeak!', 'We’re sooo hungry!'], mom: 'Snacks all over the living room… and the cat is asleep right by our hole. Quiet now, slow and quiet.' },
      start: { title: 'The cat is asleep', sub: 'Don’t wake it. Follow the tasks in the bottom-left corner.' },
      starTip: 'The cat sleeps lighter now',
      pal: livingPal, lamp: 'shade', window: { x: 680, w: 200 }, door: 240,
      catBed: [215, 500], dock: [900, 330], lights: [], decor: 'living',
      furn: livingFurniture, cracks: livingCracks, knocks: livingKnocks,
      music: { root: 55, minor: false, bpm: 66, prog: [[0, 'M'], [-3, 'm'], [-7, 'M'], [-5, 'M']] },
    },
    {
      id: 'living2', name: 'The Prowling Cat', act: 1, goal: 12, night: 720,
      cat: 'awake', catSense: 1.15, catStart: [700, 180], catBell: true, wanted: true, threats: [], openFood: true, tvOff: true,
      food: {
        spots: [
          ['cheese', 372, 28, { tag: 'q1' }], ['cheese', 520, 252, { tag: 'q2' }], ['cheese', 175, 175, { tag: 'q3' }], ['cheese', 770, 470, { tag: 'q4' }],
          ['cheese', 300, 562, { tag: 'treat' }],                                         // the cat's treat, by its bowl
          ['crumb', 90, 120], ['crumb', 270, 300], ['crumb', 700, 300], ['crumb', 880, 200],
          ['crumb', 620, 560], ['crumb', 360, 480], ['crumb', 900, 450], ['crumb', 230, 80],
        ],
        random: { crumb: 0, cheese: 0 }, refill: 0,
      },
      tasks: {
        goal: 'Fill the nest',
        chain: [
          { text: 'Hide while the cat walks past', hint: 'Listen for the bell on its collar. When it comes close, get under furniture or into a crack.', check: ['flag', 'hidNearCat'] },
          { text: 'Collect 4 cheeses from around the room', hint: 'One on the TV stand, one on the coffee table, one on the footstool and one behind the armchair.', check: ['pickN', 'q', 4] },
          { text: 'Sneak under the sofa', hint: 'Under the sofa the cat can’t reach you. It’s also a shortcut across the room.', check: ['hide', 'sofa'] },
          { text: 'Hide in a crack in the wall', hint: 'Cracks are the dark gaps at the bottom of the walls. The cat can’t get in.', check: ['hide', 'crack'] },
        ],
        side: [
          { text: 'Never get chased', check: ['keep', 'chased'] },
          { text: 'Steal the cat’s treat from by its bowl', reveal: 1, check: ['pick', 'treat'] },
        ],
        secret: [{ text: 'Find the thimble', check: ['flag', 'thimble'] }],
      },
      props: [
        { t: 'noisy', kind: 'plate', x: 440, y: 250, r: 16 },
        { t: 'noisy', kind: 'sofa', surf: 'sofa', x: 300, y: 330, w: 516, h: 110 },
        { t: 'noisy', kind: 'remote', x: 420, y: 372 },
        { t: 'noisy', kind: 'squeaky', x: 252, y: 452 },
        { t: 'noisy', kind: 'board', x: 52, y: 408, w: 120, h: 18 },
        { t: 'noisy', kind: 'cord', x: 740, y: 500, w: 120, h: 12 },
      ],
      secrets: [{ kind: 'thimble', x: 480, y: 240, floor: true }],
      blurb: 'The cat is awake and watching. Stay out of its sight.',
      teaser: 'The pantry. Food is hidden there, so you’ll need your nose.',
      intro: { pups: ['Mom, the cat was meowing all day!', 'Squeak…', 'Be careful!'], mom: 'The cat didn’t sleep after last night. It’s walking around now. I’ll stay in the shadows and hide when it looks my way.' },
      start: { title: 'The cat is awake', sub: 'Listen for its bell. Watch its sight cone and hide when it comes close.' },
      starTip: 'The cat is faster and sharper now',
      pal: Object.assign({}, livingPal, { hemi: 0.7, moon: 0.62 }), lamp: 'shade', window: { x: 680, w: 200 }, door: 240,
      catBed: [215, 500], bowl: [262, 560], dock: [900, 330], lights: [], decor: 'living',
      furn: livingFurniture, cracks: livingCracks, knocks: livingKnocks,
      music: { root: 53, minor: true, bpm: 72, prog: [[0, 'm'], [-4, 'M'], [-7, 'm'], [-5, 'M']] },
    },
    {
      id: 'pantry', name: 'The Pantry', act: 1, goal: 14, night: 720,
      cat: 'sleep', sleepSense: 1.6, wanted: true, threats: [], openFood: false,
      food: {
        spots: [
          ['cheese', 560, 360, { tag: 'cache1', hidden: true }],                 // on the workbench
          ['cheese', 350, 180, { tag: 'cache2', hidden: true }],                 // on top of the crate stairs
          ['cheese', 680, 525, { tag: 'cache3', hidden: true, floor: true }],    // under the low shelf
          ['crumb', 120, 300], ['crumb', 420, 520], ['crumb', 760, 300], ['crumb', 900, 250], ['crumb', 230, 470],
        ],
        random: { crumb: 3, cheese: 1 }, refill: 4,
      },
      tasks: {
        goal: 'Fill the nest',
        chain: [
          { text: 'Sniff out a hidden cache', hint: 'Food is hidden tonight. Hold E to stand up and sniff: scent trails lead to it.', check: ['pickN', 'cache', 1] },
          { text: 'Gnaw open the grain sack', hint: 'Hold F next to the sack by the washing machines. Gnawing is loud: check the cat’s Zzz bar first.', check: ['flag', 'gnaw'] },
          { text: 'Push the box off the top of the stack', hint: 'Climb the boxes in the corner by the window. Push the top box (F) and a cheese falls out.', check: ['knock', 'carton'] },
          { text: 'Find all 3 hidden caches', hint: 'One is on the workbench, one up the crates, one under the low shelf. Sniff to see them.', check: ['pickN', 'cache', 3] },
        ],
        side: [
          { text: 'Don’t wake the cat', check: ['keep', 'catWoke'] },
          { text: 'Don’t knock over the cans on the workbench', check: ['keep', 'can'] },
        ],
        secret: [{ text: 'Find the old photo', check: ['flag', 'photo'] }],
      },
      props: [
        { t: 'gnaw', x: 790, y: 200, spawn: 5 },
        { t: 'noisy', kind: 'bag', x: 580, y: 440, w: 56, h: 40 },
        { t: 'noisy', kind: 'bag', x: 200, y: 240, w: 60, h: 36 },
        { t: 'noisy', kind: 'grain', x: 420, y: 300, r: 26 },
      ],
      secrets: [{ kind: 'photo', x: 856, y: 560, floor: true }],
      blurb: 'Food is hidden. Sniff it out, and don’t wake the light-sleeping cat.',
      teaser: 'The kitchen again. The cat is awake and the food is hidden.',
      intro: { pups: ['Mom, we smell something yummy downstairs!', 'Squeak?', 'Hurry back!'], mom: 'The pantry. They hide the good stuff in there. I’ll need my nose tonight… and the cat sleeps lightly.' },
      start: { title: 'Food is hidden tonight', sub: 'Hold E to sniff. The cat sleeps lightly, so keep it quiet.' },
      starTip: 'The cat sleeps even lighter now',
      pal: { fog: 0x0c100f, sky: 0x6f8a7a, ground: 0x2a2620, hemi: 0.64, moon: 0.55, floor: 'concrete', floorA: '#3e4541', wall: 'brick', wallA: '#6a4636', wallB: '#3a2a24', trim: 0x2a2420, ceil: 0x1c1e1c },
      lamp: 'bulb', window: { x: 220, w: 120, y: 205, h: 60 }, door: 300,
      catBed: [300, 480], dock: [900, 380], lights: [], decor: 'pantry',
      furn: pantryFurniture,
      cracks: pantryCracks,
      knocks: [
        { kind: 'can', x: 500, y: 332, to: [500, 300], trap: true, group: 'cans' },   // cans on the workbench: walk past and they topple like dominoes
        { kind: 'can', x: 522, y: 332, to: [524, 296], trap: true, group: 'cans' },
        { kind: 'can', x: 544, y: 332, to: [548, 300], trap: true, group: 'cans' },
        { kind: 'carton', x: 140, y: 44, to: [140, 100], spawn: 'cheese' },
        { kind: 'bottle', x: 630, y: 340, to: [668, 352] },
      ],
      music: { root: 52, minor: true, bpm: 76, prog: [[0, 'm'], [-4, 'M'], [-7, 'm'], [-5, 'M']] },
    },
    {
      id: 'kitchen2', name: 'The Kitchen, Again', act: 1, goal: 16, night: 720,
      cat: 'awake', catSense: 1.2, catStart: [520, 470], catBell: true, wanted: true, threats: [], openFood: false,
      food: {
        spots: [
          ['cheese', 600, 36, { tag: 'h1', hidden: true }],                // on the counter
          ['cheese', 230, 325, { tag: 'h2', hidden: true, floor: true }],  // under the low shelf
          ['cheese', 760, 470, { tag: 'h3', hidden: true }],               // on the table
          ['sausage', 796, 222, { tag: 'sausage' }],                       // in the cat's bowl
          ['crumb', 300, 200], ['crumb', 160, 520], ['crumb', 680, 560], ['crumb', 900, 520], ['crumb', 420, 420],
        ],
        random: { crumb: 4, cheese: 1 }, refill: 5,
      },
      tasks: {
        goal: 'Fill the nest',
        chain: [
          { text: 'Knock something down to lure the cat away', hint: 'Push the spoon or the jar off the counter (F). The cat runs over to check the noise.', check: ['count', 'lure', 1] },
          { text: 'Sniff out 3 hidden cheeses', hint: 'Hold E. One is up on the counter, one under the low shelf, one on the table.', check: ['pickN', 'h', 3] },
          { text: 'Steal the sausage from the cat’s bowl', hint: 'The bowl is by the fridge. Lure the cat away first. The fridge hum hides your footsteps there.', check: ['pick', 'sausage'] },
          { text: 'Drag the sausage home', hint: 'It’s heavy: you move slowly, can’t jump up, and it scrapes the floor. Sneak to make it quieter.', check: ['deliver', 'sausage'] },
        ],
        side: [
          { text: 'Lure the cat away 3 times', check: ['count', 'lure', 3] },
          { text: 'Don’t knock over the drying glasses', check: ['keep', 'glass'] },
        ],
        secret: [{ text: 'Find the glass marble', check: ['flag', 'marble'] }],
      },
      props: [
        { t: 'hum', x: 885, y: 210, r: 130 },
        { t: 'noisy', kind: 'puddle', x: 480, y: 112, r: 26 },
        { t: 'noisy', kind: 'board', x: 250, y: 520, w: 110, h: 18 },
        { t: 'noisy', kind: 'bag', x: 620, y: 300, w: 50, h: 36 },
      ],
      secrets: [{ kind: 'marble', x: 98, y: 360, floor: true }],
      blurb: 'The cat is awake and the food is hidden. Lure it away and steal its sausage.',
      teaser: 'The owner is starting to notice. More nights are on the way.',
      intro: { pups: ['Mom, the cat has a big sausage!', 'Squeak squeak!', 'Get it, Mom!'], mom: 'The kitchen again. The cat is up, and it has a sausage in its bowl. A little noise in the right place should send it running.' },
      start: { title: 'Lure the cat, steal the sausage', sub: 'Knock things down (F) to send the cat to the noise.' },
      starTip: 'The cat is faster and sharper now',
      pal: { fog: 0x101426, sky: 0x8a8fd0, ground: 0x2a2436, hemi: 0.76, moon: 0.86, floor: 'tile', floorA: '#383c5c', floorB: '#474c76', wall: 'stripes', wallA: '#474e70', wallB: '#50587c', trim: 0x3a2e30, ceil: 0x20243a },
      lamp: 'shade', window: { x: 410, w: 220 }, door: 320,
      catBed: [470, 545], bowl: [770, 215], dock: [900, 430],
      lights: [{ x: 900, y: 560, h: 60, c: 0xffa860, i: 1.0, r: 520 }],
      decor: 'kitchen', furn: kitchenFurniture, cracks: kitchenCracks,
      knocks: [
        { kind: 'spoon', x: 300, y: 44, to: [300, 102] },
        { kind: 'jar', x: 470, y: 60, to: [470, 102] },
        { kind: 'apple', x: 520, y: 330, to: [522, 364] },
        { kind: 'glass', x: 700, y: 40, to: [700, 104], trap: true, group: 'dishes' },
        { kind: 'glass', x: 724, y: 40, to: [728, 110], trap: true, group: 'dishes' },
        { kind: 'glass', x: 748, y: 40, to: [756, 104], trap: true, group: 'dishes' },
      ],
      music: { root: 50, minor: true, bpm: 84, prog: [[0, 'm'], [-4, 'M'], [-9, 'M'], [-2, 'M']] },
    },

    // ================= ACT 2 · THE OWNER =================
    {
      id: 'water', name: 'A Glass of Water', act: 2, goal: 14, night: 720,
      cat: 'sleep', wanted: true, threats: [], openFood: true,
      owner: { type: 'water', at: [40, 250, 470], stand: [480, 104], face: -Math.PI / 2, stay: 16 },
      food: {
        spots: [
          ['crumb', 660, 420, { tag: 'tbl1' }], ['crumb', 720, 470, { tag: 'tbl2' }], ['crumb', 780, 420, { tag: 'tbl3' }],   // on the table
          ['cookie', 470, 300, { tag: 'cookie' }], ['cookie', 540, 296, { tag: 'cookie2' }],                                  // the open cookie pack on the island
          ['cheese', 116, 30, { hidden: true }], ['crumb', 300, 460], ['crumb', 880, 520], ['crumb', 160, 200],
        ],
        random: { crumb: 4, cheese: 1 }, refill: 5,
      },
      tasks: {
        goal: 'Fill the nest',
        chain: [
          { text: 'Pick up the crumbs on the table', hint: 'Climb a chair, then the table. Grab 3 crumbs.', check: ['pickN', 'tbl', 3] },
          { text: 'Hide when the owner comes in', hint: 'Footsteps and a light under the door: the owner is coming. Get under furniture or into a crack.', check: ['flag', 'hidFromOwner'] },
          { text: 'Steal a cookie while he drinks', hint: 'He drinks at the sink with his back to the room. The cookies are on the island behind him.', check: ['flag', 'underNose'] },
          { text: 'Wait until he goes back to bed', hint: 'Stay hidden until the door closes and the light goes off.', check: ['count', 'ownerLeft', 1] },
        ],
        side: [
          { text: 'Never get spotted by the owner', reveal: 1, check: ['keep', 'seenOwner'] },
          { text: 'Don’t wake the cat', check: ['keep', 'catWoke'] },
        ],
        secret: [{ text: 'Find the bottle cap', check: ['flag', 'button'] }],
      },
      props: [
        { t: 'noisy', kind: 'glasses', x: 770, y: 215, r: 20 },
        { t: 'noisy', kind: 'bag', x: 500, y: 284, w: 40, h: 24 },
        { t: 'noisy', kind: 'board', x: 180, y: 86, w: 110, h: 16 },
      ],
      secrets: [{ kind: 'button', label: 'A shiny bottle cap!', x: 262, y: 560, floor: true }],
      blurb: 'The owner comes down for a drink. Hide, then steal right under his nose.',
      teaser: 'The pantry, and the owner patrols with a flashlight.',
      intro: { pups: ['Mom, we heard footsteps upstairs!', 'Squeak…', 'Is it the big human?'], mom: 'The owner noticed food going missing. He gets up at night for water. When he comes, I hide. When he drinks, I take.' },
      start: { title: 'The owner wakes up at night', sub: 'When you hear footsteps, hide. When he drinks, steal.' },
      starTip: 'The cat sleeps lighter now',
      pal: { fog: 0x0e1220, sky: 0x7d8fc4, ground: 0x2a2430, hemi: 0.74, moon: 0.84, floor: 'tile', floorA: '#3b4058', floorB: '#4a5070', wall: 'stripes', wallA: '#4b5272', wallB: '#545c80', trim: 0x3a2e30, ceil: 0x22263a },
      lamp: 'shade', window: { x: 410, w: 220 }, door: 320,
      catBed: [470, 545], bowl: [770, 215], dock: [900, 430],
      lights: [{ x: 900, y: 560, h: 60, c: 0xffa860, i: 1.0, r: 520 }],
      decor: 'kitchen', furn: kitchenFurniture, cracks: kitchenCracks,
      knocks: [{ kind: 'jar', x: 470, y: 60, to: [470, 102] }, { kind: 'cup', x: 655, y: 398, to: [655, 362], trap: true }],
      music: { root: 57, minor: true, bpm: 70, prog: [[0, 'm'], [-5, 'm'], [-3, 'M'], [-7, 'M']] },
    },
    {
      id: 'flashlight', name: 'The Flashlight', act: 2, goal: 16, night: 720,
      cat: 'sleep', sleepSense: 1.2, wanted: true, threats: [], openFood: false,
      owner: { type: 'patrol', light: false, at: [25, 210, 400, 580], route: [[700, 300], [420, 470], [200, 330], [560, 250], [850, 420]] },
      food: {
        spots: [
          ['crumb', 350, 176, { tag: 'top' }], ['sausage', 345, 186, { tag: 'salami' }],     // on the top crate
          ['cheese', 560, 360, { hidden: true }], ['cheese', 680, 525, { hidden: true, floor: true }], ['cheese', 140, 44, { hidden: true }],
          ['crumb', 120, 300], ['crumb', 420, 520], ['crumb', 760, 300], ['crumb', 900, 250], ['crumb', 230, 470],
        ],
        random: { crumb: 3, cheese: 1 }, refill: 4,
      },
      tasks: {
        goal: 'Fill the nest',
        chain: [
          { text: 'Stay hidden through a flashlight patrol', hint: 'He sweeps the room with his flashlight, then leaves. Keep out of the beam: hide under the workbench or in a crack.', check: ['count', 'ownerClean', 1] },
          { text: 'Climb to the top of the crate stairs', hint: 'The crates go up like stairs: 40, 80, 120. Grab the crumb on top.', check: ['pick', 'top'] },
          { text: 'Steal the salami from the top crate', hint: 'It’s heavy. You can jump down with it, but not up.', check: ['pick', 'salami'] },
          { text: 'Drag the salami home', hint: 'Slow and noisy. Time it between patrols.', check: ['deliver', 'salami'] },
        ],
        side: [
          { text: 'Take the spare battery (his flashlight will die)', check: ['flag', 'battery'] },
          { text: 'Don’t wake the cat', check: ['keep', 'catWoke'] },
        ],
        secret: [{ text: 'Find the lost key', check: ['flag', 'button'] }],
      },
      props: [
        { t: 'noisy', kind: 'bag', x: 580, y: 440, w: 56, h: 40 },
        { t: 'noisy', kind: 'grain', x: 420, y: 300, r: 26 },
        { t: 'noisy', kind: 'hanger', x: 700, y: 180, w: 40, h: 20 },
      ],
      secrets: [{ kind: 'battery', x: 820, y: 560, floor: true, always: true }, { kind: 'button', label: 'A lost key! The owner looked everywhere for it.', x: 60, y: 140, floor: true }],
      blurb: 'The owner patrols with a flashlight. Stay out of the beam.',
      teaser: 'The dining room, and the paths inside the walls.',
      intro: { pups: ['Mom, there was a light under the door!', 'Squeak!', 'Stay in the dark!'], mom: 'He walks around with a flashlight now. The beam is narrow. If I stay out of it, he won’t see me.' },
      start: { title: 'Flashlight patrol', sub: 'He comes and goes. Watch the beam and hide.' },
      starTip: 'The cat sleeps lighter now',
      pal: { fog: 0x0a0d0c, sky: 0x5f7a6a, ground: 0x221f1a, hemi: 0.5, moon: 0.45, floor: 'concrete', floorA: '#3a403d', wall: 'brick', wallA: '#5e3e30', wallB: '#342620', trim: 0x2a2420, ceil: 0x1a1c1a },
      lamp: 'bulb', window: { x: 220, w: 120, y: 205, h: 60 }, door: 300,
      catBed: [300, 480], dock: [900, 380], lights: [], decor: 'pantry',
      furn: pantryFurniture, cracks: pantryCracks,
      knocks: [
        { kind: 'can', x: 500, y: 332, to: [500, 300], trap: true, group: 'cans' },
        { kind: 'can', x: 522, y: 332, to: [524, 296], trap: true, group: 'cans' },
        { kind: 'bottle', x: 630, y: 340, to: [668, 352] },
      ],
      music: { root: 50, minor: true, bpm: 80, prog: [[0, 'm'], [-4, 'M'], [-7, 'm'], [-5, 'M']] },
    },
    {
      id: 'dining', name: 'Dinner Leftovers', act: 2, goal: 16, night: 780,
      cat: 'awake', catStart: [700, 470], wanted: true, threats: ['owner'], openFood: true,
      tunnels: [[0, 2], [1, 2]],
      food: {
        spots: [
          ['chicken', 470, 270, { tag: 'chicken' }],                              // on the dining table
          ['cheese', 560, 300], ['crumb', 400, 240], ['crumb', 600, 230], ['crumb', 520, 330],
          ['cheese', 480, 28], ['crumb', 800, 160], ['crumb', 160, 480], ['crumb', 760, 560], ['crumb', 260, 120],
        ],
        random: { crumb: 3, cheese: 1 }, refill: 5,
      },
      tasks: {
        goal: 'Fill the nest',
        chain: [
          { text: 'Crawl through a path inside the wall', hint: 'Some cracks are connected. Hide in one and press Space to come out of another.', check: ['count', 'tunnel', 1] },
          { text: 'Climb onto the dining table', hint: 'Chairs stand all around it. Jump onto a chair, then the table.', check: ['surf', 'table'] },
          { text: 'Steal the chicken leg', hint: 'Careful with the glasses on the edge of the table.', check: ['pick', 'chicken'] },
          { text: 'Drag the chicken leg home', hint: 'Heavy and slow. The wall paths are a safe shortcut.', check: ['deliver', 'chicken'] },
        ],
        side: [
          { text: 'Don’t knock over the glasses', check: ['keep', 'glass'] },
          { text: 'Use the wall paths 3 times', check: ['count', 'tunnel', 3] },
        ],
        secret: [{ text: 'Find the lost ring', check: ['flag', 'ring'] }],
      },
      props: [{ t: 'noisy', kind: 'board', x: 160, y: 430, w: 120, h: 18 }],
      secrets: [{ kind: 'ring', x: 700, y: 580, floor: true }],
      blurb: 'Leftovers from a dinner party. Learn the paths inside the walls.',
      teaser: 'The laundry room, where the cat has its dinner.',
      intro: { pups: ['Mom, we smell chicken!', 'Squeak squeak!', 'Bring the big piece!'], mom: 'They had guests. The dining room is full of leftovers. And I found a path inside the walls…' },
      start: { title: 'Paths inside the walls', sub: 'Hide in a crack and press Space to crawl to another.' },
      starTip: 'The owner will come if you’re too loud',
      pal: { fog: 0x120e14, sky: 0x9a8ab0, ground: 0x2e2228, hemi: 0.7, moon: 0.75, floor: 'wood', floorA: '#4a3226', wall: 'panel', wallA: '#5c3a46', wallB: '#2e1f1a', trim: 0x2a1c18, ceil: 0x241c22 },
      lamp: 'chandelier', window: { x: 660, w: 200 }, door: 330,
      catBed: [200, 480], dock: [900, 440], lights: [], decor: 'dining',
      furn: diningFurniture,
      cracks: [{ wall: 'w', y: 400 }, { wall: 's', x: 650 }, { wall: 'e', y: 200 }],
      knocks: [
        { kind: 'glass', x: 440, y: 212, to: [440, 150], trap: true, group: 'cloth' },
        { kind: 'glass', x: 470, y: 212, to: [474, 146], trap: true, group: 'cloth' },
        { kind: 'glass', x: 500, y: 212, to: [504, 150], trap: true, group: 'cloth' },
        { kind: 'vase', x: 392, y: 24, to: [392, 72] },
        { kind: 'bottle', x: 830, y: 160, to: [832, 214] },
      ],
      music: { root: 53, minor: false, bpm: 74, prog: [[0, 'M'], [-3, 'm'], [-7, 'M'], [-5, 'M']] },
    },
    {
      id: 'laundry', name: 'The Laundry Room', act: 2, goal: 16, night: 780,
      cat: 'eating', eatTime: 45, wanted: true, threats: [], openFood: true,
      food: {
        spots: [
          ['cheese', 586, 528, { tag: 'kibble' }], ['crumb', 600, 500], ['crumb', 540, 548],   // the cat's bowl
          ['cheese', 520, 380], ['crumb', 460, 360], ['crumb', 580, 400],                     // the folding table
          ['cheese', 60, 52], ['crumb', 870, 160], ['crumb', 300, 300], ['crumb', 720, 420], ['crumb', 160, 420],
        ],
        random: { crumb: 3, cheese: 1 }, refill: 5,
      },
      tasks: {
        goal: 'Fill the nest',
        chain: [
          { text: 'Wait until the cat finishes eating and lies down', hint: 'It eats at its bowl, then goes to bed. While it eats it only notices you right in front of it.', check: ['flag', 'catNapping'] },
          { text: 'Steal food from the cat’s bowl', hint: 'Sneak. The cat sleeps right by our path now.', check: ['pick', 'kibble'] },
          { text: 'Climb onto the folding table', hint: 'Use the stool next to it.', check: ['surf', 'table'] },
          { text: 'Find a sock for the nest in the laundry basket', hint: 'The basket is next to the washing machines. Climb on top of it.', check: ['flag', 'sock'] },
        ],
        side: [
          { text: 'Start the washing machine to hide your steps', hint: '', check: ['flag', 'washer'] },
          { text: 'Don’t wake the cat once it’s asleep', check: ['keep', 'catWoke'] },
        ],
        secret: [{ text: 'Find the lost earring', check: ['flag', 'button'] }],
      },
      props: [
        { t: 'noisy', kind: 'washer', x: 185, y: 50 },
        { t: 'noisy', kind: 'hanger', x: 330, y: 110, w: 40, h: 20 },
        { t: 'noisy', kind: 'puddle', x: 120, y: 140, r: 24 },
        { t: 'noisy', kind: 'squeaky', x: 640, y: 470 },
      ],
      secrets: [{ kind: 'sock', x: 286, y: 60, always: true }, { kind: 'button', label: 'A lost earring!', x: 880, y: 300, floor: true }],
      blurb: 'The cat eats at night. Wait for it to fall asleep.',
      teaser: 'A stormy night. Thunder hides your noise, lightning shows you.',
      intro: { pups: ['Mom, the cat eats at night!', 'Squeak?', 'Wait till it sleeps!'], mom: 'The laundry room. The cat has a midnight snack there, then naps. I just have to be patient.' },
      start: { title: 'The cat is eating', sub: 'Wait until it lies down, then steal from its bowl.' },
      starTip: 'The cat sleeps lighter now',
      pal: { fog: 0x0c1014, sky: 0x7a90a8, ground: 0x242628, hemi: 0.66, moon: 0.62, floor: 'tile', floorA: '#4a5058', floorB: '#555c66', wall: 'stripes', wallA: '#4a5a62', wallB: '#52646c', trim: 0x2a2e30, ceil: 0x1c2024 },
      lamp: 'bulb', window: { x: 520, w: 140 }, door: 300,
      catBed: [330, 500], bowl: [560, 520], dock: [900, 380], lights: [], decor: 'pantry',
      furn: [
        { t: 'washer', x: 40, y: 12, w: 90, h: 80, dryer: true },
        { t: 'washer', x: 140, y: 12, w: 90, h: 80 },
        { t: 'basket', x: 260, y: 40, w: 52, h: 44, ht: 45 },
        { t: 'shelfUnit', x: 700, y: 0, w: 200, h: 50 },
        { t: 'box', x: 760, y: 120, w: 60, h: 60, ht: 50 },
        { t: 'box', x: 820, y: 120, w: 60, h: 60, ht: 92 },
        { t: 'table', x: 420, y: 330, w: 200, h: 110, cloth: 0x8aa0b8 },
        { t: 'stool', x: 376, y: 360 },
        { t: 'lowShelf', x: 100, y: 480, w: 80, h: 50 },
        { t: 'boiler', x: 870, y: 470, w: 80, h: 110 },
      ],
      cracks: [{ wall: 'w', y: 300 }, { wall: 's', x: 700 }, { wall: 'e', y: 250 }],
      knocks: [{ kind: 'bottle', x: 600, y: 350, to: [600, 312] }, { kind: 'spoon', x: 470, y: 420, to: [470, 456] }],
      music: { root: 52, minor: false, bpm: 70, prog: [[0, 'M'], [-5, 'M'], [-3, 'm'], [-7, 'M']] },
    },
    {
      id: 'storm', name: 'The Storm', act: 2, goal: 18, night: 840,
      cat: 'awake', catStart: [700, 200], wanted: true, threats: ['owner'], openFood: true, tvOff: true,
      storm: true, blackout: 0.62,
      food: {
        spots: [
          ['pizza', 470, 236, { tag: 'pizza' }],
          ['cheese', 372, 28, { tag: 'p1' }], ['cheese', 175, 175, { tag: 'p2' }], ['cheese', 770, 470, { tag: 'p3' }], ['cheese', 880, 250, { tag: 'p4' }],
          ['crumb', 340, 308], ['crumb', 430, 312], ['crumb', 548, 310], ['crumb', 90, 120], ['crumb', 620, 560], ['crumb', 360, 480],
        ],
        random: { crumb: 3, cheese: 1 }, refill: 5,
      },
      tasks: {
        goal: 'Fill the nest',
        chain: [
          { text: 'Move while the thunder rumbles', hint: 'A flash, then BOOM. While the thunder rolls, nobody can hear you, even running.', check: ['flag', 'thunderMove'] },
          { text: 'Be hidden when the lightning flashes', hint: 'The flash lights up the whole room. Out in the open, you’ll be seen.', check: ['flag', 'hidLightning'] },
          { text: 'Collect the party leftovers', hint: 'Cheese on the TV stand, the footstool, behind the armchair and by the window.', check: ['pickN', 'p', 4] },
          { text: 'Steal a slice of pizza', hint: 'It’s on the coffee table.', check: ['pick', 'pizza'] },
          { text: 'Drag the pizza home', hint: 'Move during the thunder.', check: ['deliver', 'pizza'] },
        ],
        side: [
          { text: 'Be in the nest when the power goes out', check: ['flag', 'homeAtBlackout'] },
          { text: 'Don’t pop any balloons', check: ['keep', 'balloon'] },
        ],
        secret: [{ text: 'Find the party whistle', check: ['flag', 'button'] }],
      },
      props: [
        { t: 'noisy', kind: 'balloon', x: 260, y: 300 }, { t: 'noisy', kind: 'balloon', x: 680, y: 300 }, { t: 'noisy', kind: 'balloon', x: 600, y: 520 },
        { t: 'noisy', kind: 'confetti', x: 330, y: 450, w: 80, h: 50 }, { t: 'noisy', kind: 'confetti', x: 700, y: 120, w: 70, h: 50 },
        { t: 'noisy', kind: 'plate', x: 440, y: 250, r: 16 },
        { t: 'noisy', kind: 'sofa', surf: 'sofa', x: 300, y: 330, w: 516, h: 110 },
      ],
      secrets: [{ kind: 'button', label: 'A party whistle! Don’t blow it.', x: 80, y: 480, floor: true }],
      blurb: 'Thunder hides your noise. Lightning shows you. Then the power goes out.',
      teaser: 'Mousetraps. The owner is getting serious.',
      intro: { pups: ['Mom, the thunder is scary!', 'Squeak!!', 'Don’t go!'], mom: 'A storm. When the thunder rolls, nobody can hear me. When the lightning flashes, everyone can see me.' },
      start: { title: 'A stormy night', sub: 'Move when the thunder rolls. Hide when the lightning flashes.' },
      starTip: 'The owner will come if you’re too loud',
      pal: Object.assign({}, livingPal, { hemi: 0.6, moon: 0.5, fog: 0x0c1016 }), lamp: 'shade', window: { x: 680, w: 200 }, door: 240,
      catBed: [215, 500], dock: [900, 330], lights: [], decor: 'living',
      furn: livingFurniture, cracks: livingCracks, knocks: livingKnocks,
      music: { root: 50, minor: true, bpm: 78, prog: [[0, 'm'], [-4, 'M'], [-7, 'm'], [-2, 'M']] },
    },

    // ================= ACT 3 · TRAPS (one pup comes along each night) =================
    {
      id: 'traps', name: 'Mousetraps', act: 3, goal: 18, night: 840,
      cat: 'sleep', wanted: true, threats: ['owner'], openFood: true, pups: ['brave'],
      trapSpots: [[500, 140], [832, 236], [250, 300, { hidden: true }], [650, 480], [160, 470, { hidden: true }]],
      food: {
        spots: [
          ['cheese', 480, 270], ['cheese', 560, 300], ['crumb', 400, 240], ['crumb', 600, 230], ['crumb', 520, 330],
          ['cheese', 480, 28], ['crumb', 800, 160], ['crumb', 760, 560], ['crumb', 260, 120], ['crumb', 120, 520], ['crumb', 880, 400],
        ],
        random: { crumb: 4, cheese: 2 }, refill: 6,
      },
      tasks: {
        goal: 'Fill the nest',
        chain: [
          { text: 'Tell Brave to wait (Q) while you check the way', hint: 'Brave runs ahead toward food, even into traps. Press Q and he hides and waits. Press Q again to call him.', check: ['flag', 'pupStay'] },
          { text: 'Sniff out 3 mousetraps', hint: 'Traps smell like cheese too. Hold E: the real traps light up red. Once you’ve found a trap, the pups know to avoid it.', check: ['count', 'trapFound', 3] },
          { text: 'Drop something on a mousetrap to spring it', hint: 'Push the spoon off the sideboard or the bottle off the bar cart (F): they land right on traps.', check: ['count', 'disarm', 1] },
          { text: 'Take the bait from the sprung trap', hint: 'A sprung trap is harmless. The bait is yours.', check: ['pickN', 'bait', 1] },
          { text: 'Have Brave fetch food for you (R)', hint: 'Stand near a crumb and press R. Brave grabs it and runs it home.', check: ['count', 'pupFetch', 1] },
        ],
        side: [
          { text: 'Keep Brave safe all night', check: ['keep', 'pup'] },
          { text: 'Spring 2 traps', check: ['count', 'disarm', 2] },
        ],
        secret: [{ text: 'Find the lost cufflink', check: ['flag', 'button'] }],
      },
      props: [{ t: 'noisy', kind: 'board', x: 160, y: 430, w: 120, h: 18 }],
      secrets: [{ kind: 'button', label: 'A lost cufflink!', x: 60, y: 560, floor: true }],
      blurb: 'Brave comes along tonight. Mousetraps everywhere.',
      teaser: 'Sticky traps in the pantry, and Curious comes along.',
      intro: { pups: ['Mom, can I come? Please?', 'Squeak!', 'Take Brave, he’s the bravest!'], mom: 'Brave is big enough to come with me. But the owner put out mousetraps. Stay close, little one.' },
      start: { title: 'Brave comes along', sub: 'Press Q: he waits or follows. Press R: he fetches the nearest food.' },
      starTip: 'The owner will come if you’re too loud',
      pal: diningPal, lamp: 'chandelier', window: { x: 660, w: 200 }, door: 330,
      catBed: [200, 480], dock: [900, 440], lights: [], decor: 'dining',
      furn: diningFurniture, cracks: diningCracks,
      knocks: [
        { kind: 'spoon', x: 500, y: 40, to: [500, 140] },
        { kind: 'bottle', x: 830, y: 160, to: [832, 232] },
        { kind: 'vase', x: 392, y: 24, to: [392, 72] },
      ],
      music: { root: 55, minor: true, bpm: 76, prog: [[0, 'm'], [-4, 'M'], [-7, 'm'], [-5, 'M']] },
    },
    {
      id: 'sticky', name: 'Sticky Traps', act: 3, goal: 18, night: 840,
      cat: 'sleep', sleepSense: 1.2, wanted: true, threats: ['owner'], openFood: false, pups: ['curious'],
      food: {
        spots: [
          ['cheese', 560, 360, { tag: 'rusk', hidden: true }], ['potato', 345, 186, { tag: 'potato' }],
          ['cheese', 680, 525, { hidden: true, floor: true }], ['cheese', 140, 44, { hidden: true }],
          ['crumb', 120, 300], ['crumb', 420, 520], ['crumb', 760, 300], ['crumb', 900, 250], ['crumb', 230, 470], ['crumb', 600, 560],
        ],
        random: { crumb: 3, cheese: 1 }, refill: 5,
      },
      tasks: {
        goal: 'Fill the nest',
        chain: [
          { text: 'Get the rusk from the workbench', hint: 'Sticky tape is around the stool. If you step on it you’re stuck for a moment, squeaking. Find another way up.', check: ['pick', 'rusk'] },
          { text: 'Let Curious find something shiny', hint: 'Curious spots hidden things. Walk around with him and listen.', check: ['count', 'collected', 1] },
          { text: 'Roll the potato off the top crate', hint: 'It’s on the top of the crate stairs.', check: ['pick', 'potato'] },
          { text: 'Roll the potato home', hint: 'Heavy and slow. Mind the tape on the floor.', check: ['deliver', 'potato'] },
        ],
        side: [
          { text: 'Never get stuck on the tape', check: ['keep', 'sticky'] },
          { text: 'Keep Curious safe all night', check: ['keep', 'pup'] },
        ],
        secret: [{ text: 'Find the tiny key', check: ['flag', 'button'] }],
      },
      props: [
        { t: 'sticky', x: 380, y: 340, w: 90, h: 56, floor: true },
        { t: 'sticky', x: 180, y: 380, w: 110, h: 40, floor: true },
        { t: 'sticky', x: 600, y: 420, w: 60, h: 60, floor: true },
        { t: 'sticky', x: 700, y: 250, w: 120, h: 34, floor: true },
        { t: 'noisy', kind: 'bag', x: 580, y: 480, w: 50, h: 34 },
      ],
      secrets: [{ kind: 'button', label: 'A tiny key!', x: 856, y: 560, floor: true }, { kind: 'photo', x: 60, y: 140, floor: true }],
      blurb: 'Sticky tape on the floor. Curious finds hidden things.',
      teaser: 'The kids’ room. Don’t wake the kid. Shy comes along.',
      intro: { pups: ['Mom, what’s that yellow stuff?', 'Squeak?', 'Can I look? Can I?'], mom: 'Curious wants to see everything. Good: he finds things I miss. But that yellow tape on the floor is glue.' },
      start: { title: 'Sticky traps', sub: 'Yellow tape on the floor holds you in place. Curious spots hidden things.' },
      starTip: 'The owner will come if you’re too loud',
      pal: { fog: 0x0c100f, sky: 0x6f8a7a, ground: 0x2a2620, hemi: 0.62, moon: 0.55, floor: 'concrete', floorA: '#3e4541', wall: 'brick', wallA: '#6a4636', wallB: '#3a2a24', trim: 0x2a2420, ceil: 0x1c1e1c },
      lamp: 'bulb', window: { x: 220, w: 120, y: 205, h: 60 }, door: 300,
      catBed: [300, 480], dock: [900, 380], lights: [], decor: 'pantry',
      furn: pantryFurniture, cracks: pantryCracks,
      knocks: [{ kind: 'carton', x: 140, y: 44, to: [140, 100], spawn: 'cheese' }, { kind: 'bottle', x: 630, y: 340, to: [668, 352] }],
      music: { root: 52, minor: true, bpm: 78, prog: [[0, 'm'], [-4, 'M'], [-7, 'm'], [-5, 'M']] },
    },
    {
      id: 'kids', name: 'The Kids’ Room', act: 3, goal: 18, night: 840,
      cat: 'away', wanted: true, threats: ['owner'], openFood: true, pups: ['shy'],
      sleepers: [{ kind: 'kid', x: 760, y: 95, bedH: 52, face: Math.PI, sense: 1.2 }],
      food: {
        spots: [
          ['cheese', 140, 60], ['crumb', 100, 90], ['crumb', 200, 50],   // on the desk
          ['crumb', 480, 340], ['crumb', 300, 300], ['crumb', 620, 420], ['crumb', 180, 400], ['cheese', 445, 52], ['crumb', 850, 300], ['crumb', 700, 520],
        ],
        random: { crumb: 3, cheese: 1 }, refill: 5,
      },
      tasks: {
        goal: 'Fill the nest',
        chain: [
          { text: 'Bring Shy to the backpack', hint: 'The backpack is by the toy chest. Shy freezes when something squeaks, so steer around the toys.', check: ['flag', 'pupAtBag'] },
          { text: 'Gnaw open the backpack', hint: 'Hold F next to it. It’s loud: watch the kid’s Zzz bar.', check: ['flag', 'backpack'] },
          { text: 'Find 3 small toys for the pups', hint: 'A dinosaur, a marble, a toy car. They’re scattered around the room.', check: ['count', 'collected', 3] },
          { text: 'Bring Shy back to the nest', hint: 'Lead him home. Shy warns you when danger is near.', check: ['flag', 'pupHome'] },
        ],
        side: [
          { text: 'Don’t wake the kid', check: ['keep', 'sleeper'] },
          { text: 'Keep Shy safe all night', check: ['keep', 'pup'] },
        ],
        secret: [{ text: 'Find the kid’s drawing', check: ['flag', 'drawing'] }],
      },
      props: [
        { t: 'backpack', x: 330, y: 540, spawn: 4 },
        { t: 'noisy', kind: 'squeaky', x: 420, y: 250 }, { t: 'noisy', kind: 'squeaky', x: 600, y: 330 }, { t: 'noisy', kind: 'squeaky', x: 250, y: 470 },
        { t: 'noisy', kind: 'lego', x: 520, y: 470, r: 30 }, { t: 'noisy', kind: 'lego', x: 160, y: 250, r: 26 },
        { t: 'noisy', kind: 'musicbox', x: 340, y: 44 },
        { t: 'noisy', kind: 'nightlight', x: 860, y: 200, w: 80, h: 60 },
      ],
      secrets: [
        { kind: 'toy', label: 'A tiny dinosaur!', x: 700, y: 300, floor: true, always: true },
        { kind: 'marble', x: 120, y: 330, floor: true, always: true },
        { kind: 'thimble', label: 'A toy car! Vroom.', x: 560, y: 560, floor: true, always: true },
        { kind: 'drawing', x: 900, y: 560, floor: true },
      ],
      blurb: 'A sleeping kid, squeaky toys, a backpack full of cookies. Shy comes along.',
      teaser: 'A party. Guests are sleeping over. Greedy comes along.',
      intro: { pups: ['Mom, I’m scared of the big kid…', 'Squeak…', 'Shy, you can do it!'], mom: 'The kids’ room. If the kid wakes up, the whole house wakes up. Shy is scared, but he hears danger before anyone.' },
      start: { title: 'Don’t wake the kid', sub: 'Squeaky toys and Lego bricks everywhere. Shy freezes at loud noises.' },
      starTip: 'The owner will come if you’re too loud',
      pal: { fog: 0x10101e, sky: 0x9a8ad0, ground: 0x2a2436, hemi: 0.74, moon: 0.8, floor: 'wood', floorA: '#5a4a3a', wall: 'stripes', wallA: '#4a5a8a', wallB: '#5a6a9a', trim: 0x3a2e40, ceil: 0x24243a },
      lamp: 'shade', window: { x: 420, w: 180 }, door: 300,
      catBed: [200, 480], dock: [900, 440], lights: [{ x: 880, y: 230, h: 20, c: 0xffd890, i: 0.5, r: 260 }], decor: 'living',
      furn: [
        { t: 'table', x: 620, y: 20, w: 240, h: 150, ht: 52, cloth: 0x6a9ad8 },
        { t: 'table', x: 60, y: 20, w: 170, h: 90, ht: 75 },
        { t: 'chair', x: 128, y: 118, back: 's' },
        { t: 'lowShelf', x: 300, y: 20, w: 90, h: 50 },
        { t: 'box', x: 420, y: 28, w: 60, h: 50, ht: 44 },
        { t: 'ottoman', x: 470, y: 330, w: 56, h: 56 },
        { t: 'sideTable', x: 880, y: 40, w: 50, h: 50, ht: 62 },
        { t: 'plant', x: 892, y: 530, w: 52, h: 52 },
      ],
      cracks: [{ wall: 'w', y: 300 }, { wall: 's', x: 620 }, { wall: 'e', y: 420 }],
      knocks: [{ kind: 'book', x: 160, y: 40, to: [160, 140] }, { kind: 'ball', x: 450, y: 50, to: [450, 110] }],
      music: { root: 60, minor: false, bpm: 64, prog: [[0, 'M'], [-5, 'M'], [-3, 'm'], [-7, 'M']] },
    },
    {
      id: 'party', name: 'The Party', act: 3, goal: 20, night: 900,
      cat: 'away', wanted: true, threats: ['owner'], openFood: true, pups: ['greedy'],
      sleepers: [{ kind: 'guest', x: 300, y: 470, face: 0 }, { kind: 'guest', x: 760, y: 230, face: Math.PI / 2 }],
      food: {
        spots: [
          ['cake', 720, 450, { tag: 'cake' }],
          ['cheese', 660, 410, { tag: 'plate1' }], ['cheese', 790, 480, { tag: 'plate2' }], ['cheese', 470, 300, { tag: 'plate3' }],
          ['crumb', 540, 296], ['crumb', 300, 200], ['crumb', 160, 520], ['crumb', 680, 560], ['crumb', 900, 520], ['crumb', 420, 420], ['crumb', 120, 300],
        ],
        random: { crumb: 4, cheese: 2 }, refill: 6,
      },
      tasks: {
        goal: 'Fill the nest',
        chain: [
          { text: 'Sneak past a sleeping guest', hint: 'Guests snore. When the snoring stops, they’re waking up.', check: ['flag', 'passSleeper'] },
          { text: 'Take food from 3 party plates', hint: 'Two on the table, one on the island.', check: ['pickN', 'plate', 3] },
          { text: 'Steal a piece of cake', hint: 'Greedy will run for it as soon as he smells it. Tell him to wait (Q) first.', check: ['pick', 'cake'] },
          { text: 'Drag the cake home', hint: 'Heavy and sticky. Go around the guests.', check: ['deliver', 'cake'] },
        ],
        side: [
          { text: 'Don’t wake the guests', check: ['keep', 'sleeper'] },
          { text: 'Get a birthday candle for the nest', check: ['flag', 'candle'] },
          { text: 'Keep Greedy safe all night', check: ['keep', 'pup'] },
        ],
        secret: [{ text: 'Find the party whistle', check: ['flag', 'button'] }],
      },
      props: [
        { t: 'noisy', kind: 'bottles', x: 400, y: 400, w: 40, h: 20 }, { t: 'noisy', kind: 'bottles', x: 600, y: 200, w: 40, h: 20 },
        { t: 'noisy', kind: 'popper', x: 520, y: 520 }, { t: 'noisy', kind: 'popper', x: 200, y: 200 },
        { t: 'noisy', kind: 'balloon', x: 860, y: 300 }, { t: 'noisy', kind: 'balloon', x: 250, y: 360 },
        { t: 'noisy', kind: 'confetti', x: 600, y: 520, w: 80, h: 50 },
      ],
      secrets: [{ kind: 'candle', x: 740, y: 400, always: true }, { kind: 'button', label: 'A party whistle!', x: 98, y: 360, floor: true }],
      blurb: 'Guests sleep over after a party. Greedy comes along, and there’s cake.',
      teaser: 'Poison. Sniff every piece before you take it.',
      intro: { pups: ['Mom, there was a party! CAKE!', 'Squeak squeak squeak!', 'Greedy, calm down!'], mom: 'Guests stayed the night. There’s food everywhere… Greedy, stay close, and don’t run off after the cake.' },
      start: { title: 'Guests are sleeping over', sub: 'Snoring means asleep. Greedy runs for food: keep him on a leash with Q.' },
      starTip: 'The owner will come if you’re too loud',
      pal: { fog: 0x14102a, sky: 0x9a8fd8, ground: 0x2e2440, hemi: 0.8, moon: 0.9, floor: 'tile', floorA: '#3e3c62', floorB: '#4c4a7a', wall: 'stripes', wallA: '#524a76', wallB: '#5c5482', trim: 0x3a2e40, ceil: 0x22203a },
      lamp: 'shade', window: { x: 410, w: 220 }, door: 320,
      catBed: [470, 545], dock: [900, 430], lights: [{ x: 900, y: 560, h: 60, c: 0xff9ad0, i: 0.8, r: 500 }],
      decor: 'kitchen', furn: kitchenFurniture, cracks: kitchenCracks,
      knocks: [{ kind: 'spoon', x: 300, y: 44, to: [300, 102] }, { kind: 'glass', x: 655, y: 398, to: [655, 362], trap: true }],
      music: { root: 58, minor: false, bpm: 82, prog: [[0, 'M'], [-5, 'M'], [-3, 'm'], [-7, 'M']] },
    },
    {
      id: 'poison', name: 'Poison', act: 3, goal: 20, night: 900,
      cat: 'awake', catStart: [700, 470], wanted: true, threats: ['poison', 'owner'], openFood: false, pups: ['curious', 'greedy'], poisonStart: 3,
      food: {
        spots: [
          ['cheese', 480, 28, { tag: 'wheel', hidden: true }],
          ['cheese', 480, 270, { hidden: true }], ['cheese', 560, 300, { hidden: true }], ['cheese', 400, 240, { hidden: true }], ['cheese', 800, 160, { hidden: true }],
          ['cheese', 160, 480, { hidden: true }], ['crumb', 760, 560], ['crumb', 260, 120], ['crumb', 120, 520], ['crumb', 880, 400],
        ],
        random: { crumb: 4, cheese: 2 }, refill: 6,
      },
      tasks: {
        goal: 'Bring home only clean food',
        chain: [
          { text: 'Sniff out 3 poisoned pieces', hint: 'Hold E. Poisoned cheese has a green scent trail. Curious spots food near him too.', check: ['count', 'poisonSeen', 3] },
          { text: 'Have a pup fetch clean food (R)', hint: 'Greedy grabs anything, even poison. Send him only after you’ve sniffed.', check: ['count', 'pupFetch', 1] },
          { text: 'Steal the cheese wheel from the sideboard', hint: 'Up on the sideboard. Get there from the footstool.', check: ['pick', 'wheel'] },
          { text: 'Bring it home', hint: '', check: ['deliver', 'wheel'] },
        ],
        side: [
          { text: 'Never bring poison home', check: ['keep', 'poison'] },
          { text: 'Keep both pups safe all night', check: ['keep', 'pup'] },
        ],
        secret: [{ text: 'Find the silver spoon', check: ['flag', 'button'] }],
      },
      props: [{ t: 'noisy', kind: 'board', x: 160, y: 430, w: 120, h: 18 }, { t: 'noisy', kind: 'glasses', x: 600, y: 230, r: 16 }],
      secrets: [{ kind: 'button', label: 'A silver spoon!', x: 700, y: 580, floor: true }],
      blurb: 'Some of the food is poisoned. Curious and Greedy come along.',
      teaser: 'A robot vacuum joins the hunt. Act 4: the siege.',
      intro: { pups: ['Mom, the cheese smells funny…', 'Squeak?', 'Can we both come?'], mom: 'The owner is putting out poison now. Sniff everything. Curious helps… and Greedy needs watching.' },
      start: { title: 'Poison in the food', sub: 'Green scent means poison. Greedy grabs anything he sees.' },
      starTip: 'More poison appears as the wanted level rises',
      pal: diningPal, lamp: 'chandelier', window: { x: 660, w: 200 }, door: 330,
      catBed: [200, 480], dock: [900, 440], lights: [], decor: 'dining',
      furn: diningFurniture, cracks: diningCracks, tunnels: [[0, 2], [1, 2]],
      knocks: [{ kind: 'vase', x: 392, y: 24, to: [392, 72] }, { kind: 'bottle', x: 830, y: 160, to: [832, 214] }],
      music: { root: 50, minor: true, bpm: 80, prog: [[0, 'm'], [-4, 'M'], [-7, 'm'], [-5, 'M']] },
    },

    // ================= ACT 4 · SIEGE (the pups are almost grown) =================
    {
      id: 'vacuum', name: 'The Robot Vacuum', act: 4, goal: 20, night: 900,
      cat: 'sleep', wanted: true, threats: ['owner'], openFood: true, pups: ['brave', 'shy'], pupAge: 0.75, vacuumStart: true,
      food: {
        spots: [
          ['crumb', 700, 300, { tag: 'v1' }], ['crumb', 760, 330, { tag: 'v2' }], ['crumb', 820, 300, { tag: 'v3' }], ['crumb', 650, 560, { tag: 'v4' }], ['crumb', 880, 560, { tag: 'v5' }],
          ['cheese', 680, 432], ['cheese', 116, 30, { hidden: true }], ['cheese', 539, 298], ['crumb', 300, 460], ['crumb', 160, 200], ['crumb', 420, 420],
        ],
        random: { crumb: 6, cheese: 2 }, refill: 8,
      },
      tasks: {
        goal: 'Fill the nest',
        chain: [
          { text: 'Grab 3 crumbs before the vacuum eats them', hint: 'The vacuum eats every crumb on the floor. Be quicker.', check: ['pickN', 'v', 3] },
          { text: 'Drop something in the vacuum’s way', hint: 'Push the spoon, jar or apple off (F) when the vacuum is close: it stops to think.', check: ['flag', 'vacBlock'] },
          { text: 'Ride the vacuum', hint: 'Sneak (hold Ctrl) right onto it and keep sneaking. Wheee!', check: ['flag', 'ride'] },
          { text: 'Lead both pups home', hint: 'Brave and Shy follow you. Walk into the nest.', check: ['flag', 'pupHome'] },
        ],
        side: [
          { text: 'Keep both pups safe all night', check: ['keep', 'pup'] },
          { text: 'Don’t wake the cat', check: ['keep', 'catWoke'] },
        ],
        secret: [{ text: 'Find what the vacuum swallowed', check: ['flag', 'button'] }],
      },
      props: [{ t: 'noisy', kind: 'dock', x: 900, y: 455 }, { t: 'noisy', kind: 'puddle', x: 480, y: 112, r: 26 }],
      secrets: [{ kind: 'button', label: 'Your shiny button from the first night! The vacuum had it.', x: 920, y: 400, floor: true }],
      blurb: 'A robot vacuum roams the kitchen and eats the crumbs. Brave and Shy come along.',
      teaser: 'The neighbors’ dog is staying over. It follows your scent.',
      intro: { pups: ['Mom, there’s a robot!', 'It beeps! It eats crumbs!', 'Can we ride it?'], mom: 'The owner bought a robot vacuum. It eats every crumb on the floor… and it doesn’t sleep. Brave, Shy, stay close.' },
      start: { title: 'The robot vacuum', sub: 'It eats crumbs and bumps into you. Things that fall in its way confuse it.' },
      starTip: 'The owner will come if you’re too loud',
      pal: { fog: 0x101426, sky: 0x8a8fd0, ground: 0x2a2436, hemi: 0.76, moon: 0.86, floor: 'tile', floorA: '#383c5c', floorB: '#474c76', wall: 'stripes', wallA: '#474e70', wallB: '#50587c', trim: 0x3a2e30, ceil: 0x20243a },
      lamp: 'shade', window: { x: 410, w: 220 }, door: 320,
      catBed: [470, 545], bowl: [770, 215], dock: [900, 430],
      lights: [{ x: 900, y: 560, h: 60, c: 0xffa860, i: 1.0, r: 520 }],
      decor: 'kitchen', furn: kitchenFurniture, cracks: kitchenCracks,
      knocks: [{ kind: 'spoon', x: 300, y: 44, to: [300, 102] }, { kind: 'jar', x: 470, y: 60, to: [470, 102] }, { kind: 'apple', x: 520, y: 330, to: [522, 364] }, { kind: 'cup', x: 810, y: 392, to: [840, 370] }],
      music: { root: 50, minor: true, bpm: 86, prog: [[0, 'm'], [-4, 'M'], [-9, 'M'], [-2, 'M']] },
    },
    {
      id: 'dog', name: 'The Dog', act: 4, goal: 20, night: 900,
      cat: 'away', wanted: true, threats: ['owner'], openFood: true, pups: ['shy', 'greedy'], pupAge: 0.78,
      dog: { x: 640, y: 500 },
      food: {
        spots: [
          ['biscuit', 840, 540, { tag: 'biscuit' }],
          ['cheese', 372, 28], ['cheese', 520, 252], ['cheese', 175, 175], ['crumb', 90, 120], ['crumb', 270, 300], ['crumb', 700, 300], ['crumb', 880, 200], ['crumb', 360, 480], ['crumb', 230, 80],
        ],
        random: { crumb: 4, cheese: 2 }, refill: 6,
      },
      tasks: {
        goal: 'Fill the nest',
        chain: [
          { text: 'Sneak past the sleeping dog', hint: 'It sleeps like the cat did: watch its Zzz bar. Once awake, it follows your scent.', check: ['flag', 'passDog'] },
          { text: 'Wash off your scent in the puddle', hint: 'The dog tracks your trail for 30 seconds. Walking through water or the litter box wipes it.', check: ['flag', 'trailBroken'] },
          { text: 'Distract the dog with the ball', hint: 'The ball is on the TV stand. Push it off (F) and the dog runs to play.', check: ['flag', 'dogBall'] },
          { text: 'Steal the dog biscuit', hint: 'From the dog’s bowl by the window.', check: ['pick', 'biscuit'] },
          { text: 'Drag the biscuit home', hint: 'Slow. The dog may follow your trail, so wash it off again.', check: ['deliver', 'biscuit'] },
        ],
        side: [
          { text: 'Never get chased by the dog', check: ['keep', 'dogChase'] },
          { text: 'Keep both pups safe all night', check: ['keep', 'pup'] },
        ],
        secret: [{ text: 'Find the dog’s chew toy', check: ['flag', 'toy'] }],
      },
      props: [
        { t: 'noisy', kind: 'puddle', x: 760, y: 560, r: 26 }, { t: 'noisy', kind: 'litter', x: 120, y: 470, w: 60, h: 44 },
        { t: 'noisy', kind: 'squeaky', x: 600, y: 420 }, { t: 'noisy', kind: 'board', x: 52, y: 408, w: 120, h: 18 },
        { t: 'noisy', kind: 'sofa', surf: 'sofa', x: 300, y: 330, w: 516, h: 110 },
      ],
      secrets: [{ kind: 'toy', label: 'The dog’s chew toy. Gross, but the pups love it.', x: 480, y: 240, floor: true }],
      blurb: 'The neighbors’ dog follows your scent. Shy and Greedy come along.',
      teaser: 'The basement. The owner sealed the cracks.',
      intro: { pups: ['Mom, something big is barking!', 'Squeak!!', 'It smells us!'], mom: 'The neighbors left their dog here. Dogs follow your smell, not your noise. Water washes the smell away.' },
      start: { title: 'The dog follows your scent', sub: 'Puddles and the litter box wash your trail away.' },
      starTip: 'The owner will come if you’re too loud',
      pal: livingPal, lamp: 'shade', window: { x: 680, w: 200 }, door: 240,
      catBed: [215, 500], bowl: [820, 540], dock: [900, 330], lights: [], decor: 'living',
      furn: livingFurniture, cracks: livingCracks,
      knocks: [{ kind: 'ball', x: 600, y: 28, to: [600, 92] }, { kind: 'book', x: 352, y: 26, to: [352, 82] }, { kind: 'vase', x: 865, y: 375, to: [908, 382] }],
      music: { root: 52, minor: true, bpm: 84, prog: [[0, 'm'], [-4, 'M'], [-7, 'm'], [-5, 'M']] },
    },
    {
      id: 'basement', name: 'The Basement', act: 4, goal: 22, night: 900,
      cat: 'sleep', wanted: true, threats: ['owner', 'traps'], openFood: false, pups: ['curious'], pupAge: 0.8,
      tunnels: [[0, 1]],
      trapSpots: [[600, 470], [300, 330, { hidden: true }], [760, 300]],
      food: {
        spots: [
          ['fat', 345, 186, { tag: 'fat' }],
          ['cheese', 560, 360, { hidden: true }], ['cheese', 680, 525, { hidden: true, floor: true }], ['cheese', 140, 44, { hidden: true }], ['cheese', 230, 470, { hidden: true }],
          ['crumb', 120, 300], ['crumb', 420, 520], ['crumb', 900, 250], ['crumb', 600, 560],
        ],
        random: { crumb: 4, cheese: 2 }, refill: 6,
      },
      tasks: {
        goal: 'Fill the nest',
        chain: [
          { text: 'Find the way through the pipes', hint: 'The old cracks are sealed. Curious found a vent on the left wall. Hide in it and press Space.', check: ['count', 'tunnel', 1] },
          { text: 'Climb to the winter stores on the top crate', hint: 'The crates go up like stairs.', check: ['surf', 'crate'] },
          { text: 'Steal the lard', hint: 'Heavy. You can only jump down with it.', check: ['pick', 'fat'] },
          { text: 'Drag the lard home', hint: 'Running on the pipes makes them ring through the whole house.', check: ['deliver', 'fat'] },
        ],
        side: [
          { text: 'Never get caught in a cage', check: ['keep', 'cage'] },
          { text: 'Keep Curious safe all night', check: ['keep', 'pup'] },
        ],
        secret: [{ text: 'Find the owner’s letter', check: ['flag', 'letter'] }],
      },
      props: [
        { t: 'cage', x: 520, y: 440, w: 44, h: 44 }, { t: 'cage', x: 180, y: 520, w: 40, h: 40 },
        { t: 'noisy', kind: 'pipe', x: 380, y: 250, w: 260, h: 12 }, { t: 'noisy', kind: 'pipe', x: 600, y: 200, w: 200, h: 12 },
        { t: 'noisy', kind: 'puddle', x: 820, y: 560, r: 24 },
      ],
      secrets: [{ kind: 'letter', x: 880, y: 300, floor: true }],
      blurb: 'The cracks are sealed. Find a new way through the pipes.',
      teaser: 'The whole floor. Every room, every danger.',
      intro: { pups: ['Mom, the holes are gone!', 'Squeak?', 'I know another way!'], mom: 'The owner sealed our cracks. Curious says there’s a way through the old pipes in the basement. Show me, little one.' },
      start: { title: 'The cracks are sealed', sub: 'Only the old vent pipes are left. Cage traps guard the food.' },
      starTip: 'The owner will come if you’re too loud',
      pal: { fog: 0x090b0a, sky: 0x55705f, ground: 0x1e1c18, hemi: 0.5, moon: 0.42, floor: 'concrete', floorA: '#363b38', wall: 'brick', wallA: '#4e3428', wallB: '#2c201a', trim: 0x221e1a, ceil: 0x161816 },
      lamp: 'bulb', window: { x: 220, w: 120, y: 205, h: 60 }, door: 300,
      catBed: [300, 480], dock: [900, 380], lights: [], decor: 'pantry',
      furn: pantryFurniture,
      cracks: [{ wall: 'w', y: 250 }, { wall: 'e', y: 450 }],
      knocks: [{ kind: 'carton', x: 140, y: 44, to: [140, 100], spawn: 'cheese' }, { kind: 'bottle', x: 630, y: 340, to: [668, 352] }],
      music: { root: 48, minor: true, bpm: 82, prog: [[0, 'm'], [-4, 'M'], [-7, 'm'], [-5, 'M']] },
    },
    {
      id: 'floor', name: 'The Whole Floor', act: 4, goal: 24, night: 960,
      cat: 'awake', catStart: [480, 300], wanted: true, threats: ['owner', 'traps', 'poison'], openFood: true, pups: ['brave', 'greedy', 'shy', 'curious'], pupAge: 0.82,
      vacuumStart: true, poisonStart: 1, trapSpots: [[470, 120], [800, 470, { hidden: true }], [240, 150]],
      zones: [{ id: 'dining', x: 0, y: 0, w: 300, h: 600 }, { id: 'living', x: 300, y: 0, w: 340, h: 600 }, { id: 'kitchen', x: 640, y: 0, w: 320, h: 600 }],
      food: {
        spots: [
          ['cheese', 150, 250, { tag: 'd1' }], ['cheese', 470, 236, { tag: 'l1' }], ['cheese', 800, 420, { tag: 'k1' }],
          ['crumb', 100, 120], ['crumb', 220, 400], ['crumb', 400, 520], ['crumb', 560, 420], ['crumb', 700, 200], ['crumb', 900, 300], ['crumb', 850, 560],
        ],
        random: { crumb: 6, cheese: 3 }, refill: 8,
      },
      tasks: {
        goal: 'Fill the nest',
        chain: [
          { text: 'Get the special cheese from the dining room', hint: 'West through the doorway: on the dining table.', check: ['pick', 'd1'] },
          { text: 'Get the special cheese from the living room', hint: 'On the coffee table in the middle room.', check: ['pick', 'l1'] },
          { text: 'Get the special cheese from the kitchen', hint: 'East: on the kitchen table.', check: ['pick', 'k1'] },
          { text: 'Find 3 of the pups’ lost toys', hint: 'Curious spots them.', check: ['count', 'collected', 3] },
        ],
        side: [
          { text: 'Keep all four pups safe', check: ['keep', 'pup'] },
          { text: 'Never bring poison home', check: ['keep', 'poison'] },
        ],
        secret: [],
      },
      props: [
        { t: 'noisy', kind: 'plate', x: 460, y: 240, r: 16 }, { t: 'noisy', kind: 'squeaky', x: 420, y: 470 }, { t: 'noisy', kind: 'bottles', x: 760, y: 300, w: 40, h: 20 },
        { t: 'noisy', kind: 'board', x: 120, y: 330, w: 110, h: 18 }, { t: 'noisy', kind: 'dock', x: 900, y: 120 },
      ],
      secrets: [
        { kind: 'toy', label: 'A tiny toy mouse!', x: 60, y: 560, floor: true }, { kind: 'marble', x: 560, y: 560, floor: true },
        { kind: 'thimble', x: 900, y: 500, floor: true }, { kind: 'sock', x: 380, y: 60, floor: true },
      ],
      blurb: 'Kitchen, living room and dining room in one night. All four pups come along.',
      teaser: 'The last night. The exterminator comes in the morning. Time to leave.',
      intro: { pups: ['Mom, we can all help now!', 'All four of us!', 'Let’s go!'], mom: 'The pups are almost grown. Tonight we gather food for the journey… from every room.' },
      start: { title: 'The whole floor', sub: 'Three rooms connected by doorways. All four pups follow you.' },
      starTip: 'The whole house is on alert',
      pal: { fog: 0x100e18, sky: 0x8a8ab8, ground: 0x2a2430, hemi: 0.74, moon: 0.8, floor: 'wood', floorA: '#4e3a2c', wall: 'panel', wallA: '#4e3e4c', wallB: '#2e2420', trim: 0x2a1e1a, ceil: 0x221e26 },
      lamp: 'chandelier', window: { x: 420, w: 160 }, door: 300,
      catBed: [470, 540], dock: [900, 150], lights: [], decor: 'living',
      furn: [
        { t: 'wall', x: 296, y: 0, w: 8, h: 230 }, { t: 'wall', x: 296, y: 350, w: 8, h: 250 },
        { t: 'wall', x: 636, y: 0, w: 8, h: 200 }, { t: 'wall', x: 636, y: 330, w: 8, h: 270 },
        { t: 'table', x: 60, y: 200, w: 180, h: 110, cloth: 0xd8d0c0 }, { t: 'chair', x: 100, y: 164, back: 'n' }, { t: 'chair', x: 160, y: 316, back: 's' },
        { t: 'cabinetTall', x: 0, y: 400, w: 50, h: 140 },
        { t: 'coffeeTable', x: 400, y: 190, w: 160, h: 70, plate: true }, { t: 'sofa', x: 360, y: 330, w: 240, h: 100, face: 'n', color: 0x6a5a8f },
        { t: 'ottoman', x: 340, y: 120, w: 46, h: 46 },
        { t: 'counter', x: 644, y: 0, w: 316, h: 72 }, { t: 'table', x: 720, y: 380, w: 170, h: 110, cloth: 0xc95b4a }, { t: 'chair', x: 684, y: 404, back: 'w' },
        { t: 'box', x: 690, y: 120, w: 44, h: 44, ht: 44 },
      ],
      cracks: [{ wall: 'w', y: 300 }, { wall: 's', x: 470 }, { wall: 'e', y: 260 }],
      knocks: [{ kind: 'book', x: 360, y: 140, to: [360, 190] }, { kind: 'cup', x: 860, y: 392, to: [868, 360] }, { kind: 'jar', x: 760, y: 40, to: [760, 102] }],
      music: { root: 50, minor: true, bpm: 90, prog: [[0, 'm'], [-4, 'M'], [-9, 'M'], [-2, 'M']] },
    },
    {
      id: 'moving', name: 'Moving Out', act: 4, goal: 0, night: 960, finale: true,
      cat: 'awake', catStart: [700, 200], wanted: true, threats: ['owner'], openFood: true, pups: ['brave', 'greedy', 'shy', 'curious'], pupAge: 0.9,
      owner: { type: 'patrol', light: false, at: [60, 300, 560], route: [[700, 300], [420, 470], [200, 330], [560, 250], [850, 420]] },
      exit: [520, 572],
      trapSpots: [[420, 520], [620, 500]],
      food: { spots: [['crumb', 300, 300], ['crumb', 700, 400], ['crumb', 200, 150]], random: { crumb: 2, cheese: 0 }, refill: 0 },
      tasks: {
        goal: 'Lead the family out',
        chain: [
          { text: 'Tell the pups to wait in the nest (Q)', hint: 'Scout the way alone first. Press Q near the nest: they hide and wait.', check: ['flag', 'pupStay'] },
          { text: 'Scout the way to the gap under the front door', hint: 'The glowing green ring by the south wall. That’s the way out.', check: ['flag', 'exitMom'] },
          { text: 'Spring the traps on the way', hint: 'Two traps guard the door. Climb the back of the sofa and push the book and the cup off (F): they land right on them.', check: ['count', 'disarm', 2] },
          { text: 'Lead all four pups out under the door', hint: 'Go back, press Q to call them, and lead them to the green ring. Avoid the spray clouds.', check: ['flag', 'allOut'] },
        ],
        side: [{ text: 'Don’t lose anyone on the way', check: ['keep', 'pup'] }],
        secret: [],
      },
      props: [
        { t: 'spray', x: 300, y: 420, w: 80, h: 70 }, { t: 'spray', x: 640, y: 300, w: 70, h: 80 },
        { t: 'noisy', kind: 'squeaky', x: 252, y: 452 }, { t: 'noisy', kind: 'board', x: 52, y: 408, w: 120, h: 18 },
      ],
      blurb: 'The exterminator comes in the morning. Lead the whole family out of the house.',
      teaser: '',
      intro: { pups: ['Mom… the exterminator comes tomorrow.', 'Are we leaving?', 'Together?'], mom: 'Yes. Tonight we leave this house, all of us. Stay behind me, do what I do, and we’ll make it.' },
      start: { title: 'The last night', sub: 'Scout the way, spring the traps, then lead all four pups out.' },
      starTip: 'The owner will come if you’re too loud',
      pal: Object.assign({}, livingPal, { hemi: 0.62, moon: 0.66 }), lamp: 'shade', window: { x: 680, w: 200 }, door: 240,
      catBed: [215, 500], dock: [900, 330], lights: [], decor: 'living',
      furn: livingFurniture, cracks: livingCracks,
      knocks: [{ kind: 'book', x: 420, y: 428, to: [420, 520] }, { kind: 'cup', x: 620, y: 428, to: [620, 500] }],
      music: { root: 53, minor: false, bpm: 74, prog: [[0, 'M'], [-5, 'M'], [-3, 'm'], [-7, 'M']] },
    },
  ];

  // The full game will have 20 nights. Nights past the playable ones are listed as "in development".
  window.PLANNED = [
  ];
  window.TOTAL_NIGHTS = window.LEVELS.length + window.PLANNED.length;

  window.MENU_MUSIC = { root: 57, minor: true, bpm: 64, prog: [[0, 'm'], [-4, 'M'], [-9, 'M'], [-2, 'M']] };
})();
