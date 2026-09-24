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
