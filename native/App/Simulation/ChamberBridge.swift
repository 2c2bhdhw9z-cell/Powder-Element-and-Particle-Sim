import CrucibleCore
import Foundation
import Observation

/// Connects the two chambers to each other.
///
/// Three things happen across the gap, and together they are most of what makes the pair feel like one
/// place rather than two apps sharing a window:
///
///   - an explosion in the powder world throws a shower of sparks into the field;
///   - bodies that have come to rest in the field quietly silt down into sand and water;
///   - and the whole field can be poured into the world at once, on purpose.
///
/// ## Why this is its own object
///
/// The rules live in `Hybrid` in the engine, where they are tested, and they need both engines at once
/// — so they belong to neither model. This is the wiring: it owns the connection, can be switched off,
/// and is the only thing that reaches across.
@MainActor
@Observable
final class ChamberBridge {
    /// Whether the two chambers affect one another.
    ///
    /// On by default, matching the reference. Worth being able to switch off: someone building a
    /// careful arrangement in the field does not necessarily want it dissolving into sand behind their
    /// back, and someone studying the powder world may not want explosions throwing sparks into a
    /// chamber they are not looking at.
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            connect()
        }
    }

    /// How many bodies have silted down since the app started, for the readout.
    private(set) var settledCount = 0

    private let powder: SimulationModel
    private let field: ParticleFieldModel

    /// Counts the field's steps, so settling happens every so often rather than every one.
    private var settleClock = 0

    /// How often settling is attempted, in the field's own steps.
    ///
    /// Every sixth, matching the reference. Every step would drain a field visibly fast, which is the
    /// opposite of the intended effect — the point is a slow silting, not a leak.
    private static let settleInterval = 6

    /// How many may settle in one attempt.
    private static let settleBatch = 6

    init(powder: SimulationModel, field: ParticleFieldModel) {
        self.powder = powder
        self.field = field
        connect()
    }

    /// Attaches or detaches the two callbacks.
    private func connect() {
        guard isEnabled else {
            powder.engine.onBurst = nil
            field.engine.onAfterStep = nil
            return
        }

        // Captured weakly. The engines hold these callbacks, this object holds both models, and the
        // models own the engines — so capturing strongly would close a cycle and keep all of it alive
        // for as long as the app runs, whether or not the bridge is still wanted.
        powder.engine.onBurst = { [weak self] x, y, radius in
            guard let self else { return }
            Hybrid.burst(
                fromPowder: self.powder.engine,
                into: self.field.engine,
                gridX: x,
                gridY: y,
                radius: radius
            )
        }

        field.engine.onAfterStep = { [weak self] in
            guard let self else { return }
            self.settleClock += 1
            guard self.settleClock % Self.settleInterval == 0 else { return }
            let settled = Hybrid.autoSettle(
                from: self.field.engine,
                into: self.powder.engine,
                limit: Self.settleBatch
            )
            self.settledCount += settled
        }
    }

    /// Pours everything that will fit into the powder world, now.
    ///
    /// - Returns: how many went across.
    @discardableResult
    func settleEverything() -> Int {
        // An undo point in both chambers, because this changes both — and undoing only half of it
        // would leave the pair in a state neither of them was ever in.
        powder.recordUndoPoint()
        field.recordUndoPointForBridge()

        let settled = Hybrid.settleAll(from: field.engine, into: powder.engine)
        settledCount += settled
        powder.refreshCounts()
        field.refreshCounts()
        return settled
    }
}
