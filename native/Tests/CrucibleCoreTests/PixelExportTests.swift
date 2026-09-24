import Testing

@testable import CrucibleCore

/// The pixel export, which exists in the engine precisely so that it can be tested.
///
/// Both of the mistakes this guards against are invisible to whoever writes the code, because the
/// only way to see them is to look at a finished picture on a device:
///
///   - swapping red and blue gives a *plausible* picture — blue flame, orange water — that looks
///     deliberate enough to survive a glance;
///   - an off-by-one in the enlargement gives a one-pixel seam down the right edge of every
///     screenshot, or a picture one row short.
///
/// Neither fails and neither crashes.
@Suite("Pixels are exported in the right order and at the right size")
struct PixelExportTests {
    /// A recognisable colour whose three channels are all different, so any swap shows up.
    ///
    /// Deliberately not a shade of grey and not a pure primary: with red 0x11, green 0x22 and blue
    /// 0x33, every one of the six possible orderings produces a different answer.
    private static let sample = PackedColor(r: 0x11, g: 0x22, b: 0x33)

    private static var packed: UInt32 { sample.packedRGBA }

    // MARK: Channel order

    @Test("Red comes first, then green, then blue, then alpha")
    func channelOrder() {
        let bytes = PixelExport.rgbaBytes(from: [Self.packed], width: 1, height: 1)
        #expect(bytes.count == 4)
        #expect(bytes[0] == 0x11, "byte zero should be red, got \(bytes[0])")
        #expect(bytes[1] == 0x22, "byte one should be green, got \(bytes[1])")
        #expect(bytes[2] == 0x33, "byte two should be blue, got \(bytes[2])")
        #expect(bytes[3] == 0xFF)
    }

    /// The pairing with the engine's own packing. If `PackedColor` ever changed which byte held
    /// which channel, this is what would notice — the export reads the parts out by hand.
    @Test("The order agrees with how the engine packs a colour")
    func agreesWithPackedColor() {
        for (r, g, b) in [(0, 0, 0), (255, 255, 255), (1, 2, 3), (200, 100, 50), (0, 128, 255)] {
            let colour = PackedColor(r: UInt8(r), g: UInt8(g), b: UInt8(b))
            let bytes = PixelExport.rgbaBytes(from: [colour.packedRGBA], width: 1, height: 1)
            #expect(bytes[0] == UInt8(r), "red for \(r),\(g),\(b)")
            #expect(bytes[1] == UInt8(g), "green for \(r),\(g),\(b)")
            #expect(bytes[2] == UInt8(b), "blue for \(r),\(g),\(b)")
        }
    }

    @Test("Blue-first bytes are turned round, and green and alpha are left alone")
    func bgraIsReversed() {
        // One pixel, as a GPU hands it over: blue, green, red, alpha.
        let fromGPU: [UInt8] = [0x33, 0x22, 0x11, 0xF0]
        let bytes = PixelExport.rgbaBytes(fromBGRA: fromGPU)
        #expect(bytes == [0x11, 0x22, 0x33, 0xF0])
    }

    @Test("Turning blue-first bytes round twice gives back what went in")
    func reversingTwiceIsIdentity() {
        // The strongest statement available about a swap: it is its own inverse. A version that
        // moved the wrong pair, or moved three, would not survive this.
        let original: [UInt8] = [1, 2, 3, 4, 250, 251, 252, 253, 0, 99, 40, 7]
        let once = PixelExport.rgbaBytes(fromBGRA: original)
        let twice = PixelExport.rgbaBytes(fromBGRA: once)
        #expect(twice == original)
        #expect(once != original, "a colour with distinct channels should actually change")
    }

    @Test("A length that is not a whole number of pixels is refused rather than half-read")
    func ragedInputIsRefused() {
        #expect(PixelExport.rgbaBytes(fromBGRA: [1, 2, 3]).isEmpty)
        #expect(PixelExport.rgbaBytes(fromBGRA: []).isEmpty)
    }

    // MARK: Size

