# Crucible — lab ideas

Not shipped. Not in the UI. Pick from chat.

## Shortlist

Built:
- Particle collisions that stack
- Fast path for high particle counts
- Gyro gravity
- Powder pressure
- Reaction recipes
- Lightning that seeks wet, then burns (+ Storm recipe)
- Periodic table drawer
- Daily seed
- Heat pipes (Copper)
- Encyclopedia (tap inspect chip / double-tap palette)
- Grid Native / Fast / Ultra
- Placeable gravity wells (Drop well)
- WebGL point renderer above ~2k
- SPH Pour preset
- Hybrid burst + Settle
- Shared undo
- Split view
- Scene export / import
- Real 3D particle field — a box to turn round, physics in depth, 9 3D-only scenes (build-78)

Still not (honest):
- WebGPU compute physics (typed-array + GL draw is as far as JS goes here)
- Full P2P world sync
- Workshop-tagged remix feed

## Round 1 — 19 Aug 2026

### Particle (25)

1. N-body gravity — every particle pulls every other (sampled, not O(n²) suicide).
2. Soft-body blobs — linked particles that squash and bounce as one mass.
3. Cloth / rope — spawn a grid or string, pin corners, tear it with the mouse.
4. Flocking — boids: separate, align, cohere. Predator cursor.
5. Spring lattice — grab one node, the mesh rings.
6. Collision solver — particles actually hit and stack instead of ghosting.
7. Fluid SPH — pressure + viscosity so a “water” preset pours.
8. Magnetic dipoles — north/south, they chain into field lines.
9. Orbit ribbons — trails that persist as Kepler ellipses, not smudges.
10. Particle life stages — born → hot → cool → dust → die, color by age.
11. Merge / split — two slow ones fuse; a fast one shatters on impact.
12. Wind field overlay — paint vector arrows, particles follow the flow.
13. Attractor set — drop 2–6 wells, assign mass, they orbit each other.
14. Emit from image — photo becomes a particle mosaic you can explode.
15. Audio reactive — mic or a track punches spawn rate and hue.
16. 3D tilt (gyro) — 17 Pro Max tilt is world gravity. Hold to lock.
17. Lasso select — circle a clump, drag / freeze / recolor / delete it.
18. Pin / nail tool — freeze individuals as anchors for ropes and galaxies.
19. Portal pair — enter A, exit B with velocity kept.
20. Time rewind scrub — 8-second ring buffer, drag backwards.
21. Seed from text — type a word, particles spell it then fall apart.
22. Collision shapes — drop circles/boxes the swarm bounces off.
23. Charge painting — finger paints +/−, Coulomb does the rest.
24. GPU million mode — keep the 1M cap, render as points so 1M is actually playable.
25. Save preset as scene — camera, forces, count, colors, one tap restore.

### Powder (15)

1. Pressure / airflow — gases push; fans, vacuums, chimneys.
2. Reaction recipes — one-tap volcano, ant farm, oil fire, ice dam, nuke pile.
3. Encyclopedia — tap a cell: melt point, density, what it eats.
4. Clone stamp — copy a 16×16 chunk, paint it elsewhere.
5. World wrap — left edge meets right, for rivers and loops.
6. Day/night heat — slow ambient swing; ice at night, steam at noon.
7. Growing plants 2.0 — roots seek water, leaves seek light, fruit drops seeds.
8. Concrete / cure — wet mix → set stone on a timer.
9. Electric grid — spark along metal, tripwire to C4, fuse delay.
10. Erosion — flowing water carves sand/dirt and dumps sediment.
11. Pressure cooker — sealed room + steam = rupture.
12. Life sim pack — termites, fish in water, birds in air, they interact with matter.
13. Save as blueprint — stamp a machine (pump, reactor, fountain) from workshop.
14. Pixel-perfect 1:1 / 2× / 4× grid — the old resolution scaler, restored.
15. Replace-by-element flood — “all water in this basin → ice” without painting.

