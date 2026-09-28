/// Small tools for the powder world, each leaning on what the engine already does: a tide, a rewind, a thermometer,
/// measurements as numbers, a lasso, and a line drawing for a pen plotter.

// MARK: - Tide

/// A sea along one side of the world that rises and falls, slowly, for ever.
///
/// ## How the sea rises
///
/// The whole sea at once, as a real one does. A tide is not a wave arriving from the edge: the ocean beyond the edge
/// of the world is rising, and so the level rises everywhere the sea reaches. So at the flood, water is added to the
/// sea's own surface — anywhere across it, a grain on top of the water — and at the ebb it is taken off the top again.
/// Everything the water then does is the ordinary physics: the shoreline climbs a beach as the level rises, fills a
/// harbour, reaches a sandcastle's moat, and runs back down as it falls, leaving the rock pools behind.
///
/// The sea is the water joined up with the chosen edge. A lake further inland that the sea has not reached is not
/// part of it, and is not touched — until the tide rises far enough to join the two.
///
/// It needs gravity pointing down: a sea needs a floor. With the world turned over or weightless it waits.
public struct PowderTide: Sendable, Hashable, Codable {
    public enum Side: String, Sendable, Hashable, Codable, CaseIterable {
        case left
        case right
    }

    /// Which edge the open sea is beyond.
    public var side: Side
    /// How long one rise and fall takes, in moments. The phone usually runs a hundred and twenty a second at ordinary
    /// speed, so seven thousand two hundred is about a minute.
    public var period: Double
    /// How many grains of water arrive in a moment at the height of the flood, and leave at the bottom of the ebb.
    public var strength: Double

    public init(side: Side = .left, period: Double = 1_800, strength: Double = 6) {
        self.side = side
        self.period = period.isFinite ? max(120, min(216_000, period)) : 1_800
        self.strength = strength.isFinite ? max(0, min(60, strength)) : 6
    }

    /// Where in its rise and fall the tide is at a moment, from minus one — falling fastest — to one, rising fastest.
    public func height(atMoment moment: Int) -> Double {
        jsSin(Double(moment) / period * 6.283185307179586)
    }
}

extension PowderEngine {
    /// How many columns in from the edge a sea begins, when there is no sea yet.
    static let tideBand = 3
    /// How often the sea's surface is searched for again, in moments. Between times the list is kept up to date as
    /// grains are added and taken away.
    static let tideSurfaceRefresh = 12
    /// The most cells of sea one search walks, so a sea that fills an enormous world cannot stall a moment.
    static let tideSearchLimit = 400_000

    /// The highest row the sea may rise to: a third of the way up the world from the bottom, so a flood tide is a
    /// sea and not a world filled with water.
    var tideHighestRow: Int { max(0, height - max(4, height / 3)) }

    /// Whether a material is the sea's.
    @inline(__always)
    static func isSea(_ id: ElementID) -> Bool {
        id == Element.water || id == Element.saltWater
    }

