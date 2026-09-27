import Testing

@testable import CrucibleCore

/// Writing a picture out as a PNG with nothing but arithmetic.
///
/// The claims worth making are that the bytes are a real PNG — one any reader opens — and that the pixels inside are the
/// ones that went in. The checks below take the file apart again and prove both, rather than trusting that it looked
/// right.
@Suite("Pictures out, with no libraries")
struct PNGTests {
    /// Every block in a PNG, in order, with its name and contents.
    private func blocks(_ file: [UInt8]) -> [(name: String, contents: [UInt8])] {
        var found: [(String, [UInt8])] = []
        var at = 8
        while at + 8 <= file.count {
            let length = Int(file[at]) << 24 | Int(file[at + 1]) << 16 | Int(file[at + 2]) << 8 | Int(file[at + 3])
            let name = String(decoding: file[at + 4 ..< at + 8], as: UTF8.self)
            let start = at + 8
            guard start + length + 4 <= file.count else { break }
            let contents = Array(file[start ..< start + length])
            // The checksum, checked the way a reader checks it: over the name and the contents together.
            let recorded = UInt32(file[start + length]) << 24 | UInt32(file[start + length + 1]) << 16
                | UInt32(file[start + length + 2]) << 8 | UInt32(file[start + length + 3])
            var named = Array(name.utf8)
            named.append(contentsOf: contents)
            #expect(PNG.crc32(named) == recorded, "the checksum on the \(name) block is wrong")
            found.append((name, contents))
            at = start + length + 4
        }
        return found
    }

    /// The rows of pixels back out of a stored zlib stream: the filter byte, then three bytes a pixel.
    private func pixels(from stream: [UInt8], width: Int, height: Int) -> [[UInt8]] {
        // Two bytes of header, then blocks of "stored" contents, then four bytes of checksum.
        var raw: [UInt8] = []
        var at = 2
        while at + 5 <= stream.count {
            let last = stream[at]
            let length = Int(stream[at + 1]) | Int(stream[at + 2]) << 8
            let inverted = Int(stream[at + 3]) | Int(stream[at + 4]) << 8
            #expect(length ^ 0xFFFF == inverted, "a block's length was not written twice, once inverted")
            let start = at + 5
            guard start + length <= stream.count else { break }
            raw.append(contentsOf: stream[start ..< start + length])
            at = start + length
            if last == 1 { break }
        }
        #expect(PNG.adler32(raw) != 0)
        var rows: [[UInt8]] = []
        var index = 0
        for _ in 0 ..< height {
            guard index < raw.count else { break }
            #expect(raw[index] == 0, "a row said its pixels had been altered")
            index += 1
            let until = min(index + width * 3, raw.count)
            rows.append(Array(raw[index ..< until]))
            index = until
        }
        return rows
    }

    @Test("The bytes are a real PNG, in the right order, with real checksums")
    func itIsARealPNG() throws {
        let colours: [UInt32] = [
            0x00_00_00_FF, 0x00_00_FF_00, // red, green
            0x00_FF_00_00, 0x00_FF_FF_FF, // blue, white
        ]
        let file = try #require(PNG.bytes(from: colours, width: 2, height: 2))
        // The eight bytes every PNG starts with.
        #expect(Array(file.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let found = blocks(file)
        #expect(found.map(\.name) == ["IHDR", "IDAT", "IEND"])

        // What the header says it is: two by two, eight bits a channel, red-green-blue, no interlacing.
        let header = found[0].contents
        #expect(header.count == 13)
        #expect(Array(header.prefix(4)) == PNG.fourBytes(2))
        #expect(Array(header[4 ..< 8]) == PNG.fourBytes(2))
        #expect(Array(header[8 ..< 13]) == [8, 2, 0, 0, 0])
        #expect(found[2].contents.isEmpty)
    }

    @Test("The pixels that come out are the pixels that went in")
    func thePixelsSurvive() throws {
        // Deliberately not symmetrical, so a picture written upside down or with its channels swapped fails.
        let colours: [UInt32] = [
            0x00_00_00_FF, 0x00_00_FF_00, 0x00_FF_00_00,
            0x00_10_20_30, 0x00_FF_FF_FF, 0x00_00_00_00,
        ]
        let file = try #require(PNG.bytes(from: colours, width: 3, height: 2))
        let stream = blocks(file).first { $0.name == "IDAT" }?.contents ?? []
        let rows = pixels(from: stream, width: 3, height: 2)
        #expect(rows.count == 2)
        // Red first, then green, then blue — the order a PNG wants, from colours the engine packs the other way round.
        #expect(rows[0] == [0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0xFF])
        #expect(rows[1] == [0x30, 0x20, 0x10, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00])
    }