### Neither / both (5)

1. Hybrid burst — powder explosion throws free particles that can settle back into grains.
2. Shared gravity / gyro — one tilt vector drives both chambers.
3. Split view — powder left, particles right, same clock, same undo.
4. Workshop remix — publish a scene with tags, fork someone else’s volcano into a galaxy.
5. Time-lapse export — 4× record, silent mp4 of the boil or the orbit.

---

## Round 2 — random, 19 Aug 2026

No categories. Whatever stuck.

1. A single “god finger” that is heat on powder and attract on particles, same gesture.
2. Slow-mo on impact — when a clump hits a wall, 200ms of 0.15× then snap back.
3. Particle fireworks that land as powder embers and actually burn wood.
4. A metronome: every beat, gravity flips. Watch sand and galaxies vomit.
5. Fog of war on the powder grid — you only see cells you’ve painted or that are hot.
6. “Un-simulate” brush — paint a region that ignores physics until you lift.
7. Seed a galaxy from the current powder silhouette. Sand dune → spiral arms.
8. Ants that can pick up powder grains and carry them, leave a trail.
9. A black hole in powder: cells spiral in, density crush to iridium, then a flash.
10. Rain from the top of the particle chamber that becomes water cells if you switch modes mid-fall.
11. Sticker notes on the canvas. Tiny lab labels that stay in world space.
12. A “boring” button that equalizes temperature and kills all motion. Panic reset.
13. Particle constellations — snap a photo, it names the cluster after a fake star.
14. Powder tsunami preset that wraps the screen three times.
15. Cursor mass = how hard you press. 3D Touch / Apple Pencil force.
16. A parasite element that infects neighbors on a delay, color shifts sickly.
17. Double-tap a particle to “possess” it — camera follows, flick to throw.
18. Powder “slice” tool: a moving wall that cuts the basin in half like a knife.
19. Save a 12-frame flipbook of the last second, scrub with your thumb.
20. Lightning that prefers the wettest path, then starts fires.
21. Particles that only exist in pairs. Kill one, the twin pops.
22. A quiet room: mute all sim sound except the element under your finger.
23. Reverse density — helium sand that falls up, lead steam that sinks.
24. Workshop “dare” maps: 60 seconds to freeze the lava before it eats the plant.
25. Particle snow that accumulates as powder ice when it hits the floor.
26. A ruler overlay. Density, temp, and speed along a line you draw.
27. Periodic table drawer — drag a real element in, we fake the closest behavior.
28. Screen as a drum: tap edge to send a shockwave through whichever chamber is live.
29. Memory leak as a feature: old particles become ghosts at 10% opacity.
30. One shared undo stack across Powder and Particles, so Tab doesn’t strand you.
31. A “museum mode” that pauses both and lets you pan/zoom like a specimen.
32. Powder concrete forms: place a mold, pour, wait, lift the mold.
33. Particle billiards. Six balls, one cue, walls of steel cells if you switch.
34. Smell-o-vision joke: oil + fire shows a “soot” badge. That’s it. That’s the gag.
35. Daily seed — same world hash for everyone that day, screenshot contest.
36. An element that is “nothing,” a hole that eats and leaves vacuum, air rushes in.
37. Particle handwriting: write with emit, the letters keep orbiting their centroid.
38. Heat pipes — copper cells move temperature without moving mass.
39. A tiny HUD that only appears while recording, so the clip has a lab timestamp.
40. Let two phones join a room and be left/right gravity wells. That’s the whole game.

Saved here so they don’t vanish in chat. Still not in the sim.

---

## Round 3 — random, 19 Aug 2026

