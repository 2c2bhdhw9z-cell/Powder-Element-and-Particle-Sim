import CrucibleCore
import Foundation

/// Parallel worlds: the powder world copied exactly at this moment, one thing changed in the copy, and both run
/// together side by side. See `PowderParallel.swift` in the engine for why the copy has to be exact.
///
/// The copy is a model of its own so it can be drawn by a view of its own, but it never steps itself: this world
/// steps it, in the same loop and the same moments, so the two can differ only in what happens and never in when.
extension SimulationModel {
    /// Copies the world and changes one thing in the copy.
    func beginParallel(_ change: PowderParallelChange) {
        endExperiment()
        cancelPendingEvent()
        toolsBeforeWorldReplaced()
        let twin = SimulationModel(twinOf: self)
        change.apply(to: twin.engine)
        change.keep(twin.engine, following: engine)
        twin.refreshCounts()
        setParallel(twin, change)
        isRunning = true
    }

    /// Goes back to one world: this one, or the changed one.
    ///
    /// Keeping the changed one keeps its change too — the colder room, the missing pressure — since that is what made
    /// it the world it is. It is one undo away.
    func endParallel(keepSecond: Bool) {
        guard let twin = parallel else { return }
        if keepSecond {
            recordUndoPoint()
            engine.becomeCopy(of: twin.engine)
            afterWholeWorldChange()
            refreshCounts()
        }
        setParallel(nil, nil)
    }
}
