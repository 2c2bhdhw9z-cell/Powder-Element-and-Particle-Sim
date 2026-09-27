import Foundation
import Testing

@testable import CrucibleCore

/// Old saves keep opening, and broken ones complain instead of crashing.
///
/// ## The saved worlds
///
/// `saved-2026-09-27-powder.json` and `saved-2026-09-27-field.json` were written by the app as it was on that day and
/// are **never to be regenerated**. They are what a person's own saved worlds look like, and the promise these tests
/// keep is that a world saved today still opens after every change made from now on. When a change makes one of
/// them fail, the change is what has to give — or, if the format really must move on, the new build has to read the
/// old file anyway and this test says so. Add a new dated file beside them when the format grows; never replace one.
///
/// ## Broken files
///
/// Every loader is handed saves cut short at every length, nonsense in every field, and room frames half arrived.
/// None of it may crash, and a world that refuses a file must be left exactly as it was: for somebody with no
/// debugger, a world that cannot be opened is lost, and a crash is worse.
@Suite("Old saves open, and broken ones are refused")
struct SavedWorldTests {
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    private func data(_ name: String) throws -> Data {
        try Data(contentsOf: Self.fixtures.appendingPathComponent(name))
    }

    // MARK: - Old saves

    @Test("The powder world saved on 27 September 2026 still opens, as it was")
    func powderSaveOpens() throws {
        let state = try JSONDecoder().decode(PowderState.self, from: data("saved-2026-09-27-powder.json"))
        let engine = PowderEngine(width: 10, height: 10, seed: 1)
        #expect(engine.apply(state))
        #expect(engine.width == 60 && engine.height == 90)
        var counts: [ElementID: Int] = [:]
        for i in 0 ..< engine.cellCount { counts[engine.type[i], default: 0] += 1 }
        #expect(counts[Element.sand] == 462)
        #expect(counts[Element.glass] == 208)
        #expect(counts[Element.wood] == 292)
        #expect(counts[Element.kernel] == 1, "the app's own materials were lost")
        #expect(counts[Element.belt] == 1)
        #expect(counts[Element.fan] == 1)
        #expect(counts[Element.lava] == 1)
        #expect(engine.tintedCellCount > 0, "the colours painted into it were lost")
        #expect(engine.inspect().corruptTypeCount == 0)
        // And it runs.
        for _ in 0 ..< 30 { engine.step() }
    }

    @Test("The particle field saved on 27 September 2026 still opens, as it was")
    func fieldSaveOpens() throws {
        let state = try JSONDecoder().decode(ParticleState.self, from: data("saved-2026-09-27-field.json"))
        let engine = ParticleEngine(width: 100, height: 100, seed: 1)
        #expect(engine.apply(state))
        #expect(engine.width == 400 && engine.height == 700)
        #expect(engine.arrangement == "jellyfish")
        #expect(engine.particles.count == 299)
        #expect(engine.swarm.count == 300)
        #expect(engine.springs.count == 563)
        #expect(engine.springs.filter(\.isMuscle).count == 21, "the muscles came back as plain springs")
        #expect(engine.forceLoops.count == 1 && engine.forceLoops.first?.mode == .vortex)
        #expect(engine.jellies.count == 1)
        #expect(engine.ribbons.count == 1)
        let camera = try #require(state.camera)
        #expect(camera.zoom == 1.4 && camera.flyIn == 0.25 && camera.focusBlur == 0.4 && camera.centreX == 10)
        for _ in 0 ..< 30 { engine.step() }
        let usable = engine.particles.allSatisfy { $0.isFinite }
        #expect(usable)
    }

    // MARK: - Broken saves

