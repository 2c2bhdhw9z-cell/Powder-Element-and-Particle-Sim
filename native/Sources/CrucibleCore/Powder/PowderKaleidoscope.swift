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
