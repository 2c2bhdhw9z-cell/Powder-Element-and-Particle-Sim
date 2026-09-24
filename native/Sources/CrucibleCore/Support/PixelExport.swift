// Preparing finished pixels to be written out as a picture.
//
// ## Why this is in the engine rather than beside the image code
//
// It is pure arithmetic over a buffer, and it is arithmetic of a particular kind: rearranging colour
// channels and repeating pixels. Both are things that can be wrong in a way nobody notices.
//
// A swapped red and blue produces a picture that is *plausible* — a blue flame, orange water — and
// looks deliberate enough to survive a glance, especially to someone who did not write it. An
// off-by-one in the repetition produces a one-pixel seam down the right edge of every screenshot.
// Neither fails, neither crashes, and neither is visible to whoever wrote the code, because the only
// way to see it is to look at the result on a device.
//
// So it lives here, where it is tested, rather than in the app layer where it cannot be.

/// Turning the engine's packed colours into bytes an image format wants.
public enum PixelExport {
    /// How many bytes one pixel takes once expanded.
    public static let bytesPerPixel = 4

    /// Expands packed colours into red, green, blue, alpha bytes, optionally enlarging.
    ///
    /// ## The channel order, stated once
    ///
    /// ``PackedColor`` stores a colour with red in the lowest byte — red, then green, then blue,
    /// then alpha, from least significant upward. This writes them out in that same order: byte
    /// zero of each pixel is red. That is what the note above is about; the order is chosen here and
    /// nowhere else, so there is one place to be right.
    ///
    /// ## Why enlarging repeats rather than blends
    ///
    /// The powder grid is coarser than the screen, and the display stretches it *without* smoothing
    /// — a grain is a crisp square. A picture of it should be crisp in the same way, so each cell
    /// becomes a solid block. Blending would produce a soft image that does not look like the thing
    /// that was on screen.
    ///
    /// - Parameters:
    ///   - colors: one packed colour per pixel, row by row.
    ///   - width: pixels across. Must be positive.
    ///   - height: pixels down. Must be positive.
    ///   - scale: whole-number enlargement. Anything below one is treated as one.
    ///   - opaque: when true, every pixel is written fully opaque regardless of what the packed
    ///     colour says. The renderers always produce opaque pixels, and a buffer that somehow held a
    ///     transparent one would otherwise produce a picture with invisible patches — which reads as
    ///     a bug in the simulation rather than in the export.
    /// - Returns: the bytes, or an empty array if the arguments do not describe a picture.
    public static func rgbaBytes(
        from colors: [UInt32],
        width: Int,
        height: Int,
        scale: Int = 1,
        opaque: Bool = true
    ) -> [UInt8] {
        guard width > 0, height > 0, colors.count >= width * height else { return [] }
        let factor = max(1, scale)
        let outWidth = width * factor
        let outHeight = height * factor

        var bytes = [UInt8](repeating: 0, count: outWidth * outHeight * bytesPerPixel)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let packed = colors[y * width + x]
                let red = UInt8(truncatingIfNeeded: packed)
                let green = UInt8(truncatingIfNeeded: packed >> 8)
                let blue = UInt8(truncatingIfNeeded: packed >> 16)
                let alpha = opaque ? 255 : UInt8(truncatingIfNeeded: packed >> 24)

                for dy in 0 ..< factor {
                    let row = (y * factor + dy) * outWidth
                    for dx in 0 ..< factor {
                        let at = (row + x * factor + dx) * bytesPerPixel
                        bytes[at] = red
                        bytes[at + 1] = green
                        bytes[at + 2] = blue
                        bytes[at + 3] = alpha
                    }
                }
            }
        }
        return bytes
    }

    /// Rewrites blue-first bytes as red-first, in place of a copy where possible.
    ///
    /// What a GPU hands back is usually blue, green, red, alpha — the reverse of what an image format
    /// wants. Only the outer two move; green and alpha are already where they belong.
    public static func rgbaBytes(fromBGRA source: [UInt8]) -> [UInt8] {
        guard source.count % bytesPerPixel == 0 else { return [] }
        var bytes = source
        var i = 0
        while i < bytes.count {
            let blue = bytes[i]
            bytes[i] = bytes[i + 2]
            bytes[i + 2] = blue
            i += bytesPerPixel
        }
        return bytes
    }

    /// The largest whole-number enlargement that keeps a picture within a target width.
    ///
    /// Always at least one, so a grid already wider than the target is written out at its own size
    /// rather than being shrunk — shrinking would need blending, which is the thing being avoided.
    public static func enlargement(forWidth width: Int, targetWidth: Int) -> Int {
        guard width > 0, targetWidth > 0 else { return 1 }
        return max(1, targetWidth / width)
    }
}
