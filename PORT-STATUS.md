# Port status

The working state of the native port, written so that anyone picking this up — including
me after a break — can find their footing without re-deriving it. Kept current as the
port progresses.

For *why* the project is arranged this way, read [README.md](README.md) and
[native/README.md](native/README.md) first. This file is the map, not the argument.

---

## The one idea everything rests on

The web implementation was the **starting point** for correctness. Nobody ever wrote down
how this simulation behaves — it is the accumulated result of thousands of small tuning
decisions — so the only way to carry it into Swift intact was to run the same world in both
and compare **every cell and every body**, including how many random numbers each engine
consumed. That has found about eighty real bugs. It works because it cannot be fooled.

**But `web/` is now reference material only and must not be edited.** It is going to be
deleted once the app has surpassed it; the only reason it is still here is so the app's look
and behaviour can be checked against it. Do not fix anything in it, do not regenerate its
fixtures, do not "keep the two in step".

### Which means the comparison is a tool, not an authority

Two rules, and the second replaces what this file used to say:

1. **Never regenerate a fixture to make a test pass.** If a comparison fails unexpectedly,
   that is the method working.
2. **When behaviour is deliberately changed, retire that comparison and replace it with a
   native test of the intent.** The reference is not allowed to be a defence for something
   that looks or behaves wrong — "the port is faithful" is not an answer to "this is broken".

Every comparison retired that way is recorded where it was:

- **The built-in scenes.** `RecipeGoldenTests` is gone, replaced by `RecipeTests`. The
  reference's scenes were rectangles at fixed fractions: flat ground, identical trees at equal
  spacing, and the *same picture every time*. Holding the rewritten ones to that grid would be
  holding them to the fault.
- **Two powder scenarios.** `laser-stops-at-bedrock` is filtered out of the comparison (see
  `PowderGoldenTests.retiredScenarios`) because the reference's laser did not shoot, and
  `spark-seeks-water-along-wire` because the reference's spark searched the same neighbour up to three
  times, flooding one wire three times and rolling to burn it out three times. `PowderIntentTests`
  checks what both should do. The other thirty-six are compared cell for cell.
- **Momentum in empty air.** Blasts in the reference left momentum in empty cells, where nothing damps
  it and the next grain to drift in is launched by it. The native engine no longer writes it, so the
  powder and event comparisons now compare momentum only where there is material — the cells themselves
  still match exactly.
- **Two particle scenarios.** `pour-fluid-mode` and `nbody-mutual-gravity` built their scenes in the
  object list, which neither the fluid nor gravity-between-bodies acts on — so Pour was beads falling
  through each other and N-body pulled on nothing. Both are rebuilt from the crowd, and
  `ParticleArrangementTests` checks that the liquid pours and spreads and that the disc holds together.
- **Eight finger scenarios.** `mouse-attract-sweeps-through`, `mouse-repel-and-release`,
  `mouse-vortex-swirls`, `mouse-gravity-well-swirls-inward`, `mouse-freeze-damps`,
  `mouse-hyper-drive-recolours`, `mouse-hawk-pushes-hard` and `swarm-with-cursor-and-wrapping`. The
  reference's finger was too weak on a phone to see: for the crowd — which most arrangements are made
  of — a constant push of eight hundredths of a pixel a moment with no swirl, freeze or paint at all,
  and for the individual bodies a pull that fell away with the square of the distance. Every tool now
  uses Built-Helion's brush on everything (see `ParticleBrush.swift`), and freeze stops what it touches
  after the moment's gravity and holds rather than before them, so frozen bodies no longer creep.
  `ParticleBrushTests` checks each tool on both kinds of body, and every tool on every arrangement. The
  painter and the emitter are unchanged, and `dna-helix-repainted-stays-in-the-helix` and
  `mouse-emitter-spawns-continuously` are still compared exactly.

### The finger, zooming out, and sizes

Built-Helion — the owner's working reference, a separate web project — is what the finger and the zoom
were checked against, because the owner's report was that its tools worked and these did not.

