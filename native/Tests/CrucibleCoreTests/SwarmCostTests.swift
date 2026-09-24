import Testing

@testable import CrucibleCore

/// What a crowd of bodies costs, and what the app says about it.
///
/// The measurements behind this are in the comment on ``SwarmCost``, and they are the reason it exists:
/// two hundred thousand bodies pushing each other apart costs about two hundred milliseconds a moment,
/// which is five frames a second, while the same crowd with that switched off costs under one. The
/// interface offered the crowd and said nothing about the difference.
///
/// The wording is tested rather than eyeballed, because it is the whole point of the type. A warning that
/// says "this may be slow" is an adjective somebody can reasonably disagree with; one that says how many
/// frames a second they are about to get is a fact.
@Suite("What a crowd costs")
struct SwarmCostTests {
    @Test("A crowd is affordable until it is pushing itself apart")
    func affordability() {
        // Every preset in the app spawns a few hundred, so none of them is ever in trouble.
        #expect(SwarmCost.isAffordable(bodies: 400, collisions: true))
        #expect(SwarmCost.isAffordable(bodies: 16_000, collisions: true))
        // Twenty-five thousand is twenty-one milliseconds — past sixty frames a second.
        #expect(!SwarmCost.isAffordable(bodies: 25_000, collisions: true))
        #expect(!SwarmCost.isAffordable(bodies: 50_000, collisions: true))
        #expect(!SwarmCost.isAffordable(bodies: 200_000, collisions: true))

        // With collisions off, no crowd is a problem — a million costs about four milliseconds.
        for bodies in [50_000, 200_000, 500_000, 1_000_000] {
            #expect(SwarmCost.isAffordable(bodies: bodies, collisions: false), "\(bodies)")
        }
    }

    /// Checked against the figures actually measured, so a wrong estimate is a failing test rather than a
    /// number on screen that nobody trusts.
    @Test("The estimate matches what was measured")
    func estimateIsClose() {
        let measured: [(bodies: Int, collide: Bool, milliseconds: Double)] = [
            (25_000, true, 21),
            (50_000, true, 55),
            (100_000, true, 114),
            (200_000, true, 201),
            (500_000, true, 273),
            (50_000, false, 0.2),
            (200_000, false, 0.8),
            (500_000, false, 2.1),
        ]
        for case let (bodies, collide, actual) in measured {
            let estimate = SwarmCost.estimatedMilliseconds(bodies: bodies, collisions: collide)
            // Within a third. It is a straight line through a curve, and the point is the order of
            // magnitude rather than the decimal.
            let ratio = estimate / actual
            #expect(
                ratio > 0.66 && ratio < 1.5,
                "\(bodies) bodies collide=\(collide): estimated \(estimate)ms against \(actual)ms measured"
            )
        }
    }

    @Test("Nothing is said when there is nothing worth saying")
    func quietWhenFine() {
        #expect(SwarmCost.warning(bodies: 400, collisions: true) == nil)
        #expect(SwarmCost.warning(bodies: 16_000, collisions: true) == nil)
        #expect(SwarmCost.warning(bodies: 1_000_000, collisions: false) == nil)
        #expect(SwarmCost.warning(bodies: 0, collisions: true) == nil)
    }

    /// The warning has to carry the number. That is what makes it something to act on rather than a
    /// vague apology.
    @Test("The warning says what it will cost and what to do about it")
    func warningIsUseful() throws {
        let text = try #require(SwarmCost.warning(bodies: 200_000, collisions: true))
        #expect(text.contains("200,000"), "\(text)")
        #expect(text.contains("frames a second"), "\(text)")
        #expect(text.contains("Collide"), "it should name the switch that fixes it: \(text)")
        // And the figure should be the right order of magnitude — about 5 frames a second, not 50.
        #expect(text.contains("5 frames"), "\(text)")
    }

    @Test("Numbers are grouped so they can be read at a glance")
    func numbersAreReadable() {
        #expect(1.formattedWithSeparators == "1")
        #expect(999.formattedWithSeparators == "999")
        #expect(1000.formattedWithSeparators == "1,000")
        #expect(25_000.formattedWithSeparators == "25,000")
        #expect(200_000.formattedWithSeparators == "200,000")
        #expect(1_000_000.formattedWithSeparators == "1,000,000")
        #expect(0.formattedWithSeparators == "0")
        #expect((-1234).formattedWithSeparators == "-1,234")
    }
}
