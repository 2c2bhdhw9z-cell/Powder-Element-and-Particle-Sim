import CrucibleCore
import Foundation

/// A few of the benchmark's figures, compared against the ones recorded in `bench-baseline.json`, and a verdict.
///
/// The benchmark prints on every run and nothing used to read it, so a change that made a moment twice as dear went by
/// unremarked unless somebody happened to look. This reads it. Run with `--gate`:
///
///     swift run -c release crucible-bench --gate bench-baseline.json
///
/// It fails — exits with one — when any figure is more than the file's tolerance slower than its recorded value.
///
/// ## Why the tolerance is wide
///
/// Shared machines are not quiet ones. The same build measured twice on the checks' Macs differs by a fifth or more,
/// so a tight limit would fail at random and be ignored within a week, which is worse than no limit. Each figure is the
/// best of three runs, which takes most of the noise out, and the tolerance is half as slow again: wide enough never to
/// fail by chance, narrow enough to catch anything that makes a real difference to somebody holding the phone.
///
/// ## When something is meant to be slower
///
/// A new piece of physics can legitimately cost more. Then the recorded figure is raised in the file, in the same
/// change, with a sentence in the change saying why — which is the whole point: a slowdown is decided, not drifted into.
enum SpeedGate {
    struct Baseline: Decodable {
        /// How many times slower than recorded a figure may be before the check fails.
        var tolerance: Double
        /// Milliseconds a moment, by the name of what was measured.
        var cases: [String: Double]
    }

    /// The figures the gate knows how to take.
    static let known = [
        "powder 200x430",
        "powder 420x910",
        "field 25000 pushing apart",
        "field 500000 not pushing apart",
    ]

    /// One figure, in milliseconds a moment, measured exactly as the full benchmark measures it.
    static func measure(_ name: String) -> Double? {
        switch name {
        case "powder 200x430": powder(width: 200, height: 430, steps: 120)
        case "powder 420x910": powder(width: 420, height: 910, steps: 120)
        case "field 25000 pushing apart": field(count: 25_000, collide: true)
        case "field 500000 not pushing apart": field(count: 500_000, collide: false)
        default: nil
        }
    }

    private static func powder(width: Int, height: Int, steps: Int) -> Double {
        let engine = PowderEngine(width: width, height: height, seed: 99)
        populate(engine, fill: 0.30)
        for _ in 0 ..< 20 { engine.step() }
        let started = now()
        for _ in 0 ..< steps { engine.step() }
        return (now() - started) / Double(steps) * 1000
    }

    private static func field(count: Int, collide: Bool) -> Double {
        let field = ParticleEngine(width: 400, height: 700)
        _ = field.setMaxParticles(1_000_000)
        field.collisionsEnabled = collide
        var swarmRng = Mulberry32(seed: 1)
        field.swarm.spawn(count: count, width: 400, height: 700, color: 0xFFFF_FFFF, budget: 1_000_000, rng: &swarmRng)
        for _ in 0 ..< 10 { field.step() }
        let rounds = collide ? 8 : 40
        let started = now()
        for _ in 0 ..< rounds { field.step() }
        return (now() - started) / Double(rounds) * 1000
    }

    /// Measures every figure the file records, and says which are too slow.
    ///
    /// - Returns: whether every figure was within its limit.
    static func run(baselinePath: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: baselinePath) else {
            print("Speed check: could not read \(baselinePath).")
            return false
        }
        guard let baseline = try? JSONDecoder().decode(Baseline.self, from: data),
              baseline.tolerance.isFinite, baseline.tolerance >= 1, !baseline.cases.isEmpty
        else {
            print("Speed check: \(baselinePath) is not a baseline this understands.")
            return false
        }

        print("Speed check — each figure the best of three, allowed \(baseline.tolerance)× its recorded value")
        print("")
        print("  what                               recorded       now     limit   verdict")
        print("  --------------------------------------------------------------------------")
        var allWithin = true
        for name in baseline.cases.keys.sorted() {
            guard let recorded = baseline.cases[name], recorded.isFinite, recorded > 0 else {
                print("  \(pad(name, 34)) not a usable recorded figure")
                allWithin = false
                continue
            }
            guard measure(name) != nil else {
                print("  \(pad(name, 34)) not something this knows how to measure")
                allWithin = false
                continue
            }
            // Best of three: the slowest runs are the machine being busy, not the code being slow.
            var best = Double.infinity
            for _ in 0 ..< 3 { best = min(best, measure(name) ?? .infinity) }
            let limit = recorded * baseline.tolerance
            let within = best <= limit
            if !within { allWithin = false }
            let verdict = within
                ? (best <= recorded ? "fine" : "fine, \(Int(((best / recorded) - 1) * 100))% slower")
                : "TOO SLOW, \(String(format: "%.1f", best / recorded))× recorded"
            print(String(
                format: "  %@ %8.3f  %8.3f  %8.3f   %@",
                pad(name, 34) as NSString, recorded, best, limit, verdict as NSString
            ))
        }
        print("")
        print(allWithin
            ? "Nothing has got slower than it is allowed to."
            : "Something has got slower. If it is meant to be, raise its figure in \(baselinePath) and say why.")
        return allWithin
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }
}
