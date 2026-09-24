# Crucible — native iOS app

The shipping app. 100% native: Swift, Metal, SwiftUI. No WebKit, no HTML, no
JavaScript, no web view of any kind.

The [web implementation](../web/README.md) is kept as the reference the physics
here is verified against. Nothing from it ships.

## Layout

```
native/
  Package.swift              Swift package: the CrucibleCore library and the benchmark
  Sources/CrucibleCore/      The simulation engine. Platform-independent.
    Support/                 Random generator, colour packing, JavaScript numeric semantics
    Elements/                Element model, the 50 built-ins, registry, packed physics table
    Powder/                  The cellular-automata grid: state, tick order, movement
  Sources/CrucibleBench/     Performance measurement (`swift run -c release crucible-bench`)
  Tests/CrucibleCoreTests/   The behavioural oracle, translated from the web suite
    Fixtures/                Data and golden output extracted from the web engine
  App/                       iOS app: Metal renderer, SwiftUI shell, shaders
  project.yml                Recipe the Xcode project is generated from
```

## The two-layer split, and why it matters

**`Sources/CrucibleCore` imports no Apple frameworks.** Not Metal, not SwiftUI,
not UIKit, not CoreMotion, not even Foundation. It is standard-library Swift plus
the platform's C maths library, which is needed only because Swift's standard
library has square roots but no powers or trigonometry.

That constraint is load-bearing, for two reasons.

**It makes the physics testable without Apple hardware.** The engine compiles and
its full test suite runs on Linux, which is where this port is being developed.
Bugs in sand behavior get caught in seconds, on the spot, rather than at the end
of a cloud build.

**It keeps the engine honest.** Anything needing a screen, a sensor or a GPU has
to live in `App/`. The engine cannot quietly grow a dependency on being drawn,
which is what keeps it fast, portable and testable as the project grows.

## Running the tests

```bash
cd native
swift test                 # debug
swift test -c release      # optimized, same results expected
```

No Xcode, no Mac, no simulator required. The iOS app layer on top of the engine
is compiled in CI.

## The fidelity strategy

A falling-sand simulation has no "correct" output you can derive from first
principles — its behavior is whatever thousands of small tuning decisions
accumulated into. Re-deriving that by eye would lose it.

So the web implementation's test suite is treated as the specification. It is
deterministic: it seeds the random generator, so the same start state always
produces the same world. Those tests are translated here, and when the native
engine and those tests disagree, **the native engine is wrong**.

That only works if both implementations draw the same random numbers in the same
order. Hence `Mulberry32`, which is a bit-for-bit port of the web generator,
verified against values captured from the real JavaScript function rather than
assumed. Its test suite checks the raw 32-bit stream, the derived doubles, the
distribution, and each helper against the JavaScript idiom it replaces.

**The fidelity contract when porting:** match the helper to the JavaScript idiom
rather than rewriting the arithmetic. How many random draws a piece of code
consumes, and in what order, is part of its observable behavior — change that and
everything downstream diverges even though the logic looks equivalent.

### Golden scenarios

Beyond translating the test suite, whole worlds are run in both engines and
compared cell by cell. `Tests/CrucibleCoreTests/Fixtures/web-powder-golden.json`
holds **31 scenarios** produced by the web engine, and the native engine must
reproduce, for every one of them:

- every cell's element,
- every cell's temperature,
- every cell's momentum,
- the occupied-cell count and the world fingerprint,
- **and the exact number of random numbers consumed** — up to 141,431 draws in the
  heaviest scenario.

That last check is the one that catches subtle errors. Two implementations can
produce an identical picture while consuming a different number of draws, which
means they reach their decisions at different points in the stream and will
disagree on some other world later. Matching both proves the ported logic takes
the same branches in the same order.

The scenarios deliberately include the cases most likely to expose a divergence:
explosions and chain reactions (the heaviest users of randomness, with the most
intricate draw order), lightning seeking water along a wire, and the two lava-and-
water regression cases run for 400 and 700 ticks.

### Bugs found by comparing the two engines, and fixed in both

Comparing the two implementations this closely surfaced a long list of genuine
faults in the original. Every one was fixed **on both sides at once**, and the
golden comparison still passing is itself the proof that the two fixes are
equivalent — that is what makes this safe to do at all.

**Containment failures.** A laser passed straight through bedrock, because the
beam loop did not stop when it hit an obstacle and simply tested the next cell
along — behind the wall. Liquids tunnelled through one-cell-thick walls, because
sideways levelling reached two cells without checking the first, which drained
sealed tanks. Explosion embers overwrote bedrock even though the blast wave that
threw them explicitly could not. A fan blew through solid walls, because stone
matched neither branch of its loop, so the airflow neither moved it nor stopped.