- **The finger.** One rule for every body: a circle twelve hundredths of the screen high, a push that
  fades evenly to nothing at its edge, forces measured in screen heights per second per second. The
  reach is set as a share of the screen and stays that size on the screen however far the view is
  pulled out. At the top of the slider it reaches the whole field.
- **Zooming out gives room.** Bodies are drawn at the zoom, so pulling back shrinks them along with
  the picture. Arrangements and added bodies are laid out on a screen's worth of the world in its
  middle — those that stand on the floor stand on the world's floor — so a galaxy chosen after zooming
  out is its usual size with room round it, rather than filling the grown world with bigger stars.
  Undo points follow the world when it grows or shrinks, so undoing after a zoom brings things back
  where they are rather than where they were in the smaller world.
- **Sizes.** Each body of the crowd can have a size of its own. Bodies added to an arrangement are
  made the size of the ones already in it unless "match the size of what's there" is turned off.
- **Walls and painted wind** act on the individual bodies as well as the crowd.

---

## What is done

| Area | State | Verified by |
| ---- | ----- | ----------- |
| Elements, registry, packed physics table | complete | property-by-property against extracted web data |
| Powder grid: movement, heat, pressure, phase change, chemistry, explosions, electricity, brush | complete | 38 scenarios, cell-for-cell + temperature + momentum + draw counts |
| Particle field: model, swarm, forces, integration, boundaries, springs, flock, all 20 spawners | complete | 29 scenarios, every body + springs + swarm + draw counts; 10 retired and replaced by tests of intent (above) |
| Own sine, cosine, powers | complete | several thousand recorded values, bit-exact |
| Saving, loading, undo, multiplayer wire format | complete | round trips + wire payload byte-identical across 38 scenarios |
| Health inspection and repair tools, both chambers | complete | 25 behavioural tests |
| All 13 built-in powder scenes | rewritten | native tests: rolling ground, layering, varied trees, a different world per seed, laid out at 8 sizes |
| Powder renderer | complete | 16 frames, pixel for pixel |
| Particle renderer | complete | 6 colour modes, pixel for pixel |
| The four set-piece events | complete | 4 events x 4 sizes, cells + heat + momentum + draws + the shake and sound they ask for |
| Tilt to tip gravity | complete | 12 tests on the tuning; the attitude algebra verified over 258,000 orientations |
| Encyclopedia and periodic drawer | complete | generated from the reference text, 9 tests hold it there |
| Sound — all six | complete | 18 tests, checked as signals rather than as settings |
| Trails and the touch ring | decisions complete | 9 tests; see the note below on why not pixels |
| Saving, loading, autosave, sharing, invented materials | complete | builds in CI |
| The day's shared world | complete | 10 dates compared against the web's choice, hash and all |
| The two chambers affecting each other | complete | 16 behavioural tests |
| Screenshots and screen recording | complete | pixel export tested in the engine; recording is ReplayKit |
| Brush shapes, search, detail setting, help | complete | builds in CI |
| Inspect chip, Fahrenheit, performance history, split view | complete | temperature conversion and the rolling history tested in the engine |
| iOS app: Metal, both chambers, glass dial, docks, settings | first pass | builds in CI, installs, runs |
| iOS app: real typefaces, tilt button, world controls, health report | complete | builds in CI |
| iOS app: appearance matched to the reference | complete | header, sheet chrome and trays measured from the stylesheet; colours and radii checked value by value; a CI step fails the build if a typeface name matches no bundled file |
| Shared room, phone to phone | complete | 68 tests on the protocol, the compression, the pacing and the code; the transport itself needs two real phones |
| Cloud saves, the workshop, signing in | complete | 45 engine tests on the replies and the addresses, 13 on the server's routing; the account check is asserted for every operation |
| CI: engine on Linux + macOS, unsigned `.ipa` as a release asset | complete | green |

**891 engine tests. 148 reference tests. 93 script tests.** Green on Linux and macOS, in
debug and optimised builds.

