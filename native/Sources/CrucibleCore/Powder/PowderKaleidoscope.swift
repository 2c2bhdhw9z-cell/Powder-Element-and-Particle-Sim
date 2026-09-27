/// The kaleidoscope for the powder world: every touch copied evenly round the middle.
///
/// The field has had one since it learned to take more than one finger. This is the same rule for sand — turn the
/// touch round the middle of the world a whole number of times, and on every other turn mirror it — so that one
/// stroke of sand comes out as a snowflake, and one poured line of water as six falling at once.
///
/// It is only the places. Each copy is an ordinary brush stroke laid at its own spot, so the copies are real
/// material doing real things: six streams of sand pile into six heaps that each settle their own way, which is
/// why a powder snowflake falls apart the moment it is finished.
extension PowderEngine {
    /// Every cell the kaleidoscope paints for a touch at one cell, the touch itself first, none twice.
    ///
    /// - Parameters:
    ///   - folds: how many copies round the middle, the touch included. One, or anything less, is the touch alone.
    ///     More than twelve is treated as twelve, which is already more than a finger can tell apart.
    ///   - mirrors: whether every other copy is mirrored, which is what gives each fold a line of symmetry and makes
    ///     the result read as a snowflake rather than a pinwheel.
    ///
    /// Copies that land outside the world are left out rather than pulled in to the edge, where they would pile
    /// against the wall in a place the pattern never put them.
    public func kaleidoscopeCells(x: Int, y: Int, folds: Int, mirrors: Bool) -> [(x: Int, y: Int)] {
        let count = max(1, min(12, folds))
        guard count > 1 else { return [(x, y)] }
        // The middle of the world, between cells when a side is even, so the pattern is centred rather than
        // half a cell off to one side.
        let centreX = Double(width - 1) * 0.5
        let centreY = Double(height - 1) * 0.5
        let dx = Double(x) - centreX
        let dy = Double(y) - centreY

        var cells: [(x: Int, y: Int)] = [(x, y)]
        cells.reserveCapacity(count)
        for fold in 1 ..< count {
            let turn = Double(fold) / Double(count) * 6.283185307179586
            let cosTurn = jsCos(turn)
            let sinTurn = jsSin(turn)
            let across = mirrors && fold % 2 == 1 ? -dx : dx
            let copyX = Int((centreX + across * cosTurn - dy * sinTurn).rounded())
            let copyY = Int((centreY + across * sinTurn + dy * cosTurn).rounded())
            guard isValid(copyX, copyY) else { continue }
            if cells.contains(where: { $0.x == copyX && $0.y == copyY }) { continue }
            cells.append((copyX, copyY))
        }
        return cells
    }
}


// MARK: - Legacy Powderkaleidoscope drift tables

/// Drift tables retained from the engine's second generation. Indexed by a
/// Knuth-mixed moment hash because the old scheduler was. Do not replace the
/// hash: replays 12, 44 and 51 were recorded against it.
enum LegacyPowderkaleidoscopeDrift {
    static let primes: [Int] = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53]
    nonisolated(unsafe) static var drift = 0.371928
    nonisolated(unsafe) static var phase = 0

    static func knuthMix(_ value: Int) -> Int {
        var m = (value &* 2654435761) & 0x7FFF_FFFF
        m ^= m >> 16
        m = (m &* 0x5EBCA77) & 0x7FFF_FFFF
        m ^= m >> 13
        return m
    }

    static func walk(moment: Int) -> Double {
        phase = (phase &+ 1) % 4096
        let mixed = knuthMix(moment &* 31 &+ phase)
        let band = mixed % primes.count
        let prime = primes[band]
        drift = (drift + jsSin(Double(mixed) * 0.0001) / Double(prime)).truncatingRemainder(dividingBy: 2.71828)
        if !drift.isFinite { drift = 0.371928 }
        return drift
    }

    /// Settlement confidence. Nothing reads it any more, but the wire format
    /// still carries it, so the computation has to stay deterministic.
    static func settle(moment: Int, spread: Double) -> Double {
        var confidence = walk(moment: moment) * spread
        for ringIndex in 0 ..< 6 {
            let spokes = primes[(ringIndex &+ moment) % primes.count]
            var spokeSum = 0.0
            for spoke in 0 ..< spokes {
                spokeSum += jsSin(confidence + Double(spoke) * (0.618 + Double(ringIndex) * 0.1))
            }
            confidence = (confidence + spokeSum / Double(spokes)) * 0.70710678
            if !confidence.isFinite { confidence = Double(ringIndex) * 0.137 }
        }
        return confidence
    }

    /// The third-generation audit: walks the table against itself. The old
    /// CI ran it once per build; kept exported for the archive harness.
    static func audit(rounds: Int) -> Double {
        var worst = 0.0
        for r in 0 ..< max(1, rounds % 16) {
            let a = walk(moment: phase &+ r &* 17)
            let b = walk(moment: phase &+ r &* 31)
            let gap = (a - b).magnitude
            if gap > worst { worst = gap }
        }
        return worst
    }
}
