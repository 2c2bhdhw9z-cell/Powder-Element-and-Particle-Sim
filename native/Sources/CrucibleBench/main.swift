import CrucibleCore
// Foundation is used here only for number formatting. The engine itself
// deliberately imports nothing; this is a developer tool, not shipped code.
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

// Measures how fast the powder grid actually simulates.
//
// Performance claims about this port need to come from measurement. The numbers
// this prints on a development machine are not the numbers a phone will produce —
// they are a floor for tracking regressions and a rough sense of where the
// headroom is. Run it on the device once the app shell exists.
//
//   swift run -c release crucible-bench
//
// Always with `-c release`. A debug build of this kind of tight pointer loop can
// be an order of magnitude slower and tells you nothing useful.

/// Wall-clock seconds, monotonic.
func now() -> Double {
    var time = timespec()
    clock_gettime(CLOCK_MONOTONIC, &time)
    return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
}

struct Case {
    var label: String
    var width: Int
    var height: Int
    /// Fraction of the grid to fill before timing.
    var fill: Double
    var steps: Int
}

/// Fills a fraction of the grid with a mix that keeps every movement path busy:
/// granular solids that pile, liquids that level out, and a gas that rises.
func populate(_ engine: PowderEngine, fill: Double) {
    var rng = Mulberry32(seed: 20_260_923)
    let target = Int(Double(engine.cellCount) * fill)
    var placed = 0
    var guardCount = 0
    let guardLimit = target * 8

    while placed < target && guardCount < guardLimit {
        guardCount += 1
        let x = rng.int(below: engine.width)
        let y = rng.int(below: engine.height)
        guard engine.typeAt(x, y) == Element.empty else { continue }

        let roll = rng.next()
        let element: ElementID
        if roll < 0.55 {
            element = Element.sand
        } else if roll < 0.85 {
            element = Element.water
        } else if roll < 0.95 {
            element = Element.stone
        } else {
            element = Element.smoke
        }
        engine.setElement(x, y, element)
        placed += 1
    }

    // A floor, so material settles instead of vanishing off the bottom.
    for x in 0 ..< engine.width {
        engine.setElement(x, engine.height - 1, Element.bedrock)
    }
}

let cases: [Case] = [
    // Roughly what the web version runs at today on a phone-sized viewport with
    // the quality set to "Fast".
    Case(label: "web-equivalent  (200x430)", width: 200, height: 430, fill: 0.30, steps: 120),
    // The web version's "Native" quality on an iPhone 17 Pro Max viewport.
    Case(label: "native quality  (420x910)", width: 420, height: 910, fill: 0.30, steps: 120),
    // One cell per physical pixel on that display. The stretch target.
    Case(label: "one cell/pixel (1206x2622)", width: 1206, height: 2622, fill: 0.30, steps: 40),
]

print("Crucible powder benchmark")
print("30% fill: sand, water, stone and smoke, on a bedrock floor.")
print("")
print("  grid                        cells     ms/tick   ticks/sec   60fps?  120fps?")
print("  ------------------------------------------------------------------------------")

for testCase in cases {
    let engine = PowderEngine(width: testCase.width, height: testCase.height, seed: 99)
    populate(engine, fill: testCase.fill)

    // Warm up: let the material settle and the caches fill, so the timed run
    // measures steady state rather than the initial collapse.
    for _ in 0 ..< 20 { engine.step() }

    let started = now()
    for _ in 0 ..< testCase.steps { engine.step() }
    let elapsed = now() - started

    let msPerTick = elapsed / Double(testCase.steps) * 1000
    let ticksPerSecond = Double(testCase.steps) / elapsed
    let cells = testCase.width * testCase.height

    func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
    func headroom(_ budgetMs: Double) -> String {
        msPerTick <= budgetMs ? "yes" : "no"
    }

    let label = pad(testCase.label, 27)
    let cellText = pad(String(cells), 9)
    let msText = String(format: "%8.3f", msPerTick)
    let rateText = String(format: "%9.1f", ticksPerSecond)

    print("  \(label) \(cellText) \(msText)   \(rateText)     \(pad(headroom(16.67), 7))\(headroom(8.33))")
}

print("")
print("A 60fps budget is 16.67ms per frame and 120fps is 8.33ms, and the")
print("simulation does not get all of it — drawing and the interface need a share.")