**Wrong element identifiers.** The crater of an explosion was filled with C4
explosive while the comment claimed plasma, so every large blast seeded live
charge at its own centre and explosions chained off their own debris. The
"extinguish fires" repair deleted every Portal B in the world, having tested for
id 23 while its comment said Spark — which is 16 — so sparks were left burning
and portals silently vanished. The same action turned explosives into water at
250°C, above boiling, so making a bomb safe produced a steam burst. "Neutralise
acids" turned acid into wood. Tree canopies in the forest recipe were built from
ants, which eat wood and plants, so the forest devoured its own trunks seconds
after loading.

**Edge arithmetic.** Three separate places computed a neighbour as a raw index and
then range-checked it, which at the left and right walls silently lands on the
adjacent row: liquid cohesion, the sealed-pocket wall count that decides whether
gas detonates, and the corrupt-cell test injector.

**Heat.** Conduction did not conserve heat despite a comment saying it did — the
centre cell gained an amount while its four neighbours gave up only six tenths of
it, so every pass destroyed heat around hot cells and invented it around cold
ones. It also always sampled the same fixed lattice, and since the neighbours of a
sampled cell were never themselves sampled, heat flowed one way out of that
lattice and pooled where nothing could redistribute it, leaving a permanent
checkerboard. The lattice now shifts each pass.

**Runaway state.** A spark re-stamped its own lifetime every tick on contact with
anything liquid. Against mercury — which is never consumed — that made it
immortal *and* made it seed a fresh spark every tick, forever.

**Dead declarations.** `ignitionTemp`, `spawnElementId` and `tempChange` were all
declared, documented, and read by nothing. Nothing in the world could catch fire
from heat alone; a custom reaction could not release heat or produce a third
element. All three now work. `burnRate` remains deliberately unimplemented — the
registry's own values contradict the descriptions (coal is described as burning
slowly but carries a higher rate than wood), so implementing it would mean
inventing semantics rather than restoring them.

**Missing phase change.** The engine documented freezing as one of its phase
changes but never implemented it: ice melted the instant it rose above zero while
a pond chilled to minus fifty stayed liquid forever. Fresh water now freezes. Salt
water deliberately does not, because salt lowers the freezing point.

**Name-based dispatch.** Beam physics was granted to any element whose *name*
contained "Laser". Custom elements are loaded from storage without validation, so
that was a way to inherit arbitrary physics by spelling. Behaviour now comes from
state alone.

**Silent corruption.** Resizing assigned the new dimensions and then allocated
eight buffers one at a time, so a failure part-way through left the engine
claiming a size it did not have — and because typed arrays ignore out-of-range
writes, every later write vanished and the world was permanently broken with
nothing reported. Untrusted dimensions reached it straight from scene files and
multiplayer payloads. The compact multiplayer payload wrote element ids over the
existing grid without clearing it, so every cell kept the *previous* world's
temperature, lifetime and momentum under a new layout. Scene loading bypassed the
wind clamp that every other caller must respect, and accepted raw values that
could sit in the grid as permanent corruption.

**Smaller things.** Undo cleared the redo stack last rather than first, so a failed
snapshot left a redo entry describing a future that never happened. A brush target
was ignored unless the shape was "replace". Bulk spawning was unclamped. A
malformed colour rendered as black rather than the intended white marker. Oxygen
and helium were listed as explosive but carry no flammability, so those branches
were unreachable. Plant growth was the only spread rule with no probability gate,
so a pond beside a plant filled instantly. The world fingerprint used for desync
detection ignored vertical gravity entirely. The memory report was three times too
low. The auto-repair pass printed step numbers that lied. The out-of-bounds purge
skipped the left and right columns and counted empty air as work done. Loading a
recipe was not undoable and silently discarded the user's world.

### The particle field was audited and repaired before being ported

The same audit was run over the particle half, and it was fixed **in the reference
first** — so the port copies correct behaviour instead of faithfully reproducing
faults and then having to undo them. Thirty-plus bugs, each with a regression test
(`web/src/sim/__tests__/particle.test.ts`, now 71 tests).

The worst was structural. **Springs store absolute positions in the particle list,
and six separate code paths removed or shifted particles without updating them** —
the two expiry filters, the corrupt-particle purge, the eviction when the cap is
reached, the multiplayer rebuild, and lowering the particle limit. The spring code
could only notice an index pointing off the end of the list, never one pointing at
the *wrong* particle, so every spring below a removal silently re-attached to a
different pair whose rest length no longer matched. Cloth sheared, and the mismatch
fed energy in on every frame afterwards. All removals now go through one function
that remaps the endpoints and drops springs whose ends are gone.

The most far-reaching was a misfiring force. A restoring spring meant for one
preset was applied to anything that "has an origin, ignores gravity and carries a
charge" — and because an unspecified charge defaults to a random plus or minus one,
that description also fitted seven orbital presets. The galaxy, black hole, double
vortex, repulsor, solar flare, synchrotron and DNA helix were all being pulled
toward the centre about ten times harder than the orbital physics they were built
around, quietly crushing them inward.

