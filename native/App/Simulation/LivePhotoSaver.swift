import Foundation
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

/// Puts a Live Photo into the photo library: a still picture and a few seconds of video, paired.
///
/// ## How the two are paired
///
/// By an identifier written into both: into the video as a piece of QuickTime metadata (see `ClipWriter`), and into
/// the picture in the place Apple's own camera writes it, the maker's notes, under the number seventeen. That is the
/// whole of it — the library sees the same identifier twice and shows one Live Photo.
///
/// ## Not tested on a phone
///
/// The pairing is Apple's own recipe, followed exactly, but it has not been seen to work: nothing on the machines this
/// is built on has a photo library.
enum LivePhotoSaver {
    /// Saves the pair. Tells `done` what happened, in words, on the main thread.
    static func save(video: URL, still: UIImage, pairing: String, done: @escaping @MainActor @Sendable (String) -> Void) {
        guard let picture = writeStill(still, pairing: pairing) else {
            Task { @MainActor in done("The still picture could not be written, so there is no Live Photo.") }
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    done("Crucible needs permission to add to your photos. It is in Settings, under Crucible.")
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: picture, options: nil)
                request.addResource(with: .pairedVideo, fileURL: video, options: nil)
            }, completionHandler: { saved, error in
                let said = saved
                    ? "Saved to Photos as a Live Photo. Press on it there to see it move."
                    : "It could not be saved: \(error?.localizedDescription ?? "the library said no")."
                Task { @MainActor in done(said) }
            })
        }
    }

    /// The still, as a JPEG carrying the identifier where the camera would put it.
    static func writeStill(_ image: UIImage, pairing: String) -> URL? {
        guard let cgImage = image.cgImage else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Crucible live \(pairing).jpg")
        try? FileManager.default.removeItem(at: url)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let properties: [String: Any] = [
            kCGImagePropertyMakerAppleDictionary as String: ["17": pairing],
            kCGImageDestinationLossyCompressionQuality as String: 0.92,
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? url : nil
    }
}
