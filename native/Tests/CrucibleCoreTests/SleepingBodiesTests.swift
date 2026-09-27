import Testing

@testable import CrucibleCore

/// Bodies that have come to rest being left alone.
///
/// ## What this feature is worth, measured rather than assumed
///
/// It pays for itself completely in a world where bodies stop: a crowd whose air has slowed it to a halt, a crowd
/// resting on the floor, a shape held still. In those, every body falls asleep and the moment costs almost nothing.
///
/// It is worth little in a dense pile with bodies pushing each other apart — and that is a fact about the field rather
/// than about sleep. Measured here: in such a pile the middle body travels **eight pixels in a quarter of a second**,
/// for ever, at every bounciness the field offers including none. Gravity presses the pile together and the contact pass
/// shoves it apart again, endlessly. Nothing in that pile is resting, so nothing in it is left alone, and the test below
/// says so in numbers rather than pretending otherwise.
@Suite("Bodies that have come to rest")
struct SleepingBodiesTests {
    /// A crowd in a world of the given kind, left long enough to do whatever it is going to do.
    private func crowd(
        sleeping: Bool,
        collide: Bool,
        gravity: Double,
        damping: Double = 0.9,
        elasticity: Double = 0.05,
        bodies: Int = 3_000,
        moments: Int = 700,
        depth: Bool = false
    ) -> ParticleEngine {
        let field = ParticleEngine(width: 300, height: 400, seed: 20_260_927)
        _ = field.setMaxParticles(20_000)
        if depth { _ = field.setDepthEnabled(true) }
        field.gravityY = gravity
        field.damping = damping
        field.elasticity = elasticity
        field.collisionsEnabled = collide
        field.sleepingEnabled = sleeping
        var generator = Mulberry32(seed: 5)
        field.swarm.spawn(count: bodies, width: 300, height: 400, color: 0xFFFF_FFFF, budget: 20_000, rng: &generator)
        for _ in 0 ..< moments { field.step() }
        return field
    }

    @Test("A crowd that comes to rest is left alone entirely")
    func restingCrowdsSleep() {
        // Three worlds where bodies genuinely stop: resting on the floor, drifting to a halt, and both.
        for (what, field) in [
            ("resting on the floor", crowd(sleeping: true, collide: false, gravity: 0.3)),
            ("drifting to a halt", crowd(sleeping: true, collide: true, gravity: 0)),
            ("both", crowd(sleeping: true, collide: false, gravity: 0)),
        ] {
            #expect(
                field.sleepingCount == field.bodyCount,
                "\(what): only \(field.sleepingCount) of \(field.bodyCount) were left alone"
            )
            #expect(field.swarm.isAsleep(0))
            #expect(field.inspect().isHealthy)
        }

