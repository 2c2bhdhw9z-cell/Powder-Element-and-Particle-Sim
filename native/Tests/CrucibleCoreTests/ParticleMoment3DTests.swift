@testable import CrucibleCore
import Foundation
import Testing

@Suite("A 3D moment")
struct ParticleMoment3DTests {
    /// Reads a zip's files back the way any reader would: by walking its local headers.
    static func unpack(_ bytes: [UInt8]) -> [(name: String, dataAt: Int, data: [UInt8], crc: UInt32)] {
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> UInt32 { UInt32(u16(at)) | UInt32(u16(at + 2)) << 16 }
        var found: [(String, Int, [UInt8], UInt32)] = []
        var at = 0
        while at + 30 <= bytes.count, u32(at) == 0x0403_4B50 {
            let method = u16(at + 8)
            #expect(method == 0, "a usdz must not be compressed")
            let crc = u32(at + 14)
            let size = Int(u32(at + 18))
            let nameLength = u16(at + 26)
            let extraLength = u16(at + 28)
            let name = String(decoding: bytes[(at + 30) ..< (at + 30 + nameLength)], as: UTF8.self)
            let dataAt = at + 30 + nameLength + extraLength
            found.append((name, dataAt, Array(bytes[dataAt ..< dataAt + size]), crc))
            at = dataAt + size
        }
        return found
    }

    static func galaxy(depth: Bool) -> ParticleEngine {
        let engine = ParticleEngine(width: 800, height: 600, seed: 3)
        engine.screenWidth = 800
        engine.screenHeight = 600
        if depth { engine.storedDepthEnabled = true }
        engine.loadArrangement("galaxy")
        for _ in 0 ..< 30 { engine.step() }
        return engine
    }

    @Test("It is a zip with nothing compressed, every file on a sixty-four byte boundary, and checksums that match")
    func isAUsdz() {
        let bytes = Self.galaxy(depth: false).moment3D()
        let files = Self.unpack(bytes)
        #expect(files.count == 1)
        for file in files {
            #expect(file.dataAt % 64 == 0, "\(file.name) starts at \(file.dataAt)")
            #expect(PNG.crc32(file.data) == file.crc)
        }
        #expect(files.first?.name == "moment.usda")
        // And the directory at the end says where to find everything.
        let end = Array(bytes.suffix(22))
        #expect(end.prefix(4) == [0x50, 0x4B, 0x05, 0x06])
    }

    @Test("Inside, every body is a solid with a colour, and the scene says which way is up")
    func theScene() throws {
        let engine = Self.galaxy(depth: true)
        let file = try #require(Self.unpack(engine.moment3D()).first)
        let text = String(decoding: file.data, as: UTF8.self)
        #expect(text.hasPrefix("#usda 1.0"))
        #expect(text.contains("upAxis = \"Y\""))
        #expect(text.contains("defaultPrim = \"Moment\""))
        #expect(!text.contains("nan") && !text.contains(", inf") && !text.contains("(inf") && !text.contains("-inf"))
        let meshes = text.components(separatedBy: "def Mesh").count - 1
        let materials = text.components(separatedBy: "def Material").count - 1
        #expect(meshes >= 1 && meshes <= ParticleEngine.momentColours)
        #expect(materials == meshes)
        // Every shape says it carries a material, or strict readers ignore the binding. USD's own validator found this.
        #expect(text.components(separatedBy: "prepend apiSchemas = [\"MaterialBindingAPI\"]").count - 1 == meshes)
        // Every body, as eight faces of three corners each.
        let expected = engine.momentBodies(most: ParticleEngine.momentMostBodies).count
        let faces = text.components(separatedBy: "\"3").count
        _ = faces
        var counted = 0
        for line in text.split(separator: "\n") where line.contains("faceVertexCounts") {
            counted += line.components(separatedBy: "3").count - 1
        }
        #expect(counted >= expected * 8)
    }

    @Test("A crowd far too big is sampled evenly, not cut off at one end")
    func bigCrowdSampled() {
        let engine = ParticleEngine(width: 1000, height: 1000, seed: 3)
        engine.screenWidth = 1000
        engine.screenHeight = 1000
        engine.spawnSwarmScene(count: 50_000)
        let bodies = engine.momentBodies(most: ParticleEngine.momentMostBodies)
        #expect(bodies.count <= ParticleEngine.momentMostBodies)
        #expect(bodies.count > ParticleEngine.momentMostBodies / 2)
        let lowest = bodies.map(\.y).min() ?? 0
        let highest = bodies.map(\.y).max() ?? 0
        #expect(highest - lowest > 500, "the sample only covered \(lowest) to \(highest)")
    }

    @Test("It is about as big as it was asked to be, and sits on the table rather than through it")
    func size() throws {
        let engine = Self.galaxy(depth: false)
        let text = engine.momentScene(sizeInMetres: 0.3)
        let numbers = text.split(separator: "\n").filter { $0.contains("point3f[] points") }
            .flatMap { line in line.split(whereSeparator: { "()[],= ".contains($0) }).compactMap { Double($0) } }
        #expect(!numbers.isEmpty)
        let ys = stride(from: 1, to: numbers.count, by: 3).map { numbers[$0] }
        #expect(abs(ys.min() ?? -1) < 0.001, "its lowest point was \(ys.min() ?? 0), not on the table")
        #expect((numbers.map(abs).max() ?? 9) < 0.35)
    }

    @Test("An empty field is still a file that opens")
    func empty() {
        let engine = ParticleEngine(width: 100, height: 100, seed: 1)
        let files = Self.unpack(engine.moment3D())
        #expect(files.count == 1)
        let text = String(decoding: files.first?.data ?? [], as: UTF8.self)
        #expect(text.contains("def Xform \"Moment\""))
    }
}

@Suite("A 3D moment, written out")
struct ParticleMoment3DFileTests {
    @Test("Written to a file when asked, for opening with somebody else's reader")
    func writeForChecking() throws {
        guard let path = ProcessInfo.processInfo.environment["CRUCIBLE_WRITE_MOMENT"] else { return }
        let engine = ParticleEngine(width: 800, height: 600, seed: 3)
        engine.screenWidth = 800
        engine.screenHeight = 600
        engine.storedDepthEnabled = true
        engine.loadArrangement("galaxy")
        for _ in 0 ..< 30 { engine.step() }
        try Data(engine.moment3D()).write(to: URL(fileURLWithPath: path))
    }
}