    /// Runs one moment of the tide, if there is one.
    func stepTide() {
        guard let tide, width > Self.tideBand, height > 4, gravityY > 0 else { return }
        let rise = tide.height(atMoment: frameCount)
        let wanted = abs(rise) * tide.strength
        // A fraction of a grain is carried by chance rather than rounded away, so a gentle tide still moves.
        var count = Int(wanted.rounded(.down))
        if rng.next() < wanted - Double(count) { count += 1 }
        guard count > 0 else { return }

        tideSurfaceAge -= 1
        if tideSurfaceAge <= 0 {
            findSeaSurface(tide)
            tideSurfaceAge = Self.tideSurfaceRefresh
        }

        let highest = tideHighestRow
        var tries = count * 4
        while count > 0, tries > 0 {
            tries -= 1
            if rise > 0 {
                guard !tideSurface.isEmpty else {
                    // No sea yet: it begins at the foot of the edge.
                    if startSea(tide, highest: highest) { count -= 1 }
                    continue
                }
                let pick = rng.int(below: tideSurface.count)
                // Wherever the water in that column has got to since: the grain added last moment has usually run off
                // sideways, and the column's surface is lower again, or the level has risen past where it was.
                guard let cell = seaSurface(near: tideSurface[pick]) else {
                    dropSurfaceEntry(at: pick)
                    continue
                }
                tideSurface[pick] = cell
                let row = cell / width
                // Room above it, below the highest the sea may reach.
                guard row - 1 >= highest else {
                    dropSurfaceEntry(at: pick)
                    continue
                }
                setElement(cell % width, row - 1, type[cell])
                tideSurface[pick] = cell - width
            } else {
                guard !tideSurface.isEmpty else { break }
                let pick = rng.int(below: tideSurface.count)
                guard let cell = seaSurface(near: tideSurface[pick]) else {
                    dropSurfaceEntry(at: pick)
                    continue
                }
                let row = cell / width
                setElement(cell % width, row, Element.empty)
                // The water beneath is the surface now, if there is any.
                let below = cell + width
                if row + 1 < height, Self.isSea(type[below]) { tideSurface[pick] = below } else { dropSurfaceEntry(at: pick) }
            }
            count -= 1
        }
    }

    /// The top of the water in the same column as a place that was once on the sea's surface, or nothing if that
    /// column no longer holds any sea there.
    ///
    /// Up through the water when the level has risen past the place, down through the air when it has fallen or the
    /// grain there has run off. Water capped by something solid — under an overhang — is not the surface.
    private func seaSurface(near place: Int) -> Int? {
        guard place >= 0, place < cellCount else { return nil }
        let x = place % width
        var y = place / width
        if type[place] == Element.empty {
            while y + 1 < height, type[index(x, y + 1)] == Element.empty { y += 1 }
            guard y + 1 < height else { return nil }
            let below = index(x, y + 1)
            return Self.isSea(type[below]) ? below : nil
        }
        guard Self.isSea(type[place]) else { return nil }
        while y > 0, Self.isSea(type[index(x, y - 1)]) { y -= 1 }
        guard y == 0 || type[index(x, y - 1)] == Element.empty else { return nil }
        return index(x, y)
    }

    /// Forgets one place on the sea's surface, without disturbing the order of the rest more than it has to.
    private func dropSurfaceEntry(at pick: Int) {
        tideSurface.swapAt(pick, tideSurface.count - 1)
        tideSurface.removeLast()
    }

    /// Starts a sea at the foot of the edge, in the first empty cell up from the bottom of one of its columns.
    private func startSea(_ tide: PowderTide, highest: Int) -> Bool {
        let column = rng.int(below: Self.tideBand)
        let x = tide.side == .left ? column : width - 1 - column
        var y = height - 1
        while y >= highest, type[index(x, y)] != Element.empty { y -= 1 }
        guard y >= highest else { return false }
        setElement(x, y, Element.water)
        tideSurface.append(index(x, y))
        return true
    }

    /// Finds every water cell joined up with the sea's edge and keeps the ones with air above them.
    ///
    /// Uses the per-moment marks as its record of where it has been, which is safe here and only here: this runs after
    /// everything has moved, and the marks are all cleared at the start of the next moment anyway.
    func findSeaSurface(_ tide: PowderTide) {
        tideSurface.removeAll(keepingCapacity: true)
        let seen: UInt8 = 2
        var stack: [Int] = []
        for column in 0 ..< min(Self.tideBand, width) {
            let x = tide.side == .left ? column : width - 1 - column
            for y in 0 ..< height {
                let i = index(x, y)
                if Self.isSea(type[i]), visited[i] != seen {
                    visited[i] = seen
                    stack.append(i)
                }
            }
        }
        var walked = 0
        while let cell = stack.popLast(), walked < Self.tideSearchLimit {
            walked += 1
            let x = cell % width
            let y = cell / width
            if y == 0 || type[cell - width] == Element.empty { tideSurface.append(cell) }
            if x > 0 { reachSea(cell - 1, &stack, seen) }
            if x + 1 < width { reachSea(cell + 1, &stack, seen) }
            if y > 0 { reachSea(cell - width, &stack, seen) }
            if y + 1 < height { reachSea(cell + width, &stack, seen) }
        }
    }

