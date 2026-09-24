import Testing

@testable import CrucibleCore

/// The three bridges between the two chambers.
///
/// No recorded comparison for these, and for a defensible reason: the reference decides what a
/// settling particle becomes by searching for a substring inside a CSS colour string, and there is no
/// CSS colour string here — colours are packed numbers. The *intent* ported cleanly; the mechanism
/// could not, so there is nothing to compare byte for byte.
///
/// What is checked instead is the behaviour, including the several ways these could go quietly wrong:
/// destroying something someone built, overwriting material that was already there, or leaving the
/// springs of a cloth pointing at bodies that no longer exist.
@Suite("The two chambers' bridges")
struct HybridTests {
    private func makeField(width: Double = 400, height: Double = 800) -> ParticleEngine {
        ParticleEngine(width: width, height: height, seed: 77)
    }

    private func makePowder(width: Int = 100, height: Int = 200) -> PowderEngine {
        PowderEngine(width: width, height: height, seed: 77)
    }

    /// A body resting on the floor of the field, which is what settling is looking for.
    @discardableResult
    private func addResting(
        to field: ParticleEngine,
        x: Double,
        color: PackedColor? = nil
    ) -> Int {
        field.addParticle(
            x: x,
            y: field.height - 4,
            velocityX: 0,
            velocityY: 0,
            color: color ?? PackedColor(r: 200, g: 180, b: 120)
        )
    }

    // MARK: Sparks from an explosion

    @Test("An explosion throws sparks into the field")
    func burstMakesSparks() {
        let powder = makePowder()
        let field = makeField()
        #expect(field.bodyCount == 0)

        Hybrid.burst(fromPowder: powder, into: field, gridX: 50, gridY: 100, radius: 10)
        // Four per unit of radius, between two dozen and a couple of hundred.
        #expect(field.bodyCount == 40)
    }

    @Test("A bigger explosion throws more sparks, within limits")
    func burstScalesWithRadius() {
        let powder = makePowder()

        func sparks(radius: Int) -> Int {
            let field = makeField()
            Hybrid.burst(fromPowder: powder, into: field, gridX: 50, gridY: 100, radius: radius)
            return field.bodyCount
        }

        // A firecracker and a nuke should look different.
        #expect(sparks(radius: 2) < sparks(radius: 20))
        // But a tiny one still produces something worth seeing, and an enormous one does not flood
        // the field.
        #expect(sparks(radius: 1) == 24)
        #expect(sparks(radius: 1000) == 220)
    }

    /// The grid is deliberately much coarser than the field, so a position in one means nothing in the
    /// other without scaling. Getting this wrong puts every spark in the top-left corner.
    @Test("Sparks appear where the explosion was, not where its grid numbers point")
    func burstScalesPosition() {
        let powder = makePowder(width: 100, height: 200)
        let field = makeField(width: 400, height: 800)

        // The middle of the grid should be the middle of the field.
        Hybrid.burst(fromPowder: powder, into: field, gridX: 50, gridY: 100, radius: 6)
        let sparks = field.particles
        #expect(!sparks.isEmpty)

        let averageX = sparks.map(\.x).reduce(0, +) / Double(sparks.count)
        let averageY = sparks.map(\.y).reduce(0, +) / Double(sparks.count)
        // Scattered by a few units either way, so this is a neighbourhood rather than a point.
        #expect(abs(averageX - 200) < 20, "sparks centred at x \(averageX), expected about 200")
        #expect(abs(averageY - 400) < 20, "sparks centred at y \(averageY), expected about 400")
    }

    @Test("Sparks are thrown upward and outward")
    func sparksFly() {
        let powder = makePowder()
        let field = makeField()
        Hybrid.burst(fromPowder: powder, into: field, gridX: 50, gridY: 100, radius: 10)

        let sparks = field.particles
        // Biased upward, which in these coordinates means negative. Not every one — the bias is two
        // units against a speed of up to nine — but most.
        let rising = sparks.filter { $0.velocityY < 0 }.count
        #expect(rising > sparks.count / 2, "only \(rising) of \(sparks.count) sparks rise")
        // And they have somewhere to be going.
        #expect(sparks.allSatisfy { $0.velocityX != 0 || $0.velocityY != 0 })
        // Every one should expire, so a hundred explosions do not leave the field permanently full.
        #expect(sparks.allSatisfy { $0.lifespan != nil })
    }

