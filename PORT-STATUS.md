# Port status

The working state of the native port, written so that anyone picking this up — including
me after a break — can find their footing without re-deriving it. Kept current as the
port progresses.

For *why* the project is arranged this way, read [README.md](README.md) and
[native/README.md](native/README.md) first. This file is the map, not the argument.

---

## The one idea everything rests on

The web implementation is the **specification**, not a rough draft. Nobody ever wrote
down how this simulation behaves — it is the accumulated result of thousands of small
tuning decisions — so the only way to carry it into Swift intact is to run the same world
in both and compare **every cell and every body**, including how many random numbers each
engine consumed.

Two rules follow, and breaking either loses the whole method:

1. **Fixes go into both engines at once.** The golden comparison still passing afterwards
   is what proves the two fixes are equivalent. A fix applied to one side only is
   indistinguishable from a porting bug.
2. **Never regenerate a fixture to make a test pass.** Regenerate only when a change to
   behaviour was intended, and then check that the native side shows the *same* diff.

This has found about eighty real bugs so far. It works because it cannot be fooled.

---

## What is done

| Area | State | Verified by |
| ---- | ----- | ----------- |
| Elements, registry, packed physics table | complete | property-by-property against extracted web data |
| Powder grid: movement, heat, pressure, phase change, chemistry, explosions, electricity, brush | complete | 38 scenarios, cell-for-cell + temperature + momentum + draw counts |
| Particle field: model, swarm, forces, integration, boundaries, springs, flock, all 20 spawners | complete | 39 scenarios, every body + springs + swarm + draw counts |
| Own sine, cosine, powers | complete | several thousand recorded values, bit-exact |
| Saving, loading, undo, multiplayer wire format | complete | round trips + wire payload byte-identical across 38 scenarios |
| Health inspection and repair tools, both chambers | complete | 25 behavioural tests |
| All 13 built-in powder scenes | complete | 52 scene/size combinations, cell-for-cell |
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
| CI: engine on Linux + macOS, unsigned `.ipa` as a release asset | complete | green |

**361 engine tests. 135 reference tests. 93 script tests.** Green on Linux and macOS, in
debug and optimised builds.

**The local port is complete.** Everything the web version does without a network, the app now
does. What is left is the online half, and that needs a decision rather than more porting —
see below.

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

### 3. Online — in progress

All of it is wanted; the owner has confirmed that. The plan, the findings behind it and the hosting
problem that has to be fixed before the workshop can be announced to anyone all live in
**[ONLINE-PLAN.md](ONLINE-PLAN.md)**. Read that first — several of its findings took a while to
establish and would otherwise be rediscovered the hard way.

The short version:

- **The shared room** uses iOS's own phone-to-phone networking, not WebRTC. WebRTC would mean an
  embedded framework, and an embedded framework means another provisioning profile for on-device
  signing to fail on. The protocol is done and tested; the transport is next.
- **Cloud saves and the workshop** need ordinary HTTP routes on the web side, because the existing
  ones are RPC with no URLs to call. Two things make it much easier than expected: bearer-token
  authentication already works, and the same-site guard already permits a non-browser client
  deliberately.
- **Hosting needs attention.** The database falls back to an embedded throwaway one when
  `DATABASE_URL` is unset, by design — so cloud saves would appear to work and then vanish. That has
  to be set before anyone is invited in.

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
  Sources/CrucibleBench/     performance measurement; prints in CI on every run
  Tests/CrucibleCoreTests/   the comparisons, plus Fixtures/
  App/
    Design/                  Palette, Glass
    Metal/                   GridView + GridShaders (powder), FieldView + FieldShaders
    Simulation/              SimulationModel (powder), ParticleFieldModel
    Views/                   ContentView, surfaces, docks, settings, debug readouts
web/                         the reference implementation and the fixture generators
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
- Does not want incremental builds to test — work until a thing is actually finished.
- Treats output from other AI tools as suspect: if it is wrong, say so and say why.
- Has asked for the interface to match the web version's look, in Liquid Glass, **with
  the glass adjustable all the way down to flat** — both as a matter of taste and because
  every blurred panel costs frame time the simulation needs.
