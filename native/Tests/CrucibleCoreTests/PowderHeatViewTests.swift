import Testing

@testable import CrucibleCore

/// The heat view shows where the heat is.
///
/// Everything else about the renderer is held to the web engine's exact pixels by ``RenderGoldenTests``, which is the
/// right way to check a pile of transcribed colour rules. But a golden only says "the same as before"; it cannot say
/// *why* a picture is the way it is, so when the reason matters it needs stating separately.
///
/// Here the reason matters. The heat view used to paint every cell, air included, and since air is nearly all of an
/// ordinary world and all of it sits within a degree of the room, the result was a flat green rectangle with the world
/// invisible inside it. That is not a subtle fault, but it was invisible to the golden — the pixels were
/// consistent, they were just consistently useless. So: room-temperature air is left dark, and air that is actually
/// carrying heat is not.
@Suite("The heat view shows where the heat is")
struct PowderHeatViewTests {
    /// The dark the lab sits on: red lowest, then green, then blue, then opaque, as the engine packs a colour.
    private let background = UInt32(PowderEngine.backgroundRed)
        | UInt32(PowderEngine.backgroundGreen) << 8
        | UInt32(PowderEngine.backgroundBlue) << 16
        | 0xFF00_0000

    private func picture(_ engine: PowderEngine) -> [UInt32] {
        engine.renderToArray(overlay: .temperature)
    }

    @Test("An empty world is dark rather than a flat green rectangle")
    func emptyIsDark() {
        let engine = PowderEngine(width: 30, height: 20, seed: 1)
        let pixels = picture(engine)
        #expect(pixels.allSatisfy { $0 == background }, "empty space at room temperature was painted")
    }

    @Test("The world's own shape is visible in the heat view")
    func theShapeShowsThrough() {
        let engine = PowderEngine(width: 30, height: 20, seed: 2)
        // A block of cold stone, at exactly the room's temperature, so nothing but its presence distinguishes it.
        for y in 5 ..< 10 {
            for x in 5 ..< 12 { engine.setElement(x, y, Element.stone, temp: 20) }
        }
        let pixels = picture(engine)
        let inside = pixels[7 * 30 + 8]
        let outside = pixels[2 * 30 + 2]
        #expect(outside == background)
        #expect(inside != background, "a block of material at room temperature left no mark in the heat view")
        // How much of it shows: thirty-five cells of stone and not one more.
        #expect(pixels.count { $0 != background } == 35)
    }

    @Test("Air carrying real heat is still painted")
    func hotAirStillShows() {
        let engine = PowderEngine(width: 30, height: 20, seed: 3)
        // Nothing in the world but a patch of hot air, which is the case somebody switches to this view to find.
        for x in 10 ..< 14 { engine.temperature[10 * 30 + x] = 600 }
        let pixels = picture(engine)
        #expect(pixels[10 * 30 + 11] != background, "a hot draught was invisible in the heat view")
        #expect(pixels.count { $0 != background } == 4)

        // And cold air the same way round.
        let chilled = PowderEngine(width: 30, height: 20, seed: 4)
        for x in 10 ..< 14 { chilled.temperature[10 * 30 + x] = -40 }
        #expect(picture(chilled).count { $0 != background } == 4)
    }

    @Test("Air a whisker off the room's temperature is left alone")
    func aWhiskerIsIgnored() {
        // Heat spreads through air, so after anything hot has been in the world every cell is a fraction off the
        // room. Painting those would bring the flat rectangle straight back.
        let engine = PowderEngine(width: 30, height: 20, seed: 5)
        for x in 0 ..< 30 {
            for y in 0 ..< 20 { engine.temperature[y * 30 + x] = 20 + Float(x % 9) - 4 }
        }
        #expect(picture(engine).allSatisfy { $0 == background }, "air within ten degrees of the room was painted")

        // Eleven degrees is not a whisker.
        let warmer = PowderEngine(width: 30, height: 20, seed: 6)
        warmer.temperature[5 * 30 + 5] = 31
        warmer.temperature[5 * 30 + 6] = 9
        #expect(picture(warmer).count { $0 != background } == 2)
    }

    @Test("The threshold follows the room rather than assuming twenty degrees")
    func itFollowsTheRoom() {
        // A world set to a hot room — a desert scene, a kiln — is at rest at its own temperature, not at twenty. If
        // the threshold were written down as a number instead of read from the room, every such world would be a
        // flat orange rectangle instead of a flat green one.
        let engine = PowderEngine(width: 20, height: 12, seed: 7)
        engine.ambientTemp = 300
        for x in 0 ..< 20 {
            for y in 0 ..< 12 { engine.temperature[y * 20 + x] = 300 }
        }
        #expect(picture(engine).allSatisfy { $0 == background }, "a hot room was painted as though it were heat")
        engine.temperature[6 * 20 + 9] = 320
        #expect(picture(engine).count { $0 != background } == 1)
    }

    @Test("A hot world still reads as hot")
    func heatStillReadsAsHeat() {
        // The point of leaving air dark is to make the heat visible, so the obvious thing has to hold: lava is bright
        // and ice is not, and they are not the same colour.
        let engine = PowderEngine(width: 30, height: 20, seed: 8)
        engine.setElement(5, 5, Element.lava, temp: 1_200)
        engine.setElement(20, 5, Element.ice, temp: -30)
        let pixels = picture(engine)
        let lava = pixels[5 * 30 + 5]
        let ice = pixels[5 * 30 + 20]
        #expect(lava != ice)
        // Hot is red-heavy, cold is blue-heavy, which is the whole language of the view.
        #expect(lava & 0xFF > (lava >> 16) & 0xFF, "lava did not read as hot")
        #expect((ice >> 16) & 0xFF > ice & 0xFF, "ice did not read as cold")
    }

    @Test("The picture written to a file is the picture on the screen")
    func thePictureMatches() throws {
        // The heat view is one of the pictures the day's world is published as, so the two paths must not drift.
        let engine = PowderEngine(width: 24, height: 16, seed: 9)
        engine.setElement(12, 8, Element.lava, temp: 1_100)
        for _ in 0 ..< 30 { engine.step() }
        let onScreen = engine.renderToArray(overlay: .temperature)
        let inTheFile = try #require(engine.pngBytes(overlay: .temperature))
        // Pulled back out of the file: past the header block, the stored stream's first row.
        let start = 8 + 12 + 13 + 8 + 2 + 5 + 1
        let red = inTheFile[start]
        let green = inTheFile[start + 1]
        let blue = inTheFile[start + 2]
        #expect(UInt32(red) == onScreen[0] & 0xFF)
        #expect(UInt32(green) == (onScreen[0] >> 8) & 0xFF)
        #expect(UInt32(blue) == (onScreen[0] >> 16) & 0xFF)
    }
}