        // Switched off, nothing is ever left alone however long it sits there.
        let awake = crowd(sleeping: false, collide: false, gravity: 0.3)
        #expect(awake.sleepingCount == 0)
        #expect(!awake.swarm.isAsleep(0))
    }

    @Test("Nothing falls asleep on the way down")
    func nothingSleepsInFlight() {
        let falling = crowd(sleeping: true, collide: false, gravity: 0.3, moments: 15)
        #expect(falling.sleepingCount == 0, "\(falling.sleepingCount) bodies fell asleep while still falling")
    }

    @Test("A crowd at rest is in exactly the same place whether or not it is left alone")
    func itChangesNothing() {
        let sleeping = crowd(sleeping: true, collide: false, gravity: 0.3)
        let awake = crowd(sleeping: false, collide: false, gravity: 0.3)
        #expect(sleeping.swarm.count == awake.swarm.count)
        var worst = 0.0
        for i in 0 ..< sleeping.swarm.count {
            let dx = Double(sleeping.swarm.positions[i * 2]) - Double(awake.swarm.positions[i * 2])
            let dy = Double(sleeping.swarm.positions[i * 2 + 1]) - Double(awake.swarm.positions[i * 2 + 1])
            worst = max(worst, (dx * dx + dy * dy).squareRoot())
        }
        // Under a pixel: a body left alone stops taking the last vanishing fractions of a pixel it would otherwise
        // have crept, and that is the whole of the difference.
        #expect(worst < 1, "a body ended up \(worst) pixels from where it would have been")
    }

    @Test("Leaving a resting crowd alone is several times faster")
    func itIsFaster() {
        let sleeping = crowd(sleeping: true, collide: false, gravity: 0.3, bodies: 20_000)
        let awake = crowd(sleeping: false, collide: false, gravity: 0.3, bodies: 20_000)
        #expect(sleeping.sleepingCount == sleeping.bodyCount, "\(sleeping.sleepingCount) asleep, so there is nothing to save")

        func time(_ field: ParticleEngine) -> Double {
            let started = ContinuousClock.now
            for _ in 0 ..< 300 { field.step() }
            let took = ContinuousClock.now - started
            return Double(took.components.seconds) + Double(took.components.attoseconds) / 1e18
        }
        // Warmed first, so neither pays for the first touch of its own memory.
        _ = time(sleeping)
        _ = time(awake)
        let withSleep = time(sleeping)
        let without = time(awake)
        #expect(
            withSleep < without * 0.6,
            "a resting crowd of twenty thousand cost \(withSleep)s left alone and \(without)s walked every moment"
        )
    }

    @Test("Everything that could disturb a resting body wakes it")
    func everythingWakesThem() {
        for change in ["gravity", "air", "speed", "edges", "collisions", "size", "off"] {
            let field = crowd(sleeping: true, collide: false, gravity: 0.3, bodies: 600, moments: 400)
            #expect(field.sleepingCount > 0, "nothing was asleep before changing the \(change)")
            switch change {
            case "gravity": field.gravityY = -0.4
            case "air": field.damping = 0.99
            case "speed": field.maxSpeed = 12
            case "edges": field.boundaryMode = .wrap
            case "collisions": field.collisionsEnabled = true
            case "size": field.resize(width: 400, height: 500)
            case "off": field.sleepingEnabled = false
            default: break
            }
            #expect(field.sleepingCount == 0, "changing the \(change) left \(field.sleepingCount) bodies asleep")
        }

        // A finger reaching in.
        let touched = crowd(sleeping: true, collide: false, gravity: 0.3, bodies: 600, moments: 400)
        #expect(touched.sleepingCount > 0)
        touched.step(mouseX: 150, mouseY: 390, mouseActive: true)
        #expect(touched.sleepingCount == 0, "a finger left bodies asleep")
    }

    @Test("Something landing on a resting crowd makes it notice")
    func somethingLandingWakesThem() {
        // Bodies pushing each other apart, with no gravity, so the crowd genuinely comes to rest and stays there.
        let field = crowd(sleeping: true, collide: true, gravity: 0, bodies: 1_500)
        let asleepBefore = field.sleepingCount
        #expect(asleepBefore == field.bodyCount)

        // One more of the crowd, thrown through the middle of it. One of the crowd rather than a body of its own,
        // because the two kinds do not touch each other: an object body passes straight through the crowd, which is
        // how the field has always worked.
        _ = field.swarm.append(x: 6, y: 200, velocityX: 14, velocityY: 0, color: 0xFFFF_FFFF, budget: 20_000, mass: 6)
        // Watched as it happens rather than counted at the end: what it hits wakes, is shoved, and then — with nothing
        // moving it any more — goes back to sleep within a quarter of a second. Counting afterwards would see the crowd
        // asleep again and conclude, wrongly, that nothing had noticed.
        var fewestAsleep = field.sleepingCount
        for _ in 0 ..< 60 {
            field.step()
            fewestAsleep = min(fewestAsleep, field.sleepingCount)
        }
        #expect(
            fewestAsleep < asleepBefore,
            "a crowd of \(asleepBefore) stayed asleep while something was thrown through it"
        )
        // And it settles again afterwards, rather than being left awake for ever by one disturbance.
        #expect(field.sleepingCount >= asleepBefore, "the crowd did not settle again: \(field.sleepingCount) asleep")
        #expect(field.inspect().isHealthy)
    }

    @Test("Resting bodies in the box are left alone too")
    func theBoxSleepsAsWell() {
        let field = crowd(sleeping: true, collide: false, gravity: 0.3, bodies: 2_000, depth: true)
        #expect(field.sleepingCount == field.bodyCount, "\(field.sleepingCount) of \(field.bodyCount) settled in the box")
        #expect(field.inspect().isHealthy)
    }

    @Test("A dense pile with bodies pushing each other apart never comes to rest, and the numbers say so")
    func aPileNeverRests() {
        // This is a measurement of the field's own behaviour, not of sleep. It is here because it is the reason sleep
        // helps a settled crowd and not a pile, and because it is exactly the kind of claim that gets made loosely.
        let field = crowd(sleeping: true, collide: true, gravity: 0.3, bodies: 3_000, moments: 900)
        var before: [Double] = []
        for i in 0 ..< field.swarm.count {
            before.append(Double(field.swarm.positions[i * 2]))
            before.append(Double(field.swarm.positions[i * 2 + 1]))
        }
        for _ in 0 ..< 30 { field.step() }
        var travelled: [Double] = []
        for i in 0 ..< field.swarm.count {
            let dx = Double(field.swarm.positions[i * 2]) - before[i * 2]
            let dy = Double(field.swarm.positions[i * 2 + 1]) - before[i * 2 + 1]
            travelled.append((dx * dx + dy * dy).squareRoot())
        }
        travelled.sort()
        let middle = travelled[travelled.count / 2]
        // Eight pixels a quarter of a second when this was written. The claim is only that it is far from still.
        #expect(middle > 2, "the middle body moved \(middle) pixels in a quarter of a second, so the pile does settle")
        #expect(
            field.sleepingCount < field.bodyCount / 4,
            "\(field.sleepingCount) of \(field.bodyCount) slept in a pile that is still moving"
        )
    }
}
