import Foundation
import Testing

@testable import CrucibleCore

/// Holds the renderer to the exact pixels the web engine draws.
///
/// Choosing a cell's colour is not graphics work — it is a pile of rules about grain
/// speckling, mist blending, heat tinting and four overlay modes, and each one can be got
/// subtly wrong in a way that still looks plausible. So this is measured rather than
/// reviewed, on a world containing one of everything the renderer treats differently.
///
/// Because the colour decisions all live in the engine, this covers essentially all of them.
/// What is left for Metal is handing the finished bytes over as a texture, which has no
/// colour decisions in it to get wrong.
@Suite("Rendering matches the web engine")
struct RenderGoldenTests {
    struct Frame: Decodable, CustomTestStringConvertible {
        var overlay: String
        var texture: String
        var width: Int
        var height: Int
        /// Cells that are not the plain background, as `index:aabbggrr`.
        var pixels: [String]
        var backgroundCount: Int

        var testDescription: String { "\(overlay) with \(texture)" }
    }

    struct Fixture: Decodable {
        var note: String
        var frames: [Frame]
    }

    static let fixture: Fixture = {
        guard let url = Bundle.module.url(
            forResource: "web-render-golden",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) ?? Bundle.module.url(forResource: "web-render-golden", withExtension: "json") else {
            fatalError("Fixture web-render-golden.json is missing from the test bundle")
        }
        do {
            return try JSONDecoder().decode(Fixture.self, from: try Data(contentsOf: url))
        } catch {
            fatalError("Could not decode the golden render fixture: \(error)")
        }
    }()

    /// Builds the same world the fixture generator does.
    ///
    /// Laid out by hand rather than by running the simulation, so each case sits at a known
    /// position and a failure points straight at the rule that broke.
    static func buildShowcase() -> PowderEngine {
        let engine = PowderEngine(width: 24, height: 18, seed: 1)
        engine.frameCount = 7 // Non-zero, because one grain setting moves with time.
        engine.ambientTemp = 20

        let ids: [ElementID] = [
            Element.sand, Element.stone, Element.dirt,
            Element.water, Element.oil,
            Element.smoke, Element.steam, Element.plasma, Element.fire,
            Element.lava, Element.ice, Element.metal, Element.bedrock, Element.fan,
        ]
        for (index, id) in ids.enumerated() {
            let x = index % 12
            let y = index / 12
            for dy in 0 ..< 3 {
                for dx in 0 ..< 2 {
                    engine.setElement(x * 2 + dx, y * 3 + dy + 1, id)
                }
            }
        }

        // A spread of temperatures, so every branch of the heat map and both directions of
        // the tint are reached.
        let temps: [Double] = [-120, -40, -11, 0, 19, 20, 21, 41, 150, 201, 500, 801, 1500, 3200]
        for (index, temp) in temps.enumerated() {
            engine.setElement(index, 14, Element.sand, temp: temp)
            // Air at the same temperature, which the tinted mode draws as a glow.
            engine.temperature[15 * engine.width + index] = JS.toFloat32(temp)
        }
        // Every fan direction.
        for d in 0 ..< 4 {
            engine.setElement(16 + d, 14, Element.fan)
            engine.life[14 * engine.width + 16 + d] = UInt16(d)
        }
        return engine
    }

    /// The rendered pixels, in the fixture's sparse form.
    private func sparsePixels(_ engine: PowderEngine, _ overlay: PowderOverlayMode) -> [String] {
        let words = engine.renderToArray(overlay: overlay)
        // The dark lab background dominates every frame, so recording it in full would make
        // the fixture mostly one repeated value.
        let background = UInt32(PowderEngine.backgroundRed)
            | UInt32(PowderEngine.backgroundGreen) << 8
            | UInt32(PowderEngine.backgroundBlue) << 16
            | 0xFF00_0000
        var out: [String] = []
        for (i, word) in words.enumerated() where word != background {
            let hex = String(word, radix: 16)
            out.append("\(i):\(String(repeating: "0", count: max(0, 8 - hex.count)))\(hex)")
        }
        return out
    }

    @Test("Every pixel matches", arguments: fixture.frames)
    func pixelsMatch(frame: Frame) {
        guard let overlay = PowderOverlayMode(rawValue: frame.overlay) else {
            Issue.record("Unknown overlay in fixture: \(frame.overlay)")
            return
        }
        guard let texture = PowderTextureMode(rawValue: frame.texture) else {
            Issue.record("Unknown grain setting in fixture: \(frame.texture)")
            return
        }

        let engine = Self.buildShowcase()
        engine.textureMode = texture
        let actual = sparsePixels(engine, overlay)

        #expect(
            actual.count == frame.pixels.count,
            "\(frame.testDescription): drew \(actual.count) non-background cells, web engine drew \(frame.pixels.count)"
        )