Others worth naming: the speed limit only ever applied to orbital particles, so
every ordinary particle was uncapped despite one global slider — which is also what
let particles outrun the wrapping boundary and escape the world permanently.
Recycled particles could freeze in place forever, still drawn and still counted.
Pinned objects were shoved around by the boundary. Flocking separation got *weaker*
the closer two particles came, which is backwards. Springs ignored mass, and a
spring with no rest length was disabled entirely. Undo captured only the particles,
so undoing a clear returned loose beads with no structure and an empty swarm. The
million-particle swarm ignored the world's speed limit and boundary mode, and every
mouse mode except one was mapped onto "push away". And the repair action for
excessive velocity turned an infinite velocity into a not-a-number one — it
manufactured the corruption it exists to remove, then reported success, because
every stage of the pass read a single snapshot taken before any repair ran.

Two of the existing tests turned out to be wrong rather than the code. One placed
its probe exactly on the right-hand wall, so it measured a wall bounce flipping the
sign of the force it claimed to test, and passed only when a random draw happened
to exceed the pull — about one time in twenty.

### Where the JavaScript and Swift genuinely differ

Three things do not translate directly, and each one is a silent behavior change
rather than a compile error. They are handled in `Support/JSMath.swift`:

- JavaScript rounds a half **upward**; Swift rounds a half **away from zero**. The
  two disagree on every negative half, and the momentum code rounds negative
  positions constantly.
- Storing out-of-range numbers into JavaScript's narrow typed arrays **wraps**;
  Swift's initialisers **trap**. The momentum code legitimately produces
  out-of-range velocities.
- The web grid keeps temperature and pressure as **32-bit floats**, so every store
  rounds. The native grid does the same deliberately. Holding them at double
  precision would let values drift, and the chemistry has hard thresholds — 700°C
  decides whether lava becomes obsidian — so drift eventually flips real decisions.

## Performance approach

The two chambers get different treatment, because they have different shapes.

**The powder grid runs on the CPU, across cores.** Its update walks cells in a
specific order — bottom row upward, alternating left-to-right and right-to-left
each row to cancel sideways drift — and marks each cell as already-moved so
nothing moves twice per tick. That ordering is not an implementation detail; it
*is* how the sand feels. Handing it to the GPU means thousands of cells deciding
simultaneously with no turn-taking, so two grains both claim the same empty space
and grains merge or clone. Reproducing correct behavior on a GPU requires a
fundamentally different algorithm and a visibly different result. Rewritten in
Swift over raw memory instead of a single JavaScript thread, the sequential
version is expected to be dramatically faster anyway — and the ordering survives
intact.

**The particle field runs on the GPU via Metal compute.** This one is genuinely
parallel: independent bodies, no turn-taking required. The web version already
has working GPU compute kernels for it, which serve as a written reference to
translate into Metal Shading Language.

**Both are drawn by Metal**, which is where the bulk of the rendering win is
regardless of where the physics runs.

### Measured so far

Numbers come from `swift run -c release crucible-bench`, not from estimates. These
were taken on the Linux development machine, **single-threaded**, with no
multi-core work done yet — they are a floor and a regression baseline, not a
prediction of phone performance. Each grid is 30% full of a mix of sand, water,
stone and smoke, with the full chemistry running.

| Grid                              | Cells     | ms per tick | Ticks/sec |
| --------------------------------- | --------- | ----------- | --------- |
| 200 × 430 (web's "Fast" quality)  | 86,000    | 3.5         | 285       |
| 420 × 910 (web's "Native" quality)| 382,200   | 15.2        | 66        |
| 1206 × 2622 (one cell per pixel)  | 3,162,132 | 129.4       | 8         |

For context, the web version targets **30 frames per second** at roughly the first
of those sizes. So the straight single-threaded rewrite already has a wide margin
there, clears 60 at the middle size, and one-cell-per-pixel is the case that needs
the planned multi-core work.

Cost tracks occupied cells, so a sparsely filled world is much cheaper than these
figures suggest. The real targets get re-measured on the device once the app shell
exists.

## Element property defaults

Most element properties are optional in the web implementation, with a fallback
applied at each place they are read (`def.viscosity || 1`, `def.decayTicks || 0`,
and so on). Those fallbacks were collected and are applied exactly once here, at
construction, so the physics reads non-optional values. Two stay optional because
"absent" means something no number could express:

| Property       | `nil` means                                          |
| -------------- | ---------------------------------------------------- |
| `ignitionTemp` | never self-ignites (not: ignites at zero degrees)    |
| `defaultTemp`  | placed at the world's current ambient temperature    |

`gravityFactor` is the one numeric property where an explicit zero is meaningful
— it means suspended in place — so it defaults to one only when genuinely absent.

## Distribution

The app is built by GitHub Actions on a rented Mac runner and published as an
unsigned `.ipa` attached to a release, for signing on-device with E-Sign. It
deliberately uses no capability that needs special provisioning (no push
notifications, no iCloud, no app groups) and ships as a single binary with no
app extensions or dynamic frameworks, so re-signing stays trouble-free.