    @Test("Enlarging repeats whole pixels rather than blending them")
    func enlargingKeepsItCrisp() throws {
        let colours: [UInt32] = [0x00_00_00_FF, 0x00_FF_00_00]
        let file = try #require(PNG.bytes(from: colours, width: 2, height: 1, scale: 3))
        let header = blocks(file).first { $0.name == "IHDR" }?.contents ?? []
        #expect(Array(header.prefix(4)) == PNG.fourBytes(6))
        #expect(Array(header[4 ..< 8]) == PNG.fourBytes(3))

        let stream = blocks(file).first { $0.name == "IDAT" }?.contents ?? []
        let rows = pixels(from: stream, width: 6, height: 3)
        #expect(rows.count == 3)
        // Three identical rows of three reds then three blues. Nothing in between, which is what blending would give.
        let wanted: [UInt8] = [0xFF, 0, 0, 0xFF, 0, 0, 0xFF, 0, 0, 0, 0, 0xFF, 0, 0, 0xFF, 0, 0, 0xFF]
        for row in rows { #expect(row == wanted) }
    }

    @Test("A whole world becomes a picture, with no phone and nothing imported")
    func aWorldBecomesAPicture() throws {
        let engine = PowderEngine(width: 40, height: 30, seed: 3)
        for x in 0 ..< 40 { engine.setElement(x, 29, Element.bedrock) }
        engine.drawBrush(centerX: 20, centerY: 10, radius: 6, elementID: Element.sand, shape: .circle)
        engine.setElement(5, 5, Element.lava, temp: 1_100)
        for _ in 0 ..< 60 { engine.step() }

        let file = try #require(engine.pngBytes())
        let found = blocks(file)
        #expect(found.map(\.name) == ["IHDR", "IDAT", "IEND"])
        let header = found[0].contents
        #expect(Array(header.prefix(4)) == PNG.fourBytes(40))
        #expect(Array(header[4 ..< 8]) == PNG.fourBytes(30))

        // The picture is the same picture the screen would show: taken from the one renderer.
        var pixelsIn = [UInt32](repeating: 0, count: engine.cellCount)
        pixelsIn.withUnsafeMutableBufferPointer { engine.render(into: $0.baseAddress!, overlay: .normal) }
        let rows = pixels(from: found[1].contents, width: 40, height: 30)
        #expect(rows.count == 30)
        let firstIn = pixelsIn[0]
        #expect(rows[0][0] == UInt8(truncatingIfNeeded: firstIn))
        #expect(rows[0][1] == UInt8(truncatingIfNeeded: firstIn >> 8))
        #expect(rows[0][2] == UInt8(truncatingIfNeeded: firstIn >> 16))

        // A heat view gives a different picture, and an enlarged one is bigger.
        #expect(engine.pngBytes(overlay: .temperature) != file)
        #expect((engine.pngBytes(scale: 2)?.count ?? 0) > file.count * 3)
    }

    @Test("A picture too big for one block is split into as many as it needs")
    func bigPicturesAreSplit() throws {
        // Over sixty-five thousand bytes of pixels, so the stream has to be more than one block.
        let width = 200
        let height = 200
        let colours = (0 ..< width * height).map { UInt32($0 % 255) }
        let file = try #require(PNG.bytes(from: colours, width: width, height: height))
        let stream = blocks(file).first { $0.name == "IDAT" }?.contents ?? []
        // Each block carries at most sixty-five thousand five hundred and thirty-five bytes, and 200 rows of 601 bytes
        // is over a hundred and twenty thousand.
        #expect(stream.count > 120_000)
        let rows = pixels(from: stream, width: width, height: height)
        #expect(rows.count == height, "a picture across several blocks came back short")
        #expect(rows.allSatisfy { $0.count == width * 3 })
        // And the last row is right, which is what proves the blocks were joined in order.
        let lastIn = colours[(height - 1) * width]
        #expect(rows[height - 1][0] == UInt8(truncatingIfNeeded: lastIn))
    }

    @Test("Nonsense is refused rather than written out as a broken file")
    func nonsenseIsRefused() {
        #expect(PNG.bytes(from: [], width: 0, height: 0) == nil)
        #expect(PNG.bytes(from: [1, 2], width: 4, height: 4) == nil, "a picture with too few pixels was written")
        #expect(PNG.bytes(from: [1, 2, 3, 4], width: -2, height: 2) == nil)
        #expect(PowderEngine(width: 0, height: 0, seed: 1).pngBytes() == nil)
        // A scale below one is treated as one rather than producing an empty picture.
        #expect(PNG.bytes(from: [1], width: 1, height: 1, scale: 0) == PNG.bytes(from: [1], width: 1, height: 1))
    }

    @Test("The checksums match what the format says they should be")
    func theChecksumsAreRight() {
        // Known answers, so a rewrite of either cannot quietly change them.
        #expect(PNG.crc32(Array("IEND".utf8)) == 0xAE42_6082)
        #expect(PNG.adler32([]) == 1)
        // "abc": the low sum is 1+97+98+99 = 295, and the high sum is 98+196+295 = 589.
        #expect(PNG.adler32(Array("abc".utf8)) == 0x024D_0127)
        #expect(PNG.adler32(Array("abc".utf8)) & 0xFFFF == 295)
        #expect(PNG.adler32(Array("abc".utf8)) >> 16 == 589)
        #expect(PNG.fourBytes(0x1234_5678) == [0x12, 0x34, 0x56, 0x78])
    }
}