**The port is complete.** Everything the web version does, the app now does — including the online
half. What is left is not code: the server has to be configured before anything can actually be
kept on it, and only the owner can do that. The list is at the top of
[ONLINE-PLAN.md](ONLINE-PLAN.md).

---

## What is left

Roughly in the order it should be done.

### 1. Tick optimisation — as far as it is worth taking alone

**This section is now mostly a record of what not to try.** Three plans in it turned out to
be wrong once measured, and the measurements are permanent so nobody has to rediscover them.

Run `swift run -c release crucible-bench`; it prints everything below on every CI run.
Figures are from the Linux container, about 1.2× slower than the Apple hardware the macOS
job reports — ratios transfer, absolutes do not.

#### What the app actually runs at

Worth stating first, because it governs whether any of this matters. `SimulationModel`
caps the world at **150,000 cells**, chosen from measurement to leave the drawing and the
interface a real share of a 120 fps frame. One cell per screen pixel would be 3.16 million.

#### Where a tick's time goes

| | Cost at 3.16M cells |
| --- | --- |
| Rebuilding the pressure field | **6.5 ms** |
| The bare walk plus clearing the visited marks | **3.5 ms** |
| Spreading heat | **1.6 ms** |
| Each occupied cell, on top of all that | **41–226 ns**, by element |

Per occupied cell, attributed by stubbing each stage in turn:

| | inert stone | sand | water |
| --- | --- | --- | --- |
| the walk itself | ~22 ns | ~22 ns | ~30 ns |
| phase change | now skipped | 15 ns | 57 ns |
| chemistry | 5 ns | 5 ns | 17 ns |
| movement | ~0 | **61 ns** | **93 ns** |
| **total** | **41 ns** | **97 ns** | **191 ns** |

#### Four things that were tried or planned, and what came of them

**Skipping empty rows — dropped, worthless.** An empty cell already costs two reads and a
branch.

**Skipping the portal scan — done, and exact.** It was a whole extra pass for something
almost no world contains. Now behind `portalBMayExist`; see the comment on that property
for why it cannot be fooled. Fixed cost 13.6 ms → 11.3 ms.

**Skipping the phase-change chain — done, and exact.** Forty of the fifty built-ins have no
phase change and it walked the whole chain to find out. See `PhaseChangeParticipants`, and
the brute-force test that stops the list rotting.

**Narrowing heat and pressure to a bounding box — dropped, and this file used to recommend
it.** Two independent reasons, either alone sufficient:

1. At the size the app runs, the whole-grid sweeps cost about **half a millisecond total**.
   There is nothing meaningful to win.
2. The box would have to cover anything not empty *or* off ambient *or* holding pressure.
   Pressure decays by a factor each pass and only reaches exactly zero after some five
   hundred of them, so the box lags far behind the material. In any world busy enough to be
   slow, it covers nearly everything and saves nothing. It is most effective precisely where
   it is least needed.

#### The honest ceiling

**The per-cell path does not have 2–4× in it.** This file used to claim it did, reasoning
from cycle counts. Measurement says otherwise: the time is in `movement`, which is the
physics itself, not in dispatch or lookups. Maybe 1.2–1.4× remains, with care and risk.

So **resolution is the lever, not micro-optimisation**, and choosing it needs the user.

**Decision on record: do not spread the tick across processor cores without asking.** The
sand's whole character comes from a strict processing order — bottom row first, horizontal
direction alternating per row and per tick, each cell moving at most once. Reordering it
changes how the sand behaves and forfeits the cell-for-cell verification that has found
about eighty bugs. The choice to put to the user is between:

1. today's 150,000 cells at 120 fps;
2. something nearer full resolution at around 30 fps;
3. full resolution at 120 fps, by processing cells in a different order — faster, and no
   longer quite their simulation.

### 2. App features — done

Nothing local is outstanding. For the record, the last few were: the inspect chip on the canvas,
Fahrenheit, the performance history behind the frame-rate chip, and split view.

