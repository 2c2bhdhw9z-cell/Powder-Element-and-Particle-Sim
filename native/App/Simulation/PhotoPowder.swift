import CoreGraphics
import UIKit

/// A photograph's pixels at the size it will be laid into the powder world.
///
/// Everything that decides what the picture becomes — which colours turn to water, snow or lava, how it is fitted
/// and centred — is in the engine, where it is tested. This only hands it the pixels, upright and at the right size.
enum PhotoPowder {
    /// Four bytes a point — red, green, blue, and how solid — row by row from the top, at exactly the given size.
    ///
    /// Drawn through UIKit first rather than straight from the underlying image, because that is what honours the
    /// way the photo was taken. A picture from a phone held upright is stored on its side with a note to turn it,
    /// and read directly it arrived in the world lying down.
    static func pixels(of image: UIImage, width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0 else { return nil }
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        // One point a pixel, so the drawing is exactly the size asked for whatever screen this is.
        format.scale = 1
        format.opaque = false
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let source = upright.cgImage else { return nil }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drew = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return false }
            context.interpolationQuality = .medium
            context.draw(source, in: CGRect(origin: .zero, size: size))
            return true
        }
        guard drew else { return nil }

        // The drawing hands back colours already multiplied by how solid they are. Undone for the edges of a cut-out,
        // which would otherwise come out darker than the picture is.
        for at in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Int(bytes[at + 3])
            guard alpha > 0, alpha < 255 else { continue }
            for channel in 0 ..< 3 {
                bytes[at + channel] = UInt8(min(255, Int(bytes[at + channel]) * 255 / alpha))
            }
        }
        return bytes
    }
}
