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

### Quirks reproduced rather than corrected

Comparing the two engines this closely surfaced behaviour in the original that
looks unintended. It is reproduced faithfully, because a one-sided "fix" would
break the cell-for-cell agreement that makes the whole verification meaningful.
Recorded here so each can be decided on deliberately:

- **Explosion embers can overwrite bedrock.** The blast wave itself has an explicit
  bedrock exemption and honours it completely, but the ember phase that follows
  does not check what it lands on. Bedrock is documented as indestructible.
- **The crater core places C4 explosive.** The code comment says plasma, but the
  identifier used is C4. So a large blast seeds unexploded charge at its centre,
  which is part of how explosions currently chain.
- **Explosion debris is thermite.** Another case where the comment says sparks and
  the identifier says something else. This one at least produces plausible
  behaviour — hot incendiary debris.
- **A liquid at the grid edge sees a wrapped neighbour.** The cohesion rule computes
  neighbour indices without bounds checking and then filters by range, so at the
  left and right walls one index lands on the adjacent row. This affects how
  liquids behave against the walls.
- **A target element is ignored unless the brush shape is "replace".** Passing one
  with a circle or square shape silently paints over everything.

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
