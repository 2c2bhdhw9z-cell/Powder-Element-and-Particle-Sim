import Foundation
import Testing

@testable import CrucibleCore

@Suite("PackedColor parsing and packing")
struct PackedColorTests {
    @Test("Six-digit hex parses each channel correctly")
    func sixDigitHex() {
        let color = PackedColor(hex: "#E0C068")
        #expect(color?.r == 0xE0)
        #expect(color?.g == 0xC0)
        #expect(color?.b == 0x68)
        #expect(color?.a == 255, "a six-digit color is fully opaque")
    }

    @Test("Accepted spellings all land on the same color")
    func toleratedSpellings() {
        // Custom elements and hand-edited save files are the reason for this
        // tolerance: losing someone's element because they typed no leading hash
        // would be a poor trade.
        let canonical = PackedColor(hex: "#ff8800")
        #expect(PackedColor(hex: "ff8800") == canonical, "leading hash is optional")
        #expect(PackedColor(hex: "#FF8800") == canonical, "case-insensitive")
        #expect(PackedColor(hex: "  #ff8800\n") == canonical, "surrounding whitespace ignored")
        #expect(PackedColor(hex: "#f80") == canonical, "three-digit shorthand expands by repeating nibbles")
        #expect(PackedColor(hex: "#ff8800ff") == canonical, "explicit opaque alpha")
    }

    @Test("Shorthand expansion reaches full white and full black")
    func shorthandExtremes() {
        #expect(PackedColor(hex: "#fff") == PackedColor(r: 255, g: 255, b: 255))
        #expect(PackedColor(hex: "#000") == PackedColor(r: 0, g: 0, b: 0))
    }

    @Test("Alpha is read when supplied")
    func alphaChannel() {
        #expect(PackedColor(hex: "#11223344")?.a == 0x44)
        #expect(PackedColor(hex: "#1234")?.a == 0x44)
    }

    @Test("Malformed input is rejected rather than guessed at")
    func malformedInputRejected() {
        let bad = ["", "#", "#f", "#ff", "#fffff", "#fffffff", "#covfefe", "#12 34 56", "0x112233", "rgb(1,2,3)"]
        for candidate in bad {
            #expect(PackedColor(hex: candidate) == nil, "\"\(candidate)\" should not parse")
        }
    }

    @Test("Packed word has red in the lowest byte and alpha in the highest")
    func packedByteOrder() {
        // This layout is what Metal's rgba8Unorm textures expect. Getting it
        // backwards would render the whole simulation with red and blue swapped.
        let color = PackedColor(r: 0x11, g: 0x22, b: 0x33, a: 0x44)
        #expect(color.packedRGBA == 0x4433_2211)
    }

    @Test("Packing round-trips")
    func packRoundTrip() {
        for candidate in [
            PackedColor(r: 0, g: 0, b: 0, a: 0),
            PackedColor(r: 255, g: 255, b: 255, a: 255),
            PackedColor(r: 1, g: 128, b: 254, a: 7),
        ] {
            #expect(PackedColor(packedRGBA: candidate.packedRGBA) == candidate)
        }
    }

    @Test("Hex string round-trips, and omits alpha when opaque")
    func hexStringRoundTrip() {
        let opaque = PackedColor(r: 0xE0, g: 0xC0, b: 0x68)
        #expect(opaque.hexString == "#e0c068")
        #expect(PackedColor(hex: opaque.hexString) == opaque)

        let translucent = PackedColor(r: 0x0A, g: 0x0B, b: 0x0C, a: 0x0D)
        #expect(translucent.hexString == "#0a0b0c0d")
        #expect(PackedColor(hex: translucent.hexString) == translucent)
    }

    @Test("Every byte value survives a hex round-trip")
    func exhaustiveChannelRoundTrip() {
        for value in UInt8.min ... UInt8.max {
            let color = PackedColor(r: value, g: value, b: value)
            #expect(PackedColor(hex: color.hexString) == color, "channel value \(value) failed")
        }
    }

    @Test("Codable encodes as a plain hex string")
    func codableUsesHexString() throws {
        // Scenes stay human-readable and interchangeable with the web reference
        // implementation's format, which stores colors as strings.
        struct Holder: Codable, Equatable {
            var color: PackedColor
        }
        let original = Holder(color: PackedColor(r: 0xAB, g: 0xCD, b: 0xEF))
        let data = try JSONEncoder().encode(original)
        let json = String(decoding: data, as: UTF8.self)
        // Extra `#` delimiters: the encoded text itself contains a quote
        // followed by a hash, which would close a singly-delimited raw string.
        #expect(json == ##"{"color":"#abcdef"}"##)
        let decoded = try JSONDecoder().decode(Holder.self, from: data)
        #expect(decoded == original)
    }

    @Test("Decoding a bad color reports a useful error instead of crashing")
    func codableRejectsBadColor() {
        struct Holder: Codable {
            var color: PackedColor
        }
        let data = Data(#"{"color":"not-a-color"}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(Holder.self, from: data)
        }
    }
}