Split view is worth a note. It looked like the least important thing on the list and turned out to
be the opposite: the two chambers affect one another — explosions throw sparks across, resting
bodies silt down into sand — and none of that is visible unless both are on screen. The bridges had
been built two commits earlier and were, in practice, invisible.

#### Verified differently, and why

Five things in the app are *not* compared against the reference frame for frame. All five are
recorded here so nobody later assumes it was an oversight:

- **Trails and the touch ring.** The reference draws them with the browser's 2D canvas, whose
  antialiasing and line joins are specified nowhere. A recorded picture would prove only that one
  rasteriser agrees with itself. Every decision feeding into them is tested instead.
- **The six sounds.** The reference hands a description to the browser and lets it generate the
  samples. They are checked as signals — that the meteor falls and the freeze rises, that the
  explosion darkens, that nothing clips — rather than sample for sample.
- **The chamber bridges.** The reference decides what a settling body becomes by searching for a
  substring inside a CSS colour string. There is no CSS colour string here, so there is nothing to
  compare; the behaviour is tested instead, including the ways it could quietly destroy something.
- **Screen recording.** The reference records its canvas element. This records the screen through
  ReplayKit, which also captures the sound and does not compete with the simulation for frame time.
- **Split view's layout.** Stacked rather than side by side, because on a phone held upright two
  tall thin chambers are worse than two short wide ones — and the reference's side-by-side layout
  only applies from tablet widths up anyway.

#### Small deliberate departures

Each is an improvement rather than a translation, and each is commented where it happens:

- The inspect chip updates on every touch, not only at the start of a stroke, so dragging across a
  world reveals how hot the middle of a lava flow is.
- The screen-shake offset uses its own random numbers, so a decorative wobble cannot change the
  physics.
- Sparks from an explosion draw from the field's random numbers, not the grid's, so switching the
  bridge on does not alter how the powder world unfolds.
- A meteor and the explosion it causes are one undo, not two.
- Kept scenes have visible share and delete buttons rather than hidden swipes.
- The eyedropper is a one-shot rather than a mode.

#### Three bugs found in the reference along the way

All three are cases where the reference describes behaviour it does not have:

- Its help screen says a cloth tears when pulled. No spring is ever removed in either engine, so it
  does not — here *or* there. The line was copied across before being checked, and checking is the
  only reason it was caught.
- Its stylesheet names IBM Plex Mono for every numeric readout and never requests it, so all of them
  render in whatever monospace the browser defaults to. Fixed on the web side.
- Lowering the body limit left the swarm untouched while the readout insisted it had obeyed.

### 3. Online — built, and waiting on the server being set up

The shared room, cloud saves, the workshop and signing in are all done. How and why is in
**[ONLINE-PLAN.md](ONLINE-PLAN.md)**, which is now a record rather than a plan. Read it before
touching any of it — several of its findings took a while to establish and would otherwise be
rediscovered the hard way.

The short version:

- **The shared room** uses iOS's own phone-to-phone networking, not WebRTC, because WebRTC would
  mean an embedded framework and every embedded framework is another provisioning profile for
  on-device signing to fail on. Followers do not simulate — two engines come apart inside a frame —
  so the host sends the whole world continuously, compressed, and paced by acknowledgements so a slow
  link gets fewer current frames instead of a backlog.
- **Cloud saves and the workshop** reach the same queries the website does, through new HTTP routes,
  with the server functions reduced to wrappers. They read a bearer token and refuse to look at
  cookies, which makes a cross-site request structurally unable to borrow somebody's session.
- **Signing in** goes through the phone's own sign-in window. The token is kept in a protected file
  rather than the keychain, because the keychain depends on entitlements a re-signed app cannot rely
  on having.
- **The server still needs setting up by hand.** Without `DATABASE_URL` nothing is kept, by design —
  the app now detects that and says so before anybody saves anything, but it is a warning, not a fix.
  The exact list is at the top of ONLINE-PLAN.md.

### 4. Deleting the web front end

Only once the app has surpassed it. The **server** stays either way; it is the back end
the app will need. See the note in README.md.

