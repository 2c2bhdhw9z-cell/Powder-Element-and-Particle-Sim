# Crucible — native iOS app

The shipping app. 100% native: Swift, Metal, SwiftUI. No WebKit, no HTML, no
JavaScript, no web view of any kind.

The [web implementation](../web/README.md) is kept as the reference the physics
here is verified against. Nothing from it ships.

## Layout

```
native/
  Package.swift              Swift package defining the CrucibleCore library
  Sources/CrucibleCore/      The simulation engine. Platform-independent.
    Support/                 Random generator, color packing
    Elements/                Element model and registry
  Tests/CrucibleCoreTests/   The behavioral oracle, translated from the web suite
  App/                       iOS app: Metal renderer, SwiftUI shell, shaders
  project.yml                Recipe the Xcode project is generated from
```

## The two-layer split, and why it matters

**`Sources/CrucibleCore` imports no Apple frameworks.** Not Metal, not SwiftUI,
not UIKit, not CoreMotion — not even Foundation. It is standard-library Swift and
nothing else.

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

Numbers will be measured and reported rather than assumed.

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
