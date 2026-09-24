/// Undo and redo for the powder world.
///
/// A snapshot is a straight copy of three of the eight grids — which element is in each
/// cell, how hot it is, and how long it has left — plus the four world settings that a
/// brush stroke can change. Momentum, pressure and the per-tick visited marks are
/// deliberately not captured: they are regenerated within a tick or two of resuming, and
/// copying them would nearly double the cost of every stroke for no visible benefit.
///
/// ## Why this is lossy on purpose
///
/// Undo therefore returns the world to the *shape* it had, not to the exact instant. A
/// grain that was mid-fall comes back at rest. That is the same behaviour the web
/// reference has, and the two must agree — a scene that has been undone is still
/// compared against it.
public final class PowderHistory {
    /// One captured world.
    public struct Snapshot: Sendable {
        public var width: Int
        public var height: Int
        public var type: [ElementID]
        public var temperature: [Float]
        public var life: [UInt16]
        public var gravityX: Double
        public var gravityY: Double
        public var windX: Double
        public var ambientTemp: Double

        /// How many cells this snapshot describes.
        public var cellCount: Int { width * height }
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private let maximumSteps: Int

    /// - Parameter maximumSteps: How many strokes can be taken back. Forced to at least
    ///   one: a limit of zero made `push` discard the snapshot it had just taken, so
    ///   undo was permanently unavailable with nothing to indicate why.
    public init(maximumSteps: Int = 25) {
        self.maximumSteps = max(1, maximumSteps)
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Copies the current world.
    public func capture(_ engine: PowderEngine) -> Snapshot {
        let count = engine.cellCount
        return Snapshot(
            width: engine.width,
            height: engine.height,
            type: Array(UnsafeBufferPointer(start: engine.type, count: count)),
            temperature: Array(UnsafeBufferPointer(start: engine.temperature, count: count)),
            life: Array(UnsafeBufferPointer(start: engine.life, count: count)),
            gravityX: engine.gravityX,
            gravityY: engine.gravityY,
            windX: engine.windX,
            ambientTemp: engine.ambientTemp
        )
    }

    /// Puts a captured world back.
    ///
    /// - Returns: whether it was applied. The one case where it cannot be is a snapshot
    ///   whose size the engine will not adopt, and the caller has to know rather than be
    ///   handed a world that looks loaded and is not.
    @discardableResult
    public func restore(_ engine: PowderEngine, _ snapshot: Snapshot) -> Bool {
        if snapshot.width != engine.width || snapshot.height != engine.height {
            engine.resize(width: snapshot.width, height: snapshot.height)
            // Checked, not assumed. `resize` returns quietly when the size is unusable,
            // and the copy below would then lay the snapshot out at the wrong row
            // length — sliding every row along, shearing the whole world, silently.
            if snapshot.width != engine.width || snapshot.height != engine.height {
                return false
            }
        }
        guard snapshot.type.count >= engine.cellCount else { return false }

        // The ambient temperature goes on before the clear, because the clear is what
        // fills the grid with it. Set afterwards, any cell the snapshot did not reach
        // was left holding the temperature of the world being replaced.
        engine.ambientTemp = snapshot.ambientTemp
        engine.resetGrid()

        let count = engine.cellCount
        for i in 0 ..< count {
            let id = snapshot.type[i]
            engine.type[i] = id
            engine.temperature[i] = snapshot.temperature[i]
            engine.life[i] = snapshot.life[i]
            // Undoing back to a world that had a portal has to restore the engine's
            // knowledge of it too, or teleportation would quietly stop working after an
            // undo. Spotted in the copy that was happening anyway.
            if id == Element.portalB { engine.portalBMayExist = true }
        }
        engine.gravityX = snapshot.gravityX
        engine.gravityY = snapshot.gravityY
        // Through the clamp, like every other writer. Wind is a plain property, so
        // anything could have put an out-of-range value in it, and undo used to carry
        // that value straight back out.
        engine.setWind(snapshot.windX)
        return true
    }

    /// Records the current world as a point to come back to. Call before mutating.
    public func push(_ engine: PowderEngine) {
        // Cleared first, so a failure below cannot leave a redo entry describing a
        // future that never happened.
        redoStack.removeAll(keepingCapacity: true)
        undoStack.append(capture(engine))
        if undoStack.count > maximumSteps { undoStack.removeFirst() }
    }

    @discardableResult
    public func undo(_ engine: PowderEngine) -> Bool {
        guard let previous = undoStack.last else { return false }
        let current = capture(engine)
        undoStack.removeLast()
        guard restore(engine, previous) else {
            // Could not be applied, so the step is put back rather than lost.
            undoStack.append(previous)
            return false
        }
        redoStack.append(current)
        if redoStack.count > maximumSteps { redoStack.removeFirst() }
        return true
    }

    @discardableResult
    public func redo(_ engine: PowderEngine) -> Bool {
        guard let next = redoStack.last else { return false }
        let current = capture(engine)
        redoStack.removeLast()
        guard restore(engine, next) else {
            redoStack.append(next)
            return false
        }
        undoStack.append(current)
        // Trimmed here as well as in `push`. Without it, cycling undo and redo grew the
        // undo stack past its own limit.
        if undoStack.count > maximumSteps { undoStack.removeFirst() }
        return true
    }

    public func clear() {
        undoStack.removeAll(keepingCapacity: true)
        redoStack.removeAll(keepingCapacity: true)
    }
}
