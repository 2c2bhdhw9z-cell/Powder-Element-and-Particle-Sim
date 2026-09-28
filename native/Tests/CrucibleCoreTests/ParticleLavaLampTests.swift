@testable import CrucibleCore
import Testing

@Suite("A lava lamp")
struct ParticleLavaLampTests {
    static func lamp() -> ParticleEngine {
        let engine = ParticleEngine(width: 400, height: 700, seed: 8)
        engine.screenWidth = 400
        engine.screenHeight = 700
        #expect(engine.loadArrangement("lavalamp"))
        return engine
    }

    @Test("It is blobs of wax, each with a warmth of its own")
    func blobs() {
        let engine = Self.lamp()
        #expect(engine.jellies.count == ParticleEngine.lampBlobs)
        #expect(engine.lampBlobs.count == ParticleEngine.lampBlobs)
        #expect(engine.lampWarmth.count == engine.lampBlobs.count)
    }

    @Test("The wax goes up and comes down again, over and over")
    func risesAndFalls() {
        let engine = Self.lamp()
        var crossings = 0
        var wasAbove: [Bool?] = Array(repeating: nil, count: engine.lampBlobs.count)
        for moment in 0 ..< 60 * 90 {
            engine.step()
            guard moment % 30 == 0 else { continue }
            var place: [Int: Int] = [:]
            for (index, body) in engine.particles.enumerated() { place[body.id] = index }
            for (index, blob) in engine.lampBlobs.enumerated() {
                let ys = blob.compactMap { place[$0] }.map { engine.particles[$0].y }
                guard !ys.isEmpty else { continue }
                let above = ys.reduce(0, +) / Double(ys.count) < 350
                if let was = wasAbove[index], was != above { crossings += 1 }
                wasAbove[index] = above
            }
        }
        #expect(crossings >= 10, "in a minute and a half the wax crossed the middle only \(crossings) times")
        #expect(engine.particles.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    @Test("Warm wax is orange and cold wax is red")
    func colours() {
        let engine = Self.lamp()
        for _ in 0 ..< 600 { engine.step() }
        var place: [Int: Int] = [:]
        for (index, body) in engine.particles.enumerated() { place[body.id] = index }
        for (index, blob) in engine.lampBlobs.enumerated() {
            guard let first = blob.first, let member = place[first] else { continue }
            let hue = ParticleEngine.hsl(engine.particles[member].color).hue
            let expected = 2 + 30 * engine.lampWarmth[index]
            #expect(abs(hue - expected) < 8, "blob \(index) is hue \(hue), warmth says \(expected)")
        }
    }

    @Test("Leaving the lamp forgets the wax's warmth")
    func leaving() {
        let engine = Self.lamp()
        engine.loadArrangement("galaxy")
        engine.step()
        #expect(engine.lampWarmth.isEmpty)
    }

    @Test("In 3D it is balls of wax in the box, rising and sinking too")
    func inDepth() {
        let engine = ParticleEngine(width: 400, height: 700, seed: 8)
        engine.screenWidth = 400
        engine.screenHeight = 700
        engine.storedDepthEnabled = true
        #expect(engine.loadArrangement("lavalamp"))
        #expect(engine.lampBlobs.count == ParticleEngine.lampBlobs)
        let before = engine.lampBlobs.map { blob in blob.count }
        #expect(before.allSatisfy { $0 > 10 })
        for _ in 0 ..< 600 { engine.step() }
        #expect(engine.particles.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
    }
}