---

## Where things are

```
native/
  Package.swift              engine + benchmark; imports nothing, builds anywhere
  project.yml                Xcode project is GENERATED from this, never committed
  Sources/CrucibleCore/
    Support/                 Mulberry32, PackedColor, JSMath, FDLibm
    Elements/                ids, the 50 built-ins, registry, packed table
    Powder/                  engine, movement, thermals, phase change, reactions,
                             electricity, explosion, brush, history, serialization,
                             diagnostics, recipes, render
    Particle/                model, swarm, engine, step, spawners, serialization,
                             diagnostics, render
    Room/                    what two phones say to each other, the compressed world
                             frame, and every decision a room makes
    Cloud/                   the server's replies, its paths, and what a refusal means
  Sources/CrucibleBench/     performance measurement; prints in CI on every run
  Tests/CrucibleCoreTests/   the comparisons, plus Fixtures/
  App/
    Design/                  Palette, Glass, LabSheet
    Metal/                   GridView + GridShaders (powder), FieldView + FieldShaders
    Simulation/              SimulationModel (powder), ParticleFieldModel,
                             RoomSession + RoomBridge, CloudClient + CloudAccount
    Views/                   ContentView, surfaces, docks, settings, panels
web/
  src/sim/                   the reference implementation and the fixture generators
  src/lib/lab-store.ts       every query, shared by the website and the app
  src/lib/api/               the app's HTTP routes and native sign-in
  migrations/                the schema — NOT at the repository root
.github/workflows/           engine.yml (Linux + macOS), ipa.yml (unsigned .ipa)
```

---

## Regenerating a fixture

Each generator lives beside the suite it feeds. Always confirm the assertion mode passes
straight afterwards, which proves the web engine has not drifted either.

```bash
cd web
CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-powder           # 38 powder scenarios
CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-particle         # 39 particle scenarios
CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-recipes          # 13 scenes x 4 sizes
CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-render           # powder pixels
CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-particle-render  # particle pixels
CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-math             # sin/cos/pow — see below
npx vitest run                                                 # then assert everything
```

`golden-math` is different in kind: it records a fixed mathematical fact rather than this
project's behaviour. If it changes, the host JavaScript engine changed, and the native
implementation should be left exactly as it is.

---

## Interface faults, and the one thing they all had in common

**Every fault in this list was found by the owner installing the app and looking at it. Not one
was found by a test, and not one was found by CI.** That is the single most important fact in
this file about the app layer: CI proves the app *compiles*. It proves nothing whatsoever about
whether it works, and there is no automated coverage below `CrucibleCore`. Read that as a
standing instruction to look at screenshots and to be suspicious of anything you have only
compiled.

They also share a shape: **each one looked like the app being broken rather than like a mistake
in a specific place**, and several were surrounded by things that looked perfect. That is why
they survived so long.

