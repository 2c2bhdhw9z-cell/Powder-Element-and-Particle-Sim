// A short rolling history of a measured value.
//
// ## Why this is in the engine
//
// It is not simulation logic, and the engine is otherwise strictly about the simulation. It is here for
// one reason: it is a ring buffer, and ring buffers are where off-by-one errors live. A history that
// drops its oldest sample one too early, or reads the newest one from the wrong end, produces a graph
// that looks entirely plausible and is wrong — a performance graph with the values in the wrong order
// would have somebody chasing a slowdown that happened a minute ago.
//
// The engine is where things can be tested, and this belongs with the diagnostics it charts.

/// The last so many readings of one measurement.
///
/// Fixed capacity, overwriting the oldest. Values are single precision because they are drawn on a
/// graph a few dozen pixels tall — double precision would be storing sixteen digits to plot about two.
public struct SampleHistory: Sendable, Equatable {
    /// How many readings are kept.
    public let capacity: Int

    /// Backing store, used as a ring.
    private var storage: [Float]
    /// Where the next reading goes.
    private var writeIndex = 0
    /// How many readings have been taken, capped at the capacity.
    public private(set) var count = 0

    /// - Parameter capacity: how many readings to keep. Forced to at least one, so a history is never
    ///   a thing that silently discards everything given to it.
    public init(capacity: Int = 120) {
        let size = max(1, capacity)
        self.capacity = size
        self.storage = [Float](repeating: 0, count: size)
    }

    /// Records a reading.
    ///
    /// A value that is not a number is stored as zero. Left alone it would poison the range the graph
    /// is scaled to, and every bar would collapse to nothing — one bad reading would blank the whole
    /// chart rather than showing as a single gap.
    public mutating func record(_ value: Double) {
        storage[writeIndex] = value.isFinite ? Float(value) : 0
        writeIndex = (writeIndex + 1) % capacity
        if count < capacity { count += 1 }
    }

    /// The readings in order, oldest first.
    ///
    /// Oldest first because that is the order a graph is drawn in. Returning them newest-first and
    /// drawing them straight would produce a chart that runs backwards, which reads as the value
    /// having done the opposite of what it did.
    public var values: [Float] {
        guard count > 0 else { return [] }
        if count < capacity {
            // Not yet wrapped, so the readings are simply the first `count` of the store.
            return Array(storage[0 ..< count])
        }
        // Wrapped: the oldest reading is wherever the next write is about to land.
        return Array(storage[writeIndex ..< capacity]) + Array(storage[0 ..< writeIndex])
    }

    /// The most recent reading, or nothing if there has not been one.
    public var latest: Float? {
        guard count > 0 else { return nil }
        // One before the write position, wrapping round the start.
        return storage[(writeIndex + capacity - 1) % capacity]
    }

    /// The largest reading kept, or nothing.
    public var maximum: Float? {
        guard count > 0 else { return nil }
        return values.max()
    }

    /// The smallest reading kept, or nothing.
    public var minimum: Float? {
        guard count > 0 else { return nil }
        return values.min()
    }

    /// The mean of the readings kept, or nothing.
    public var average: Float? {
        guard count > 0 else { return nil }
        let all = values
        return all.reduce(0, +) / Float(all.count)
    }

    /// Forgets everything.
    public mutating func removeAll() {
        storage = [Float](repeating: 0, count: capacity)
        writeIndex = 0
        count = 0
    }
}
