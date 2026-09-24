import Foundation
import Testing

@testable import CrucibleCore

/// Holds the particle field's colour choices to the exact pixels the web engine draws.
///
/// The app draws the field on the GPU as points rather than as a grid of pixels, so it does not
/// take this path — but it makes the same decision about what colour each body should be, from
/// the same function. Comparing a finished picture checks that decision and also pins down
/// which pixel each body lands on, which a list of colours would not.
@Suite("Particle rendering matches the web engine")
struct ParticleRenderGoldenTests {
    struct Frame: Decodable, CustomTestStringConvertible {
        var mode: String
        var width: Int
        var height: Int
        var bodyCount: Int
        /// Cells that are not plain background, as `index:aabbggrr`.
        var pixels: [String]

        var testDescription: String { mode }
    }

    struct Fixture: Decodable {
        var note: String
        var seed: UInt32
        var frames: [Frame]
    }

    static let fixture: Fixture = {
        guard let url = Bundle.module.url(
            forResource: "web-particle-render-golden",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) ?? Bundle.module.url(forResource: "web-particle-render-golden", withExtension: "json")
        else {
            fatalError("Fixture web-particle-render-golden.json is missing from the test bundle")
        }
        do {
            return try JSONDecoder().decode(Fixture.self, from: try Data(contentsOf: url))
        } catch {
            fatalError("Could not decode the golden particle render fixture: \(error)")
        }
    }()

    /// Builds the same field the fixture generator does.
    ///
    /// The order matters: the flare is the only preset here that gives its bodies a lifespan,
    /// and every preset but the burst clears the field, so it has to come first.
    static func buildShowcase(seed: UInt32) -> ParticleEngine {
        let engine = ParticleEngine(width: 160, height: 120, seed: seed)
        engine.spawnSolarFlare(count: 500)
        engine.spawnBurst(count: 400)
        engine.spawnBurst(count: 350)
        engine.addParticle(x: 0, y: 0, velocityX: 0, velocityY: 0, radius: 1, charge: 0,
                           color: PackedColor(r: 0, g: 0, b: 0))
        engine.addParticle(x: 159, y: 119, velocityX: 40, velocityY: 30, radius: 1, charge: 1,
                           color: PackedColor(r: 255, g: 255, b: 255))
        engine.addParticle(x: 80, y: 60, velocityX: 0, velocityY: 0, radius: 1, charge: -1,
                           color: PackedColor(r: 0x11, g: 0x22, b: 0x33))
        // Outside the world, and unusable. Both must be left out rather than folded into the
        // corner, which is what truncating their coordinates would do.
        engine.addParticle(x: -50, y: 60, velocityX: 0, velocityY: 0, radius: 1, charge: 1)
        engine.addParticle(x: .nan, y: 60, velocityX: 0, velocityY: 0, radius: 1, charge: 1)
        return engine
    }

    private func sparsePixels(_ engine: ParticleEngine) -> [String] {
        let words = engine.renderToArray()
        var out: [String] = []
        for (i, word) in words.enumerated() where word != ParticleEngine.backgroundColor {
            let hex = String(word, radix: 16)
            out.append("\(i):\(String(repeating: "0", count: max(0, 8 - hex.count)))\(hex)")
        }
        return out
    }

    @Test("Every pixel matches", arguments: fixture.frames)
    func pixelsMatch(frame: Frame) {
        guard let mode = ParticleColorMode(rawValue: frame.mode) else {
            Issue.record("Unknown colour mode in fixture: \(frame.mode)")
            return
        }
        let engine = Self.buildShowcase(seed: Self.fixture.seed)
        engine.colorMode = mode

        #expect(
            engine.particles.count == frame.bodyCount,
            "\(frame.mode): \(engine.particles.count) bodies, web engine had \(frame.bodyCount)"
        )
        // Above the count at which the web engine switches to writing pixels. Below it the
        // recorded picture would be of something else entirely.
        #expect(engine.particles.count > ParticleEngine.pixelPathThreshold)

