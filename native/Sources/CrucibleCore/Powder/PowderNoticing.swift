// Noticing what the world made by itself.
//
// ## The one distinction this rests on
//
// Painting glass is not discovering glass. Making sand hot enough that it becomes glass on its own is.
//
// Both go through the same door — ``PowderEngine/setElement(_:_:_:temp:life:)`` is how a cell's material changes,
// whether a finger or a rule asked for it — so the difference cannot be told from the call. What can be told is
// *when*: the engine is either running a moment of its own rules, or it is not. So it only listens while it is
// running, and a brush stroke between moments is silent.
//
// ## Why it is a set of flags drained on reading
//
// The same shape as ``PowderEngine/takeLargestBurst()``, and for the same reason. A callback would need a listener
// slot, and the engine's one slot is already taken by the bridge between the two chambers. A list would allocate in
// the hot loop. A flag per material costs one byte written when a cell changes — and cells only change when something
// actually happens, not every cell every moment — and the app empties the whole lot once a frame.
//
// ## What is not noticed, and why that is written here
//
// Four places change a cell's material without going through the door: the deep-freeze event, lava being quenched,
// the repair tools, and loading a world. The first two are real changes a player made happen and are reported by hand
// where they are. The repairs and loading are deliberately silent — being handed a world with glass in it is not
// finding out how glass is made.

extension PowderEngine {
    /// How many materials there could be, which is the width of the flag set.
    ///
    /// The whole range an element's number can take, rather than how many exist: a user-authored material has a number
    /// in the reserved band, and a flag set sized to the built-in count would be written past its end by one.
    static let noticedWidth = 256

    /// Starts and stops noticing. Only true while the engine is running a moment of its own rules.
    var noticing: Bool {
        get { storedNoticing }
        set { storedNoticing = newValue }
    }

    /// Runs something with the notebook listening, and leaves listening exactly as it was.
    ///
    /// Saved and restored rather than simply switched off at the end, because these nest: an event sets off explosions,
    /// and an explosion sets off more. Switching off at the end of the inner one would go deaf for the rest of the
    /// outer one, which is where most of what an event makes actually appears.
    func whileNoticing<T>(_ body: () throws -> T) rethrows -> T {
        let was = storedNoticing
        storedNoticing = true
        defer { storedNoticing = was }
        return try body()
    }

    /// Records that a material appeared because the world's own rules made it appear.
    ///
    /// Called from the places a cell's material changes. Cheap enough to sit in the middle of the tick: a bounds check
    /// and a byte.
    @inline(__always)
    func noticeMade(_ elementID: ElementID) {
        guard storedNoticing else { return }
        if storedNoticed.isEmpty {
            storedNoticed = [UInt8](repeating: 0, count: Self.noticedWidth)
        }
        let at = Int(elementID)
        guard at >= 0, at < Self.noticedWidth else { return }
        storedNoticed[at] = 1
        storedNoticedAny = true
    }

    /// Every material the world made since this was last asked, and forgets them.
    ///
    /// Drained on reading, like the largest explosion, so nothing accumulates unread and the caller cannot be handed
    /// the same news twice.
    public func takeNewlyMade() -> [ElementID] {
        guard storedNoticedAny else { return [] }
        defer {
            for i in 0 ..< storedNoticed.count { storedNoticed[i] = 0 }
            storedNoticedAny = false
        }
        var found: [ElementID] = []
        for i in 0 ..< storedNoticed.count where storedNoticed[i] != 0 {
            found.append(ElementID(i))
        }
        return found
    }

    /// How many explosions went off in a row without anybody touching anything, and forgets it.
    ///
    /// A chain reaction is not one explosion and it is not a number of explosions — it is explosions *following each
    /// other*, which means the count has to be reset by time passing quietly rather than by being read. Twelve moments
    /// of calm ends a chain, which is a fifth of a second: long enough that one blast setting off its neighbour counts,
    /// short enough that two separate things a player lit are two chains.
    public func takeLongestChain() -> Int {
        defer { storedLongestChain = 0 }
        return storedLongestChain
    }

    /// Counts an explosion towards a chain. Called where explosions are made.
    func noteChainLink() {
        // Still within earshot of the last one, so it is the same chain.
        if frameCount - storedLastBurstFrame <= Self.chainGap {
            storedChainLength += 1
        } else {
            storedChainLength = 1
        }
        storedLastBurstFrame = frameCount
        storedLongestChain = max(storedLongestChain, storedChainLength)
    }

    /// How many quiet moments end a chain of explosions.
    static let chainGap = 12
}
