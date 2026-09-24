import Testing

@testable import CrucibleCore

/// The rolling history behind the performance graphs.
///
/// A ring buffer, which is where off-by-one errors live. Every failure here produces a graph that looks
/// entirely plausible and is wrong: readings in the wrong order run the chart backwards, an oldest
/// sample dropped one too early loses a column, and a `latest` read from the wrong end reports a value
/// from a minute ago as the current one — which would have somebody chasing a slowdown that had already
/// passed.
@Suite("A rolling history keeps the right readings in the right order")
struct SampleHistoryTests {
    @Test("A fresh history has nothing in it")
    func startsEmpty() {
        let history = SampleHistory(capacity: 5)
        #expect(history.count == 0)
        #expect(history.values.isEmpty)
        #expect(history.latest == nil)
        #expect(history.maximum == nil)
        #expect(history.minimum == nil)
        #expect(history.average == nil)
    }

    @Test("Readings come back oldest first, before it has filled up")
    func ordersBeforeWrapping() {
        var history = SampleHistory(capacity: 5)
        for value in [1.0, 2, 3] { history.record(value) }
        #expect(history.count == 3)
        #expect(history.values == [1, 2, 3])
        #expect(history.latest == 3)
    }

    @Test("Exactly full holds everything, still oldest first")
    func exactlyFull() {
        var history = SampleHistory(capacity: 4)
        for value in [1.0, 2, 3, 4] { history.record(value) }
        #expect(history.count == 4)
        #expect(history.values == [1, 2, 3, 4])
        #expect(history.latest == 4)
    }

    /// The case that matters. Once it wraps, the oldest reading is no longer at the start of the store,
    /// and reading them out in storage order gives a chart with a discontinuity in the middle.
    @Test("Once it has wrapped, the order is still oldest first")
    func ordersAfterWrapping() {
        var history = SampleHistory(capacity: 4)
        for value in [1.0, 2, 3, 4, 5, 6] { history.record(value) }
        #expect(history.count == 4)
        // One and two have fallen off the back.
        #expect(history.values == [3, 4, 5, 6])
        #expect(history.latest == 6)
    }

    @Test("It never keeps more than it was asked to")
    func neverExceedsCapacity() {
        var history = SampleHistory(capacity: 10)
        for i in 0 ..< 1000 { history.record(Double(i)) }
        #expect(history.count == 10)
        #expect(history.values.count == 10)
        // The last ten, in order.
        #expect(history.values == (990 ..< 1000).map { Float($0) })
        #expect(history.latest == 999)
    }

    /// Walked one reading at a time across the wrap, because the boundary is where a ring buffer goes
    /// wrong and a single test either side of it can miss by one.
    @Test("The newest reading is right at every step across the wrap")
    func latestIsRightThroughout() {
        var history = SampleHistory(capacity: 3)
        for i in 1 ... 20 {
            history.record(Double(i))
            #expect(history.latest == Float(i), "after \(i) readings the newest should be \(i)")
            #expect(history.values.last == Float(i))
            #expect(history.values.first == Float(max(1, i - 2)))
        }
    }

    @Test("A capacity of one keeps only the newest")
    func capacityOfOne() {
        var history = SampleHistory(capacity: 1)
        history.record(7)
        #expect(history.values == [7])
        history.record(9)
        #expect(history.values == [9])
        #expect(history.latest == 9)
        #expect(history.count == 1)
    }

    /// A capacity of nothing would be a history that silently discards everything given to it, which is
    /// worse than refusing — the graph would simply be empty with no explanation.
    @Test("A nonsensical capacity becomes one rather than nothing")
    func capacityFloor() {
        for requested in [0, -1, -100] {
            var history = SampleHistory(capacity: requested)
            #expect(history.capacity == 1)
            history.record(4)
            #expect(history.values == [4])
        }
    }

    // MARK: Summaries

    @Test("The range and mean describe what is kept, not what has been forgotten")
    func summariesFollowTheWindow() {
        var history = SampleHistory(capacity: 3)
        for value in [100.0, 1, 2, 3] { history.record(value) }
        // The hundred has fallen off, so it must not still be the maximum.
        #expect(history.maximum == 3)
        #expect(history.minimum == 1)
        #expect(history.average == 2)
    }

    /// One unusable reading must show as a single gap rather than blanking the chart. Left alone it
    /// would poison the range the graph is scaled to and every column would collapse to nothing.
    @Test("An unusable reading becomes zero rather than ruining the scale")
    func unusableReadings() {
        var history = SampleHistory(capacity: 4)
        history.record(10)
        history.record(.nan)
        history.record(20)
        history.record(.infinity)

        #expect(history.values == [10, 0, 20, 0])
        #expect(history.maximum == 20)
        #expect(history.average != nil)
        let average = history.average ?? .nan
        #expect(average.isFinite, "one bad reading should not make the mean unusable")
    }

    @Test("Clearing it empties it completely, ready to be reused")
    func clearing() {
        var history = SampleHistory(capacity: 3)
        for value in [1.0, 2, 3, 4] { history.record(value) }
        history.removeAll()
        #expect(history.count == 0)
        #expect(history.values.isEmpty)
        #expect(history.latest == nil)

        // And it fills up correctly again afterwards, rather than resuming mid-ring.
        history.record(9)
        #expect(history.values == [9])
        #expect(history.latest == 9)
    }
}
