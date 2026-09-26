import CrucibleCore
import MetalKit
import SwiftUI

/// The simulation surface, as something SwiftUI can place in a layout.
///
/// SwiftUI has no Metal view of its own, so this wraps the one from MetalKit. Everything here
/// is plumbing: the drawing is in `GridView` and the decisions are in the engine.
struct SimulationSurface: UIViewRepresentable {
    let model: SimulationModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> MTKView {
        guard let view = GridView(model: model) else {
            // Without Metal there is nothing to show. A blank view rather than a crash, and
            // the app declares Metal as a requirement so a device that cannot run it is never
            // offered the app in the first place.
            let placeholder = MTKView()
            placeholder.isPaused = true
            placeholder.enableSetNeedsDisplay = true
            return placeholder
        }
        context.coordinator.attachGestures(to: view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        // Nothing to push: the view reads the model every frame.
    }

    /// Turns touches into painting.
    ///
    /// A gesture recogniser rather than a SwiftUI drag gesture. SwiftUI is free to coalesce
    /// drag updates, and a painting tool wants every point the hardware reported — coalesced,
    /// a quick stroke arrives as a dotted line.
    @MainActor
    final class Coordinator: NSObject {
        private let model: SimulationModel

        init(model: SimulationModel) {
            self.model = model
            super.init()
        }

        func attachGestures(to view: UIView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
            // One finger paints. Two are left free for whatever the surrounding interface
            // wants to do with them.
            pan.maximumNumberOfTouches = 1
            view.addGestureRecognizer(pan)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            view.addGestureRecognizer(tap)
        }

        @objc private func handleDrag(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            if gesture.state == .began {
                // One point to come back to per stroke, not per touch report. Otherwise a
                // single swipe fills the whole undo record and undo becomes useless.
                //
                // The starting point goes with it, because the replace brush needs to know what was
                // under the beginning of the drag rather than under the current touch.
                begin(at: gesture.location(in: view), in: view)
            }
            paint(at: gesture.location(in: view), in: view)
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            begin(at: gesture.location(in: view), in: view)
            paint(at: gesture.location(in: view), in: view)
        }

        private func begin(at point: CGPoint, in view: UIView) {
            guard let fraction = fraction(of: point, in: view) else { return }
            Haptics.touchDown()
            model.beginStroke(atFractionX: fraction.x, fractionY: fraction.y)
        }

        private func paint(at point: CGPoint, in view: UIView) {
            guard let fraction = fraction(of: point, in: view) else { return }
            model.paint(atFractionX: fraction.x, fractionY: fraction.y)
        }

        /// Where a touch fell, as fractions of the view.
        ///
        /// Fractions rather than pixels, because the view and the grid are different sizes and the
        /// conversion belongs wherever both are known — which is the model.
        private func fraction(of point: CGPoint, in view: UIView) -> (x: Double, y: Double)? {
            let bounds = view.bounds
            guard bounds.width > 0, bounds.height > 0 else { return nil }
            return (Double(point.x / bounds.width), Double(point.y / bounds.height))
        }
    }
}