    /// The sparks come out of the *field's* random numbers, not the grid's. Taking them from the grid
    /// would mean an explosion consumed a different number of the grid's draws depending on whether
    /// this bridge was switched on — and the whole powder world would then unfold differently.
    @Test("Sparks do not disturb the powder world's random stream")
    func burstLeavesThePowderStreamAlone() {
        let powder = makePowder()
        let field = makeField()
        let before = powder.rng.state

        Hybrid.burst(fromPowder: powder, into: field, gridX: 50, gridY: 100, radius: 12)
        #expect(powder.rng.state == before, "the grid's generator moved")
        #expect(field.rng.state != before, "the field's generator should have moved")
    }

    // MARK: Settling

    @Test("A resting body becomes a grain of sand")
    func restingBodySettles() {
        let field = makeField()
        let powder = makePowder()
        addResting(to: field, x: 200)

        let settled = Hybrid.autoSettle(from: field, into: powder)
        #expect(settled == 1)
        #expect(field.bodyCount == 0, "the body should be gone once it has become sand")
        #expect(powder.activeParticleCount == 1)
    }

    @Test("A blue body becomes water instead")
    func blueBodySettlesAsWater() {
        let field = makeField()
        let powder = makePowder()
        // The cyan the field's water uses.
        addResting(to: field, x: 200, color: PackedColor(r: 0x06, g: 0xB6, b: 0xD4))

        Hybrid.autoSettle(from: field, into: powder)

        var foundWater = false
        for i in 0 ..< powder.cellCount where powder.type[i] == Element.water { foundWater = true }
        #expect(foundWater, "a blue body should settle as water, not sand")
    }

    @Test("A body still travelling is left alone")
    func fastBodyDoesNotSettle() {
        let field = makeField()
        let powder = makePowder()
        _ = field.addParticle(x: 200, y: field.height - 4, velocityX: 20, velocityY: 0)

        #expect(Hybrid.autoSettle(from: field, into: powder) == 0)
        #expect(field.bodyCount == 1, "a moving body should stay in the field")
    }

    @Test("A body high above the floor is left alone")
    func highBodyDoesNotSettle() {
        let field = makeField()
        let powder = makePowder()
        _ = field.addParticle(x: 200, y: 50, velocityX: 0, velocityY: 0)

        #expect(Hybrid.autoSettle(from: field, into: powder) == 0)
        #expect(field.bodyCount == 1)
    }

    @Test("Only a few settle at a time")
    func settlingIsGradual() {
        let field = makeField()
        let powder = makePowder()
        for i in 0 ..< 50 { addResting(to: field, x: Double(i) * 7 + 5) }

        // A field should silt up into the grid rather than vanishing in one frame.
        #expect(Hybrid.autoSettle(from: field, into: powder, limit: 8) == 8)
        #expect(field.bodyCount == 42)
    }

    /// Black holes and repulsors are machinery, and a pinned body is part of a structure someone built.
    /// Turning any of them into a grain of sand would be destructive rather than charming.
    @Test("Machinery and pinned bodies never settle")
    func machineryIsSpared() {
        let field = makeField()
        let powder = makePowder()

        _ = field.addParticle(x: 100, y: field.height - 4, velocityX: 0, velocityY: 0, kind: .blackhole)
        _ = field.addParticle(x: 150, y: field.height - 4, velocityX: 0, velocityY: 0, kind: .repulsor)
        _ = field.addParticle(x: 200, y: field.height - 4, velocityX: 0, velocityY: 0, isFixed: true)

        #expect(Hybrid.autoSettle(from: field, into: powder, limit: 99) == 0)
        #expect(Hybrid.settleAll(from: field, into: powder) == 0)
        #expect(field.bodyCount == 3, "none of these should have been converted")
    }

