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
  ];

  // The full game will have 20 nights. Nights past the playable ones are listed as "in development".
  window.PLANNED = [
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
