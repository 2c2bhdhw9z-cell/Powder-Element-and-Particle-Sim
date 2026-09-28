import AVFoundation
import CrucibleCore
import Foundation
import UIKit
import Vision

/// The front camera, watching for a hand waved at the field and a head moved to look round it.
///
/// The phone's own vision finds the hand or the face in each picture; what that means for the lab — smoothing, when a
/// pinch is a pinch, how far a head moved turns the view — is `CameraSteering.swift` in the engine, where it is
/// checked. This opens the camera, hands the pictures to the phone's vision about fifteen times a second, and passes
/// on where things are.
///
/// ## Not tested on a phone
///
/// Built on a machine with no camera, and the checks' Macs have none either. Everything it decides is tested; that it
/// sees is not, yet.
@MainActor
@Observable
final class CameraSenses {
    /// Whether to look for a hand.
    private(set) var watchesHands = false
    /// Whether to look for a face.
    private(set) var watchesHead = false
    /// The hand touching the field now, if there is one.
    private(set) var hand: HandTouch?
    /// How far the head has turned the view, in degrees.
    private(set) var headTurn: (yaw: Double, pitch: Double) = (0, 0)
    /// Whether a face is being seen at the moment, for saying so.
    private(set) var seesFace = false
    /// Why it cannot see, if it cannot.
    private(set) var problem: String?

    @ObservationIgnored private var session: AVCaptureSession?
    @ObservationIgnored private var watcher: FrameWatcher?
    @ObservationIgnored private var steering = HandSteering()
    @ObservationIgnored private var look = HeadLook()
    @ObservationIgnored private var sceneIsActive = true

    var isRunning: Bool { session != nil }

    /// Switches looking for a hand on or off.
    func setWatchesHands(_ wanted: Bool) {
        watchesHands = wanted
        if !wanted { hand = nil; steering = HandSteering() }
        refresh()
    }

    /// Switches looking for a face on or off.
    func setWatchesHead(_ wanted: Bool) {
        watchesHead = wanted
        if !wanted { headTurn = (0, 0); look = HeadLook(); seesFace = false }
        refresh()
    }

    /// Takes where the head is now as straight on.
    func recentre() { look.recentre() }

    /// Stops the camera while away without changing either switch, then resumes what was wanted on return.
    func sceneChanged(active: Bool) {
        sceneIsActive = active
        if active { refresh() } else { stop() }
    }

    private func refresh() {
        guard sceneIsActive else { stop(); return }
        if watchesHands || watchesHead {
            watcher?.wants(hands: watchesHands, face: watchesHead)
            if session == nil { start() }
        } else {
            stop()
        }
    }

    private func start() {
        problem = nil
        Task { @MainActor [weak self] in
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard let self, self.sceneIsActive, self.watchesHands || self.watchesHead else { return }
            guard granted else {
                self.problem = "Crucible needs permission to use the front camera. It is in Settings, under Crucible."
                return
            }
            self.open()
        }
    }