    @Test("Without enlargement the picture is exactly the size it was")
    func plainSize() {
        let colors = [UInt32](repeating: Self.packed, count: 7 * 5)
        let bytes = PixelExport.rgbaBytes(from: colors, width: 7, height: 5)
        #expect(bytes.count == 7 * 5 * 4)
    }

    @Test("Enlarging multiplies both sides, with no row left short")
    func enlargedSize() {
        let colors = [UInt32](repeating: Self.packed, count: 7 * 5)
        let bytes = PixelExport.rgbaBytes(from: colors, width: 7, height: 5, scale: 3)
        // Twenty-one across by fifteen down. A picture one row or column short is the off-by-one
        // this is here to catch.
        #expect(bytes.count == 21 * 15 * 4)
    }

    /// The seam test. A block-fill that stops one short leaves the last column of every block black,
    /// which on a screenshot is a faint grid over the whole picture.
    @Test("Every pixel of an enlarged block is filled, including the last")
    func enlargementLeavesNoGaps() {
        let colors = [UInt32](repeating: Self.packed, count: 4 * 4)
        let scale = 5
        let bytes = PixelExport.rgbaBytes(from: colors, width: 4, height: 4, scale: scale)
        let outWidth = 4 * scale

        var wrong = 0
        for y in 0 ..< (4 * scale) {
            for x in 0 ..< outWidth {
                let at = (y * outWidth + x) * 4
                if bytes[at] != 0x11 || bytes[at + 1] != 0x22 || bytes[at + 2] != 0x33 {
                    wrong += 1
                }
            }
        }
        #expect(wrong == 0, "\(wrong) pixels were not filled")
    }

    /// Enlargement must not smear one cell into its neighbour, which is what separates repeating
    /// from blending. Two different colours side by side should stay two solid blocks with a hard
    /// edge between them.
    @Test("Neighbouring cells stay separate blocks with a hard edge")
    func enlargementDoesNotBlend() {
        let left = PackedColor(r: 255, g: 0, b: 0).packedRGBA
        let right = PackedColor(r: 0, g: 0, b: 255).packedRGBA
        let scale = 4
        let bytes = PixelExport.rgbaBytes(from: [left, right], width: 2, height: 1, scale: scale)
        let outWidth = 2 * scale

        for y in 0 ..< scale {
            for x in 0 ..< outWidth {
                let at = (y * outWidth + x) * 4
                let expectRed: UInt8 = x < scale ? 255 : 0
                let expectBlue: UInt8 = x < scale ? 0 : 255
                #expect(bytes[at] == expectRed, "red at \(x),\(y)")
                #expect(bytes[at + 2] == expectBlue, "blue at \(x),\(y)")
                // Nothing in between: a blended edge would put a middling value here.
                #expect(bytes[at + 1] == 0, "green should never appear at \(x),\(y)")
            }
        }
    }

    @Test("The rows are in the right order, top to bottom")
    func rowOrder() {
        // A picture written bottom-up is upside down, which is obvious on a photograph and
        // surprisingly easy to miss on a symmetrical simulation.
        let top = PackedColor(r: 10, g: 0, b: 0).packedRGBA
        let bottom = PackedColor(r: 20, g: 0, b: 0).packedRGBA
        let bytes = PixelExport.rgbaBytes(from: [top, bottom], width: 1, height: 2)
        #expect(bytes[0] == 10, "the first row out should be the first row in")
        #expect(bytes[4] == 20)
    }

    // MARK: Refusals and edges

    @Test("Arguments that do not describe a picture give nothing back")
    func badArgumentsRefused() {
        #expect(PixelExport.rgbaBytes(from: [], width: 0, height: 0).isEmpty)
        #expect(PixelExport.rgbaBytes(from: [1], width: -4, height: 4).isEmpty)
        // Fewer colours than the size claims. Reading on would run off the end of the array.
        #expect(PixelExport.rgbaBytes(from: [1, 2], width: 4, height: 4).isEmpty)
    }