    @inline(__always)
    private func reachSea(_ cell: Int, _ stack: inout [Int], _ seen: UInt8) {
        guard Self.isSea(type[cell]), visited[cell] != seen else { return }
        visited[cell] = seen
        stack.append(cell)
    }
}

// MARK: - Rewind

/// The last little while of a world, kept a moment every so often, to scrub back through.
///
/// Built from the same snapshots undo takes, so a rewound world is exactly an undone one: the shape of everything,
/// its heat and its colours, with what was moving at rest. A kept moment every so often rather than every one, because
/// each is a copy of the whole world — and how many are kept is set from how much memory they may have between them,
/// so a finely detailed world keeps fewer and a coarse one more.
///
/// Scrubbing is looking, not changing: the present is kept while the slider moves, and going back to it puts the world
/// exactly as it was. Only choosing to keep a past moment lets go of everything after it.
///
/// Each kept moment also remembers when it was, by whatever clock the caller keeps — the engine has none of its own —
/// so the slider can say how long ago a moment was in seconds rather than in moments, which are a different length on
/// every phone.
public final class PowderRewind {
    /// How many moments apart the kept ones are.
    public let spacing: Int
    /// The most that are kept.
    public private(set) var capacity: Int
    /// The most memory the kept moments may use between them, once it has been set by ``fit(budgetBytes:cellCount:)``.
    ///
    /// Checked against what each kept moment really costs, as well as setting ``capacity``: a world in which grains
    /// have colours of their own costs half as much again for every moment kept, and the capacity alone assumes none.
    public private(set) var budgetBytes: Int?

    private struct Kept {
        var snapshot: PowderHistory.Snapshot
        /// When it was kept, by the caller's clock.
        var time: Double
        /// How much memory it takes.
        var bytes: Int
    }

    private var kept: [Kept] = []
    /// What the kept moments cost between them.
    public private(set) var keptBytes = 0
    /// The world as it was when scrubbing began, so it can be gone back to.
    private var present: PowderHistory.Snapshot?
    /// When scrubbing began, by the caller's clock.
    private var presentTime = 0.0
    private let history = PowderHistory(maximumSteps: 1)
    private var sinceLast = 0

    /// However tight the memory, this many are kept, or there would be nothing worth scrubbing through.
    public static let fewestKept = 3

    public init(spacing: Int = 60, capacity: Int = 20) {
        self.spacing = max(1, spacing)
        self.capacity = max(1, capacity)
    }

    /// How many moments are kept to go back to.
    public var count: Int { kept.count }

    /// How far back the oldest is, in moments.
    public var reach: Int { kept.count * spacing }

    /// Whether the world is being scrubbed through, with the present waiting to be gone back to.
    public var isScrubbing: Bool { present != nil }

    /// The world as it was when scrubbing began, for recording as the point to undo back to when a past moment is
    /// kept.
    public var presentSnapshot: PowderHistory.Snapshot? { present }

    /// Sets how many moments are kept from how much memory they may use between them, for a world of this many cells.
    public func fit(budgetBytes: Int, cellCount: Int) {
        // A cell costs eight bytes in a snapshot: what it is, how hot, how long it has left. Twelve with a colour of
        // its own, which the byte check in `trim` catches.
        let each = max(1, cellCount * 8)
        self.budgetBytes = max(0, budgetBytes)
        capacity = max(Self.fewestKept, min(90, budgetBytes / each))
        trim()
    }

