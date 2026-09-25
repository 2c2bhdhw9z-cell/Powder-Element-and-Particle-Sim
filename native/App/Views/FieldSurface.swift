import SwiftUI
import MetalKit

/// The particle field, as something SwiftUI can place in a layout.
///
/// The counterpart to `SimulationSurface`. The touch handling differs in kind: painting into the
/// powder grid places material at a point, while touching the particle field applies a force for
/// as long as the finger is down — so this reports when the touch ends, which the powder surface
/// has no need to.
struct FieldSurface: UIViewRepresentable {
    let model: ParticleFieldModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> MTKView {
        guard let view = FieldView(model: model) else {
            let placeholder = MTKView()
            placeholder.isPaused = true
            placeholder.enableSetNeedsDisplay = true
            return placeholder
        }
        context.coordinator.attachGestures(to: view)
        // Handed to the model so that anything wanting a picture of the field can ask for one
        // without having to reach through the view hierarchy to find this. The field is drawn as
        // geometry on the GPU, so the view is the only thing that can produce one.
        //
        // Captured weakly: the model outlives the view, and a strong reference here would keep a
        // discarded Metal view and its buffers alive for as long as the app runs.
        // Written out rather than as `view?.snapshot()`: optional chaining on a method that already
        // returns an optional gives an optional of an optional, which is not what the model wants.
        model.snapshotProvider = { [weak view] in
            guard let view else { return nil }
            return view.snapshot()
        }
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject {
        private let model: ParticleFieldModel

        init(model: ParticleFieldModel) {
            self.model = model
            super.init()
        }

        /// One finger works the field; two fingers move the camera.
        ///
        /// That division is the whole scheme, and it is the only one that works here. A tool has to
        /// be usable with one finger — the force ones are held down, not tapped — so a single finger
        /// cannot also mean "pan". And a camera gesture has to be available without first putting a
        /// tool away, or looking closely at something becomes a three-step chore.
        ///
        /// Worth noting what the reference implementation does here, because it is why this had to be
        /// designed rather than ported: it pans with a middle-click, a right-click or a held Alt key,
        /// and its turn and tilt are reachable only from sliders. None of those exist on a phone. Its
        /// pinch-to-zoom is the one gesture that carried over.
        func attachGestures(to view: UIView) {
            // A long-press recogniser with no delay, rather than a pan. A pan does not begin
            // until the finger has moved, and holding still in one place is a perfectly good
            // thing to do with a force tool — with a pan, nothing would happen until you
            // twitched.
            let press = UILongPressGestureRecognizer(
                target: self,
                action: #selector(handlePress(_:))
            )
            press.minimumPressDuration = 0
            press.allowableMovement = .greatestFiniteMagnitude
            press.delegate = self
            view.addGestureRecognizer(press)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            view.addGestureRecognizer(pinch)

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            // Exactly two. One belongs to the tool, and three or more is nothing in this app — and
            // leaving the maximum open would let a stray third finger during a pinch be read as a
            // pan and jerk the view sideways.
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            pan.delegate = self
            view.addGestureRecognizer(pan)

            let rotate = UIRotationGestureRecognizer(
                target: self,
                action: #selector(handleRotate(_:))
            )
            rotate.delegate = self
            view.addGestureRecognizer(rotate)
        }

        @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
            guard let view = gesture.view else { return }
            let bounds = view.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }

            // A second finger means the camera, not the field. The tool is let go the moment one
            // arrives, because otherwise pinching to zoom would also drag whatever was under the
            // first finger halfway across the world.
            if gesture.numberOfTouches > 1 {
                model.endTouch()
                return
            }

            let point = gesture.location(in: view)
            let fx = Double(point.x / bounds.width)
            let fy = Double(point.y / bounds.height)

            switch gesture.state {
            case .began:
                model.beginTouch(atFractionX: fx, fractionY: fy)
            case .changed:
                model.updateTouch(atFractionX: fx, fractionY: fy)
            default:
                // Ended, cancelled or failed all mean the finger is gone. Treated the same,
                // because a force left switched on by a cancelled gesture would go on pulling
                // the field around with nothing touching the screen.
                model.endTouch()
            }
        }

        /// How many of the three camera gestures are running.
        ///
        /// Counted rather than a single flag, because all three are deliberately allowed to run at once —
        /// see the delegate below. One finishing while another continues must not be read as the whole
        /// motion being over.
        private var cameraGesturesRunning = 0

        /// Tells the model when a camera motion starts and when the last of it finishes.
        ///
        /// What this buys: while a finger is moving the view, the dock's readouts hold still instead of
        /// several hundred controls being reassembled on every touch sample. They catch up once, at the
        /// end. UIKit guarantees a recogniser that begins also ends, cancels or fails, so the count
        /// cannot be left stranded.
        private func track(_ gesture: UIGestureRecognizer) {
            switch gesture.state {
            case .began:
                cameraGesturesRunning += 1
                model.beginCameraGesture()
            case .ended, .cancelled, .failed:
                cameraGesturesRunning = max(0, cameraGesturesRunning - 1)
                if cameraGesturesRunning == 0 { model.endCameraGesture() }
            default:
                break
            }
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            track(gesture)
            // The scale is reported cumulatively from the start of the gesture, so it is reset to one
            // after each reading and what gets applied is the change since the last. Applying the
            // cumulative value directly would fight the clamp: once the zoom hit its limit, pinching
            // back would do nothing until the fingers had returned all the way to where they started.
            guard gesture.state == .changed || gesture.state == .began else { return }
            model.zoomCamera(by: Double(gesture.scale))
            gesture.scale = 1
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            track(gesture)
            guard let view = gesture.view else { return }
            guard gesture.state == .changed || gesture.state == .began else { return }
            let movement = gesture.translation(in: view)
            model.panCamera(byPointsX: Double(movement.x), y: Double(movement.y))
            gesture.setTranslation(.zero, in: view)
        }

        @objc private func handleRotate(_ gesture: UIRotationGestureRecognizer) {
            track(gesture)
            guard gesture.state == .changed || gesture.state == .began else { return }
            model.rotateCamera(byRadians: Double(gesture.rotation))
            gesture.rotation = 0
        }
    }
}

extension FieldSurface.Coordinator: UIGestureRecognizerDelegate {
    /// All four run together.
    ///
    /// Pinch, two-finger drag and twist are one continuous motion of the same two fingers, and a
    /// system that made you choose between them would feel broken — letting go to change from
    /// zooming to turning is not how a phone behaves. The press recogniser also has to keep running
    /// alongside them, because it is the thing that notices the second finger arriving and puts the
    /// tool down.
    func gestureRecognizer(
        _ gesture: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
