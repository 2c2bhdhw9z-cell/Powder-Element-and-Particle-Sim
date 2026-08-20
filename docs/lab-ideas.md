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

