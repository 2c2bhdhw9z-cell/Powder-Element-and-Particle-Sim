import Foundation
import Testing

@testable import CrucibleCore

/// Saving, loading, undo, and the compact format two players exchange.
///
/// Everything here reads data the simulation did not produce: a file someone edited, an
/// autosave from a build that crashed mid-write, a packet from a peer on another version.
/// The failure that matters is not a crash — it is a world that looks loaded and is
/// quietly wrong. Each of these began as exactly that.
@Suite("Powder saving, loading and undo")
struct PowderPersistenceTests {
    /// A small world with a few recognisable things in it.
    private func makeWorld(width: Int = 24, height: Int = 18) -> PowderEngine {
        let engine = PowderEngine(width: width, height: height, seed: 1234)
        engine.setElement(3, 4, Element.sand)
        engine.setElement(10, 12, Element.bedrock)
        engine.setElement(5, 5, Element.water, temp: 45)
        engine.setElement(7, 2, Element.fire)
        engine.gravityX = 0.25
        engine.ambientTemp = 18
        engine.setWind(2)
        return engine
    }

    // MARK: - Full fidelity

    @Test("A world survives a round trip through the save format")
    func stateRoundTrips() {
        let source = makeWorld()
        let state = source.captureState()

        let target = PowderEngine(width: 8, height: 8, seed: 1)
        #expect(target.apply(state))

        #expect(target.width == source.width)
        #expect(target.height == source.height)
        for i in 0 ..< source.cellCount {
            #expect(target.type[i] == source.type[i], "cell \(i) holds a different element")
            #expect(target.temperature[i] == source.temperature[i], "cell \(i) is a different temperature")
            #expect(target.life[i] == source.life[i], "cell \(i) has a different lifetime")
        }
        #expect(target.gravityX == source.gravityX)
        #expect(target.ambientTemp == source.ambientTemp)
        #expect(target.windX == source.windX)
    }

    @Test("A world survives a round trip through JSON")
    func stateRoundTripsThroughJSON() throws {
        // The engine defines the shape and leaves JSON to the caller, so this is the test
        // that the two halves of that split actually meet.
        let source = makeWorld()
        let data = try JSONEncoder().encode(source.captureState())
        let decoded = try JSONDecoder().decode(PowderState.self, from: data)

        let target = PowderEngine(width: 4, height: 4, seed: 1)
        #expect(target.apply(decoded))
        #expect(target.hashLite() == source.hashLite())
    }

    @Test("The saved field names match the web implementation's")
    func stateUsesTheWebFieldNames() throws {
        // A scene saved in a browser has to open in the app and vice versa, which comes
        // down to these names.
        let data = try JSONEncoder().encode(makeWorld(width: 2, height: 2).captureState())
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        for key in [
            "width", "height", "gridType", "gridTemp", "gridLife",
            "gravityX", "gravityY", "windX", "ambientTemp",
        ] {
            #expect(object[key] != nil, "the save format is missing \(key)")
        }
    }