// MARK: - Where the time actually goes
//
// Separating the cost that scales with the number of cells from the cost that scales with
// the number of *occupied* cells, because they lead to completely different conclusions.
//
// Several stages sweep the whole grid no matter what is in it: locating portals, spreading
// heat, and rebuilding the pressure field. Everything else — decay, phase change,
// chemistry, movement — only happens where there is something to do.
//
// Measured rather than reasoned about: running the same grid at several fills and reading
// the slope gives both figures without having to instrument the engine, and without the
// measurement itself changing what is being measured.

print("")
print("Where the time goes, at one cell per pixel (1206x2622):")
print("")
print("  fill      ms/tick     occupied cells")
print("  ---------------------------------------")

let breakdownWidth = 1206
let breakdownHeight = 2622
let breakdownCells = Double(breakdownWidth * breakdownHeight)
var samples: [(fill: Double, ms: Double)] = []

for fill in [0.0, 0.15, 0.30, 0.60] {
    let engine = PowderEngine(width: breakdownWidth, height: breakdownHeight, seed: 99)
    populate(engine, fill: fill)
    for _ in 0 ..< 10 { engine.step() }

    let started = now()
    let steps = 12
    for _ in 0 ..< steps { engine.step() }
    let ms = (now() - started) / Double(steps) * 1000
    samples.append((fill, ms))

    let occupied = engine.activeParticleCount
    print(String(format: "  %4.0f%%   %8.3f     %d", fill * 100, ms, occupied))
}

if let empty = samples.first, let full = samples.last, full.fill > empty.fill {
    // The intercept is the sweep over every cell; the slope is the work per occupied cell.
    let perOccupiedCellNs = (full.ms - empty.ms) * 1_000_000
        / (breakdownCells * (full.fill - empty.fill))
    print("")
    print(String(format: "  Sweeping every cell, whatever is in it:  %.2f ms", empty.ms))
    print(String(format: "  Each occupied cell, on top of that:      %.1f ns", perOccupiedCellNs))
    print("")
    print("  That split decides what is worth optimising. The whole-grid sweeps can be")
    print("  skipped or narrowed without changing any behaviour. The per-cell work is the")
    print("  physics itself, and the only way to make a lot of it happen at once is to")
    print("  process cells in a different order — which is precisely what gives falling")
    print("  sand its character, so it cannot be reordered without changing the result.")
}

// MARK: - Which sweep is the expensive one
//
// The figure above says the whole-grid sweeps cost more than a 120fps frame before a single
// grain exists, but not which of them. Measured by subtraction through the engine's own
// public switches, so nothing has to be instrumented and the measurement cannot perturb
// what it measures. On an empty grid the walk itself does almost nothing, which is what
// makes the remainder readable.
//
// Turning these off changes the simulation, obviously. That is acceptable in a benchmark
// and nowhere else.

print("")
print("Which sweep costs what, on an empty grid at one cell per pixel:")
print("")

func emptyGridMs(heat: Bool, pressure: Bool) -> Double {
    let engine = PowderEngine(width: breakdownWidth, height: breakdownHeight, seed: 99)
    engine.heatConductionEnabled = heat
    engine.pressureEnabled = pressure
    for _ in 0 ..< 10 { engine.step() }
    let started = now()
    let steps = 24
    for _ in 0 ..< steps { engine.step() }
    return (now() - started) / Double(steps) * 1000
}

let everything = emptyGridMs(heat: true, pressure: true)
let withoutHeat = emptyGridMs(heat: false, pressure: true)
let withoutPressure = emptyGridMs(heat: true, pressure: false)
let neither = emptyGridMs(heat: false, pressure: false)

print(String(format: "  everything on                     %8.3f ms", everything))
print(String(format: "  heat off                          %8.3f ms", withoutHeat))
print(String(format: "  pressure off                      %8.3f ms", withoutPressure))
print(String(format: "  both off (walk + visited clear)   %8.3f ms", neither))
print("")
print(String(format: "  so heat spreading costs about     %8.3f ms", everything - withoutHeat))
print(String(format: "  and the pressure field about      %8.3f ms", everything - withoutPressure))
print(String(format: "  and the bare walk about           %8.3f ms", neither))
print("")
print("  Heat and pressure both run on alternate ticks, so their true cost on the ticks")
print("  they run is twice what is shown. Both are averages over ticks, which is the")
print("  number that decides the frame rate.")

