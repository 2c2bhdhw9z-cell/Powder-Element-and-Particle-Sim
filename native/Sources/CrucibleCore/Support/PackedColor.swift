/// An 8-bit-per-channel RGBA color, laid out so it can be written straight into
/// a texture upload buffer.
///
/// The web reference implementation stores element colors as `"#RRGGBB"` strings
/// and re-parses them while filling its pixel buffer. Here the parse happens
/// once, when elements are loaded, and the simulation's draw path only ever
/// touches the packed integer form. That removes all string work from the render
/// loop.
///
/// The type is exactly four bytes with no padding, so an array of these is a
/// valid RGBA8 image buffer.
public struct PackedColor: Sendable, Hashable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    @inlinable
    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Fully transparent black — the value used for empty cells.
    public static let clear = PackedColor(r: 0, g: 0, b: 0, a: 0)

    /// Builds a colour from hue, saturation and lightness.
    ///
    /// The particle presets and the painter tool describe colours this way, and the
    /// web implementation builds a CSS string for each one and re-parses it. Doing the
    /// conversion directly avoids creating and parsing a string per particle per
    /// frame, which in painter mode is once for every particle under the finger.
    ///
    /// - Parameters:
    ///   - hue: Degrees. Wrapped, so any value is valid.
    ///   - saturation: `0 ... 1`.
    ///   - lightness: `0 ... 1`.
    public init(hue: Double, saturation: Double, lightness: Double, alpha: UInt8 = 255) {
        let h = ((hue.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 360
        let s = max(0, min(1, saturation))
        let l = max(0, min(1, lightness))

        func channel(_ offset: Double) -> UInt8 {
            guard s > 0 else { return UInt8(max(0, min(255, (l * 255).rounded()))) }
            let q = l < 0.5 ? l * (1 + s) : l + s - l * s
            let p = 2 * l - q
            var t = h + offset
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            let value: Double
            if t < 1.0 / 6.0 {
                value = p + (q - p) * 6 * t
            } else if t < 1.0 / 2.0 {
                value = q
            } else if t < 2.0 / 3.0 {
                value = p + (q - p) * (2.0 / 3.0 - t) * 6
            } else {
                value = p
            }
            return UInt8(max(0, min(255, (value * 255).rounded())))
        }

        self.init(
            r: channel(1.0 / 3.0),
            g: channel(0),
            b: channel(-1.0 / 3.0),
            a: alpha
        )
    }

    /// Parses a CSS-style hex color.
    ///
    /// Accepts `#RGB`, `#RGBA`, `#RRGGBB` and `#RRGGBBAA`, with or without the
    /// leading `#`, in either letter case, and tolerates surrounding whitespace.
    /// Returns `nil` for anything else.
    ///
    /// The registry's own 50 elements are all plain `#RRGGBB`; the wider set of
    /// accepted forms is for user-authored custom elements and hand-edited save
    /// files, where being forgiving is better than losing someone's work.
    public init?(hex: String) {
        var digits = Substring(hex)
        while let first = digits.first, first.isWhitespace { digits = digits.dropFirst() }
        while let last = digits.last, last.isWhitespace { digits = digits.dropLast() }
        if digits.first == "#" { digits = digits.dropFirst() }

        func value(_ character: Character) -> UInt8? {
            guard let digit = character.hexDigitValue, digit >= 0, digit <= 15 else { return nil }
            return UInt8(digit)
        }

        switch digits.count {
        case 3, 4:
            var channels: [UInt8] = []
            channels.reserveCapacity(4)
            for character in digits {
                guard let nibble = value(character) else { return nil }
                // Shorthand expands by repeating the nibble: `f` becomes `ff`.
                channels.append(nibble << 4 | nibble)
            }
            self.init(r: channels[0], g: channels[1], b: channels[2], a: channels.count == 4 ? channels[3] : 255)

        case 6, 8:
            var channels: [UInt8] = []
            channels.reserveCapacity(4)
            var iterator = digits.makeIterator()
            while let high = iterator.next(), let low = iterator.next() {
                guard let highNibble = value(high), let lowNibble = value(low) else { return nil }
                channels.append(highNibble << 4 | lowNibble)
            }
            self.init(r: channels[0], g: channels[1], b: channels[2], a: channels.count == 4 ? channels[3] : 255)

        default:
            return nil
        }
    }

    /// The color packed into a single 32-bit word whose in-memory byte order is
    /// red, green, blue, alpha.
    ///
    /// This is the layout Metal's `.rgba8Unorm` pixel format expects and matches
    /// what the web renderer's `Uint32Array` view produces. The shifts are
    /// written against little-endian byte order, which holds on every platform
    /// this project targets (Apple silicon and the x86 Linux test host).
    @inlinable
    public var packedRGBA: UInt32 {
        UInt32(r) | UInt32(g) << 8 | UInt32(b) << 16 | UInt32(a) << 24
    }

    /// Rebuilds a color from ``packedRGBA``.
    @inlinable
    public init(packedRGBA value: UInt32) {
        self.init(
            r: UInt8(truncatingIfNeeded: value),
            g: UInt8(truncatingIfNeeded: value >> 8),
            b: UInt8(truncatingIfNeeded: value >> 16),
            a: UInt8(truncatingIfNeeded: value >> 24)
        )
    }

    private static let hexDigits: [Character] = Array("0123456789abcdef")

    /// The color as a lowercase `#RRGGBB` string, or `#RRGGBBAA` when not fully
    /// opaque. Round-trips through ``init(hex:)``.
    ///
    /// Formatted by hand rather than with `String(format:)` so that this module
    /// needs no Foundation import at all — keeping the engine's dependency
    /// surface to the standard library alone.
    public var hexString: String {
        var out = "#"
        out.reserveCapacity(a == 255 ? 7 : 9)
        let channels: [UInt8] = a == 255 ? [r, g, b] : [r, g, b, a]
        for channel in channels {
            out.append(Self.hexDigits[Int(channel >> 4)])
            out.append(Self.hexDigits[Int(channel & 0x0f)])
        }
        return out
    }
}

extension PackedColor: Codable {
    /// Encoded as a hex string so save files and shared scenes stay readable and
    /// stay compatible with the web reference implementation's format.
    public init(from decoder: any Decoder) throws {
        let hex = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = PackedColor(hex: hex) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Not a hex color: \(hex)")
            )
        }
        self = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}

extension PackedColor: CustomStringConvertible {
    public var description: String { hexString }
}