    private func open() {
        guard session == nil else { return }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera)
        else {
            problem = "This phone has no front camera that can be used."
            return
        }
        let session = AVCaptureSession()
        // Small pictures: finding a hand needs nothing like the camera's full size, and small is fast.
        session.sessionPreset = .vga640x480
        guard session.canAddInput(input) else {
            problem = "The front camera could not be opened."
            return
        }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        let watcher = FrameWatcher(report: Self.receiver(for: self))
        watcher.wants(hands: watchesHands, face: watchesHead)
        output.setSampleBufferDelegate(watcher, queue: watcher.queue)
        guard session.canAddOutput(output) else {
            problem = "The front camera could not be read."
            return
        }
        session.addOutput(output)
        self.session = session
        self.watcher = watcher
        watcher.orientation = Self.orientation()
        // Started away from the main thread, as the system asks: starting a camera can take a moment.
        let running = SessionBox(session)
        watcher.queue.async { running.session.startRunning() }
    }

    private func stop() {
        guard let session else { return }
        let running = SessionBox(session)
        watcher?.queue.async { running.session.stopRunning() }
        self.session = nil
        watcher = nil
        hand = nil
        seesFace = false
    }

    /// Which way up the pictures are, for the phone's vision. The front camera's, mirrored as a mirror is, so a hand
    /// moved right is seen moving right.
    private static func orientation() -> CGImagePropertyOrientation {
        switch UIDevice.current.orientation {
        case .portraitUpsideDown: .rightMirrored
        case .landscapeLeft: .downMirrored
        case .landscapeRight: .upMirrored
        default: .leftMirrored
        }
    }

    /// Where results cross back to the main thread. Made outside it, because the pictures are looked at elsewhere.
    private nonisolated static func receiver(for senses: CameraSenses) -> @Sendable (FrameWatcher.Seen) -> Void {
        { [weak senses] seen in
            Task { @MainActor in senses?.take(seen) }
        }
    }

    private func take(_ seen: FrameWatcher.Seen) {
        let now = CFAbsoluteTimeGetCurrent()
        watcher?.orientation = Self.orientation()
        if watchesHands {
            let touch = steering.sighted(seen.hand, at: now)
            if touch != hand { hand = touch }
        }
        if watchesHead {
            let turn = look.sighted(faceX: seen.face?.x, faceY: seen.face?.y, at: now)
            headTurn = turn
            if seesFace != (seen.face != nil) { seesFace = seen.face != nil }
        }
    }
}

/// A capture session handed to the camera's own queue to be started and stopped there.
final class SessionBox: @unchecked Sendable {
    let session: AVCaptureSession
    init(_ session: AVCaptureSession) { self.session = session }
}

/// Looks at each picture from the camera, on the camera's own queue, and says where the hand and the face are.
final class FrameWatcher: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// What was found in one picture, as plain numbers: fractions of the picture from its top left.
    struct Seen: Sendable {
        var hand: HandSighting?
        var face: (x: Double, y: Double)?
    }

    let queue = DispatchQueue(label: "crucible.front-camera")
    private let report: @Sendable (Seen) -> Void
    private let lock = NSLock()
    private var hands = false
    private var face = false
    private var lastLooked = 0.0
    private var storedOrientation = CGImagePropertyOrientation.leftMirrored

    /// About fifteen pictures a second are looked at; the rest are let go.
    static let everySeconds = 1.0 / 15

    init(report: @escaping @Sendable (Seen) -> Void) {
        self.report = report
    }

    var orientation: CGImagePropertyOrientation {
        get { lock.lock(); defer { lock.unlock() }; return storedOrientation }
        set { lock.lock(); storedOrientation = newValue; lock.unlock() }
    }

    func wants(hands: Bool, face: Bool) {
        lock.lock()
        self.hands = hands
        self.face = face
        lock.unlock()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastLooked >= Self.everySeconds, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastLooked = now
        lock.lock()
        let wantsHands = hands
        let wantsFace = face
        let orientation = storedOrientation
        lock.unlock()

        var requests: [VNRequest] = []
        let handRequest = VNDetectHumanHandPoseRequest()
        handRequest.maximumHandCount = 1
        let faceRequest = VNDetectFaceRectanglesRequest()
        if wantsHands { requests.append(handRequest) }
        if wantsFace { requests.append(faceRequest) }
        guard !requests.isEmpty else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: orientation, options: [:])
        try? handler.perform(requests)

        var seen = Seen()
        if wantsHands, let observation = handRequest.results?.first,
           let tip = try? observation.recognizedPoint(.indexTip), tip.confidence > 0.3
        {
            var pinch = 1.0
            if let thumb = try? observation.recognizedPoint(.thumbTip), thumb.confidence > 0.3 {
                let dx = Double(thumb.location.x - tip.location.x)
                let dy = Double(thumb.location.y - tip.location.y)
                pinch = (dx * dx + dy * dy).squareRoot()
            }
            // The phone's vision measures from the bottom left; the lab measures from the top left.
            seen.hand = HandSighting(x: Double(tip.location.x), y: 1 - Double(tip.location.y), pinch: pinch)
        }
        if wantsFace, let faceFound = faceRequest.results?.first {
            let box = faceFound.boundingBox
            seen.face = (Double(box.midX), 1 - Double(box.midY))
        }
        report(seen)
    }
}
