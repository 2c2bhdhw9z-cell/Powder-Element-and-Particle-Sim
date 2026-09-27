# Crucible — lab ideas

Not shipped. Not in the UI. Pick from chat.

## Shortlist

Built:
- Light painting: draw ribbons that stay where you put them, and turn the box to see the shape
- Turntable video: one slow turn, recorded, stopping itself after a full circle
- Colours from a photo: the field drawn in whatever colours a picture is made of
- Particle life: five colours with their own likes and dislikes, and a Shuffle for new creatures
- Arrangement morphing: slide between any two crowd scenes, touchable all the way
- Physics lens: tap a body to see what is acting on it and where it is heading
- Red-and-blue glasses: the box drawn twice, once for each eye (Round 4 item 4, Round 7 item 41)
- An app icon at last, drawn by the same golden spiral the sunflower uses (Round 7, item 18)
- The cost warning knows the box costs more, and says so (Round 7, item 38)
- Nine materials of this app's own — corn that pops, soap, foam, sponge, belt, magnet, iron dust — each tested for doing what its card says
- Galaxy crash, Solar system, Pendulum wave, Marbling, Atom and Jellyfish — six scenes from Rounds 5 and 6
- Living clock: the field spells the time and tumbles into the next minute
- Floating labels: names that hang beside the things they name and follow them
- Feel it: a knock in the hand when a bolt strikes or a shell bursts
- Relax mode: the field drifts between scenes by itself, turning slowly
- Real down: laid flat, the phone makes things fall into the box (3D)
- A slice through the box, colour by how far away things are, and shadows on the floor (3D)
- Ten fingers: every finger on the glass is its own tool
- Kaleidoscope: every stroke copied evenly round the middle (particle field; the powder world not yet)
- Muscles: springs whose length pulses, and that push while they squeeze (what makes the jellyfish swim)
- Gravity that points at the middle of the world, for little round worlds
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

---

## Round 6 — substantial rather than stuffed, 26 Sep 2026

Ten additions meant to make Crucible feel deeper and more complete, not merely make its download larger.
Checked against the earlier rounds and the app before saving; none is already listed or built.

1. Guided lab book — a set of hands-on experiments such as making glass, balancing an orbit and building a
   pressure cooker. Each starts with a small setup, asks the player to discover the answer, then explains what
   happened using their own world rather than a prerecorded video.
2. Movie studio — set camera stops around a world, choose how quickly the camera travels between them, add
   slow motion and short captions, then export a finished clip. It turns creations into something worth sharing
   without putting large videos inside the app.
3. Living soundscape — properly recorded water, fire, glass, electricity and impacts, mixed according to what
   the simulation is doing. A quiet stream sounds unlike a flood, and ten sparks sound unlike a lightning strike.
   This is the one idea here that would deliberately add some worthwhile download size.
4. Layers — keep several named groups in one world, each with its own colour and rules. Hide, lock, duplicate or
   mix them; for example, build a still globe on one layer and an orbiting storm on another.
5. Physics lens — tap one body and see every force acting on it as an arrow, its predicted path, speed and the
   neighbours affecting it. Slow only that small area down so the reason something moved becomes visible.
6. Creature builder — join bodies into bones, joints and muscles, then make the muscles pulse in a sequence.
   Build walkers, swimmers and strange soft animals that genuinely have to balance and move under the physics.
7. Arrangement morphing — choose any two arrangements and smoothly transform between them while every body
   remains touchable. A globe can open into a knot, a word can become a galaxy, and a slider can stop anywhere
   between the two.
8. Recorded force loops — perform a finger movement once, then let the app repeat it on a loop. Stack several
   loops to make orbiting stirrers, beating hearts, wave machines or repeating choreography without writing code.
9. Parallel worlds — duplicate the current world into two views, change one thing in only one copy, then run
   them together. Compare gravity, liquid thickness, particle count or any other setting from exactly the same
   starting moment.
10. Worlds within worlds — zoom into a selected body and find another complete simulation inside it; zoom back
    out and it is still one moving point in the larger scene. A galaxy can contain an atom, whose centre contains
    a tiny powder world.

Best first three: Guided lab book for depth, Arrangement morphing for immediate spectacle, and Movie studio for
sharing what people make.


---

## Round 7 — outside the simulation, 26 Sep 2026

Brought in from a branch where it was written, so it is not lost. Not one of these is physics: they are about
who can install the app, what it tells us when it breaks, what it costs to run, and what it is for. Rough sizes
are in brackets. Nearly everything from "after 11" onwards waits on the last item.

### Seeing what the app looks like without a phone

1. A fast lane in the checks. Every change costs a full run — two operating systems, two build configurations,
   about ten minutes. A job started by hand that runs one system, unoptimised, and can be pointed at a single
   test makes the loop two to four minutes. [small]
