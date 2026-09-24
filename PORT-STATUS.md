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
| iOS app: Metal, both chambers, glass dial, docks, settings | first pass | builds in CI, installs, runs |
| CI: engine on Linux + macOS, unsigned `.ipa` as a release asset | complete | green |

**234 engine tests. 127 reference tests. 93 script tests.** Green on Linux and macOS, in
debug and optimised builds.

---

## What is left

Roughly in the order it should be done.

### 1. Tick optimisation — in progress

The goal is one cell per screen pixel: 3.1 million cells. Currently **124 ms a tick**
against an 8.3 ms budget.

**Decision on record: do not spread the tick across processor cores.** The sand's whole
character comes from a strict processing order — bottom row first, horizontal direction
alternating per row and per tick, each cell moving at most once. Reordering that changes
how the sand behaves, and would forfeit the cell-for-cell verification. Two provably
identical savings first:

- The tick walks the whole grid **a second time** just to locate portals, which almost no
  world contains. Keep a count of portal-B cells and skip the pass when it is zero.
- The tick walks rows that are **entirely empty**. In a settled world that is most of
  them. Keep a per-row count of occupied cells and skip a row whose count is zero —
  provably identical, because processing an empty cell already does nothing.

Both need an occupancy count maintained at every site that writes `type[…]`. Missing a
site makes the counts drift and rows get wrongly skipped, which the golden comparison
will catch loudly — so the refactor is safe to attempt.

If that is not enough, come back to the user before changing how the sand behaves.

### 2. App features still missing

- Tilt to tip gravity (`web/src/sim/gyro.ts`) — engine side already supports it via
  `gravityX` and `jostle`.
- Element editor and custom elements. The registry already supports ids 50–99 and
  round-trips them; there is no interface.
- Save, load and autosave in the app. Engine side complete (`PowderSerialization.swift`,
  `ParticleSerialization.swift`); no file picker, no autosave timer.
- Diagnostics panel. Engine side complete; nothing shows it.
- Encyclopedia and periodic table (`web/src/sim/encyclopedia.ts`, `periodic.ts`).
- Sound (`web/src/sim/audio-engine.ts`).
- Screen recording (`web/src/sim/canvas-recorder.ts`).
- Real fonts. Syne and IBM Plex are currently system stand-ins; see `Font.labDisplay`.
- Particle trails and the touch-reach ring are not drawn yet.

### 3. Online

Accounts, cloud saves, the workshop, multiplayer. Needs a hosting decision from the user.
Note that the deployed web app already *is* a server — TanStack Start, Postgres and
authentication — so the sensible move is to keep it and point the app at it rather than
build a second one.

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
