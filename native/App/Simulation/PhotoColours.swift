import CoreGraphics
import CrucibleCore
import UIKit

/// Turning a photograph into the colours the field is drawn in.
///
/// ## Why this is so little code
///
/// Because the hard half is already done and tested in the engine: it can look at a picture's pixels, work out which
/// colours it is mostly made of, and build a colour ramp from them. All that was missing was a way to hand it a
/// picture — which is this, and nothing more.
///
/// The picture is shrunk first, hard. A ramp of five colours does not become more accurate for having read twelve
/// million pixels rather than four thousand, and reading twelve million of them on the main thread while the field is
/// running is felt as a stutter. Ninety-six across is far more than enough to find what a photograph is made of.
enum PhotoColours {
    /// How wide the picture is shrunk to before its colours are counted.
    static let sampleWidth = 96

    /// The colours a picture is mostly made of, as a ramp the field can be drawn in.
    ///
    /// - Returns: nothing if the picture could not be read at all, so the caller can say so rather than silently
    ///   applying an empty ramp and leaving the field grey.
    static func palette(from image: UIImage, stops: Int = 5) -> ParticlePaletteSpec? {
        guard let pixels = sample(image) else { return nil }
        let spec = ParticlePaletteSpec.fromImage(pixels, stopCount: max(2, min(8, stops)))
        // A picture of one flat colour gives a ramp with nothing to ramp between, which would look like a fault
        // rather than like a choice.
        guard spec.stops.count >= 2 else { return nil }
        return spec
    }

    /// The picture's pixels, shrunk, in the order the engine packs a colour: red lowest, then green, then blue.
    private static func sample(_ image: UIImage) -> [UInt32]? {
        guard let source = image.cgImage else { return nil }
        let width = sampleWidth
        // The same shape as the picture, so a tall photograph is not squashed into a square and its sky given the
        // same weight as its ground.
        let ratio = source.height > 0 ? Double(source.height) / Double(source.width) : 1
        let height = max(1, min(sampleWidth, Int((Double(width) * ratio).rounded())))

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colours = CGColorSpaceCreateDeviceRGB()
        // Premultiplied last, which is what `CGImage` will actually give us without complaint, and the alpha is
        // ignored below anyway.
        guard let context = bytes.withUnsafeMutableBytes({ raw -> CGContext? in
            guard let base = raw.baseAddress else { return nil }
            return CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colours,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }) else { return nil }

        context.interpolationQuality = .medium
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        var packed: [UInt32] = []
        packed.reserveCapacity(width * height)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let red = UInt32(bytes[index])
            let green = UInt32(bytes[index + 1])
            let blue = UInt32(bytes[index + 2])
            let alpha = bytes[index + 3]
            // Anything see-through is not a colour the picture is made of — it is the space around a cut-out.
            guard alpha > 40 else { continue }
            packed.append(red | (green << 8) | (blue << 16) | (0xFF << 24))
        }
        return packed.count > 16 ? packed : nil
    }
}
