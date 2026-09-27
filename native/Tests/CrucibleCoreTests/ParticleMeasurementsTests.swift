import Testing

@testable import CrucibleCore

/// The particle field's measurements, as numbers for a spreadsheet.
@Suite("The field's measurements, as numbers")
struct ParticleMeasurementsTests {
    @Test("Speed, energy, the middle and the spread come out right for bodies whose motion is known")
    func knownBodies() {
        let engine = ParticleEngine(width: 400, height: 300, seed: 1)
        // Two ordinary bodies and one of the crowd: speeds five, nought and one; masses two, two and four.
        engine.addParticle(x: 100, y: 100, velocityX: 3, velocityY: 4, mass: 2)
        engine.addParticle(x: 300, y: 100, velocityX: 0, velocityY: 0, mass: 2)
        engine.swarm.append(x: 200, y: 200, velocityX: 0, velocityY: -1, color: 0, budget: 10, mass: 4)

        let measurements = ParticleMeasurements()
        measurements.sample(engine, seconds: 1.5)
        let row = measurements.rows[0]
        #expect(row.seconds == 1.5)
        #expect(row.bodies == 3)
        #expect(abs(row.averageSpeed - 2) < 1e-9, "average speed \(row.averageSpeed)")
        #expect(row.fastest == 5)
        // Half of two times twenty-five, and half of four times one.
        #expect(abs(row.energy - 27) < 1e-9, "energy \(row.energy)")
        // Balanced by weight: the heavier crowd body pulls the middle towards itself.
        #expect(abs(row.middleX - 200) < 1e-9 && abs(row.middleY - 150) < 1e-9, "middle \(row.middleX), \(row.middleY)")
        #expect(row.middleZ == nil, "a flat field was given a depth")
        #expect(abs(row.spread - (27_500.0 / 3).squareRoot()) < 1e-9, "spread \(row.spread)")
        #expect(row.rabbits == nil && row.foxes == nil)
    }

    @Test("Foxes and rabbits are counted, and the sheet has only the columns it needs")
    func herdAndColumns() {
        let engine = ParticleEngine(width: 400, height: 300, seed: 2)
        engine.spawnFoxesAndRabbits(rabbits: 20, foxes: 3)
        let measurements = ParticleMeasurements()
        measurements.sample(engine, seconds: 0)
        #expect(measurements.rows[0].rabbits == 20 && measurements.rows[0].foxes == 3)
        let lines = measurements.csv().split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0] == "seconds,bodies,average speed (points a moment),fastest (points a moment),energy of motion,"
            + "middle across (points),middle down (points),spread (points),rabbits,foxes")
        #expect(lines[1].hasPrefix("0,23,"), "\(lines[1])")
        #expect(lines[1].hasSuffix(",20,3"), "\(lines[1])")

        let plain = ParticleEngine(width: 400, height: 300, seed: 2)
        plain.addParticle(x: 5, y: 5, velocityX: 0, velocityY: 0)
        let sheet = ParticleMeasurements()
        sheet.sample(plain, seconds: 0)
        #expect(!sheet.csv().contains("rabbits"), "an ordinary field's sheet had columns for rabbits")
        #expect(!sheet.csv().contains("into the box"), "a flat field's sheet had a column for depth")
    }

    @Test("In 3D the middle has a depth, and the sheet a column for it")
    func depth() {
        let engine = ParticleEngine(width: 400, height: 300, seed: 3)
        #expect(engine.setDepthEnabled(true))
        engine.addParticle(x: 100, y: 100, velocityX: 0, velocityY: 0, mass: 1, z: 40, velocityZ: 2)
        engine.addParticle(x: 100, y: 100, velocityX: 0, velocityY: 0, mass: 1, z: -20)
        let measurements = ParticleMeasurements()
        measurements.sample(engine, seconds: 0)
        let row = measurements.rows[0]
        #expect(row.middleZ == 10)
        // Speed into the box counts as speed.
        #expect(row.fastest == 2)
        #expect(abs(row.spread - 30) < 1e-9, "spread \(row.spread)")
        #expect(measurements.csv().contains("middle into the box (points)"))
    }

    @Test("Bodies that are not numbers are left out, the oldest rows go, and going back in time forgets")
    func nonsenseLimitAndForgetting() {
        let engine = ParticleEngine(width: 400, height: 300, seed: 4)
        engine.addParticle(x: .nan, y: 5, velocityX: 1, velocityY: 1)
        engine.addParticle(x: 10, y: 20, velocityX: 1, velocityY: 0)
        let measurements = ParticleMeasurements(limit: 2)
        for second in 0 ..< 3 { measurements.sample(engine, seconds: Double(second)) }
        #expect(measurements.rows.count == 2)
        #expect(measurements.rows[0].seconds == 1, "the oldest row was not the one let go")
        #expect(measurements.rows[0].bodies == 1, "a body with no place was counted")
        #expect(measurements.rows[0].middleX == 10 && measurements.rows[0].averageSpeed == 1)
        #expect(measurements.rows[0].energy.isFinite && measurements.rows[0].spread == 0)
        measurements.forget(after: 1.5)
        #expect(measurements.rows.count == 1)

        // An empty field has its middle in the middle of the world, and nothing moving.
        let empty = ParticleMeasurements()
        empty.sample(ParticleEngine(width: 400, height: 300, seed: 5), seconds: 0)
        #expect(empty.rows[0].bodies == 0 && empty.rows[0].middleX == 200 && empty.rows[0].middleY == 150)
        #expect(empty.rows[0].averageSpeed == 0 && empty.rows[0].energy == 0)
    }
}