2. Pictures of the app, made automatically. Build for the simulator on the Mac runner, walk the main screens,
   and commit the pictures to a branch. Anything attached to a run cannot be fetched back into a workshop; a
   branch can. Every interface fault so far was found by eye — this is a pair of eyes that never blinks.
   [medium]
3. A tap-through that fails the build. Open the tray, choose sand, draw, press play, open settings, move a
   slider, switch chamber, split the view — and fail on a crash, a hang or a blank screen. The panel that drew
   once and never again is exactly this kind of fault, and no unit test can catch it. [medium]
4. Keep the build's work between runs. The Linux job rebuilds from nothing every time. [small]
5. Check the server's half, not the reference's. Do not wire the whole web suite into the checks — most of it
   guards the engine that is being deleted. The routes and the schema the phone actually talks to are worth a
   job of their own. [small]
6. Talk to the real server, from the workshop. Once the four variables are set, replay the exact requests the
   app makes and check the answers against what it expects to parse. [medium, waits on the owner]
7. A bad link, on purpose. Delay, loss and a slow peer against the room's pacing, proving it degrades into
   fewer, fresher frames rather than a growing backlog, and that a peer who walks away times out. [small]
8. Release notes that say what changed since your build, in plain English, plus three things worth checking on
   the phone. [small]

### Never lose a fault again

9. Where crashes already are. The app has no crash handling of any kind — nothing written down anywhere. But
   every crash on your own phone is already recorded by iOS, under Analytics Data in the privacy settings, and
   can be shared from there. Worth knowing before anything is built. [nothing]
10. A breadcrumb, and "last time ended badly". Keep a small note of what the world was doing — seed, settings,
    the last things touched — rewritten as you go, and on the next launch notice the last session never
    finished and offer to send the note. No account, no server, no entitlement, nothing that can make signing
    the app harder than it already is. Apple's report says where in the code it died; this says what the world
    was doing, which is the half that makes it reproducible. [medium]
11. TestFlight, which is also the answer to the widget question below. Not the App Store — TestFlight on its
    own, which needs the paid developer account and nothing else. Internal testers (up to 100) install straight
    away with no review at all; outside people (up to 10,000) need a lighter beta review; a build lasts ninety
    days; crashes and tester feedback arrive in App Store Connect by themselves, symbolised. It also makes the
    app installable by somebody who is not you, without a re-signing tool, and without it expiring every week.
    [medium, costs the membership]
12. The numbers Apple will not otherwise hand over. There is an Apple framework that gives the app its own
    reports: crashes with stacks, hangs, slow launches, disk-write spikes, battery and energy. It only delivers
    for TestFlight or App Store builds — never for a sideloaded one — so it is a reason to do item 11 rather
    than a replacement for it. [small, after 11]
13. A one-tap "that looked wrong". Not a crash: a fault with no crash at all, which is most of what you have
    found. The same note as item 10, sent on purpose, with a picture. [medium]
14. Break the files on purpose. Truncated saves, nonsense replies, half-arrived room frames — every loader
    should complain rather than die. A world that cannot be opened is unrecoverable for somebody with no
    debugger. [small]
15. Long runs with rules that must hold. Every scene for tens of thousands of moments, asserting that nothing
    impossible happens rather than that it matches a recording. Recorded comparisons prove identical; these
    prove sane. [medium]
16. Fail the build when it gets slower. The benchmark prints on every run and nothing reads it. [small]
17. Old saves keep opening. Keep an old world file in the repository and load it on every build. [small]

### Getting it to other people

18. An icon at last. Still nothing — no icon, no asset catalogue. Every install on your phone wears a blank
    square, and it is the first thing anybody else would see. [small]
19. A public face. The banner, the share picture and the install page all live in the part being deleted.
    Whatever replaces them should not live in the app's repository. [small]
20. Worlds that open where they are. The app can send a world out and pull one in through a file picker, but it
    does not handle world files: no double-tap to open, no "open in Crucible" from a message. Small change, and
    it turns a world into something you can post to somebody. [small]
21. The engine where there is no Apple. It imports nothing at all — not even the platform's maths library — and
    the renderers live inside it and write plain pixels, which is why pictures of the world can be made without
    a screen. That is exactly what a build for a browser would need, so a world could be watched by somebody
    who will never install anything, and a day's world could be drawn by a machine with nobody's phone
    involved. Not reviving the web app; it is this engine, somewhere else. [large]
22. The television. The field already reacts to sound, and mirroring to a screen costs no extension — which
    matters, because extensions are the one thing this app cannot have. [medium]
23. Publish the day's world. Everybody is given the same world each day and there is no way to compare, so it
    is a shared thing that nobody shares. A picture a day, drawn without a phone, is enough. [medium]
