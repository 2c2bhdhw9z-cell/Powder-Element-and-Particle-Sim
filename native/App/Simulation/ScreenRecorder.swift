import Observation
import ReplayKit
import UIKit

/// Recording a clip of the lab.
///
/// ## Why the system's recorder rather than writing frames by hand
///
/// The web version records the canvas element directly, which captures the world and nothing else.
/// The equivalent here would be to grab each finished frame off the GPU, convert it and feed it to a
/// video writer — and doing that at a hundred and twenty frames a second, on the same device that is
/// simulating a million bodies, is a reliable way to make both worse. It would also miss the sound.
///
/// ReplayKit is what the platform provides for exactly this. It records outside the app's own frame
/// loop, so the simulation is not slowed by it; it captures the app's audio as well as its picture;
/// and it ends with the system's own preview, from which a clip can be trimmed, saved to Photos or
/// sent anywhere. None of that would be worth rebuilding.
///
/// **One honest difference from the web version:** this records the whole screen, so the dock and the
/// header appear in the clip. The web version's records only the canvas. On a phone that is arguably
/// the better result — a clip with no interface gives no sense of what was being done — but it is a
/// difference rather than a translation.
///
/// ## Permission
///
/// The first attempt raises a system prompt. Refusing it is a perfectly reasonable answer and leaves
/// everything else working, so a refusal is reported quietly rather than pressed.
@MainActor
@Observable
final class ScreenRecorder {
    /// Whether a recording is running.
    private(set) var isRecording = false

    /// Something worth telling the person, if anything went wrong.
    private(set) var problem: String?

    /// The system's preview, once a recording has finished.
    ///
    /// Published already wrapped, so a view can present it from an item-based cover without watching
    /// for changes. SwiftUI's change observation needs a value it can compare, and a view controller
    /// from ReplayKit is neither comparable nor ours to make so.
    private(set) var pending: RecordingTarget?

    /// Whether recording is possible at all on this device and in this state.
    ///
    /// Reports false while a call is in progress, during another app's recording, and on hardware
    /// that cannot do it — all of which are worth showing as an unavailable button rather than one
    /// that fails when pressed.
    var isAvailable: Bool {
        RPScreenRecorder.shared().isAvailable
    }

    private let recorder = RPScreenRecorder.shared()
    private var delegate: PreviewDelegate?

    // MARK: Control

    func toggle() {
        if isRecording {
            stop()
        } else {
            start()
        }
    }

    private func start() {
        guard !isRecording else { return }
        guard isAvailable else {
            problem = "Recording is not available right now."
            return
        }

        // Deliberately off. Turning it on would mean asking for microphone access, and a physics
        // sandbox has no business listening to the room — the app's own sound is captured either way.
        recorder.isMicrophoneEnabled = false

        recorder.startRecording { [weak self] error in
            // ReplayKit does not promise which thread this arrives on.
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.isRecording = false
                    self.problem = Self.describe(error)
                    return
                }
                self.problem = nil
                self.isRecording = true
            }
        }
    }

    private func stop() {
        guard isRecording else { return }
        recorder.stopRecording { [weak self] controller, error in
            Task { @MainActor in
                guard let self else { return }
                self.isRecording = false
                if let error {
                    self.problem = Self.describe(error)
                    return
                }
                guard let controller else {
                    // Nothing was captured, which happens if a recording is stopped the instant it
                    // starts. Not worth an error — there is simply nothing to show.
                    self.problem = nil
                    return
                }
                let delegate = PreviewDelegate { [weak self] in
                    self?.pending = nil
                }
                // Held, because the controller's delegate is a weak reference and nothing else would
                // keep this alive long enough to be called.
                self.delegate = delegate
                controller.previewControllerDelegate = delegate
                self.problem = nil
                self.pending = RecordingTarget(controller: controller)
            }
        }
    }

    /// Clears a message once it has been seen.
    func clearProblem() {
        problem = nil
    }

    /// Puts the preview away.
    ///
    /// Called both by the preview's own Done button, through the delegate, and by the cover being
    /// dismissed any other way — so the two cannot get out of step.
    func dismissPreview() {
        pending = nil
    }

    /// Turns ReplayKit's errors into something worth reading.
    ///
    /// Its own descriptions are written for a developer. The two that a person can actually do
    /// something about are named; the rest fall back to a plain statement rather than a code.
    private static func describe(_ error: any Error) -> String {
        let code = (error as NSError).code
        switch code {
        case RPRecordingErrorCode.userDeclined.rawValue:
            return "Recording needs your permission, which you can give the next time you tap it."
        case RPRecordingErrorCode.insufficientStorage.rawValue:
            return "There is not enough space left on the phone to record."
        case RPRecordingErrorCode.failedToStart.rawValue:
            return "Recording could not start. Another app may already be recording."
        default:
            return "Recording stopped unexpectedly."
        }
    }

    /// Dismisses the system's preview when it is finished with.
    ///
    /// A small object of its own because the preview's delegate has to be an `NSObject`, and the
    /// recorder is not one.
    ///
    /// The callback is marked as safe to send and as belonging to the main actor, and it is copied
    /// into a local before being used. Both are needed to satisfy Swift's concurrency checking:
    /// ReplayKit does not promise which thread calls a delegate, so reaching the recorder means
    /// hopping to the main actor — and hopping means whatever is carried across has to be safe to
    /// carry. Reading it off `self` inside the hop would carry this object instead, which is not.
    private final class PreviewDelegate: NSObject, RPPreviewViewControllerDelegate {
        private let onFinish: @Sendable @MainActor () -> Void

        init(onFinish: @escaping @Sendable @MainActor () -> Void) {
            self.onFinish = onFinish
            super.init()
        }

        func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
            let finish = onFinish
            Task { @MainActor in finish() }
        }
    }
}
