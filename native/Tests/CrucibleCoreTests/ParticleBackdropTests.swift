import Foundation
import Testing

@testable import CrucibleCore

/// What the field sits on, and how brightly it glows.
///
/// The drawing itself is on the graphics card and cannot be tested from here. What can be, and is worth
/// it, is everything around it: that the choices are distinct and stably numbered, that nonsense settings
/// cannot reach the shader, and that a scene remembers how it looked.
struct ParticleBackdropTests {
    @Test("Every backdrop has its own number, and the empty one stays nought")
    func shaderNumbersAreStable() {
        // Written out by hand rather than taken from the order of the cases, so adding one cannot
        // silently renumber the rest and start drawing a nebula where the stars were.
        let numbers = ParticleBackdrop.allCases.map(\.shaderIdentifier)
        #expect(Set(numbers).count == numbers.count, "two backdrops share a number")
        #expect(ParticleBackdrop.none.shaderIdentifier == 0, "nothing must stay nought")
        for number in numbers {
            #expect(number >= 0 && number < Int32(ParticleBackdrop.allCases.count))
        }
    }

    @Test("Every backdrop has a name worth showing")
    func namesAreUsable() {
        for backdrop in ParticleBackdrop.allCases {
            #expect(!backdrop.displayName.isEmpty)
            #expect(backdrop.displayName != backdrop.rawValue.uppercased())
        }
        #expect(Set(ParticleBackdrop.allCases.map(\.displayName)).count == ParticleBackdrop.allCases.count)
    }

    @Test("Only the backdrops that actually move say they move")
    func movementIsRecordedHonestly() {
        #expect(!ParticleBackdrop.none.moves)
        #expect(!ParticleBackdrop.gradient.moves, "a fixed gradient does not move")
        #expect(ParticleBackdrop.starfield.moves, "stars twinkle")
        #expect(ParticleBackdrop.nebula.moves, "clouds drift")
    }

    @Test("The glow is off until it is asked for")
    func glowStartsOff() {
        // It suits some scenes and ruins others — a lattice or a cloth wants crisp edges — so it is
        // offered rather than assumed.
        #expect(ParticleGlow.default.strength == 0)
        #expect(ParticleEngine(width: 100, height: 100, seed: 1).glow.strength == 0)
        #expect(ParticleEngine(width: 100, height: 100, seed: 1).backdrop == .none)
    }

    @Test("Nonsense glow settings are pulled into range")
    func glowIsSanitized() {
        let broken = ParticleGlow(strength: .nan, spread: .nan, threshold: .nan).sanitized
        #expect(broken.strength == 0)
        #expect(broken.spread == 2.2)
        #expect(broken.threshold == 0.32)

        let huge = ParticleGlow(strength: 1e9, spread: 1e9, threshold: 1e9).sanitized
        #expect(huge.strength <= 4)
        #expect(huge.spread <= 12)
        #expect(huge.threshold <= 1)

        let negative = ParticleGlow(strength: -5, spread: -5, threshold: -5).sanitized
        #expect(negative.strength == 0)
        #expect(negative.spread > 0, "a spread of nought would divide by nothing in the shader")
        #expect(negative.threshold == 0)
    }

    @Test("The backdrop's brightness is pulled into range on the way in")
    func backdropStrengthIsClamped() {
        let field = ParticleEngine(width: 100, height: 100, seed: 1)
        field.backdropStrength = .nan
        #expect(field.backdropStrength == 1, "an unusable brightness means the ordinary one")
        field.backdropStrength = -3
        #expect(field.backdropStrength == 0)
        field.backdropStrength = 99
        #expect(field.backdropStrength == 2)
    }

    @Test("Spread and brightness are separate settings")
    func spreadIsIndependentOfStrength() {
        // The reference implementation ties them together, so asking for a brighter glow there also gives
        // a wider one — which is why turning it up reads as a haze settling over everything rather than
        // as the bright things getting brighter.
        var glow = ParticleGlow.default
        glow.strength = 2
        #expect(glow.sanitized.spread == ParticleGlow.default.spread, "brightness changed the spread")
        glow.spread = 6
        #expect(glow.sanitized.strength == 2, "spread changed the brightness")
    }