    /// What one kept moment costs, in bytes.
    static func bytes(of snapshot: PowderHistory.Snapshot) -> Int {
        snapshot.type.count * MemoryLayout<ElementID>.size
            + snapshot.temperature.count * MemoryLayout<Float>.size
            + snapshot.life.count * MemoryLayout<UInt16>.size
            + (snapshot.tint?.count ?? 0) * MemoryLayout<UInt32>.size
            + snapshot.population.people.count * MemoryLayout<PowderPerson>.stride
    }

    /// Keeps the world as it is now if it is time to. Call once for every moment the world is stepped.
    ///
    /// - Parameter time: when this is, by the caller's own clock, for saying later how long ago a moment was.
    public func noteMoment(_ engine: PowderEngine, time: Double = 0) {
        guard present == nil else { return }
        // A world that has changed size cannot go back to moments of another size, so they are let go.
        if let first = kept.first, first.snapshot.width != engine.width || first.snapshot.height != engine.height {
            kept.removeAll()
            keptBytes = 0
        }
        sinceLast += 1
        guard sinceLast >= spacing else { return }
        sinceLast = 0
        let snapshot = history.capture(engine)
        let bytes = Self.bytes(of: snapshot)
        kept.append(Kept(snapshot: snapshot, time: time.isFinite ? time : 0, bytes: bytes))
        keptBytes += bytes
        trim()
    }

    /// Lets the oldest go until what is kept is within both the count and the memory.
    private func trim() {
        let budget = budgetBytes ?? .max
        while kept.count > capacity || (kept.count > Self.fewestKept && keptBytes > budget) {
            keptBytes -= kept.removeFirst().bytes
        }
    }

    /// Starts scrubbing: the world as it is now is kept, to come back to.
    ///
    /// - Parameter time: now, by the same clock the moments were kept by.
    public func beginScrub(_ engine: PowderEngine, time: Double = 0) {
        guard present == nil else { return }
        present = history.capture(engine)
        presentTime = time.isFinite ? time : 0
    }

    /// When a moment was, by the caller's clock: nought steps back is the present, while scrubbing.
    public func time(stepsBack: Int) -> Double? {
        if stepsBack <= 0 { return present == nil ? nil : presentTime }
        guard !kept.isEmpty else { return nil }
        return kept[kept.count - min(kept.count, stepsBack)].time
    }

    /// How long before the present a moment was, by the caller's clock, while scrubbing. Nought for the present.
    public func timeBack(stepsBack: Int) -> Double {
        guard present != nil, stepsBack > 0, let then = time(stepsBack: stepsBack) else { return 0 }
        return max(0, presentTime - then)
    }

    /// Shows one moment while scrubbing: nought is the present, one the most recent kept moment, and each step further
    /// another ``spacing`` moments back.
    ///
    /// - Returns: whether it was shown. A moment of another size than the world is refused rather than resizing it.
    @discardableResult
    public func show(_ engine: PowderEngine, stepsBack: Int) -> Bool {
        guard let present else { return false }
        guard let snapshot = stepsBack <= 0 ? present : moment(stepsBack: stepsBack) else { return false }
        guard snapshot.width == engine.width, snapshot.height == engine.height else { return false }
        return history.restore(engine, snapshot)
    }

    /// Stops scrubbing, either keeping a past moment — everything after it is let go, since time runs forward again
    /// from there — or, with nothing to keep, going back to the present exactly as it was.
    ///
    /// - Returns: whether a past moment was kept. When it was, the world's time has gone back to that moment's, which
    ///   ``time(stepsBack:)`` said before this was called.
    @discardableResult
    public func endScrub(_ engine: PowderEngine, keepingStepsBack stepsBack: Int?) -> Bool {
        guard let present else { return false }
        var keptPast = false
        if let stepsBack, stepsBack > 0, let snapshot = moment(stepsBack: stepsBack),
           snapshot.width == engine.width, snapshot.height == engine.height, history.restore(engine, snapshot)
        {
            let at = kept.count - min(kept.count, stepsBack)
            for later in kept[(at + 1)...] { keptBytes -= later.bytes }
            kept.removeSubrange((at + 1)...)
            keptPast = true
        } else if present.width == engine.width, present.height == engine.height {
            history.restore(engine, present)
        }
        self.present = nil
        sinceLast = 0
        return keptPast
    }