24. Something to hold. The renderer produces exact pixels, so a poster of your own lava flow or a drawing from
    a pen plotter is a print job rather than a feature. [small]

### What it costs to run

25. The battery. Frames and milliseconds are measured; energy is not. A field running at the full refresh rate,
    a microphone and screen recording together is about the most expensive thing a phone can be asked to do,
    and the bill is counted nowhere. [medium]
26. A hot phone, and a tired one. Nothing reads the phone's temperature or its Low Power setting, so when the
    phone slows the app down it simply looks like the app going bad. The decision belongs in the engine, where
    it can be tested; only the reading is app-side. [medium]
27. Sensors it ignores. Tilt and the microphone are the only two it uses. Air pressure falling as weather comes
    in, your steps as a slow tide, where the sun actually is, how bright the room is — all of it app-side
    plumbing onto physics that already exists. [medium]

### What it is for

28. Take things away. Fifty materials, twenty-odd arrangements, nine 3D scenes, dozens of settings, and a
    hundred ideas queued. A way to hand the phone to somebody with five materials and three tools is the one
    feature nobody has asked for and nobody can currently have. [medium]
29. Say 1.0 and stop adding. The only item on this list that lowers risk instead of raising it. [nothing]
30. Give it a memory. Saves are names and files — no picture of the world, no gallery, nothing that shows you
    what you built last week. Every other creative tool on the phone remembers for you; this makes the app
    about your worlds rather than about its engine. [medium]
31. A first run. Nothing introduces the app to anybody. Fifty materials, brushes, recipes, tilt, split view and
    recording, and no path through any of it. [medium]
32. Seen once on a tablet, and sideways. Both are declared in the project and neither has ever been looked at.
    [small, needs 2]
33. Something to plot. Measurements out as numbers rather than only as pictures, for somebody learning. The
    encyclopedia, the recipes and the day's world are most of a classroom toy already. [small]
34. The written-down method. Roughly four and a half thousand lines of notes, written to a standard almost
    nothing else meets: status that admits what is skipped, decisions recorded with their reasons, work tried
    and abandoned with the measurement that killed it, comparisons retired on the record instead of quietly
    regenerated, and a list of what will waste your time. That is a way of building a large verified thing with
    an agent, and as far as I can tell nobody has published it. [medium]
35. A second opinion. One agent writes and grades its own work. A different model, on a different provider,
    told to find faults and prove them, is the check this project has never had. [small]
36. A page for "if this stops". Where the worlds live, the account, the address, the four server variables, how
    a build is made. The only document here that assumes it outlives your attention to it. [small]

### The two chambers, after 3D

37. The room cannot carry the field. What travels between two phones is the powder grid — a width, a height,
    gravity and the cells. The particle chamber, which is the one that just grew the most, has never been
    shareable in any form. Either give it a wire format or say plainly in the panel that a room is powder only.
    [medium]
38. The cost guard does not know the box exists. The limit that exists because the field once fell over at two
    hundred thousand bodies takes only a count and whether collisions are on, and the benchmark has no cases
    for depth at all. In the box, neighbours are found in cubes and the depth passes are extra work on top — so
    the number you are shown before setting off a big scene is a flat-world guess. [small]
39. Sleeping bodies, done properly. The notes already record that the reference's sleep saves no time at all —
    a sleeping body is still walked end to end — and that a version that genuinely skipped settled bodies is a
    different piece of work. The box doubles the cost of walking every body, so that work is now worth twice
    what it was. [medium]
40. The powder world seen through the box's camera. Not a second simulation: the same grid drawn as a slab of
    cubes in the 3D view that already exists, with the shadows and fog already built, so a castle you just
    made can be walked round. Say plainly that it is a view of the same world. [medium]
41. Red-and-blue glasses. Already in Round 4 and still unbuilt, and the drawing now knows how far away every
    body is — two offsets, red and cyan. The cheapest spectacle here, and the only one you can show somebody
    without handing them a second phone. [small]
42. A steady view, and the system's own settings honoured. The phone can now move the view by itself, and
    nothing in the app reads Reduce Motion, Reduce Transparency or Increase Contrast. Buttons have labels;
    nothing else does. [small]
43. Four small ones, each leaning entirely on machinery that already exists: lasso select, rewind scrub, a
    thermometer you stab into the grid, and a tide that is a slow sine on how much water arrives. [medium]

### The thing nobody has tested

44. Find out whether an extension can be installed at all. You have never tested it, and the reasons to expect
    trouble are specific: a widget is a second program inside the app with its own identity and its own
    signing, the re-signing tool has to sign that too or the install fails or the widget never appears, and
    sharing anything between the app and the widget needs a capability that free accounts cannot have. The test
    is cheap: one throwaway widget, built by the checks, installed the way you install everything. Either
    answer is worth having. [small]