    @Test("A powder save cut short anywhere is refused, and the world is left alone")
    func truncatedPowderSaves() throws {
        let whole = try data("saved-2026-09-27-powder.json")
        let engine = PowderEngine(width: 20, height: 20, seed: 1)
        engine.setElement(3, 3, Element.stone)
        let before = Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount))
        var refused = 0
        // Every hundredth length, and every length of the first and last hundred bytes.
        let lengths = Array(0 ..< 100) + Array(stride(from: 100, to: whole.count - 100, by: 97))
            + Array((whole.count - 100) ..< whole.count)
        for length in lengths {
            let cut = whole.prefix(length)
            if let state = try? JSONDecoder().decode(PowderState.self, from: cut) {
                // A cut that still happens to be a whole document is allowed to load; anything else is refused.
                _ = engine.apply(state)
            } else {
                refused += 1
            }
        }
        #expect(refused > lengths.count - 3)
        #expect(Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount)) == before)
    }

    @Test("A field save cut short anywhere is refused")
    func truncatedFieldSaves() throws {
        let whole = try data("saved-2026-09-27-field.json")
        for length in stride(from: 0, to: whole.count, by: 211) {
            #expect((try? JSONDecoder().decode(ParticleState.self, from: whole.prefix(length))) == nil)
        }
    }

    @Test("Nonsense in every field of a powder save is refused or made harmless")
    func nonsensePowderSaves() throws {
        let engine = PowderEngine(width: 20, height: 20, seed: 1)
        let bad: [PowderState] = [
            PowderState(width: -5, height: 10, gridType: [], gridTemp: [], gridLife: [], gravityX: 0, gravityY: 1, windX: 0, ambientTemp: 20),
            PowderState(width: 100_000, height: 100_000, gridType: [], gridTemp: [], gridLife: [], gravityX: 0, gravityY: 1, windX: 0, ambientTemp: 20),
            PowderState(width: 4, height: 4, gridType: [9999, 65535, 1, 2], gridTemp: [.nan, .infinity, -.infinity, 1e30],
                        gridLife: [], gravityX: .infinity, gravityY: -.nan, windX: 1e300, ambientTemp: .nan,
                        gridTint: "!!!not base64"),
            PowderState(width: 4, height: 4, gridType: Array(repeating: 1, count: 3), gridTemp: [], gridLife: Array(repeating: 65535, count: 99),
                        gravityX: 0, gravityY: 1, windX: 0, ambientTemp: 20, gridTint: "AAAA"),
        ]
        for state in bad {
            _ = engine.apply(state)
            #expect(engine.inspect().corruptTypeCount == 0)
            for _ in 0 ..< 5 { engine.step() }
            for i in 0 ..< engine.cellCount { #expect(engine.temperature[i].isFinite) }
            #expect(engine.gravityX.isFinite && engine.gravityY.isFinite && engine.windX.isFinite)
        }
    }

    @Test("Nonsense in a field save is refused or made harmless")
    func nonsenseFieldSaves() throws {
        var state = try JSONDecoder().decode(ParticleState.self, from: data("saved-2026-09-27-field.json"))
        state.width = 1e12
        state.height = 1e12
        state.maxParticles = -4
        state.springs = [SpringRecord(a: 0, b: 999_999, rest: -1, k: .infinity)]
        state.loops = [ForceLoopRecord(mode: "not a tool", reach: .nan, strength: 1e9, x: [], y: [], z: [])]
        state.jellies = [JellyRecord(members: [-1, 10_000_000, 3], x: [.nan, 1, 2], y: [0], firmness: 99)]
        state.particleLifeRules = [[.nan]]
        let engine = ParticleEngine(width: 400, height: 700, seed: 1)
        // A world a million million pixels across is refused outright, and the field is left as it was.
        #expect(!engine.apply(state))
        #expect(engine.width == 400)
        // At a size that is merely odd, everything else in the file is loaded and made harmless.
        state.width = 900
        state.height = 300
        #expect(engine.apply(state))
        for _ in 0 ..< 10 { engine.step() }
        let usable = engine.particles.allSatisfy { $0.isFinite }
        #expect(usable)
        #expect(engine.swarm.corruptCount() == 0)
        #expect(engine.forceLoops.isEmpty, "a loop made of a tool that does not exist was kept")
        #expect(engine.jellies.isEmpty, "a jelly of bodies that do not exist was kept")
    }

    // MARK: - Room frames

    @Test("A room frame arriving in pieces, or as rubbish, is refused")
    func brokenRoomFrames() throws {
        let engine = PowderEngine(width: 40, height: 30, seed: 3)
        for x in 0 ..< 40 { engine.setElement(x, 29, Element.bedrock) }
        engine.drawBrush(centerX: 20, centerY: 10, radius: 4, elementID: Element.sand, shape: .circle)
        let frame = try #require(engine.captureRoomWorld(sequence: 7).encoded())
        #expect(RoomWorld.decode(frame) != nil)
        for length in 0 ..< frame.count {
            #expect(RoomWorld.decode(Array(frame.prefix(length))) == nil, "a frame cut to \(length) bytes was accepted")
        }
        var random = Mulberry32(seed: 5)
        for _ in 0 ..< 500 {
            let size = Int(random.next() * 300)
            let rubbish = (0 ..< size).map { _ in UInt8(truncatingIfNeeded: Int(random.next() * 256)) }
            if let decoded = RoomWorld.decode(rubbish) {
                // Rubbish that happens to decode must still be a world that can be adopted without harm.
                let receiver = PowderEngine(width: 10, height: 10, seed: 1)
                _ = receiver.apply(roomWorld: decoded)
                #expect(receiver.inspect().corruptTypeCount == 0)
            }
        }
        // And every other kind of message, cut short.
        let message = RoomMessage.stroke(RoomStroke(x: 1, y: 2, radius: 3, elementID: Element.water, shape: .circle))
        let text = try JSONEncoder().encode(message)
        #expect((try? JSONDecoder().decode(RoomMessage.self, from: text)) != nil)
        for length in 0 ..< text.count - 1 {
            #expect((try? JSONDecoder().decode(RoomMessage.self, from: text.prefix(length))) == nil)
        }
    }
}