    /// Goes straight back to a past moment and keeps it.
    @discardableResult
    public func rewind(_ engine: PowderEngine, stepsBack: Int) -> Bool {
        guard !kept.isEmpty else { return false }
        beginScrub(engine)
        let steps = max(1, min(kept.count, stepsBack + 1))
        guard show(engine, stepsBack: steps) else {
            endScrub(engine, keepingStepsBack: nil)
            return false
        }
        endScrub(engine, keepingStepsBack: steps)
        return true
    }

    /// Forgets everything kept, for a world that has been replaced.
    public func clear() {
        kept.removeAll()
        keptBytes = 0
        present = nil
        sinceLast = 0
    }

    private func moment(stepsBack: Int) -> PowderHistory.Snapshot? {
        guard stepsBack > 0, !kept.isEmpty else { return nil }
        return kept[kept.count - min(kept.count, stepsBack)].snapshot
    }
}

// MARK: - Thermometer

/// A thermometer pushed into one place in the world, read every so often, remembering what it has read.
///
/// The readout under a finger says how hot something is while it is touched; this stays where it was put and keeps
/// reading as things change around it — a kiln warming, a pond freezing — which is what a thermometer is for.
public struct PowderThermometer: Sendable, Hashable {
    public var x: Int
    public var y: Int
    /// The readings, oldest first: at most ``remembered`` of them.
    public private(set) var readings: [Double] = []
    public private(set) var lowest: Double = .infinity
    public private(set) var highest: Double = -.infinity

    /// How many readings are kept for its little graph.
    public static let remembered = 240

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    /// The last reading, or nothing before the first.
    public var current: Double? { readings.last }

    /// Takes a reading. Nothing is read from outside the world.
    public mutating func read(_ engine: PowderEngine) {
        guard engine.isValid(x, y) else { return }
        let value = Double(engine.temperature[engine.index(x, y)])
        guard value.isFinite else { return }
        readings.append(value)
        if readings.count > Self.remembered { readings.removeFirst(readings.count - Self.remembered) }
        lowest = min(lowest, value)
        highest = max(highest, value)
    }

    /// Moves it, forgetting what it read where it was.
    public mutating func move(toX x: Int, y: Int) {
        self.x = x
        self.y = y
        readings.removeAll()
        lowest = .infinity
        highest = -.infinity
    }
}

// MARK: - Measurements, as numbers

/// A powder world's measurements over time, as rows of numbers for a spreadsheet: for somebody learning, a graph they
/// draw themselves says more than any picture.
public final class PowderMeasurements {
    public struct Row: Sendable, Hashable {
        public var seconds: Double
        public var filled: Int
        public var hottest: Double
        public var coldest: Double
        public var average: Double
        public var thermometer: Double?
        public var counts: [ElementID: Int]
    }

    /// The rows, oldest first.
    public private(set) var rows: [Row] = []
    /// The most rows kept: an hour of them at one a second. Past that the oldest go.
    public let limit: Int

    public init(limit: Int = 3_600) {
        self.limit = max(1, limit)
    }

    /// Measures the world as it is now.
    public func sample(_ engine: PowderEngine, seconds: Double, thermometer: Double? = nil) {
        var counts: [ElementID: Int] = [:]
        var filled = 0
        var hottest = -Double.infinity
        var coldest = Double.infinity
        var total = 0.0
        for i in 0 ..< engine.cellCount {
            let id = engine.type[i]
            guard id != Element.empty else { continue }
            filled += 1
            counts[id, default: 0] += 1
            let t = Double(engine.temperature[i])
            guard t.isFinite else { continue }
            hottest = max(hottest, t)
            coldest = min(coldest, t)
            total += t
        }
        let ambient = engine.ambientTemp
        rows.append(Row(
            seconds: seconds.isFinite ? seconds : 0,
            filled: filled,
            hottest: hottest.isFinite ? hottest : ambient,
            coldest: coldest.isFinite ? coldest : ambient,
            average: filled > 0 ? total / Double(filled) : ambient,
            thermometer: thermometer.flatMap { $0.isFinite ? $0 : nil },
            counts: counts
        ))
        if rows.count > limit { rows.removeFirst(rows.count - limit) }
    }