    @Test("A size that cannot be used is refused rather than loaded crooked")
    func refusesAnUnusableSize() {
        let engine = makeWorld()
        let before = Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount))

        for (width, height) in [(0, 10), (10, 0), (-4, 10), (PowderEngine.maximumDimension + 1, 10)] {
            var state = engine.captureState()
            state.width = width
            state.height = height
            // The declared width sets the length of every row, so applying the cells
            // under a size that was never adopted lays each row down at the wrong offset
            // and the whole world slides diagonally. Silently, before this check.
            #expect(!engine.apply(state), "\(width)x\(height) should have been refused")
        }

        #expect(engine.width == 24)
        #expect(Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount)) == before)
    }

    @Test("Values that make no sense are replaced rather than stored")
    func sanitisesBadValues() {
        let engine = PowderEngine(width: 4, height: 4, seed: 1)
        engine.ambientTemp = 20
        var state = engine.captureState()
        // An element nothing can describe, and a temperature that is not a number. The
        // first used to sit in the grid behaving as air while counting as a real particle
        // forever; the second spread through heat diffusion until the whole world was
        // unusable.
        state.gridType[0] = 9999
        state.gridType[1] = 400
        state.gridType[2] = Element.sand
        state.gridTemp[3] = .nan
        state.gridTemp[4] = .infinity
        state.windX = 900

        #expect(engine.apply(state))
        #expect(engine.type[0] == Element.empty)
        #expect(engine.type[1] == Element.empty)
        #expect(engine.type[2] == Element.sand)
        #expect(engine.temperature[3] == Float(20))
        #expect(engine.temperature[4] == Float(20))
        #expect(engine.windX <= 5, "wind has to come in through its clamp")
    }

    // MARK: - The compact wire format

    @Test("The compact payload is byte-identical to the web engine's", arguments: PowderGoldenTests.fixture.scenarios)
    func liteMatchesTheWebEngine(scenario: PowderGoldenTests.Scenario) {
        // Cross-play is the whole point of matching here. If the two encoders disagree by
        // a single byte, the host's "have we drifted apart?" check is true forever: it
        // resends the entire grid every tick and the two worlds never converge.
        let engine = PowderGoldenTests().play(scenario)
        #expect(
            engine.captureLiteState().t == scenario.liteBase64,
            "\(scenario.name): the compact payload differs from the web engine's"
        )
    }

    @Test("A layout survives a round trip through the compact format")
    func liteRoundTrips() {
        let source = makeWorld()
        let target = PowderEngine(width: 6, height: 6, seed: 1)
        #expect(target.apply(lite: source.captureLiteState()))

        #expect(target.width == source.width)
        #expect(target.height == source.height)
        for i in 0 ..< source.cellCount {
            #expect(target.type[i] == source.type[i], "cell \(i) holds a different element")
        }
        // The compact format carries no temperatures or lifetimes, so each cell is given
        // what its element should start with. Without that, incoming ice landed at the
        // temperature of the lava it replaced and melted on the spot, and incoming fire
        // arrived with no lifetime and vanished on the very next tick.
        let fireIndex = source.index(7, 2)
        #expect(target.life[fireIndex] > 0, "fire arrived with no lifetime")
    }

    @Test("Two worlds that send the same bytes fingerprint the same")
    func fingerprintFollowsTheWire() {
        let a = makeWorld()
        // An element that cannot fit in the single byte the wire format carries.
        a.type[100] = 300

        let b = PowderEngine(width: 24, height: 18, seed: 1)
        b.gravityX = a.gravityX
        #expect(b.apply(lite: a.captureLiteState()))

        // The fingerprint used to be taken from the raw cell while the encoder flattened
        // it, so the sender's fingerprint described a world the receiver could not build.
        #expect(b.hashLite() == a.hashLite())
    }

    @Test("An unreadable payload leaves the world alone")
    func badPayloadIsHarmless() {
        let engine = makeWorld()
        let before = Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount))

        // The world used to be cleared before the payload was decoded, so one damaged
        // message from a peer left the receiving player staring at nothing.
        #expect(!engine.apply(lite: PowderLiteState(w: 24, h: 18, t: "!!!! not base64 !!!!")))
        #expect(!engine.apply(lite: PowderLiteState(w: 0, h: 18, t: "AAAA")))
        #expect(Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount)) == before)
    }

    @Test("Base64 matches what a browser produces")
    func base64IsStandard() {
        // Checked against known values rather than against itself, so a round trip that
        // is self-consistently wrong cannot pass.
        #expect(Base64.encode(Array("".utf8)) == "")
        #expect(Base64.encode(Array("f".utf8)) == "Zg==")
        #expect(Base64.encode(Array("fo".utf8)) == "Zm8=")
        #expect(Base64.encode(Array("foo".utf8)) == "Zm9v")
        #expect(Base64.encode(Array("foob".utf8)) == "Zm9vYg==")
        #expect(Base64.encode(Array("fooba".utf8)) == "Zm9vYmE=")
        #expect(Base64.encode(Array("foobar".utf8)) == "Zm9vYmFy")
        #expect(Base64.encode([0, 1, 2, 253, 254, 255]) == "AAEC/f7/")

        #expect(Base64.decode("Zm9vYmFy").map { String(decoding: $0, as: UTF8.self) } == "foobar")
        #expect(Base64.decode("Zg==").map { String(decoding: $0, as: UTF8.self) } == "f")
        #expect(Base64.decode("AAEC/f7/") == [0, 1, 2, 253, 254, 255])
        #expect(Base64.decode("!!!") == nil, "invalid input has to be rejected, not guessed at")
        #expect(Base64.decode("Zm9v\nYmFy") != nil, "whitespace is tolerated")
    }

    @Test("Every byte value survives the round trip")
    func base64CoversEveryByte() {
        let all = (0 ... 255).map { UInt8($0) }
        #expect(Base64.decode(Base64.encode(all)) == all)
        // Every tail length, since the padding differs for each.
        for length in 0 ... 8 {
            let bytes = Array(all.prefix(length))
            #expect(Base64.decode(Base64.encode(bytes)) == bytes, "length \(length)")
        }
    }

    // MARK: - Undo

    @Test("Undo brings back the world and its settings together")
    func undoRestoresEverything() {
        let engine = makeWorld()
        let history = PowderHistory(maximumSteps: 5)
        let sandIndex = engine.index(3, 4)

        history.push(engine)
        engine.setElement(3, 4, Element.empty)
        engine.ambientTemp = -40
        engine.setWind(-5)

        #expect(history.undo(engine))
        #expect(engine.type[sandIndex] == Element.sand)
        #expect(engine.ambientTemp == 18)
        #expect(engine.windX == 2)
    }

    @Test("Redo puts the change back")
    func redoReappliesTheChange() {
        let engine = makeWorld()
        let history = PowderHistory(maximumSteps: 5)
        let index = engine.index(3, 4)

        history.push(engine)
        engine.setElement(3, 4, Element.empty)
        #expect(history.undo(engine))
        #expect(engine.type[index] == Element.sand)
        #expect(history.redo(engine))
        #expect(engine.type[index] == Element.empty)
    }

    @Test("Undo refuses a snapshot it cannot lay down, rather than shearing the world")
    func undoRefusesAnImpossibleSnapshot() {
        let engine = makeWorld()
        let history = PowderHistory(maximumSteps: 5)
        let before = Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount))

        // A snapshot whose size can never be adopted, which is what a refused resize
        // leaves behind. Laying it down anyway puts every row at the wrong offset.
        let forged = PowderHistory.Snapshot(
            width: 0,
            height: 0,
            type: [],
            temperature: [],
            life: [],
            gravityX: 0,
            gravityY: 1,
            windX: 0,
            ambientTemp: 20
        )
        #expect(!history.restore(engine, forged))
        #expect(engine.width == 24)
        #expect(Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount)) == before)
    }

    @Test("Cells the snapshot does not describe get the ambient being restored")
    func undoUsesTheRestoredAmbient() {
        let engine = PowderEngine(width: 8, height: 8, seed: 1)
        engine.ambientTemp = 100
        engine.resetGrid()
        engine.setElement(3, 3, Element.sand, temp: 450)

        let history = PowderHistory(maximumSteps: 5)
        history.push(engine)

        engine.ambientTemp = -50
        engine.resetGrid()
        #expect(history.undo(engine))

        // The ambient has to be in place before the clear, since the clear is what fills
        // the grid with it. Set afterwards, every untouched cell kept the temperature of
        // the world being replaced.
        #expect(engine.ambientTemp == 100)
        #expect(engine.temperature[engine.index(3, 3)] == Float(450))
        #expect(engine.temperature[0] == Float(100))
    }

    @Test("A depth of zero still gives one working step")
    func zeroDepthStillWorks() {
        // A limit of zero made the record discard the snapshot it had just taken, so undo
        // was permanently unavailable with nothing to say why.
        let engine = makeWorld()
        let history = PowderHistory(maximumSteps: 0)
        history.push(engine)
        #expect(history.canUndo)
    }

    @Test("The record never grows past its limit")
    func depthIsRespected() {
        let engine = PowderEngine(width: 8, height: 8, seed: 1)
        let history = PowderHistory(maximumSteps: 3)
        for i in 0 ..< 10 {
            history.push(engine)
            engine.setElement(i % 8, 0, Element.sand)
        }
        var taken = 0
        while history.undo(engine) { taken += 1 }
        #expect(taken == 3)
    }

    @Test("Recording a new step clears the redo trail")
    func pushClearsRedo() {
        let engine = makeWorld()
        let history = PowderHistory(maximumSteps: 5)
        history.push(engine)
        engine.setElement(3, 4, Element.empty)
        #expect(history.undo(engine))
        #expect(history.canRedo)
        // A new change makes the old future unreachable, so keeping it would let a redo
        // apply a world that never existed.
        history.push(engine)
        #expect(!history.canRedo)
    }
}
