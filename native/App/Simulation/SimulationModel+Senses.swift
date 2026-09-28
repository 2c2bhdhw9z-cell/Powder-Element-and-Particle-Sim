import CrucibleCore
import Foundation

extension SimulationModel {
    /// Pours some of a material in from the top, across the middle: what "make it rain" does.
    ///
    /// Into empty places only, and one undo away, like a stroke.
    func pour(_ id: ElementID) {
        guard !isFollowingRoom else { return }
        endParallel(keepSecond: false)
        recordUndoPoint()
        let width = engine.width
        let across = max(4, width * 3 / 10)
        let left = (width - across) / 2
        let rows = max(2, engine.height / 25)
        for y in 1 ... rows {
            for x in left ..< (left + across) where engine.typeAt(x, y) == Element.empty {
                // Not every cell, so it arrives as a shower rather than a slab.
                if engine.rng.chance(0.55) { engine.setElement(x, y, id) }
            }
        }
        isRunning = true
        refreshCounts()
    }

    /// Changes the brush's size by a step, as "bigger" and "smaller" do.
    func changeBrush(bigger: Bool) {
        brushRadius = max(1, min(40, bigger ? brushRadius + 3 : brushRadius - 3))
    }

    /// Changes how fast time runs by a step.
    func changeSpeed(faster: Bool) {
        speed = max(0.25, min(4, faster ? speed * 2 : speed / 2))
    }
}
