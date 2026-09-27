import Foundation
import Testing

@testable import CrucibleCore

/// Grains with a colour of their own: sand art, and a photograph turned into powder.
@Suite("Grains in a colour of their own")
struct PowderTintTests {
    private let pink = PowderEngine.tintWord(red: 236, green: 72, blue: 153)
    private let teal = PowderEngine.tintWord(red: 20, green: 184, blue: 166)

    /// A small world with a bedrock floor.
    private func world(width: Int = 30, height: Int = 24, seed: UInt32 = 5) -> PowderEngine {
        let engine = PowderEngine(width: width, height: height, seed: seed)
        for x in 0 ..< width { engine.setElement(x, height - 1, Element.bedrock) }
        return engine
    }

    private func cells(_ engine: PowderEngine) -> [ElementID] {
        Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount))
    }

    @Test("A coloured grain is still that colour after it has fallen")
    func theColourFallsWithTheGrain() {
        let engine = world()
        engine.drawBrush(centerX: 15, centerY: 2, radius: 0, elementID: Element.sand, shape: .circle, tint: pink)
        #expect(engine.tintAt(15, 2) == pink)
        for _ in 0 ..< 60 { engine.step() }

        var landed: (Int, Int)?
        for y in 0 ..< engine.height {
            for x in 0 ..< engine.width where engine.type[engine.index(x, y)] == Element.sand { landed = (x, y) }
        }
        guard let (x, y) = landed else {
            Issue.record("the grain disappeared")
            return
        }
        #expect(y > 15, "the grain did not fall")
        #expect(engine.tintAt(x, y) == pink, "the grain lost its colour on the way down")
        #expect(engine.tintAt(15, 2) == 0, "the colour stayed behind in the air it left")
        #expect(engine.tintedCellCount == 1)
    }

    @Test("Colour changes nothing about how anything behaves")
    func colourIsNeverConsulted() {
        let plain = world(seed: 11)
        let coloured = world(seed: 11)
        for engine in [plain, coloured] {
            engine.drawBrush(centerX: 8, centerY: 4, radius: 3, elementID: Element.sand, shape: .circle)
            engine.drawBrush(centerX: 20, centerY: 4, radius: 3, elementID: Element.water, shape: .circle)
            engine.drawBrush(centerX: 14, centerY: 12, radius: 2, elementID: Element.lava, shape: .square)
        }
        coloured.drawBrush(centerX: 8, centerY: 4, radius: 3, elementID: Element.sand, shape: .circle, tint: pink)
        coloured.drawBrush(centerX: 20, centerY: 4, radius: 3, elementID: Element.water, shape: .circle, tint: teal)
        // Re-seeded, because the plain world's painting drew no numbers for the second strokes.
        plain.rng = Mulberry32(seed: 99)
        coloured.rng = Mulberry32(seed: 99)
        for _ in 0 ..< 200 {
            plain.step()
            coloured.step()
        }
        #expect(cells(plain) == cells(coloured), "a coloured world moved differently from a plain one")
    }

    @Test("A world with no colour in it is drawn exactly as before")
    func noColourMeansTheSamePicture() {
        let untouched = world()
        let wasColoured = world()
        for engine in [untouched, wasColoured] {
            engine.drawBrush(centerX: 10, centerY: 10, radius: 4, elementID: Element.sand, shape: .circle)
            engine.drawBrush(centerX: 22, centerY: 10, radius: 3, elementID: Element.stone, shape: .square)
        }
        // Coloured and then uncoloured, so the drawing takes the path that looks at colours and finds none.
        wasColoured.setTint(10, 10, pink)
        wasColoured.setTint(10, 10, 0)
        #expect(wasColoured.tintMayExist)
        #expect(untouched.renderToArray() == wasColoured.renderToArray())
    }

    @Test("A coloured grain is drawn in its colour, with its grain")
    func itIsDrawnInItsColour() {
        let engine = world()
        engine.setElement(5, 5, Element.stone)
        engine.setTint(5, 5, teal)
        engine.textureMode = .flat
        #expect(engine.renderToArray()[engine.index(5, 5)] == teal)

        // With the usual speckle it is near its colour rather than exactly it, as a grain of real sand would be.
        engine.textureMode = .naturalGrain
        let drawn = engine.renderToArray()[engine.index(5, 5)]
        let red = Int(drawn & 0xFF)
        let green = Int((drawn >> 8) & 0xFF)
        let blue = Int((drawn >> 16) & 0xFF)
        #expect(abs(red - 20) <= 20 && abs(green - 184) <= 40 && abs(blue - 166) <= 40)
    }

    @Test("Becoming something else drops the colour")
    func aNewMaterialHasItsOwnColour() {
        let engine = world()
        engine.setElement(4, 4, Element.water)
        engine.setTint(4, 4, pink)
        _ = engine.start(.freeze)
        #expect(engine.type[engine.index(4, 4)] == Element.ice)
        #expect(engine.tintAt(4, 4) == 0, "frozen pink water came out as pink ice")

        engine.setElement(6, 6, Element.sand)
        engine.setTint(6, 6, pink)
        engine.setElement(6, 6, Element.stone)
        #expect(engine.tintAt(6, 6) == 0)

        // Air cannot be coloured, so nothing is waiting in an empty cell for the next grain to fall into.
        engine.setTint(8, 8, pink)
        #expect(engine.tintAt(8, 8) == 0)
    }

    @Test("Colours are kept through saving, and through a file that went through text")
    func coloursSurviveSaving() throws {
        let engine = world()
        engine.drawBrush(centerX: 10, centerY: 10, radius: 3, elementID: Element.sand, shape: .circle, tint: pink)
        engine.setElement(2, 2, Element.stone)
        engine.setTint(2, 2, PowderEngine.tintWord(red: 0, green: 0, blue: 0))
        let before = engine.tintedCellCount

        let text = try JSONEncoder().encode(engine.captureState())
        let state = try JSONDecoder().decode(PowderState.self, from: text)
        let other = PowderEngine(width: 30, height: 24, seed: 1)
        #expect(other.apply(state))
        #expect(other.tintedCellCount == before)
        #expect(other.tintAt(10, 10) == pink)
        // Pure black comes back a single step off black, not as "no colour".
        #expect(PowderEngine.tintChannels(other.tintAt(2, 2)).map { $0.red + $0.green + $0.blue } == 3)
    }

    @Test("A world with no colour saves exactly as it always did, and old files open")
    func plainWorldsAreUnchanged() throws {
        let engine = world()
        engine.drawBrush(centerX: 10, centerY: 10, radius: 3, elementID: Element.sand, shape: .circle)
        let state = engine.captureState()
        #expect(state.gridTint == nil)
        let text = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        #expect(!text.contains("gridTint"))

        // Colours that describe some other world are ignored, and the world still opens.
        var wrong = state
        wrong.gridTint = "AAAA"
        let other = PowderEngine(width: 30, height: 24, seed: 1)
        #expect(other.apply(wrong))
        #expect(other.tintedCellCount == 0)
        wrong.gridTint = "not base64 at all!"
        #expect(other.apply(wrong))
        #expect(other.tintedCellCount == 0)
    }

    @Test("Undo and redo bring colours back")
    func undoKeepsColours() {
        let engine = world()
        let history = PowderHistory(maximumSteps: 5)
        engine.drawBrush(centerX: 10, centerY: 10, radius: 2, elementID: Element.stone, shape: .square, tint: pink)
        history.push(engine)
        engine.drawBrush(centerX: 10, centerY: 10, radius: 2, elementID: Element.stone, shape: .square, tint: teal)
        #expect(engine.tintAt(10, 10) == teal)
        #expect(history.undo(engine))
        #expect(engine.tintAt(10, 10) == pink)
        #expect(history.redo(engine))
        #expect(engine.tintAt(10, 10) == teal)
    }

    @Test("A coloured fill recolours a region without replacing it")
    func fillRecolours() {
        let engine = world()
        engine.drawBrush(centerX: 10, centerY: 10, radius: 2, elementID: Element.stone, shape: .square)
        engine.drawBrush(centerX: 10, centerY: 10, radius: 0, elementID: Element.stone, shape: .fill, tint: teal)
        for y in 8 ... 12 {
            for x in 8 ... 12 { #expect(engine.tintAt(x, y) == teal) }
        }
        #expect(engine.tintedCellCount == 25, "the fill spilled beyond the stone")
        // A fill without a colour on the same material still does nothing at all.
        engine.drawBrush(centerX: 10, centerY: 10, radius: 0, elementID: Element.stone, shape: .fill)
        #expect(engine.tintAt(10, 10) == teal)
    }

    @Test("Resizing and redrawing at another size keep colours on their grains")
    func resizingKeepsColours() {
        let engine = world()
        engine.setElement(3, 3, Element.stone)
        engine.setTint(3, 3, pink)
        engine.resize(width: 40, height: 30)
        #expect(engine.tintAt(3, 3) == pink)
        engine.resample(width: 80, height: 60)
        #expect(engine.tintAt(6, 6) == pink)
        #expect(engine.tintMayExist)
    }

    @Test("A photograph becomes the materials that look like it")
    func photoMaterials() {
        #expect(PowderEngine.pictureMaterial(red: 135, green: 206, blue: 235) == Element.water, "sky blue")
        #expect(PowderEngine.pictureMaterial(red: 250, green: 250, blue: 250) == Element.snow, "white")
        #expect(PowderEngine.pictureMaterial(red: 240, green: 80, blue: 20) == Element.lava, "fierce orange")
        #expect(PowderEngine.pictureMaterial(red: 224, green: 172, blue: 105) == Element.sand, "a face is not lava")
        #expect(PowderEngine.pictureMaterial(red: 30, green: 30, blue: 30) == Element.sand, "dark")
        #expect(PowderEngine.pictureMaterial(red: 60, green: 160, blue: 60) == Element.sand, "green")
    }

    @Test("A photograph is laid in to fit, keeping its shape and its colours")
    func placingAPicture() {
        let engine = PowderEngine(width: 40, height: 40, seed: 2)
        // Two points across, one down: sky on the left, a see-through point on the right.
        let picture: [UInt8] = [135, 206, 235, 255, 10, 10, 10, 0]
        let placed = engine.placePicture(rgba: picture, width: 2, height: 1, fill: 1)
        // Forty across and twenty down, of which only the left half is solid.
        #expect(placed == 20 * 20)
        #expect(engine.type[engine.index(5, 15)] == Element.water)
        #expect(engine.tintAt(5, 15) == PowderEngine.tintWord(red: 135, green: 206, blue: 235))
        #expect(engine.type[engine.index(30, 15)] == Element.empty, "a see-through point was filled in")
        #expect(engine.type[engine.index(5, 5)] == Element.empty, "the picture was stretched to the world's shape")

        // A picture whose bytes do not match its size is refused rather than guessed at.
        #expect(engine.placePicture(rgba: [1, 2, 3], width: 2, height: 2) == 0)
    }

    @Test("A stroke from another phone arrives in the material's own colour")
    func roomStrokesCarryNoColour() {
        let engine = world()
        #expect(engine.apply(RoomStroke(x: 10, y: 10, radius: 1, elementID: Element.sand, shape: .circle)))
        #expect(engine.tintedCellCount == 0)
    }
}
