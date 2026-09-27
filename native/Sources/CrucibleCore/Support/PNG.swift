/// Writing a picture out as a PNG, with nothing but arithmetic.
///
/// ## Why this is here at all
///
/// The engine renders every world into plain pixels and imports nothing from anybody — no Apple frameworks, no
/// compression library, not even a maths library. That is what lets the physics be checked on any machine. But it also
/// meant a world could only become a *picture* on a phone, because turning pixels into a file was the app's job.
///
/// So: a day's world cannot be published without a phone, a world cannot be drawn by a machine with nobody's phone
/// involved, and the same engine running in a browser could compute a world and not show anybody. All three were
/// blocked by the same small gap, and this closes it — a PNG writer with no dependencies at all.
///
/// ## Why it stores rather than compresses
///
/// A PNG's pixels are wrapped in a zlib stream, and zlib streams may be *stored* — laid down as they are, in blocks,
/// with a checksum — rather than squeezed. That is a legal PNG that every reader in the world opens, and it is about
/// eighty lines of arithmetic instead of a compression library the engine is not allowed to have.
///
/// The cost is size: a stored picture is roughly its pixel count times four, plus a fraction. A day's world at eight
/// hundred by sixteen hundred is about five megabytes. For a picture a day that is nothing, and it buys the engine the
/// ability to produce one anywhere.
public enum PNG {
    /// A picture from packed colours, one per pixel, as the renderers produce them.
    ///
    /// - Parameters:
    ///   - colors: one colour a pixel, rows top to bottom. Blue in the high byte, as the engine packs them.
    ///   - width: how many pixels across.
    ///   - height: how many down.
    ///   - scale: whole-number enlargement, applied by repeating pixels rather than blending them, so a grain stays a
    ///     crisp square exactly as it is on screen.
    /// - Returns: the bytes of a PNG file, or nothing if the arguments do not describe a picture.
    public static func bytes(from colors: [UInt32], width: Int, height: Int, scale: Int = 1) -> [UInt8]? {
        guard width > 0, height > 0, colors.count >= width * height else { return nil }
        let factor = max(1, scale)
        let outWidth = width * factor
        let outHeight = height * factor

        // The raw image: each row preceded by a filter byte, which is nought — "this row is as it is".
        var raw: [UInt8] = []
        raw.reserveCapacity(outHeight * (outWidth * 3 + 1))
        for y in 0 ..< height {
            for _ in 0 ..< factor {
                raw.append(0)
                for x in 0 ..< width {
                    let packed = colors[y * width + x]
                    let red = UInt8(truncatingIfNeeded: packed)
                    let green = UInt8(truncatingIfNeeded: packed >> 8)
                    let blue = UInt8(truncatingIfNeeded: packed >> 16)
                    for _ in 0 ..< factor {
                        raw.append(red)
                        raw.append(green)
                        raw.append(blue)
                    }
                }
            }
        }

        var file: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        // What the picture is: its size, eight bits a channel, colour type 2 (red, green, blue), no interlacing.
        var header: [UInt8] = []
        header.append(contentsOf: fourBytes(UInt32(outWidth)))
        header.append(contentsOf: fourBytes(UInt32(outHeight)))
        header.append(contentsOf: [8, 2, 0, 0, 0])
        file.append(contentsOf: chunk("IHDR", header))
        file.append(contentsOf: chunk("IDAT", zlibStored(raw)))
        file.append(contentsOf: chunk("IEND", []))
        return file
    }

    // MARK: - The pieces a PNG is made of

    /// One labelled block: its length, its name, its contents, and a checksum of the last two.
    static func chunk(_ name: String, _ contents: [UInt8]) -> [UInt8] {
        var out = fourBytes(UInt32(contents.count))
        var named: [UInt8] = Array(name.utf8)
        named.append(contentsOf: contents)
        out.append(contentsOf: named)
        out.append(contentsOf: fourBytes(crc32(named)))
        return out
    }

