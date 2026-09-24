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
            view.addGestureRecognizer(press)
        }

        @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
            guard let view = gesture.view else { return }
            let bounds = view.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }
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
    }
}
