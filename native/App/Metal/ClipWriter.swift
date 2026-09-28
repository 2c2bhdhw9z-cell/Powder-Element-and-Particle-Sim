import AVFoundation
import CoreGraphics
import CoreText
import CoreVideo
import Foundation
import Metal

/// Writes the field, as it is drawn, into a video file: the movie studio's "record a clip".
///
/// ## Why this and not the screen recorder
///
/// The screen recorder records the whole screen — the bar at the top, the tray, the tools — because that is all the
/// system's recorder can do. A movie is the world and nothing else, so it is written here instead, from the same
/// finished picture the screen gets.
///
/// ## Why this costs almost nothing
///
/// The recorder's own notes explain why the app never copied frames itself: bringing every frame back from the
/// graphics chip to be handed to an encoder is expensive. This does not bring anything back. Each frame is drawn a
/// second time, by the graphics chip, straight into a picture the video encoder reads from the same memory — a
/// picture shared between the two rather than copied — so the only cost is one more full-screen draw, thirty times a
/// second. The caption is the one thing written by the processor, and only while there is a caption.
///
/// ## What it does not do
///
/// It has no sound: the lab's sound is made live and is not a picture. It says so where the clip is handed over.
final class ClipWriter: @unchecked Sendable {
    /// One frame's picture, lent out to be drawn into and then handed back to be written.
    final class Frame: @unchecked Sendable {
        let pixels: CVPixelBuffer
        /// Held so the texture drawn into stays alive until the drawing has finished.
        let shared: CVMetalTexture
        let texture: MTLTexture
        let time: CMTime

        init(pixels: CVPixelBuffer, shared: CVMetalTexture, texture: MTLTexture, time: CMTime) {
            self.pixels = pixels
            self.shared = shared
            self.texture = texture
            self.time = time
        }
    }

    /// How often a frame is kept. The screen runs at up to a hundred and twenty; a clip at thirty is what every
    /// phone and every website expects, and a quarter the size.
    static let framesPerSecond = 30.0

    let url: URL
    let width: Int
    let height: Int
    /// For the video half of a Live Photo, the identifier that pairs it with its still picture. Nothing for a clip.
    let pairing: String?
    /// When, in seconds into the clip, the Live Photo's still picture is taken from.
    static let stillAt = 1.5
    /// The still picture, once the frame it comes from has been drawn. See ``wantsStill(at:)``.
    private var stillTaken = false
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let cache: CVMetalTextureCache
    /// The track saying which moment the still picture is from, for a Live Photo.
    private let stillTrack: AVAssetWriterInputMetadataAdaptor?
    /// Everything that touches the writer after it has started happens in here, in order.
    private let queue = DispatchQueue(label: "crucible.clip-writer")
    /// Read and written only on the main thread, where frames are asked for.
    private var startedAt: CFTimeInterval?
    private var lastFrameAt = -1.0
    /// Read and written only in ``queue``.
    private var written = 0
    private var isFinished = false

