import ReplayKit
import SwiftUI

/// The system's own screen-recording preview, as something SwiftUI can present.
///
/// Deliberately left looking like iOS rather than like Crucible. It is the phone's furniture — the
/// same trimming and sharing interface that appears for any screen recording — and someone who has
/// used it before should find it exactly where they expect. Restyling it would be both impossible and
/// the wrong instinct.
struct RecordingPreview: UIViewControllerRepresentable {
    let controller: RPPreviewViewController

    func makeUIViewController(context: Context) -> RPPreviewViewController {
        controller
    }

    func updateUIViewController(_ controller: RPPreviewViewController, context: Context) {}
}

/// Lets the preview be presented from an item-based sheet.
///
/// A wrapper rather than making the controller itself identifiable: it is a class from ReplayKit, and
/// conforming somebody else's type to a protocol it does not declare is the sort of thing that
/// compiles today and collides with a future release.
struct RecordingTarget: Identifiable {
    let id = UUID()
    let controller: RPPreviewViewController
}