    /// Settling must never destroy what is already in the grid. The body stays in the field instead,
    /// which is the only answer that loses nothing.
    @Test("A body over an occupied cell stays where it is")
    func occupiedCellsAreNotOverwritten() {
        let field = makeField(width: 100, height: 200)
        let powder = makePowder(width: 100, height: 200)

        // Fill the row the body would land in.
        for x in 0 ..< powder.width { powder.setElement(x, powder.height - 5, Element.stone) }
        let landingY = Double(powder.height - 5) / Double(powder.height) * field.height
        _ = field.addParticle(x: 50, y: landingY, velocityX: 0, velocityY: 0)

        #expect(Hybrid.settleAll(from: field, into: powder) == 0)
        #expect(field.bodyCount == 1, "the body should stay rather than be destroyed")
        // And the stone is untouched.
        #expect(powder.type[powder.index(50, powder.height - 5)] == Element.stone)
    }

    @Test("Settling everything empties the field into the grid")
    func settleAllWorks() {
        let field = makeField()
        let powder = makePowder()
        for i in 0 ..< 30 { addResting(to: field, x: Double(i) * 13 + 5) }

        let settled = Hybrid.settleAll(from: field, into: powder)
        #expect(settled > 0)
        #expect(powder.activeParticleCount == settled)
        #expect(field.bodyCount == 30 - settled)
    }

    /// The failure that would be hardest to spot. Springs refer to bodies by position in the array, so
    /// removing one without going through the engine renumbers every later body and leaves every spring
    /// pointing one place too high — a cloth that quietly deforms some time after a settle.
    @Test("Settling leaves a cloth's springs intact")
    func springsSurviveSettling() {
        let field = makeField()
        let powder = makePowder()

        field.spawnCloth(cols: 6, rows: 5)
        let springsBefore = field.springs.count
        #expect(springsBefore > 0, "the cloth should have springs")

        // A loose body to settle, on top of the cloth, so the array is genuinely disturbed.
        addResting(to: field, x: 200)
        #expect(Hybrid.autoSettle(from: field, into: powder, limit: 8) >= 1)

        // Every spring still points at a body that exists.
        let count = field.particles.count
        let valid = field.springs.allSatisfy { $0.a >= 0 && $0.a < count && $0.b >= 0 && $0.b < count }
        #expect(valid, "a spring points outside the body list")
    }

    @Test("A body with unusable coordinates is skipped rather than settling somewhere absurd")
    func corruptBodiesAreSkipped() {
        let field = makeField()
        let powder = makePowder()
        _ = field.addParticle(x: .nan, y: field.height - 4, velocityX: 0, velocityY: 0)
        _ = field.addParticle(x: 200, y: .infinity, velocityX: 0, velocityY: 0)

        // Converting a coordinate that is not a number gives zero, which would pile them into the
        // corner of the grid — the health report would count them while the picture hid where they were.
        #expect(Hybrid.autoSettle(from: field, into: powder, limit: 99) == 0)
        #expect(Hybrid.settleAll(from: field, into: powder) == 0)
        #expect(powder.activeParticleCount == 0)
    }

    @Test("Nothing settles into the bottom rows, which are usually the floor")
    func theFloorIsSpared() {
        let field = makeField(width: 100, height: 200)
        let powder = makePowder(width: 100, height: 200)
        // Right at the very bottom of the field.
        _ = field.addParticle(x: 50, y: field.height - 1, velocityX: 0, velocityY: 0)

        Hybrid.autoSettle(from: field, into: powder, limit: 9)
        // Wherever it went, it did not go into the last two rows.
        for x in 0 ..< powder.width {
            #expect(powder.type[powder.index(x, powder.height - 1)] == Element.empty)
            #expect(powder.type[powder.index(x, powder.height - 2)] == Element.empty)
        }
    }
}