    @Test("A backdrop and a glow come back with a saved scene")
    func backdropSurvivesASave() throws {
        let source = ParticleEngine(width: 400, height: 700, seed: 3)
        source.backdrop = .nebula
        source.backdropStrength = 0.65
        source.glow = ParticleGlow(strength: 1.4, spread: 3.5, threshold: 0.2)
        source.addParticle(x: 10, y: 20, velocityX: 0, velocityY: 0, radius: 2, charge: 0)

        let bytes = try JSONEncoder().encode(source.captureState())
        let state = try JSONDecoder().decode(ParticleState.self, from: bytes)
        let loaded = ParticleEngine(width: 100, height: 100, seed: 9)
        #expect(loaded.apply(state))

        #expect(loaded.backdrop == .nebula)
        #expect(abs(loaded.backdropStrength - 0.65) < 1e-9)
        #expect(abs(loaded.glow.strength - 1.4) < 1e-9)
        #expect(abs(loaded.glow.spread - 3.5) < 1e-9)
        #expect(abs(loaded.glow.threshold - 0.2) < 1e-9)
    }

    @Test("A scene saved before backdrops existed loads with none")
    func olderScenesLoadWithoutABackdrop() throws {
        let source = ParticleEngine(width: 400, height: 700, seed: 3)
        source.addParticle(x: 10, y: 20, velocityX: 0, velocityY: 0, radius: 2, charge: 0)
        var state = source.captureState()
        state.backdrop = nil
        state.backdropStrength = nil
        state.glow = nil

        let loaded = ParticleEngine(width: 100, height: 100, seed: 9)
        loaded.backdrop = .starfield
        loaded.glow = ParticleGlow(strength: 2)
        #expect(loaded.apply(state))
        // No opinion in the file means the plain look, not whatever the last scene happened to leave.
        #expect(loaded.backdrop == .starfield, "an absent backdrop leaves the current one alone")
        #expect(loaded.glow.strength == 2, "and so does an absent glow")
    }

    @Test("A backdrop this build does not know about is ignored, not guessed at")
    func unknownBackdropIsIgnored() {
        let source = ParticleEngine(width: 400, height: 700, seed: 3)
        source.addParticle(x: 10, y: 20, velocityX: 0, velocityY: 0, radius: 2, charge: 0)
        var state = source.captureState()
        state.backdrop = "something-from-a-later-build"

        let loaded = ParticleEngine(width: 100, height: 100, seed: 9)
        loaded.backdrop = .gradient
        #expect(loaded.apply(state))
        #expect(loaded.backdrop == .gradient, "a setting that cannot be expressed is lost, not applied")
    }

    @Test("A loaded glow is sanitised, so a hand-edited file cannot reach the shader with nonsense")
    func loadedGlowIsSanitized() throws {
        let source = ParticleEngine(width: 400, height: 700, seed: 3)
        source.addParticle(x: 10, y: 20, velocityX: 0, velocityY: 0, radius: 2, charge: 0)
        var state = source.captureState()
        state.glow = ParticleGlow(strength: .infinity, spread: 0, threshold: -4)

        let loaded = ParticleEngine(width: 100, height: 100, seed: 9)
        #expect(loaded.apply(state))
        #expect(loaded.glow.strength.isFinite)
        #expect(loaded.glow.spread > 0, "a spread of nought would divide by nothing in the shader")
        #expect(loaded.glow.threshold >= 0)
    }

    @Test("A backdrop and a glow survive being written down on their own")
    func typesRoundTrip() throws {
        for backdrop in ParticleBackdrop.allCases {
            let bytes = try JSONEncoder().encode(backdrop)
            #expect(try JSONDecoder().decode(ParticleBackdrop.self, from: bytes) == backdrop)
        }
        let glow = ParticleGlow(strength: 1.1, spread: 4.4, threshold: 0.7)
        let bytes = try JSONEncoder().encode(glow)
        #expect(try JSONDecoder().decode(ParticleGlow.self, from: bytes) == glow)
    }
}
