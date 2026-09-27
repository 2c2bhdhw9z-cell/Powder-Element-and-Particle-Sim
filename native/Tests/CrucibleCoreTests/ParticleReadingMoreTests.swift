import Testing

@testable import CrucibleCore

/// The Look tool's springs, liquid, charge, swirl and loops, and the knocks for a supernova and a slam.
@Suite("What the Look tool reads, and what the hand feels")
struct ParticleReadingMoreTests {
    private func field(seed: UInt32 = 4) -> ParticleEngine {
        let engine = ParticleEngine(width: 400, height: 700, seed: seed)
        engine.screenWidth = 400
        engine.screenHeight = 700
        return engine
    }

    private func push(_ reading: ParticleReading, named prefix: String) -> ParticleReading.Push? {
        reading.pushes.first { $0.name.hasPrefix(prefix) }
    }

    @Test("A spring's push is exactly what the moment gives the body")
    func springsAreReal() {
        let engine = field()
        engine.gravityY = 0
        engine.damping = 1
        engine.addParticle(x: 100, y: 300, velocityX: 0, velocityY: 0, radius: 3, mass: 2, charge: 0)
        engine.addParticle(x: 180, y: 300, velocityX: 0, velocityY: 0, radius: 3, mass: 1, charge: 0, isFixed: true)
        engine.addSpring(a: 0, b: 1, rest: 50, k: 0.2)
        let reading = engine.reading(nearX: 100, y: 300)
        let spring = push(reading, named: "The spring")
        engine.step()
        let gained = engine.particles[0].velocityX
        #expect(spring != nil)
        #expect(abs((spring?.x ?? 0) - gained) < 1e-9, "the reading said \(spring?.x ?? 0), the moment gave \(gained)")
        #expect((spring?.x ?? 0) > 0, "a stretched spring should pull toward its other end")
    }

    @Test("A muscle is read as a muscle, and a jellyfish's bell has them")
    func musclesAreNamed() {
        let engine = field()
        #expect(engine.loadArrangement("jellyfish"))
        guard let index = engine.springs.first(where: \.isMuscle)?.a else {
            Issue.record("no muscles in the jellyfish")
            return
        }
        let body = engine.particles[index]
        let reading = engine.reading(nearX: body.x, y: body.y, within: 1)
        #expect(push(reading, named: "Its muscle") != nil, "no muscle in \(reading.pushes.map(\.name))")
    }

    @Test("The liquid's push is the one it really gave")
    func liquidIsReal() {
        let engine = field()
        #expect(engine.loadArrangement("pour"))
        for _ in 0 ..< 30 { engine.step() }
        let index = engine.swarm.count / 2
        let x = Double(engine.swarm.positions[index * 2])
        let y = Double(engine.swarm.positions[index * 2 + 1])
        let reading = engine.reading(nearX: x, y: y, within: 0.001)
        #expect(reading.isCrowd)
        let liquid = push(reading, named: "The liquid")
        #expect(liquid != nil, "no liquid in \(reading.pushes.map(\.name))")
        if let liquid, let real = engine.fluid.lastPush(at: index) {
            #expect(liquid.x == real.x && liquid.y == real.y)
        }
    }

    @Test("A recorded loop is read as what it is doing here")
    func loopsAreRead() {
        let engine = field()
        engine.mouseMode = .vortex
        engine.mouseRadius = 200
        #expect(engine.beginLoopRecording())
        for moment in 0 ..< 30 {
            engine.step(mouseX: 200 + Double(moment), mouseY: 350, mouseActive: true)
        }
        #expect(engine.finishLoopRecording())
        let reading = engine.readingAt(x: 220, y: 380)
        #expect(push(reading, named: "Your recorded swirl") != nil, "no loop in \(reading.pushes.map(\.name))")
    }

    @Test("A supernova is felt the moment it goes off, and only then")
    func supernovaKnocks() {
        let engine = field()
        #expect(engine.loadArrangement("supernova"))
        engine.step()
        #expect(engine.bigMomentStrength == 1)
        engine.step()
        #expect(engine.bigMomentStrength == 0)
    }

    @Test("A crowd slamming into the floor is felt once, and a steady stream is not felt for ever")
    func slamsKnock() {
        let engine = field()
        engine.setMaxParticles(100_000)
        engine.gravityY = 0
        engine.collisionsEnabled = false
        // A block of bodies thrown hard at the floor.
        for index in 0 ..< 8_000 {
            _ = engine.swarm.append(
                x: 20 + Double(index % 180) * 2,
                y: 640 + Double(index / 180) * 0.5,
                velocityX: 0,
                velocityY: 9,
                color: 0,
                budget: 100_000
            )
        }
        var felt: [Double] = []
        for _ in 0 ..< 60 {
            engine.step()
            if engine.bigMomentStrength > 0 { felt.append(engine.bigMomentStrength) }
        }
        #expect(!felt.isEmpty, "a slam of eight thousand bodies was not felt")
        #expect(felt.count <= 5, "one slam was felt \(felt.count) times")

        // Resting on the floor under gravity: hitting it every moment, but gently, which is not a slam.
        let resting = field()
        resting.setMaxParticles(100_000)
        resting.collisionsEnabled = false
        for index in 0 ..< 8_000 {
            _ = resting.swarm.append(
                x: 20 + Double(index % 180) * 2, y: 699, velocityX: 0, velocityY: 0, color: 0, budget: 100_000
            )
        }
        var restingFelt = 0
        for _ in 0 ..< 120 {
            resting.step()
            if resting.bigMomentStrength > 0 { restingFelt += 1 }
        }
        #expect(restingFelt == 0, "a crowd lying on the floor knocked \(restingFelt) times")
    }
}

extension ParticleEngine {
    /// A reading at a place, of whatever is nearest within a generous reach.
    fileprivate func readingAt(x: Double, y: Double) -> ParticleReading {
        if particles.isEmpty && swarm.count == 0 {
            addParticle(x: x, y: y, velocityX: 0, velocityY: 0, radius: 2, mass: 1, charge: 0)
        }
        return reading(nearX: x, y: y, within: 400)
    }
}
