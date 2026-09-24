import CrucibleCore
import MetalKit
import SwiftUI

/// The simulation surface: a Metal view, plus the touch handling that paints into it.
///
/// SwiftUI has no Metal view of its own, so this wraps the one from MetalKit. Everything
/// below is plumbing — the drawing is in `GridRenderer` and the decisions are in the engine.
struct GridView: UIViewRepresentable {
    let model: SimulationModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        // Straight 8-bit channels, matching what the engine produces, so nothing is converted
        // on the way to the screen.
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isOpaque = true
        // Driven by the display's own refresh signal rather than a timer, so the simulation
        // advances exactly once per frame shown and stops entirely when nothing is on screen.
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        // No depth buffer and no multisampling: this draws one flat quad.
        view.depthStencilPixelFormat = .invalid
        view.sampleCount = 1
        view.preferredFramesPerSecond = 120

        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.model = model
    }

    /// Holds the renderer and turns touches into painting.
    ///
    /// Touch handling is done with a gesture recogniser on the Metal view rather than a
    /// SwiftUI drag gesture, because a drag gesture reports a stream of points that SwiftUI is
    /// free to coalesce — and a painting tool wants every point the hardware reported, or a
    /// fast stroke comes out as a dotted line.
    @MainActor
    final class Coordinator: NSObject {
        var model: SimulationModel
        private var renderer: GridRenderer?
        private var tickDriver: TickDriver?

        init(model: SimulationModel) {
            self.model = model
            super.init()
        }

        func attach(to view: MTKView) {
            guard let renderer = GridRenderer(view: view, source: model) else {
                // Without Metal there is nothing to show. The view stays blank rather than the
                // app crashing, and the Info.plist declares Metal as required so a device that
                // cannot run it is never offered the app.
                return
            }
            self.renderer = renderer

            // The simulation is advanced from the same signal that drives drawing, so the two
            // cannot drift apart.
            let driver = TickDriver { [weak self] in self?.model.tick() }
            driver.wrap(renderer, for: view)
            tickDriver = driver
            view.delegate = driver

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
            // One finger paints; two are left for the scroll and zoom the surrounding
            // interface may want.
            pan.maximumNumberOfTouches = 1
            view.addGestureRecognizer(pan)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            view.addGestureRecognizer(tap)
        }

        @objc private func handleDrag(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            if gesture.state == .began {
                // One undo point per stroke, not per touch report. Otherwise a single swipe
                // fills the entire record and undo becomes useless.
                model.beginStroke()
            }
            paint(at: gesture.location(in: view), in: view)
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            model.beginStroke()
            paint(at: gesture.location(in: view), in: view)
        }

        private func paint(at point: CGPoint, in view: UIView) {
            guard view.bounds.width > 0, view.bounds.height > 0 else { return }
            model.paint(
                atFractionX: Double(point.x / view.bounds.width),
                fractionY: Double(point.y / view.bounds.height)
            )
        }
    }
}

/// Advances the simulation one step, then lets the renderer draw.
///
/// A thin wrapper around the renderer rather than a separate timer. Tying the tick to the
/// display's refresh signal means the world advances once per frame actually shown: when the
/// app is backgrounded or obscured the signal stops, and so does time — which is what anyone
/// would expect, and what a timer would get wrong.
@MainActor
private final class TickDriver: NSObject, MTKViewDelegate {
    private let onTick: () -> Void
    private var renderer: GridRenderer?

    init(onTick: @escaping () -> Void) {
        self.onTick = onTick
        super.init()
    }

    func wrap(_ renderer: GridRenderer, for view: MTKView) {
        self.renderer = renderer
        renderer.mtkView(view, drawableSizeWillChange: view.drawableSize)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer?.mtkView(view, drawableSizeWillChange: size)
    }

    func draw(in view: MTKView) {
        onTick()
        renderer?.draw(in: view)
    }
}