    @Test("An enlargement below one is treated as one rather than emptying the picture")
    func scaleFloor() {
        let colors = [UInt32](repeating: Self.packed, count: 4)
        for scale in [0, -1, -100] {
            let bytes = PixelExport.rgbaBytes(from: colors, width: 2, height: 2, scale: scale)
            #expect(bytes.count == 2 * 2 * 4, "scale \(scale) should behave as 1")
        }
    }

    @Test("Alpha is forced opaque by default, and can be taken from the colour instead")
    func alphaHandling() {
        // A colour whose alpha byte is nought, which would otherwise be an invisible patch.
        let transparent: UInt32 = 0x0033_2211
        let forced = PixelExport.rgbaBytes(from: [transparent], width: 1, height: 1)
        #expect(forced[3] == 255, "a picture should not come out with invisible patches")

        let honest = PixelExport.rgbaBytes(from: [transparent], width: 1, height: 1, opaque: false)
        #expect(honest[3] == 0)
    }

    // MARK: Choosing an enlargement

    @Test("The enlargement chosen fits inside the target and is never below one")
    func enlargementChoice() {
        #expect(PixelExport.enlargement(forWidth: 300, targetWidth: 1200) == 4)
        #expect(PixelExport.enlargement(forWidth: 500, targetWidth: 1200) == 2)
        // A grid already wider than the target is left at its own size rather than shrunk, since
        // shrinking needs the blending this whole path avoids.
        #expect(PixelExport.enlargement(forWidth: 2000, targetWidth: 1200) == 1)
        #expect(PixelExport.enlargement(forWidth: 0, targetWidth: 1200) == 1)
        #expect(PixelExport.enlargement(forWidth: 300, targetWidth: 0) == 1)
    }

    /// The chosen enlargement has to actually fit, or a screenshot is larger than intended on some
    /// grid sizes and not others — which is the sort of thing that only shows up on one phone.
    @Test("The chosen enlargement always fits the target")
    func enlargementAlwaysFits() {
        for width in stride(from: 40, through: 2000, by: 7) {
            let target = 1200
            let scale = PixelExport.enlargement(forWidth: width, targetWidth: target)
            if width <= target {
                #expect(width * scale <= target, "\(width) × \(scale) overshoots \(target)")
                // And it is the largest that fits, not merely one that does.
                #expect(width * (scale + 1) > target, "\(width) could have gone bigger than \(scale)")
            } else {
                #expect(scale == 1)
            }
        }
    }

    // MARK: Against the real renderer

    /// End to end: a world the engine has drawn, exported, and checked against the engine's own
    /// idea of what colour those cells are. This is what ties the export to reality rather than to
    /// its own assumptions.
    @Test("A rendered world exports the colours the engine says it drew")
    func exportMatchesTheRenderer() {
        let engine = PowderEngine(width: 8, height: 6, seed: 3)
        engine.setElement(2, 3, Element.sand)
        engine.setElement(5, 1, Element.water)

        let pixels = engine.renderToArray(overlay: .normal)
        let bytes = PixelExport.rgbaBytes(from: pixels, width: 8, height: 6)

        for i in 0 ..< (8 * 6) {
            let packed = pixels[i]
            #expect(bytes[i * 4] == UInt8(truncatingIfNeeded: packed), "red at \(i)")
            #expect(bytes[i * 4 + 1] == UInt8(truncatingIfNeeded: packed >> 8), "green at \(i)")
            #expect(bytes[i * 4 + 2] == UInt8(truncatingIfNeeded: packed >> 16), "blue at \(i)")
        }

        // And the sand really is sand-coloured, so the whole chain is anchored to something
        // recognisable rather than only being self-consistent.
        let sandColour = engine.elements[Element.sand].color
        let at = (3 * 8 + 2) * 4
        // Grain varies the shade a little, so this is a family resemblance rather than an identity.
        #expect(abs(Int(bytes[at]) - Int(sandColour.r)) < 80, "sand should look like sand")
        #expect(bytes[at] > bytes[at + 2], "sand should be warmer than it is blue")
    }
}