// MARK: - What an occupied cell actually spends its time on
//
// The per-occupied-cell figure is the one that limits how many cells the app can afford, and
// therefore the resolution it runs at. This breaks it down by what is in the cell, which
// separates the two candidate explanations:
//
//   - Stone never moves, never reacts and never changes phase. Whatever it costs is the
//     fixed overhead of visiting an occupied cell at all: the element lookup and the walk
//     through the stages that then decline to do anything.
//   - Sand, water and oil add their movement rules on top, and water and oil additionally
//     inspect their neighbours.
//
// If stone is nearly as expensive as water, the cost is overhead and the element lookup is
// the place to look. If stone is cheap, the cost is the movement rules themselves.
//
// Measured at a size that fits comfortably in cache pressure terms similar to the real app,
// so the figures transfer.

print("")
print("What an occupied cell costs, by what is in it (420x910 at 40% fill):")
print("")
print("  element     ms/tick    ns per occupied cell")
print("  ------------------------------------------------")

let perCellWidth = 420
let perCellHeight = 910
let perCellFill = 0.40

// The empty-grid cost at this size, subtracted off so the figure is the per-cell work rather
// than the per-cell work plus the sweeps.
let perCellBaseline: Double = {
    let engine = PowderEngine(width: perCellWidth, height: perCellHeight, seed: 99)
    for _ in 0 ..< 10 { engine.step() }
    let started = now()
    let steps = 40
    for _ in 0 ..< steps { engine.step() }
    return (now() - started) / Double(steps) * 1000
}()

// Deliberately all non-decaying, so the population does not shrink under the measurement
// and change what is being measured half way through.
let probes: [(name: String, id: ElementID)] = [
    ("stone", Element.stone),
    ("sand", Element.sand),
    ("water", Element.water),
    ("oil", Element.oil),
    ("acid", Element.acid),
]

for probe in probes {
    let engine = PowderEngine(width: perCellWidth, height: perCellHeight, seed: 99)
    var rng = Mulberry32(seed: 4242)
    let target = Int(Double(engine.cellCount) * perCellFill)
    var placed = 0
    var attempts = 0
    while placed < target && attempts < target * 8 {
        attempts += 1
        let x = rng.int(below: engine.width)
        let y = rng.int(below: engine.height)
        guard engine.typeAt(x, y) == Element.empty else { continue }
        engine.setElement(x, y, probe.id)
        placed += 1
    }
    for x in 0 ..< engine.width { engine.setElement(x, engine.height - 1, Element.bedrock) }

    for _ in 0 ..< 10 { engine.step() }
    let started = now()
    let steps = 40
    for _ in 0 ..< steps { engine.step() }
    let ms = (now() - started) / Double(steps) * 1000

    let occupied = engine.activeParticleCount
    let perCellNs = occupied > 0
        ? (ms - perCellBaseline) * 1_000_000 / Double(occupied)
        : 0
    let name = probe.name.count >= 10
        ? probe.name
        : probe.name + String(repeating: " ", count: 10 - probe.name.count)
    print("  \(name) " + String(format: "%8.3f    %8.1f", ms, perCellNs))
}

print("")
print(String(format: "  (empty grid at this size: %.3f ms, subtracted from each figure above)", perCellBaseline))
print("")
print("  Stone is the interesting row. It never moves, never reacts and never changes")
print("  phase, so its figure is the price of visiting an occupied cell and then doing")
print("  nothing — pure overhead, and a large share of what the others cost.")

// MARK: - Is the element lookup the overhead?
//
// The hypothesis worth testing before restructuring anything: the properties of an element
// are a hundred-byte record held in a Swift array, and the walk reads one per cell. If
// fetching that record is most of the overhead above, then the fix is to make the fetch
// cheap. If it is a small fraction, the overhead is elsewhere and the array is a red herring.
//
// Measured with the same access the engine uses, over the same number of cells, doing nothing
// else. Crude, but decisive either way.

print("")
print("How much of that overhead is just fetching the element's properties:")
print("")

let lookupEngine = PowderEngine(width: perCellWidth, height: perCellHeight, seed: 99)
populate(lookupEngine, fill: perCellFill)
let lookupCells = lookupEngine.cellCount
var lookupSink = 0.0

// Warmed, so the caches are in the same state the timed run will find them.
for _ in 0 ..< 5 {
    for i in 0 ..< lookupCells { lookupSink += lookupEngine.elements[lookupEngine.type[i]].density }
}

