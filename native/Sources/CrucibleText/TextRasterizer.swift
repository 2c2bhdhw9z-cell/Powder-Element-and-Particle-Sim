#if canImport(CoreText)

import CoreGraphics
import CoreText
import Foundation

/// Drawing a word into a small picture, so the field can turn it into particles.
///
/// This is the half of the text scene that cannot live in the engine: laying out letters needs fonts, and
/// fonts need the system's drawing machinery, which the engine deliberately cannot reach. Everything that
/// involves a *decision* — which pixels become bodies, how coarsely, where they land — is in
/// `ParticleTextShape` over in `CrucibleCore`, where it can be tested against arithmetic.
///
/// ## Why this is its own library rather than part of the app
///
/// Because otherwise none of it could be checked. The app target only builds on a Mac with Xcode, and
/// nothing in this project ever runs one interactively — so code that lives there is code that gets read and
/// hoped about. Drawing letters has exactly the kind of fault that reading does not catch: a picture handed
/// over upside down, or mirrored, or stretched, is perfectly sensible code that produces a wrong image.
///
/// Sitting here instead, built on CoreText rather than UIKit, it compiles and runs under `swift test` on the
/// macOS half of the checks — so those three things are *tested*, on Apple's own text machinery, rather than
/// argued about. On Linux the whole file disappears and the engine half is tested alone.
public enum TextRasterizer {
    /// How wide the picture is drawn, in pixels.
    ///
    /// Five hundred and twelve. Wide enough that the smoothed edges of the letters come out two or three
    /// pixels rather than a large fraction of a stroke, and small enough that reading every pixel back costs
    /// a fraction of a millisecond. The engine samples this down to however many bodies were asked for, so
    /// drawing it larger would only make the sampling coarser for no gain.
    public static let pictureWidth = 512

    /// How tall, allowing one line of large type with room above and below.
    public static let pictureHeight = 192

    /// A drawn word: how dark every pixel came out, and the shape of the sheet it was drawn on.
    public struct Picture: Sendable, Hashable {
        /// One value a pixel, nought to one, row by row **from the top**.
        public var coverage: [Double]
        /// How many pixels across.
        public var width: Int
        /// How many down.
        public var height: Int

        public init(coverage: [Double], width: Int, height: Int) {
            self.coverage = coverage
            self.width = width
            self.height = height
        }

        /// How dark one pixel came out, counting from the top left.
        public func darkness(column: Int, row: Int) -> Double {
            guard column >= 0, column < width, row >= 0, row < height else { return 0 }
            return coverage[row * width + column]
        }
    }

    /// Draws a word and reports how dark each pixel came out.
    ///
    /// - Returns: the picture, or nothing when there is no word or it leaves no mark.
    public static func picture(
        of text: String,
        width: Int = pictureWidth,
        height: Int = pictureHeight
    ) -> Picture? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, width > 0, height > 0 else { return nil }

        // One line only. A return in the middle of a word would lay out a second line that the single-line
        // measuring below knows nothing about, and it would be drawn over the first.
        let single = trimmed.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        // Measured, then scaled, rather than guessed at and retried. A size fixed in advance either clips a
        // long word or draws a short one tiny; the reference implementation does the latter, and stretches
        // its letters to twice their height besides.
        let reference = 100.0
        guard let probe = measure(single, size: reference), probe.bounds.width > 0.5,
              probe.bounds.height > 0.5
        else { return nil }
        let fitAcross = Double(width) * 0.94 / probe.bounds.width
        let fitDown = Double(height) * 0.82 / probe.bounds.height
        let size = max(4, min(Double(height), reference * min(fitAcross, fitDown)))
        guard let drawn = measure(single, size: size) else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height)
        let marked = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let space = CGColorSpace(name: CGColorSpace.linearGray),
                  let context = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width,
                      space: space,
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  )
            else { return false }

            // White letters on black, one byte a pixel: what comes back *is* the coverage the engine wants —
            // no colour to unpack, no alpha to divide out.
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: Double(width), height: Double(height)))
            context.setShouldAntialias(true)
            // Set rather than assumed. Glyphs are placed through the text matrix, and a stray one would
            // rotate or stretch every letter.
            context.textMatrix = .identity

            // Centred on the ink's own box rather than on the type's metrics, so a word in capitals and a
            // word with tails below the line both end up in the middle instead of riding high or low.
            context.textPosition = CGPoint(
                x: (Double(width) - drawn.bounds.width) / 2 - drawn.bounds.minX,
                y: (Double(height) - drawn.bounds.height) / 2 - drawn.bounds.minY
            )
            CTLineDraw(drawn.line, context)
            return true
        }
        guard marked else { return nil }

        // Straight through, in the order the bytes sit in.
        //
        // No flip. A bitmap drawing sheet stores its *top* row of pixels first, while its coordinates count
        // upward from the bottom — the two conventions are opposite, and they cancel. So the first byte is
        // the top left corner, which is the corner the engine's world starts at too. (This is the one claim
        // in the file that reading cannot settle, which is why there is a test for which way up a T comes
        // out.)
        var coverage = [Double](repeating: 0, count: width * height)
        var anyInk = false
        for index in 0 ..< (width * height) {
            let value = Double(pixels[index]) / 255
            coverage[index] = value
            if value > 0.2 { anyInk = true }
        }
        // A string of nothing but characters that draw no marks is not a word.
        guard anyInk else { return nil }
        return Picture(coverage: coverage, width: width, height: height)
    }

    // MARK: - Type

    private struct Measured {
        var line: CTLine
        var bounds: CGRect
    }

    /// Lays the word out at a size and reports the box its ink occupies.
    private static func measure(_ text: String, size: Double) -> Measured? {
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font(size: size),
                kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 1, alpha: 1),
            ]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        // Optical bounds are the ink; they are what "centre the word" should mean. They can come back empty
        // for some strings, so the ordinary layout box is the fallback rather than a failure.
        var bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        if bounds.width <= 0.5 || bounds.height <= 0.5 {
            bounds = CTLineGetBoundsWithOptions(line, [])
        }
        guard bounds.width.isFinite, bounds.height.isFinite else { return nil }
        return Measured(line: line, bounds: bounds)
    }

    /// The heaviest ordinary face of the system's own type.
    ///
    /// Heavy on purpose. The picture is then sampled down to a few thousand bodies, and a light face's thin
    /// strokes come out of that as a dotted line with gaps in it — the letters stop being letters. Thick
    /// strokes survive the sampling.
    private static func font(size: Double) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let bold = CTFontCreateCopyWithSymbolicTraits(base, size, nil, .boldTrait, .boldTrait)
        return bold ?? base
    }
}

#endif