45. A widget that needs nothing shared. If extensions do install, a widget does not need the app's data at all,
    because the day's world is a pure function of the date: the widget can work out today's world itself and
    draw it with the engine's own renderer. No shared container, so no capability to be refused. [medium,
    after 44]
46. A clock, on the lock screen and on a table. The same experiment decides it. A clock is one of the few things
    a widget does update second by second. [small, after 44]

### The repository itself

47. ~~There is no history.~~ **Not true any more, since 27 September 2026.** The main line now has a real history —
    a hundred and eighty-odd commits, each one a change with its reasons, so a change can be compared against what
    came before it and rolled back on its own. That is also how two changes that deliberately broke the project were
    undone without losing anything. The original note follows, for the record.

    There is no history. The main branch is a single commit, and every push replaces it with a new single
    commit containing everything. So there is nothing to compare a change against, nothing to roll back to,
    and no way to find which change broke something. Deliberate or not, it is worth knowing. [small]
48. Two notes have gone stale. The gh commands listed as failing in the workshop now work, and the engine is
    listed as building and testing there, where there is no Swift at all any more. Every agent that reads the
    stale version loses time to it. [small]

### The decision that unlocks half of this round

49. Pay for the developer account, or don't. It is the difference between TestFlight (install without a
    re-signing tool, ninety-day builds, crashes collected for you), widgets and a lock-screen clock, and an app
    somebody else can install — and the present arrangement, which works, costs nothing, and is yours alone.
    Everything here marked "after 11" or "after 44" is waiting on this one answer.

---

## Tried and not shipped

Kept so the next attempt does not repeat the work.

**Tiny planet** (Round 5). Gravity pointing at the middle of the world is built, tested and available to any
scene — that part shipped. The world itself did not, because the crowd cannot yet hold a ball of loose matter up
against its own gravity:

- **As liquid**, the ball keeps its shape perfectly, and cannot be dug. Everything in it is already pressed
  toward one point from every side, so the liquid sits at the limit of how tightly it can pack. A pull held in it
  moves matter *outward*, because the pressure pushes back harder than the finger pulls. Softening the liquid a
  long way barely changed it.
- **As grains that collide**, it can be dug, and it collapses through itself. The ball fell from two hundred and
  seventy pixels across to sixty. Tried at two grain sizes, three packing densities and pulls from a fifth of the
  usual strength down to a fiftieth; it collapses every time. The crowd's collisions cap how many neighbours each
  square examines — which is what keeps a million bodies affordable — and a ball being squeezed from all sides is
  exactly the case where that cap means most of the overlaps are never resolved.

**Lava lamp** (Round 5). Not shipped, and for a plainer reason than the tiny planet: the particle field has no heat.
A lava lamp is one thing — warm matter rises, cools at the top, sinks, warms again — and every part of that cycle is
temperature. Two weights of liquid gives the rising half honestly, through the pressure between them, and then the
blobs simply stay at the top for ever, because nothing can cool them. The powder world has temperature and would do
this readily; the particle field would need it adding, and a temperature is a per-body number with a whole set of
rules behind it rather than a scene's worth of work.

Everything short of that was considered and rejected as dishonest: a timer that sinks blobs on a schedule, a
height-dependent push, a slow wobble in gravity. Each would look approximately right and none would be a lava lamp —
they would be an animation of one, which is the thing this field is built not to be.

So it needs one of: collisions that hold a pile under pressure from every direction, or letting things built from
springs push the crowd (which the jellyfish would also use — see `Spring.thrust`). Both are real pieces of
physics and both are bigger than the scene.

---

## Tried and not shipped

Kept so the next attempt does not repeat the work.

**Tiny planet** (Round 5). Gravity pointing at the middle of the world is built, tested and available to any
scene — that part shipped. The world itself did not, because the crowd cannot yet hold a ball of loose matter up
against its own gravity:

- **As liquid**, the ball keeps its shape perfectly, and cannot be dug. Everything in it is already pressed
  toward one point from every side, so the liquid sits at the limit of how tightly it can pack. A pull held in it
  moves matter *outward*, because the pressure pushes back harder than the finger pulls. Softening the liquid a
  long way barely changed it.
- **As grains that collide**, it can be dug, and it collapses through itself. The ball fell from two hundred and
  seventy pixels across to sixty. Tried at two grain sizes, three packing densities and pulls from a fifth of the
  usual strength down to a fiftieth; it collapses every time. The crowd's collisions cap how many neighbours each
  square examines — which is what keeps a million bodies affordable — and a ball being squeezed from all sides is
  exactly the case where that cap means most of the overlaps are never resolved.

So it needs one of: collisions that hold a pile under pressure from every direction, or letting things built from
springs push the crowd (which the jellyfish would also use — see `Spring.thrust`). Both are real pieces of
physics and both are bigger than the scene.