1. A fuse you can coil. Fire walks the line at a set cells-per-second.
2. Particle “molasses” field — a painted oval where velocity is divided by ten.
3. Sand that remembers the last wind direction and leans that way when still.
4. A thermometer probe. Stab the grid, HUD shows a live °C sparkline at that pixel.
5. Binary stars. Two wells, adjustable mass ratio, Lagrange dust collects at L4/L5.
6. Powder photocopier — scan a rectangle, spawn the copy offset, slightly degraded.
7. Particles that bounce in pitch. Higher speed = higher tone. The chamber is an instrument.
8. Drought. Water slowly vanishes from the top down. Plants brown. Lava doesn’t care.
9. A “sample jar” — pinch a clump of powder, it lives in a vial in the menu, dump later.
10. Mouse as a comet. Hold, you grow a tail of ice particles that sublimate.
11. Insulation foam element. Expands into air, then goes inert. Traps heat.
12. Voronoi fracture — tap a solid, it cracks along a generated pattern, then falls.
13. Night vision overlay that only shows temperature, no element color.
14. Particle “current” — a river of charge you can close into a loop and watch it run.
15. A clock element. Oscillates. You can build a timer that opens a gate of stone.
16. Snowpack layers. New snow, old snow, firn, ice. Weight compresses the stack.
17. Gravity well that only affects one color. Blue orbits, red ignores it.
18. Powder “smudge” tool — smear existing cells like wet paint, density conserved.
19. Afterimage recording: the sim draws, the previous 8 frames stay as graphite ghosts.
20. A catalyst element. Doesn’t burn, but everything next to it ignites easier.
21. Particle cage. Draw a polyline, they ricochet inside like a Newton’s cradle gone feral.
22. Tide. A sine on ambient water spawn at the bottom. Build sea walls or don’t.
23. “Translate” brush — grab a rectangle of powder and slide it, physics paused inside.
24. Supernova preset. Outward shock, then a neutron-star well in the hole.
25. Rust. Iron + water + time. Slow. Ugly. Permanent unless you acid it.
26. A guestbook. First paint of the day writes into a public wall of silhouettes.
27. Particle friction floor. Bottom 10% of the chamber is sandpaper. They pile.
28. Cryogenic leak. A cracked pipe element hisses cold gas that freezes on contact.
29. Mirror world: powder on top, particles underneath, the silhouette is shared.
30. An element called “question.” Random valid reaction every contact. Lab hazard.
31. Pinch-to-time. Two fingers apart = faster, together = crawl. iPhone native.
32. Seed crystals. Drop one ice nucleus in supercooled water, the freeze races.
33. Particle “shepherd” moons. Two small wells herd a ring into a sharp band.
34. Ash that is lighter than smoke but wettable. Rain turns it to sludge.
35. A wager with yourself: start a scene, lock tools, 30 seconds, screenshot or discard.
36. Conductive ink. Draw a trace, spark follows your line like a PCB.
37. Particles inherit the hue of the powder cell they were born from. Genealogy.
38. A “still” button that exports the canvas as a 4K PNG, no HUD, no chrome.
39. Swarm panic. One loud sound (or tap) and flocking particles scatter, then regroup.
40. Geode. Fill a cavity with mineral, wait, crack it — crystals on the inside only.



---

## Round 4 — after 3D, 26 Sep 2026

Saved from chat, after building 3D and comparing it with particles.casberry.in — where every dot's place
comes from a small formula, often written by an AI, and nothing has physics or can be pushed.

1. Shape recipe box — describe a shape and the bodies form it, with sliders made for it and a title on
   screen. Push it apart and it pulls itself back together. Their idea, plus our physics.
2. Floating labels in the box — names that hang in 3D space and turn with it.
3. Colour by distance — near bodies one colour, far ones another.
4. Red-and-blue glasses mode — real depth with cheap 3D glasses.
5. Slice — show only a thin slab of the box, to see inside a crowd.
6. Turntable video — record one slow spin all the way round, ready to share.

---

## Round 5 — anything, 26 Sep 2026

### In 3D

1. On your table — the camera shows your room and the box sits on the real table; walk round it.
2. Look round with your head — the front camera follows your face, and moving your head shifts the view,
   like looking through a window.