| What was seen | What it actually was |
| --- | --- |
| The recording preview's Save and close buttons sitting up inside the clock and the battery | `.ignoresSafeArea()` on a UIKit controller that positions its own bar relative to the top of whatever it is handed. Hand it the whole screen and its buttons go behind the island. Not fixable from inside — stop giving it the space. |
| The play and clear buttons clipped at the very bottom edge | `.ignoresSafeArea(edges: .bottom)` on the content. Only the *backdrop* wanted to reach under the home indicator; the controls went with it, into the band iOS takes the swipe from. |
| 4× and the tilt button missing from the screen | The row was about 446 points wide on a 440-point phone. It also slid under the readout in the opposite corner, which a comment in the same file confidently described as impossible. Two rows now. |
| The tray opening with **no materials in it at all** | The tray is taller than what is left of the screen, so something must shrink. A `ScrollView` with only a `maxHeight` has no height of its own, so it was the only thing that could give — and it gave all of it, silently, with everything above it looking right. A **minimum** height is what fixes this; a maximum alone permits nought. |
| "Heaviness" drawn on top of "Temperatures in" | `LabFlow` measured its rows against the width it was *offered* and reported the width it had *used*, which is narrower. It was then placed in that narrower box, so it wrapped a row the height had no room for. Measure and place must use one width. |
| A whole settings panel where dragging a slider changed the number not at all | **The big one.** Both models are `@Observable`, but every setting is a *computed* property forwarding to the engine — and Observation only watches stored properties. So reading one registered nothing and writing one notified nobody. The panel drew once and never again; the knobs stayed where a finger left them because nothing redrew them either. Fixed with one stored counter per model that every forwarding property reads and bumps. **Anything added that forwards to the engine must do the same.** |
| Blur still present with the glass setting on Flat | iOS 26 fades the edge of anything that scrolls behind a pane of its own. Apple's glass, in a place the app never put any. `labScrollEdges(_:)` asks for a hard edge below the top setting. |
| The particle field "shitting itself" at 200,000 bodies | Collisions cost about a millisecond per thousand bodies — 210ms against 0.85ms with them off, a factor of 250 — from a switch that was on by default and said nothing. Not an implementation fault; see `SwarmCost`. The field was also the one engine with **no benchmark at all**, which is why nobody noticed. |
| The four events appearing to do nothing | They worked perfectly, behind the panel that started them. A meteor falls before it detonates and all of that happened under the sheet. It closes first now, and switches to the powder chamber. |
| Undo lit up only by accident, and Redo never | `undo`, `redo` and every place that recorded an undo point changed the engine without bumping the revision count, in both chambers. The same rule as the settings panel, missed in a second place. |
| Turning on "move to music" | The microphone callback was written inside a main-thread class, so Swift 6 treated it as main-thread code and stopped the app when the audio thread called it. Made in a `nonisolated` function now. |
| A zoomed-out field drawn as a small square in the middle | The shader scaled by the zoom while the processor scaled by the picture's scale, which differ once zooming out adds room. |
| "20°C" directly beneath the same panel's own switch set to °F | The unit was written into the slider's format string. A setting the app contradicts on the next line. |

### Arrangements — what changed in the particle chamber, and why

The owner's report was that many of the presets were poor or broken, that nothing showed which one was
chosen, that the size slider only worked on presets, and that bodies added to a preset ignored it. All
four were true, and they had causes worth recording:

- **Presets inherited the previous preset's world.** Most set gravity downward and nothing else, so the
  same chip behaved differently depending on what was tapped before it. Every scene now sets its whole
  world through `beginScene` (gravity both ways, collisions, wind, a paused timeline) — see
  `ParticleArrangement.swift`, and the test that loads every scene after the fire and compares.
- **The crowd could not hold a shape or orbit anything.** Twelve of the pattern scenes live in the crowd,
  which had no per-body behaviour, so a sunflower, a mandala or a word slid to the floor within a second.
  The crowd now carries a role per body — `orbits` (keeps its speed, as orbiting object bodies do) and
  `holds` (drawn back to a place on a turning circle, which covers still shapes, spinning ones, a
  tornado's side-on swing and an aurora's ripple). Black holes and repulsors now act on the crowd too.
- **Two scenes were events that happened once.** Lightning and fireworks now keep going
  (`stepArrangement`), and their bodies fade as they expire rather than blinking out.
- **Adding bodies can join the arrangement** (`ParticleJoining.swift`): into orbit round the holes, as
  copies of what the crowd is doing, as copies of the object bodies (capped at 8,000 — that list is the
  expensive one), or for a cloth or rope, another one. A switch in the tray turns it off.
- **The size slider did not reach the crowd**, which was drawn one pixel wide whatever it said, and every
  object body was drawn the same size. Now each object body is drawn at its own radius times the slider,
  and the crowd at the slider's width.
- The arrangement showing is remembered by the engine — saved, undone, cleared — so its chip stays lit.

## Things that will waste your time otherwise

- **`/tmp` does not persist between shell calls.** Download, extract and read in one
  command, or use a directory inside the workspace.