    /// Starts a clip the size of the field's picture, or returns nothing if the phone will not make one.
    init?(width: Int, height: Int, device: MTLDevice, pairing: String? = nil) {
        self.pairing = pairing
        // Even, because the video format stores colour at half size in each direction.
        let evenWidth = max(2, width & ~1)
        let evenHeight = max(2, height & ~1)
        self.width = evenWidth
        self.height = evenHeight
        let stamp = Int(Date().timeIntervalSince1970)
        url = FileManager.default.temporaryDirectory.appendingPathComponent(
            pairing == nil ? "Crucible movie \(stamp).mp4" : "Crucible live \(stamp).mov"
        )
        try? FileManager.default.removeItem(at: url)

        // A Live Photo's video is a QuickTime movie carrying the same identifier as its still picture, which is the
        // whole of what pairs the two in the photo library.
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: pairing == nil ? .mp4 : .mov) else { return nil }
        if let pairing {
            let identifier = AVMutableMetadataItem()
            identifier.keySpace = .quickTimeMetadata
            identifier.key = "com.apple.quicktime.content.identifier" as NSString
            identifier.value = pairing as NSString
            identifier.dataType = "com.apple.metadata.datatype.UTF-8"
            writer.metadata = [identifier]
        }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: evenWidth,
            AVVideoHeightKey: evenHeight,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: evenWidth,
            kCVPixelBufferHeightKey as String: evenHeight,
            // Shareable with the graphics chip: this is what lets a frame be drawn straight into the encoder's
            // picture instead of being copied there.
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )
        guard writer.canAdd(input) else { return nil }
        writer.add(input)

        // And the moment the still is from, as a track of its own.
        if pairing != nil {
            let spec: [String: Any] = [
                kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
                    "mdta/com.apple.quicktime.still-image-time",
                kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
                    "com.apple.metadata.datatype.int8",
            ]
            var description: CMFormatDescription?
            CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
                allocator: kCFAllocatorDefault,
                metadataType: kCMMetadataFormatType_Boxed,
                metadataSpecifications: [spec] as CFArray,
                formatDescriptionOut: &description
            )
            let track = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: description)
            track.expectsMediaDataInRealTime = true
            guard writer.canAdd(track) else { return nil }
            writer.add(track)
            stillTrack = AVAssetWriterInputMetadataAdaptor(assetWriterInput: track)
        } else {
            stillTrack = nil
        }

        var made: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &made) == kCVReturnSuccess,
              let cache = made
        else { return nil }

        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        self.cache = cache
    }

    /// A picture to draw this frame into, if it is time for another frame and the encoder is keeping up.
    ///
    /// Called on the main thread, from the field's drawing.
    func frame(at now: CFTimeInterval) -> Frame? {
        let started = startedAt ?? now
        startedAt = started
        let seconds = now - started
        // A hair early is still on time, so a frame arriving a fraction of a millisecond ahead is not skipped.
        guard lastFrameAt < 0 || seconds - lastFrameAt >= 1 / Self.framesPerSecond - 0.002 else { return nil }
        guard input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else { return nil }

        var made: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made) == kCVReturnSuccess, let pixels = made else {
            return nil
        }
        var sharedMade: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixels, nil, .bgra8Unorm, width, height, 0, &sharedMade
        ) == kCVReturnSuccess,
            let shared = sharedMade,
            let texture = CVMetalTextureGetTexture(shared)
        else { return nil }

        lastFrameAt = seconds
        return Frame(
            pixels: pixels,
            shared: shared,
            texture: texture,
            time: CMTime(seconds: seconds, preferredTimescale: 600)
        )
    }

    /// Whether the frame at this moment is the one a Live Photo's still picture should be taken from. Yes once.
    func wantsStill(at now: CFTimeInterval) -> Bool {
        guard pairing != nil, !stillTaken, let startedAt, now - startedAt >= Self.stillAt else { return false }
        stillTaken = true
        let at = CMTime(seconds: now - startedAt, preferredTimescale: 600)
        let track = StillBox(stillTrack)
        // Made on the writer's own queue: the pieces of a metadata group are not safe to hand between threads, and a
        // time is.
        queue.async { [self] in
            guard !isFinished, let adaptor = track.adaptor, adaptor.assetWriterInput.isReadyForMoreMediaData else { return }
            let item = AVMutableMetadataItem()
            item.keySpace = .quickTimeMetadata
            item.key = "com.apple.quicktime.still-image-time" as NSString
            item.value = 0 as NSNumber
            item.dataType = "com.apple.metadata.datatype.int8"
            let range = CMTimeRange(start: at, duration: CMTime(value: 20, timescale: 600))
            adaptor.append(AVTimedMetadataGroup(items: [item], timeRange: range))
        }
        return true
    }

    /// Writes a drawn frame into the clip, with the caption laid over it. Called once the drawing has finished.
    func write(_ frame: Frame, caption: String?, opacity: Double) {
        queue.async { [self] in
            guard !isFinished else { return }
            if let caption, opacity > 0.01 {
                burn(caption, opacity: opacity, into: frame.pixels)
            }
            guard input.isReadyForMoreMediaData else { return }
            if adaptor.append(frame.pixels, withPresentationTime: frame.time) {
                written += 1
            }
        }
    }

    /// Finishes the clip.
    ///
    /// - Parameter done: given the file once it is complete, or nothing and a reason if there is no clip to give.
    func finish(_ done: @escaping @Sendable (URL?, String?) -> Void) {
        queue.async { [self] in
            guard !isFinished else { return }
            isFinished = true
            guard written > 0 else {
                writer.cancelWriting()
                done(nil, "Nothing was recorded: the movie stopped before its first frame.")
                return
            }
            input.markAsFinished()
            stillTrack?.assetWriterInput.markAsFinished()
            // Through this object rather than the writer itself, which is not safe to hand between threads; this is
            // looked after by its own queue, and so is.
            writer.finishWriting { [self] in
                if writer.status == .completed {
                    done(url, nil)
                } else {
                    done(nil, writer.error?.localizedDescription ?? "The clip could not be finished.")
                }
            }
        }
    }

    /// Lays the caption over the bottom of a frame: light text on a dark rounded band, the same as on screen.
    private func burn(_ caption: String, opacity: Double, into pixels: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixels, [])
        defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixels),
              let context = CGContext(
                  data: base,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return }

        // Sized from the frame, then shrunk if the sentence would not fit across it.
        var size = max(14, min(64, CGFloat(min(width, height)) * 0.045))
        func line(at size: CGFloat) -> CTLine {
            let font = CTFontCreateWithName("IBMPlexSans-Medm" as CFString, size, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    CGColor(red: 0.94, green: 0.94, blue: 0.95, alpha: CGFloat(opacity)),
            ]
            return CTLineCreateWithAttributedString(NSAttributedString(string: caption, attributes: attributes))
        }
        var text = line(at: size)
        let widest = CGFloat(width) * 0.86
        let measured = CTLineGetTypographicBounds(text, nil, nil, nil)
        if measured > widest {
            size = max(10, size * widest / CGFloat(measured))
            text = line(at: size)
        }
        let textWidth = CGFloat(CTLineGetTypographicBounds(text, nil, nil, nil))

        // Drawn from the bottom up: in this context the first row of the picture is the top one, so nought is the
        // bottom edge, which is where a caption goes.
        let baseline = CGFloat(height) * 0.07 + size
        let x = (CGFloat(width) - textWidth) / 2
        let padding = size * 0.7
        let band = CGRect(
            x: x - padding,
            y: baseline - size * 0.45,
            width: textWidth + padding * 2,
            height: size * 1.6
        )
        context.setFillColor(CGColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 0.78 * CGFloat(opacity)))
        context.addPath(CGPath(
            roundedRect: band,
            cornerWidth: band.height / 2,
            cornerHeight: band.height / 2,
            transform: nil
        ))
        context.fillPath()
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(text, context)
    }
}

/// The still-time track, carried onto the writer's queue.
final class StillBox: @unchecked Sendable {
    let adaptor: AVAssetWriterInputMetadataAdaptor?
    init(_ adaptor: AVAssetWriterInputMetadataAdaptor?) { self.adaptor = adaptor }
}
