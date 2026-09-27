import CoreGraphics
import CrucibleCore
import Foundation
// For writing a picture straight to a file, without a `UIImage` in between.
import ImageIO
import UIKit

/// Turning a buffer of pixels into a picture that can be shared.
///
/// The rearranging and enlarging is **not** here — it is `PixelExport` in the engine, where it is
/// tested. Both of the mistakes available in that step are invisible to whoever writes the code: a
/// swapped red and blue gives a plausible-looking picture, and an off-by-one in the enlargement gives
/// a faint grid of seams. The only way to see either is to look at a finished picture on a device,
/// which is exactly why the arithmetic was moved somewhere it can be checked without one.
///
/// What is left here is the part that genuinely needs Apple's frameworks: wrapping known-good bytes
/// in an image, and writing it to a file.
///
/// ## Why the byte layout is spelled out rather than described to Core Graphics
///
/// Core Graphics can be told how a pixel is laid out through a combination of an alpha position and
/// a byte-order flag, and those interact in a way that is genuinely hard to reason about — several
/// combinations describe the same layout, and several plausible-looking ones describe a layout
/// nothing produces. So the bytes are put in a known order first, by the tested code, and this asks
/// for the one description that matches: four bytes a pixel, alpha last, default order.
enum LabSnapshot {
    /// Builds a picture from the engine's own pixels.
    ///
    /// - Parameter scale: a whole-number enlargement, applied by repeating pixels rather than
    ///   blending them. The powder grid is coarser than the screen and the display stretches it
    ///   without smoothing, so a shared picture should be crisp in the same way.
    static func image(
        fromEngineColors colors: [UInt32],
        width: Int,
        height: Int,
        scale: Int = 1
    ) -> UIImage? {
        let factor = max(1, scale)
        let bytes = PixelExport.rgbaBytes(from: colors, width: width, height: height, scale: factor)
        guard !bytes.isEmpty else { return nil }
        return image(fromRGBA: bytes, width: width * factor, height: height * factor)
    }

    /// Builds a picture from what the GPU drew.
    ///
    /// Metal's usual layout puts blue first, so these are turned round on the way through.
    static func image(fromMetalBGRA source: [UInt8], width: Int, height: Int) -> UIImage? {
        guard width > 0, height > 0, source.count >= width * height * PixelExport.bytesPerPixel else {
            return nil
        }
        let bytes = PixelExport.rgbaBytes(fromBGRA: source)
        guard !bytes.isEmpty else { return nil }
        return image(fromRGBA: bytes, width: width, height: height)
    }

    /// The last step, once the bytes are known to be in red, green, blue, alpha order.
    private static func image(fromRGBA bytes: [UInt8], width: Int, height: Int) -> UIImage? {
        guard let picture = Self.cgImage(fromRGBA: bytes, width: width, height: height) else { return nil }
        return UIImage(cgImage: picture)
    }

    /// Writes a large picture of the engine's pixels straight to a file, without making a `UIImage` of it on the way.
    ///
    /// For the poster, which is ten million pixels or so: compressing that takes long enough to be felt, so it is done
    /// away from the interface, and this touches nothing that belongs to it — the bytes, Core Graphics and Image I/O,
    /// nothing else. The name is chosen by the caller for the same reason.
    static func writePNG(
        fromEngineColors colors: [UInt32],
        width: Int,
        height: Int,
        scale: Int,
        named name: String
    ) -> URL? {
        let factor = max(1, scale)
        let bytes = PixelExport.rgbaBytes(from: colors, width: width, height: height, scale: factor)
        guard !bytes.isEmpty,
              let picture = cgImage(fromRGBA: bytes, width: width * factor, height: height * factor)
        else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, picture, nil)
        return CGImageDestinationFinalize(destination) ? url : nil
    }

    /// Wraps bytes already in red, green, blue, alpha order as a Core Graphics picture.
    private static func cgImage(fromRGBA bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * PixelExport.bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            // The fourth byte is ignored rather than treated as transparency. Every renderer here
            // produces opaque pixels, and asking for it to be honoured would mean the values had to
            // be premultiplied — a needless conversion, and one more thing to get wrong.
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            // Kept crisp when something later scales it. A screenshot of a grid of cells should look
            // like a grid of cells.
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Writes some text to a file that can be handed on, and returns where — for the plotter's drawing and the
    /// spreadsheet of measurements.
    static func write(text: String, named name: String, extension kind: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).\(kind)")
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Writes a picture somewhere it can be handed to something else, and returns where.
    ///
    /// A file rather than the picture itself, because sharing an image offers a short list of
    /// destinations while sharing a file offers everything — including saving it into Files, which is
    /// what someone collecting a series of them will want.
    ///
    /// Into the temporary directory: it is a copy made to be handed on, and the system clears it up.
    static func write(_ image: UIImage, named name: String) -> URL? {
        guard let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// A name with the moment in it, so a series of them sorts in the order they were taken.
    static func fileName(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "crucible-\(formatter.string(from: date))"
    }
}
