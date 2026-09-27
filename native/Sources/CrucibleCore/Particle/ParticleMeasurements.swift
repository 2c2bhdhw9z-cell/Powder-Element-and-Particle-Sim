/// A particle field's measurements over time, as rows of numbers for a spreadsheet — the field's half of "something to
/// plot". An orbit that keeps its energy, a crowd spreading out as it cools, foxes and rabbits chasing each other up and
/// down: each is a graph somebody can draw for themselves from these.
public final class ParticleMeasurements {
    public struct Row: Sendable, Hashable {
        public var seconds: Double
        public var bodies: Int
        /// The average speed of every body, in points a moment.
        public var averageSpeed: Double
        public var fastest: Double
        /// The energy of motion of the whole field: half of each body's mass times its speed squared, added up.
        public var energy: Double
        /// The middle of the field by weight — where it would balance.
        public var middleX: Double
        public var middleY: Double
        /// How far into the box the middle is, when the field has depth.
        public var middleZ: Double?
        /// How spread out the bodies are: the typical distance of a body from the middle.
        public var spread: Double
        /// How many rabbits and foxes there are, when they are what the field is showing.
        public var rabbits: Int?
        public var foxes: Int?
    }

    /// The rows, oldest first.
    public private(set) var rows: [Row] = []
    /// The most rows kept: an hour of them at one a second. Past that the oldest go.
    public let limit: Int

    public init(limit: Int = 3_600) {
        self.limit = max(1, limit)
    }

    /// Measures the field as it is now.
    ///
    /// One pass over every body, the crowd included — a few milliseconds at a million, once a second. A body whose
    /// place or speed is not a number is left out rather than turning every total into one that is not.
    public func sample(_ engine: ParticleEngine, seconds: Double) {
        var bodies = 0
        var speedTotal = 0.0
        var fastest = 0.0
        var energy = 0.0
        var weight = 0.0
        var sumX = 0.0
        var sumY = 0.0
        var sumZ = 0.0
        let depth = engine.depthEnabled

        func count(x: Double, y: Double, z: Double, vx: Double, vy: Double, vz: Double, mass: Double) {
            guard x.isFinite, y.isFinite, z.isFinite, vx.isFinite, vy.isFinite, vz.isFinite else { return }
            let m = mass.isFinite && mass > 0 ? mass : 1
            let squared = vx * vx + vy * vy + vz * vz
            let speed = squared.squareRoot()
            bodies += 1
            speedTotal += speed
            fastest = max(fastest, speed)
            energy += 0.5 * m * squared
            weight += m
            sumX += m * x
            sumY += m * y
            sumZ += m * z
        }

        for body in engine.particles {
            count(
                x: body.x, y: body.y, z: depth ? body.z : 0,
                vx: body.velocityX, vy: body.velocityY, vz: depth ? body.velocityZ : 0,
                mass: body.mass
            )
        }
        let swarm = engine.swarm
        let crowdDepth = depth && swarm.hasDepth
        for i in 0 ..< swarm.count {
            count(
                x: Double(swarm.positions[i * 2]), y: Double(swarm.positions[i * 2 + 1]),
                z: crowdDepth ? Double(swarm.depths[i]) : 0,
                vx: Double(swarm.velocities[i * 2]), vy: Double(swarm.velocities[i * 2 + 1]),
                vz: crowdDepth ? Double(swarm.depthVelocities[i]) : 0,
                mass: Double(swarm.masses[i])
            )
        }

        let middleX = weight > 0 ? sumX / weight : engine.width / 2
        let middleY = weight > 0 ? sumY / weight : engine.height / 2
        let middleZ = weight > 0 ? sumZ / weight : 0

        // A second pass for the spread, which needs the middle first. Measured unweighted, as how far a typical body
        // is from the middle.
        var spreadTotal = 0.0
        var spreadCount = 0
        func distance(x: Double, y: Double, z: Double) {
            guard x.isFinite, y.isFinite, z.isFinite else { return }
            let dx = x - middleX
            let dy = y - middleY
            let dz = z - middleZ
            spreadTotal += dx * dx + dy * dy + dz * dz
            spreadCount += 1
        }
        for body in engine.particles {
            guard body.velocityX.isFinite, body.velocityY.isFinite, !depth || body.velocityZ.isFinite else { continue }
            distance(x: body.x, y: body.y, z: depth ? body.z : middleZ)
        }
        for i in 0 ..< swarm.count {
            let vx = Double(swarm.velocities[i * 2])
            let vy = Double(swarm.velocities[i * 2 + 1])
            guard vx.isFinite, vy.isFinite, !crowdDepth || swarm.depthVelocities[i].isFinite else { continue }
            distance(
                x: Double(swarm.positions[i * 2]),
                y: Double(swarm.positions[i * 2 + 1]),
                z: crowdDepth ? Double(swarm.depths[i]) : middleZ
            )
        }

        let herd = engine.predatorsEnabled ? engine.herdCount : nil
        rows.append(Row(
            seconds: seconds.isFinite ? seconds : 0,
            bodies: bodies,
            averageSpeed: bodies > 0 ? speedTotal / Double(bodies) : 0,
            fastest: fastest,
            energy: energy,
            middleX: middleX,
            middleY: middleY,
            middleZ: depth ? middleZ : nil,
            spread: spreadCount > 0 ? (spreadTotal / Double(spreadCount)).squareRoot() : 0,
            rabbits: herd?.rabbits,
            foxes: herd?.foxes
        ))
        if rows.count > limit { rows.removeFirst(rows.count - limit) }
    }

    /// Forgets every row.
    public func clear() { rows.removeAll() }

    /// Forgets the rows measured after a moment, for a field whose time has gone back to it.
    public func forget(after seconds: Double) {
        guard seconds.isFinite else { return }
        rows.removeAll { $0.seconds > seconds }
    }

    /// The rows as a spreadsheet. The depth column appears only when some row had depth, and the rabbits and foxes
    /// only when some row had them, so an ordinary field's sheet is not full of empty columns.
    public func csv() -> String {
        let hasDepth = rows.contains { $0.middleZ != nil }
        let hasHerd = rows.contains { $0.rabbits != nil }
        var header = [
            "seconds", "bodies", "average speed (points a moment)", "fastest (points a moment)", "energy of motion",
            "middle across (points)", "middle down (points)",
        ]
        if hasDepth { header.append("middle into the box (points)") }
        header.append("spread (points)")
        if hasHerd { header.append(contentsOf: ["rabbits", "foxes"]) }

        var lines = [header.map(PowderMeasurements.field).joined(separator: ",")]
        for row in rows {
            var cells = [
                PowderMeasurements.number(row.seconds),
                String(row.bodies),
                PowderMeasurements.number(row.averageSpeed),
                PowderMeasurements.number(row.fastest),
                PowderMeasurements.number(row.energy),
                PowderMeasurements.number(row.middleX),
                PowderMeasurements.number(row.middleY),
            ]
            if hasDepth { cells.append(row.middleZ.map(PowderMeasurements.number) ?? "") }
            cells.append(PowderMeasurements.number(row.spread))
            if hasHerd {
                cells.append(row.rabbits.map { String($0) } ?? "")
                cells.append(row.foxes.map { String($0) } ?? "")
            }
            lines.append(cells.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