    /// A zlib stream that stores its contents rather than squeezing them.
    ///
    /// Two bytes saying what kind of stream it is, then the contents in blocks of at most sixty-five thousand five
    /// hundred and thirty-five bytes — each with its length written twice, once inverted, which is what "stored" means
    /// in this format — and a checksum of everything at the end.
    static func zlibStored(_ contents: [UInt8]) -> [UInt8] {
        // 0x78 says "deflate, with a 32k window"; 0x01 makes the pair divide by thirty-one, which is the format's own
        // check on those two bytes.
        var out: [UInt8] = [0x78, 0x01]
        let most = 65_535
        var at = 0
        repeat {
            let length = min(most, contents.count - at)
            let last: UInt8 = at + length >= contents.count ? 1 : 0
            out.append(last)
            out.append(UInt8(length & 0xFF))
            out.append(UInt8((length >> 8) & 0xFF))
            let inverted = ~UInt16(truncatingIfNeeded: length)
            out.append(UInt8(inverted & 0xFF))
            out.append(UInt8((inverted >> 8) & 0xFF))
            if length > 0 {
                out.append(contentsOf: contents[at ..< at + length])
            }
            at += length
        } while at < contents.count
        out.append(contentsOf: fourBytes(adler32(contents)))
        return out
    }

    /// A number as four bytes, biggest first, which is how every length and checksum in a PNG is written.
    static func fourBytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
    }

    /// The table the checksum is built from, worked out once.
    ///
    /// Two hundred and fifty-six entries, each the result of pushing one byte through the polynomial the format names.
    /// Built rather than written out, because a mistyped digit in a table of two hundred and fifty-six would produce
    /// files that are subtly and untraceably broken.
    static let crcTable: [UInt32] = {
        (0 ..< 256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0 ..< 8 {
                value = (value & 1) != 0 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
            }
            return value
        }
    }()

    /// The checksum a PNG puts after every block.
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var value: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            value = crcTable[Int((value ^ UInt32(byte)) & 0xFF)] ^ (value >> 8)
        }
        return value ^ 0xFFFF_FFFF
    }

    /// The checksum a zlib stream ends with: two running sums, one of the bytes and one of those sums.
    static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var low: UInt32 = 1
        var high: UInt32 = 0
        // The largest prime below sixty-five thousand five hundred and thirty-six, which is what both sums are kept
        // inside. Taken every few thousand bytes rather than every byte, which is the usual way and cannot overflow.
        let prime: UInt32 = 65_521
        var at = 0
        while at < bytes.count {
            let until = min(at + 5_552, bytes.count)
            for index in at ..< until {
                low += UInt32(bytes[index])
                high += low
            }
            low %= prime
            high %= prime
            at = until
        }
        return (high << 16) | low
    }
}

extension ParticleEngine {
    /// The field as the bytes of a PNG file: soft dots, light adding up where bodies crowd.
    ///
    /// A likeness of the screen rather than a copy of it — the glow, the trails and the silhouettes are the GPU's, and
    /// are not here. See ``fieldPicture(scale:dotSize:)`` for what is and is not reproduced, and why.
    ///
    /// - Parameters:
    ///   - scale: whole-number enlargement. Dots grow with it.
    ///   - glowing: whether the bright parts spread light. Defaults to whatever the field's own glow is set to.
    public func pngBytes(scale: Int = 1, glowing: Bool? = nil) -> [UInt8]? {
        let factor = max(1, scale)
        let pixels = fieldPicture(scale: factor, glowing: glowing)
        guard !pixels.isEmpty else { return nil }
        // Already enlarged, dots and all, so the writer is handed the finished size and does no repeating of its own.
        return PNG.bytes(from: pixels, width: Int(width) * factor, height: Int(height) * factor)
    }
}

extension PowderEngine {
    /// The world as the bytes of a PNG file, with no phone and no libraries involved.
    ///
    /// - Parameters:
    ///   - overlay: which colours — the same choice the app offers.
    ///   - scale: whole-number enlargement. One grain becomes a square of this many pixels.
    public func pngBytes(overlay: PowderOverlayMode = .normal, scale: Int = 1) -> [UInt8]? {
        guard cellCount > 0 else { return nil }
        var pixels = [UInt32](repeating: 0, count: cellCount)
        pixels.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            render(into: base, overlay: overlay)
        }
        return PNG.bytes(from: pixels, width: width, height: height, scale: scale)
    }
}