3. Shadows — every body casts a soft shadow on the floor of the box, so you can tell how high it is.
4. Camera focus — near and far go soft like a real photo; tap a body to bring it into focus.
5. Fly inside — steer the view into the middle of a galaxy or a tornado and look around from in there.
6. Real down — the box knows which way is really down: lay the phone flat and everything falls to the back.
7. Light painting — drag through the box to leave ribbons of light that stay, a sculpture to go round.
8. Tiny planet — gravity pulls to the middle of a ball, and sand and water settle into a little round world
   with a sea on it.
9. Atom — the electron clouds round an atom in their real shapes: balls, dumbbells and rings.
10. Jellyfish — a see-through jelly made of springs that swims by pulsing, tentacles trailing.

### Particle field

1. Particle life — a few colours, each with secret likes and dislikes of the others; they sort themselves
   into things that look alive. Shuffle for a new world.
2. Foxes and rabbits — one kind hunts the other, both have babies, and a small graph shows the numbers rise
   and fall.
3. Galaxy crash — two galaxies collide and fling out long tails of stars.
4. Lava lamp — warm blobs rise, cool at the top and sink again, forever.
5. Paper marbling — drop coloured inks on water, drag a comb through, get marbled-paper swirls.
6. Jelly pen — draw any outline and it becomes a wobbly jelly of that shape that drops and bounces.
7. Slingshot — pull back and let go to throw a body; a dotted line shows the path it will take round the
   wells.
8. Pendulum wave — a row of swings of slightly different lengths that drift in and out of snake patterns.
9. The solar system — the real planets at their real speeds, the Moon round the Earth; speed time up to
   watch a year go by.
10. Living clock — the time spelt in bodies that tumble into the next number every minute.
11. Colours from a photo — pick a picture and the bodies take its colours. The engine can already do this;
    it only needs a button.
12. Feel it — a buzz in the hand when a supernova goes off or a crowd slams into a wall. The powder side
    already does this for explosions.

### Powder world

1. Popcorn — kernels that pop when heated, jump about and turn fluffy and white.
2. Soap — stirred into water it makes foam that piles up and slowly pops.
3. Sponge — soaks up water and swells; squashed by something heavy, it drips it back out.
4. Conveyor belt — a strip that carries whatever lands on it along. Build sorters and factories.
5. Magnet — iron dust stands up in spiky lines round it and follows it when it is dragged.
6. Sand on a drum — play music and the sand jumps into neat patterns, like salt on a speaker.
7. Little people — stick figures that walk, climb and run from lava, and can be picked up and dropped.
8. Photo into powder — a picture made of real sand, water and lava that falls apart when you let go.
9. Sand art — sand in any colour, for layered pictures like the bottles at the seaside.
10. Hourglass — sand pours through the neck; tap to flip it.

### Both chambers

1. Kaleidoscope — whatever your finger does is copied round the middle six times, so every stroke makes a
   snowflake.
2. Powder in 3D — a sand box to turn round, where sand piles into real cones and water finds its level.
   A big job.
3. Discoveries notebook — the first time you make glass, obsidian or a supernova, it is noted with a picture
   of the moment.
4. Relax mode — leave it on the table and it drifts from scene to scene by itself, slowly turning.

### New ways to touch it

1. Wave at it — the front camera sees your hand, and waving pushes the particles without touching the
   screen.
2. Talk to it — say "boom", "freeze" or "spin" and the field does it.
3. Ten fingers — switch off the view gestures and every finger is its own tool: ten whirlpools at once.
4. The big screen — the field on the TV through AirPlay, with the phone as the remote.

### Keeping and showing off

1. Send a 3D moment — freeze a 3D scene as a little model anyone with an iPhone can spin round or put on
   their table, without the app.
2. Live Photo — save a few seconds as a Live Photo that plays when pressed.

Five to start with: the shape recipe box, On your table, Particle life, Kaleidoscope, Colours from a photo.