        var reported = 0
        for i in 0 ..< min(actual.count, frame.pixels.count) where actual[i] != frame.pixels[i] {
            if reported < 5 {
                Issue.record(
                    """
                    \(frame.testDescription), pixel \(i) differs
                      native: \(actual[i])
                      web:    \(frame.pixels[i])
                    """
                )
            }
            reported += 1
        }
        if reported > 5 {
            Issue.record("\(frame.testDescription): \(reported) pixels differ in total")
        }
    }

    @Test("Every mode and grain setting is covered")
    func coverageIsComplete() {
        // Asserted rather than assumed: a narrowed fixture would leave this suite passing
        // while having quietly stopped testing whole modes.
        let overlays = Set(Self.fixture.frames.map(\.overlay))
        let textures = Set(Self.fixture.frames.map(\.texture))
        #expect(overlays == Set(PowderOverlayMode.allCases.map(\.rawValue)))
        #expect(textures == Set(PowderTextureMode.allCases.map(\.rawValue)))
    }

    @Test("A measurement mode ignores the grain setting")
    func measurementModesIgnoreGrain() {
        // The heat map and the density map describe what a cell *is*, not what it looks like,
        // so the speckle must not reach them. If it ever does, a decorative setting has
        // leaked into something being read as data.
        for overlay in [PowderOverlayMode.temperature, .density] {
            var reference: [String]?
            for texture in PowderTextureMode.allCases {
                let engine = Self.buildShowcase()
                engine.textureMode = texture
                let pixels = sparsePixels(engine, overlay)
                if let reference {
                    #expect(pixels == reference, "\(overlay.rawValue) changed with \(texture.rawValue)")
                } else {
                    reference = pixels
                }
            }
        }
    }

    @Test("The grain setting does change the ordinary mode")
    func grainSettingHasAnEffect() {
        let flat = Self.buildShowcase()
        flat.textureMode = .flat
        let grained = Self.buildShowcase()
        grained.textureMode = .naturalGrain
        #expect(sparsePixels(flat, .normal) != sparsePixels(grained, .normal))
    }

    @Test("Speckling is fixed to the cell, not to the frame")
    func speckleDoesNotFlicker() {
        // A grain that has not moved must not change colour between frames. Keying the noise
        // to live coordinates is fine for something that stays put and disastrous for
        // anything that flows, which is why only solids are speckled at all — but the
        // natural setting must also not drift with the frame counter.
        let first = Self.buildShowcase()
        first.textureMode = .naturalGrain
        let before = sparsePixels(first, .normal)

        let later = Self.buildShowcase()
        later.textureMode = .naturalGrain
        later.frameCount = 9999
        #expect(sparsePixels(later, .normal) == before)
    }

    @Test("The flowing grain setting is the one that moves with time")
    func organicFlowMovesWithTime() {
        let early = Self.buildShowcase()
        early.textureMode = .organicFlow
        early.frameCount = 0
        let late = Self.buildShowcase()
        late.textureMode = .organicFlow
        late.frameCount = 40
        #expect(sparsePixels(early, .normal) != sparsePixels(late, .normal))
    }

    @Test("Rendering does not disturb the world")
    func renderingIsReadOnly() {
        // The display loop calls this every frame, so it must not touch the simulation. A
        // renderer that quietly wrote to the grid would show up as physics that behaves
        // differently depending on whether anyone was looking at it.
        let engine = Self.buildShowcase()
        let typesBefore = Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount))
        let tempsBefore = Array(UnsafeBufferPointer(start: engine.temperature, count: engine.cellCount))
        let lifeBefore = Array(UnsafeBufferPointer(start: engine.life, count: engine.cellCount))

        for overlay in PowderOverlayMode.allCases {
            _ = engine.renderToArray(overlay: overlay)
        }

        #expect(Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount)) == typesBefore)
        #expect(Array(UnsafeBufferPointer(start: engine.temperature, count: engine.cellCount)) == tempsBefore)
        #expect(Array(UnsafeBufferPointer(start: engine.life, count: engine.cellCount)) == lifeBefore)
    }

    @Test("A world with no cells draws nothing rather than crashing")
    func emptyWorldIsSafe() {
        let engine = PowderEngine(width: 0, height: 0, seed: 1)
        for overlay in PowderOverlayMode.allCases {
            #expect(engine.renderToArray(overlay: overlay).isEmpty)
        }
    }
}