    /// Forgets every row.
    public func clear() { rows.removeAll() }

    /// Forgets the rows measured after a moment, for a world whose time has been rewound to it: what they describe
    /// did not, in the end, happen.
    public func forget(after seconds: Double) {
        guard seconds.isFinite else { return }
        rows.removeAll { $0.seconds > seconds }
    }

    /// The rows as a spreadsheet: a column for each measurement and one for every material that appeared at all.
    ///
    /// - Parameters:
    ///   - name: what to call each material in its column's heading.
    ///   - temperature: turns a temperature in degrees Celsius into whatever scale the reader uses, and says what that
    ///     scale is called, for the headings.
    public func csv(
        name: (ElementID) -> String,
        temperature: (Double) -> Double = { $0 },
        unit: String = "°C"
    ) -> String {
        var materials = Set<ElementID>()
        for row in rows { materials.formUnion(row.counts.keys) }
        let columns = materials.sorted()
        var header = ["seconds", "cells filled", "hottest \(unit)", "coldest \(unit)", "average \(unit)", "thermometer \(unit)"]
        header.append(contentsOf: columns.map { name($0) })
        var lines = [header.map(Self.field).joined(separator: ",")]
        for row in rows {
            var cells = [
                Self.number(row.seconds),
                String(row.filled),
                Self.number(temperature(row.hottest)),
                Self.number(temperature(row.coldest)),
                Self.number(temperature(row.average)),
                row.thermometer.map { Self.number(temperature($0)) } ?? "",
            ]
            cells.append(contentsOf: columns.map { String(row.counts[$0] ?? 0) })
            lines.append(cells.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A number as a spreadsheet reads it: two decimal places at most, no thousands separators.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(rounded)
    }

    /// A heading, quoted when it has anything in it a spreadsheet would split on.
    static func field(_ text: String) -> String {
        guard text.contains(",") || text.contains("\"") || text.contains("\n") else { return text }
        // Every quotation mark inside doubled, which is how a spreadsheet reads one that belongs to the text. Done by
        // hand because the engine imports nothing that would do it.
        var quoted = "\""
        for character in text {
            if character == "\"" { quoted += "\"\"" } else { quoted.append(character) }
        }
        return quoted + "\""
    }
}

// MARK: - Lasso

/// A piece of a world lifted out by the lasso, to be put down somewhere else.
public struct PowderStamp: Sendable, Hashable {
    /// Each cell's place relative to the middle of what was lifted, and what was in it.
    public var offsetsX: [Int]
    public var offsetsY: [Int]
    public var types: [ElementID]
    public var temperatures: [Float]
    public var lives: [UInt16]
    public var tints: [UInt32]
    /// Where its middle was when it was lifted, so it can be put back exactly where it came from.
    public var originX = 0
    public var originY = 0

    public var count: Int { types.count }
}

extension PowderEngine {
    /// Every cell whose middle is inside a loop drawn round it, as places in the grid. The loop is closed from its last
    /// point back to its first.
    public func cells(insideLoop loop: [(x: Double, y: Double)]) -> [Int] {
        guard loop.count >= 3, width > 0, height > 0 else { return [] }
        var left = Double.infinity, right = -Double.infinity, top = Double.infinity, bottom = -Double.infinity
        for point in loop where point.x.isFinite && point.y.isFinite {
            left = min(left, point.x)
            right = max(right, point.x)
            top = min(top, point.y)
            bottom = max(bottom, point.y)
        }
        guard left.isFinite, top.isFinite else { return [] }
        let x0 = max(0, Int(left.rounded(.down)))
        let x1 = min(width - 1, Int(right.rounded(.up)))
        let y0 = max(0, Int(top.rounded(.down)))
        let y1 = min(height - 1, Int(bottom.rounded(.up)))
        guard x0 <= x1, y0 <= y1 else { return [] }
        var inside: [Int] = []
        for y in y0 ... y1 {
            let cy = Double(y) + 0.5
            // Where the loop crosses this row, left to right: a cell is inside between each pair of crossings.
            var crossings: [Double] = []
            var previous = loop.count - 1
            for current in loop.indices {
                let a = loop[current]
                let b = loop[previous]
                if (a.y > cy) != (b.y > cy) {
                    crossings.append(a.x + (cy - a.y) * (b.x - a.x) / (b.y - a.y))
                }
                previous = current
            }
            crossings.sort()
            var pair = 0
            while pair + 1 < crossings.count {
                let from = max(x0, Int((crossings[pair] - 0.5).rounded(.up)))
                let to = min(x1, Int((crossings[pair + 1] - 0.5).rounded(.down)))
                if from <= to {
                    for x in from ... to { inside.append(y * width + x) }
                }
                pair += 2
            }
        }
        return inside
    }

    /// Empties the given cells.
    public func clear(cells: [Int]) {
        for cell in cells where cell >= 0 && cell < cellCount {
            setElement(cell % width, cell / width, Element.empty)
        }
    }

    /// Heats or cools the given cells by an amount, in degrees.
    public func warm(cells: [Int], by degrees: Double) {
        guard degrees.isFinite else { return }
        for cell in cells where cell >= 0 && cell < cellCount && type[cell] != Element.empty {
            temperature[cell] = JS.toFloat32(max(-273, min(10_000, Double(temperature[cell]) + degrees)))
        }
    }

    /// Gives the given cells a colour of their own, or takes their own colours away again with nought. Air is left
    /// alone, as painting in colour leaves it.
    public func tint(cells: [Int], with word: UInt32) {
        for cell in cells where cell >= 0 && cell < cellCount && type[cell] != Element.empty {
            setTint(cell % width, cell / width, word)
        }
    }

    /// Lifts a copy of the given cells, air left out, to be put down elsewhere.
    public func stamp(of cells: [Int]) -> PowderStamp {
        var solid: [Int] = []
        for cell in cells where cell >= 0 && cell < cellCount && type[cell] != Element.empty { solid.append(cell) }
        var stamp = PowderStamp(offsetsX: [], offsetsY: [], types: [], temperatures: [], lives: [], tints: [])
        guard !solid.isEmpty else { return stamp }
        var sumX = 0
        var sumY = 0
        for cell in solid {
            sumX += cell % width
            sumY += cell / width
        }
        let middleX = sumX / solid.count
        let middleY = sumY / solid.count
        stamp.originX = middleX
        stamp.originY = middleY
        for cell in solid {
            stamp.offsetsX.append(cell % width - middleX)
            stamp.offsetsY.append(cell / width - middleY)
            stamp.types.append(type[cell])
            stamp.temperatures.append(temperature[cell])
            stamp.lives.append(life[cell])
            stamp.tints.append(tint[cell])
        }
        return stamp
    }

    /// Puts a lifted piece down with its middle at a cell. What lands off the edge of the world is left out.
    ///
    /// - Returns: how many cells were put down.
    @discardableResult
    public func place(_ stamp: PowderStamp, atX x: Int, y: Int) -> Int {
        var placed = 0
        for at in 0 ..< stamp.count {
            let cx = x + stamp.offsetsX[at]
            let cy = y + stamp.offsetsY[at]
            guard isValid(cx, cy), Element.isKnown(stamp.types[at]) else { continue }
            let temp = Double(stamp.temperatures[at])
            setElement(cx, cy, stamp.types[at], temp: temp.isFinite ? temp : nil, life: Int(stamp.lives[at]))
            if stamp.tints[at] != 0 { setTint(cx, cy, stamp.tints[at]) }
            placed += 1
        }
        return placed
    }
}

// MARK: - A line drawing, for a pen plotter

extension PowderEngine {
    /// The world as lines: every edge between two cells holding different things, joined into the longest straight
    /// runs they make, as a drawing a pen plotter can draw — or anything else that reads SVG.
    ///
    /// Lines rather than filled squares because a plotter draws with a pen: what it can draw of a world is where one
    /// thing meets another. Air counts as a thing, so the outline of everything is there too.
    ///
    /// - Parameter cell: how long one cell's edge is in the drawing, in millimetres.
    public func outlineSVG(cellMillimetres cell: Double = 1) -> String {
        Self.outlineSVG(
            types: Array(UnsafeBufferPointer(start: type, count: cellCount)),
            width: width,
            height: height,
            cellMillimetres: cell
        )
    }

    /// The same drawing, made from a copy of what is in each cell rather than from the engine itself — so it can be
    /// drawn somewhere other than where the engine is being stepped, while the world carries on.
    public static func outlineSVG(
        types type: [ElementID],
        width: Int,
        height: Int,
        cellMillimetres cell: Double = 1
    ) -> String {
        guard width > 0, height > 0, type.count >= width * height else {
            return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"0mm\" height=\"0mm\" viewBox=\"0 0 0 0\"></svg>"
        }
        let size = cell.isFinite && cell > 0 ? cell : 1
        func number(_ value: Double) -> String {
            let whole = (value * 100).rounded() / 100
            return whole == whole.rounded() ? String(Int(whole)) : String(whole)
        }
        var lines: [String] = []
        // Horizontal edges: between each row and the one below it, and along the top and bottom of the world.
        for boundary in 0 ... height {
            var runStart: Int?
            for x in 0 ... width {
                let differs: Bool
                if x == width {
                    differs = false
                } else {
                    let above = boundary > 0 ? type[(boundary - 1) * width + x] : Element.empty
                    let below = boundary < height ? type[boundary * width + x] : Element.empty
                    differs = above != below
                }
                if differs, runStart == nil { runStart = x }
                if !differs, let start = runStart {
                    lines.append("M\(number(Double(start) * size)) \(number(Double(boundary) * size))H\(number(Double(x) * size))")
                    runStart = nil
                }
            }
        }
        // Vertical edges: between each column and the one to its right.
        for boundary in 0 ... width {
            var runStart: Int?
            for y in 0 ... height {
                let differs: Bool
                if y == height {
                    differs = false
                } else {
                    let left = boundary > 0 ? type[y * width + boundary - 1] : Element.empty
                    let right = boundary < width ? type[y * width + boundary] : Element.empty
                    differs = left != right
                }
                if differs, runStart == nil { runStart = y }
                if !differs, let start = runStart {
                    lines.append("M\(number(Double(boundary) * size)) \(number(Double(start) * size))V\(number(Double(y) * size))")
                    runStart = nil
                }
            }
        }
        let w = number(Double(width) * size)
        let h = number(Double(height) * size)
        var svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(w)mm\" height=\"\(h)mm\" viewBox=\"0 0 \(w) \(h)\">"
        svg += "<path fill=\"none\" stroke=\"black\" stroke-width=\"\(number(size * 0.25))\" stroke-linecap=\"square\" d=\""
        svg += lines.joined(separator: " ")
        svg += "\"/></svg>"
        return svg
    }

    /// How many separate straight lines the drawing is made of, for a plotter's time estimate and for tests.
    public func outlineLineCount() -> Int {
        var count = 0
        let svg = outlineSVG()
        for character in svg where character == "M" { count += 1 }
        return count
    }
}