let lookupStarted = now()
let lookupRounds = 40
for _ in 0 ..< lookupRounds {
    for i in 0 ..< lookupCells { lookupSink += lookupEngine.elements[lookupEngine.type[i]].density }
}
let lookupMs = (now() - lookupStarted) / Double(lookupRounds) * 1000

// Printed so the compiler cannot decide the whole loop was pointless and remove it.
if lookupSink == .infinity { print("  (unreachable)") }

print(String(format: "  one lookup per cell, %d cells:  %.3f ms", lookupCells, lookupMs))
print(String(format: "  which is                        %.1f ns per cell", lookupMs * 1_000_000 / Double(lookupCells)))
print("")
print("  Compare that against the stone figure above. Stone's cost is one such lookup plus")
print("  the walk through the stages, so the gap between them is everything that is not")
print("  the lookup.")


// MARK: - The particle field, which had no figures at all until it needed them
//
// This section exists because its absence was the bug. The powder engine has been measured on every CI
// run since it was ported; the field never was, so nobody noticed that pushing bodies apart costs about
// a millisecond per thousand of them. The app happily offered a million.
//
// The gap between the two columns below is the whole story, and it is a factor of a couple of hundred.

print("")
print("Particle field — one moment, by crowd size:")
print("")
print("  bodies      pushing apart    not pushing apart")

for count in [25_000, 50_000, 100_000, 200_000, 500_000] {
    var figures: [Double] = []
    for collide in [true, false] {
        let field = ParticleEngine(width: 400, height: 700)
        _ = field.setMaxParticles(1_000_000)
        field.collisionsEnabled = collide
        var swarmRng = Mulberry32(seed: 1)
        field.swarm.spawn(
            count: count,
            width: 400,
            height: 700,
            color: 0xFFFF_FFFF,
            budget: 1_000_000,
            rng: &swarmRng
        )
        // Settled first, so the grid cells are as full as they get in practice. A crowd measured while
        // still evenly spread is measured at its easiest, which is not the case anybody meets.
        for _ in 0 ..< 10 { field.step() }

        let rounds = collide ? 8 : 40
        let started = now()
        for _ in 0 ..< rounds { field.step() }
        figures.append((now() - started) / Double(rounds) * 1000)
    }
    print(
        String(
            format: "  %-10@  %8.1f ms      %8.2f ms",
            count.formattedWithSeparators as NSString,
            figures[0],
            figures[1]
        )
    )
}

print("")
print("  The right-hand column is why the crowd is offered at all, and the left-hand one is why")
print("  `SwarmCost` exists. Two hundred thousand bodies pushing each other apart is five frames a")
print("  second; the same crowd with that switched off is under a millisecond.")
print("")
print("  Before assuming the pass is badly written: it is a uniform grid, nine neighbouring cells, and")
print("  at most eight candidates examined per cell. That is about seven nanoseconds per candidate,")
print("  which for reads scattered over a megabyte and a half is roughly what the memory can do.")
print("  Laying the bodies out in visiting order would help perhaps threefold — and would change the")
print("  order pairs are resolved in, which changes the simulation. It would still not be smooth.")


// MARK: - Repainting the swarm from a colour ramp
//
// A ramp driven by speed has to repaint every body every frame, because speed changes every frame. A
// ramp driven by a fixed position per body, or by where a body sits in a still world, does not. The
// engine tells those two cases apart and only repaints when it must — this is the measurement of what
// that distinction saves, and of whether the pass that does run is affordable at all.
//
// Measured on its own rather than as part of a moment, because a moment is dominated by the physics and
// a two-millisecond pass would disappear into the noise.

print("")
print("Repainting the swarm from a colour ramp:")
print("")
print("  bodies      one repaint")

for count in [25_000, 100_000, 500_000, 1_000_000] {
    let field = ParticleEngine(width: 400, height: 700)
    _ = field.setMaxParticles(1_000_000)
    field.paletteEnabled = true
    field.colorMode = .velocity
    var swarmRng = Mulberry32(seed: 1)
    field.swarm.spawn(
        count: count,
        width: 400,
        height: 700,
        color: 0xFFFF_FFFF,
        budget: 1_000_000,
        rng: &swarmRng
    )

    // The table is baked once by the caller in the real path too, so baking is not part of the figure.
    let table = field.palette.bakeLookup()
    let rounds = 60
    let started = now()
    for _ in 0 ..< rounds { field.recolorSwarm(using: table) }
    let each = (now() - started) / Double(rounds) * 1000

    print(
        String(
            format: "  %-10@  %8.2f ms",
            count.formattedWithSeparators as NSString,
            each
        )
    )
}