        let actual = sparsePixels(engine)
        #expect(
            actual.count == frame.pixels.count,
            "\(frame.mode): drew \(actual.count) non-background pixels, web engine drew \(frame.pixels.count)"
        )

        var reported = 0
        for i in 0 ..< min(actual.count, frame.pixels.count) where actual[i] != frame.pixels[i] {
            if reported < 5 {
                Issue.record(
                    """
                    \(frame.mode), pixel \(i) differs
                      native: \(actual[i])
                      web:    \(frame.pixels[i])
                    """
                )
            }
            reported += 1
        }
        if reported > 5 {
            Issue.record("\(frame.mode): \(reported) pixels differ in total")
        }
    }

    @Test("Every colour mode is covered")
    func coverageIsComplete() {
        let modes = Set(Self.fixture.frames.map(\.mode))
        #expect(modes == Set(ParticleColorMode.allCases.map(\.rawValue)))
    }

    @Test("No two colour modes draw the same thing")
    func modesAreDistinct() {
        // Six modes the interface presents as different must actually differ. Two of them once
        // measured the same thing — crowding computed speed, exactly as speed did, with only
        // the hue range differing — so the interface offered a choice that did nothing.
        var seen: [String: String] = [:]
        for mode in ParticleColorMode.allCases {
            let engine = Self.buildShowcase(seed: Self.fixture.seed)
            engine.colorMode = mode
            let signature = sparsePixels(engine).joined(separator: "|")
            if let twin = seen[signature] {
                Issue.record("\(mode.rawValue) draws exactly the same as \(twin)")
            }
            seen[signature] = mode.rawValue
        }
    }

    @Test("The colours handed to the GPU are the ones that get drawn")
    func gpuColoursAgreeWithThePicture() {
        // The app never takes the pixel path; it asks for one colour per body and draws points.
        // Both come from the same function, and this is the check that they have not been
        // allowed to drift apart — otherwise the verified path would not be the shipped one.
        for mode in ParticleColorMode.allCases {
            let engine = Self.buildShowcase(seed: Self.fixture.seed)
            engine.colorMode = mode

            var colors: [UInt32] = []
            engine.fillRenderColors(into: &colors)

            let density = engine.densityGridIfNeeded()
            for (index, body) in engine.particles.enumerated() {
                let expected = engine.renderColor(of: body, density: density).packedRGBA
                #expect(colors[index] == expected, "\(mode.rawValue), body \(index)")
            }
        }
    }

    @Test("A body that cannot be placed is left out")
    func unplaceableBodiesAreSkipped() {
        let engine = ParticleEngine(width: 40, height: 40, seed: 1)
        engine.colorMode = .native
        engine.addParticle(x: .nan, y: 10, radius: 1, charge: 1, color: PackedColor(r: 255, g: 0, b: 0))
        engine.addParticle(x: 10, y: .infinity, radius: 1, charge: 1, color: PackedColor(r: 255, g: 0, b: 0))
        engine.addParticle(x: -5, y: 10, radius: 1, charge: 1, color: PackedColor(r: 255, g: 0, b: 0))
        engine.addParticle(x: 100, y: 10, radius: 1, charge: 1, color: PackedColor(r: 255, g: 0, b: 0))

        // Truncating an unusable coordinate gives zero, so these used to pile into a bright dot
        // in the corner: the health report counted them while the picture hid where they were.
        let drawn = engine.renderToArray().filter { $0 != ParticleEngine.backgroundColor }
        #expect(drawn.isEmpty)
    }

    @Test("A dying body is coloured as dying")
    func lifespanRatioIsNotInverted() {
        // The original tested the remaining lifespan for being non-zero, which made a body one
        // frame from deletion report a full ratio — so the mode painted dying bodies as brand
        // new, the exact opposite of its purpose.
        var fresh = ParticleObject(id: 0, x: 0, y: 0)
        fresh.maxLife = 100
        fresh.lifespan = 100
        var dying = fresh
        dying.lifespan = 1
        var gone = fresh
        gone.lifespan = 0

        #expect(ParticleEngine.lifespanRatio(of: fresh) == 1)
        #expect(ParticleEngine.lifespanRatio(of: dying) < 0.05)
        #expect(ParticleEngine.lifespanRatio(of: gone) == 0)

        // Something with no lifespan at all counts as full, which is what the colour should say
        // about a body that is never going to expire.
        let immortal = ParticleObject(id: 1, x: 0, y: 0)
        #expect(ParticleEngine.lifespanRatio(of: immortal) == 1)
    }
}