- **`node` is not on the PATH by default.** Prefix with
  `export PATH="$HOME/.nvm/versions/node/v22.23.2/bin:$PATH"`.
- **`gh run list` fails** in this sandbox (it resolves the wrong host). Use
  `gh api repos/{owner}/{repo}/actions/runs` instead. Same for anything under `gh pr`
  and `gh issue` — they are GraphQL-backed and always fail here; `gh api` works.
- **The app layer cannot be compiled locally.** There is no Mac and no iOS SDK. CI is the
  only compiler for anything under `native/App/`, so expect to iterate through pushes.
  The engine under `native/Sources/` does build and test locally — use that.
- **Swift's `rounded()` is not JavaScript's `Math.round`** for negative halves. Use
  `JS.round`. This produced four apparent physics failures that were identical to the
  last bit.
- **`#expect` cannot call a mutating method or a key-path `allSatisfy` inline.** Compute
  into a `let` first.
- **A parameterised test prints its argument in the test name.** Conform the argument to
  `CustomTestStringConvertible` or one failure buries the log in hundreds of kilobytes.
- **`#expect(condition, message)` needs a literal message.** A plain `String` variable does
  not compile — interpolate it: `"\(message)"`.
- **`#require` cannot be nested inside another `#require`.** Compute into a `let` first.
- **The releases list from `gh api` is not in date order.** Sort by `created_at` yourself, or
  you will look at a build from hours ago and conclude nothing shipped.
- **For a failed CI build:** `gh api repos/{owner}/{repo}/actions/runs/{id}/jobs` to find the
  failing job, then `gh api repos/{owner}/{repo}/actions/jobs/{id}/logs`. `gh run view
  --log-failed` cannot resolve the repository here.
- **Fixtures are committed and regenerated occasionally**, so their size compounds in the
  history. Record sparsely — only what differs from the default.

---

## Decisions worth not relitigating

- **`CrucibleCore` imports nothing at all** — not Metal, not SwiftUI, not Foundation, not
  even the C maths library. That is what lets the physics be tested on any machine, and
  it is why the renderer lives in the engine and only the drawing is in Metal.
- **The engine carries its own trigonometry.** glibc, Darwin and V8 all disagree in the
  last bit, differences compound in an orbit, and physics verified on one machine would
  otherwise not be the physics that ships. `pow` cannot match V8 exactly — V8 uses a more
  accurate one — which is established, harmless and documented in `FDLibm.swift`.
- **`Double` throughout the physics**, because JavaScript numbers are doubles. `Float`
  storage for temperature and pressure, matching the reference's arrays.
- **The swarm draws from the engine's random stream**, not one of its own, so the whole
  field replays from a single seed.
- **Each stage of the swarm's update rounds to single precision**, because its buffers
  are single precision and the stored velocity is the velocity.
- **Applying a scene records no undo point** — that is the caller's business. The
  reference bundled the two, so clearing the world and recording an undo step could not
  be had separately.
- **Unsigned `.ipa`, no entitlements, no app extensions, no dynamic frameworks.** Each of
  those needs a matching provisioning profile, and each is a way for signing on the
  device to fail.
- **`macos-26` pinned in CI, not `macos-latest`**, which lags a release behind and would
  quietly rule out the current SDK.

---

## The user

- Has only an iPhone 17 Pro Max. No Mac, no PC. Installs by signing the `.ipa` on the
  device with E-Sign.
- **Does not read code.** Explain in plain English, no snippets, no jargon.
- Wants everything committed and pushed **straight to `main`**. No branches, no pull
  requests.
- Wants haptics throughout, with a switch in Settings to turn them off. Everything that buzzes goes
  through `App/Audio/Haptics.swift`, which checks the switch.
- Does not want incremental builds to test — work until a thing is actually finished.
- Treats output from other AI tools as suspect: if it is wrong, say so and say why.
- Has asked for the interface to match the web version's look, in Liquid Glass, **with
  the glass adjustable all the way down to flat** — both as a matter of taste and because
  every blurred panel costs frame time the simulation needs.