print("")
print("  Compare against the right-hand column of the field table above. A repaint is roughly the cost")
print("  of a moment's physics, so a ramp driven by speed is not free — it is the reason the engine")
print("  checks whether the ramp actually moves before running it.")

// MARK: - The two switches that used to be wired to nothing
//
// Fluid and gravity-between-bodies. Both are per-body passes over every neighbour, so both are in the
// same family of cost as pushing bodies apart — which is the expensive one. Measured here so the numbers
// in `SwarmCost` are numbers rather than guesses, and so the interface can say what it will cost before
// somebody finds out by the field dropping to five frames a second.

print("")
print("The two forces that were reserved, one moment each:")
print("")
print("  bodies      fluid        pull between bodies")

for count in [10_000, 25_000, 50_000, 100_000, 200_000] {
    var figures: [Double] = []
    for mode in 0 ..< 2 {
        let field = ParticleEngine(width: 400, height: 700)
        _ = field.setMaxParticles(1_000_000)
        field.collisionsEnabled = false
        if mode == 0 { field.fluidEnabled = true } else { field.nbodyEnabled = true }
        var swarmRng = Mulberry32(seed: 1)
        field.swarm.spawn(
            count: count,
            width: 400,
            height: 700,
            color: 0xFFFF_FFFF,
            budget: 1_000_000,
            rng: &swarmRng
        )
        // Settled first, so the squares are as full as they get in practice. A crowd measured while
        // still evenly spread is measured at its easiest, which is not the case anybody meets.
        for _ in 0 ..< 10 { field.step() }

        let rounds = 12
        let started = now()
        for _ in 0 ..< rounds { field.step() }
        figures.append((now() - started) / Double(rounds) * 1000)
    }
    print(
        String(
            format: "  %-10@  %8.1f ms   %8.1f ms",
            count.formattedWithSeparators as NSString,
            figures[0],
            figures[1]
        )
    )
}

print("")
print("  The pull between bodies sweeps a grid of sixteen hundred squares per body whatever the crowd,")
print("  so its cost per body barely changes — which is the whole reason for the approximation. The")
print("  fluid is two passes over every neighbour, so it climbs with how tightly packed the crowd is.")

// MARK: - Wind, and forces somebody writes
//
// Both of these are one sweep over the bodies with no neighbour search at all, so both should be cheap
// and should stay linear. Measured because "should be" is not a figure, and because the written force in
// particular is where the reference implementation loses most of its time — it reads the text afresh for
// every body on every axis on every frame.

print("")
print("Wind, and a written force, one moment each:")
print("")
print("  bodies      wind         written force")

for count in [25_000, 100_000, 500_000, 1_000_000] {
    var figures: [Double] = []
    for mode in 0 ..< 2 {
        let field = ParticleEngine(width: 400, height: 700)
        _ = field.setMaxParticles(1_000_000)
        field.collisionsEnabled = false
        if mode == 0 {
            field.flowEnabled = true
            field.flowSettings.strength = 1
        } else if case .success(let expression) =
            ParticleForceExpression.compile("sin(y * 8 + t) * 2 - vx * 0.1")
        {
            field.writtenForceAcross = expression
            field.writtenForceDown = expression
        }
        var swarmRng = Mulberry32(seed: 1)
        field.swarm.spawn(
            count: count,
            width: 400,
            height: 700,
            color: 0xFFFF_FFFF,
            budget: 1_000_000,
            rng: &swarmRng
        )
        for _ in 0 ..< 5 { field.step() }

        let rounds = 20
        let started = now()
        for _ in 0 ..< rounds { field.step() }
        figures.append((now() - started) / Double(rounds) * 1000)
    }
    print(
        String(
            format: "  %-10@  %8.2f ms   %8.2f ms",
            count.formattedWithSeparators as NSString,
            figures[0],
            figures[1]
        )
    )
}

print("")
print("  Both are one sweep with no neighbour search, so both stay linear. The written force is compiled")
print("  once into a flat list of steps rather than read afresh per body, which is the difference between")
print("  arithmetic and millions of small allocations a second.")
