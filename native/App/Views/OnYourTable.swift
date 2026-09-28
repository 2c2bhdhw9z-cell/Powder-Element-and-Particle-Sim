import ARKit
import CrucibleCore
import SceneKit
import SwiftUI

/// The powder world standing on a real table, through the back camera: point the phone at a table, tap it, and the
/// world is there, running, as a slab you can walk round.
///
/// ## How it is drawn
///
/// As a picture of the world laid on a thin slab, refreshed fifteen times a second from the engine's own pixels —
/// the same picture the notebook and the gallery take. Not the world's own graphics view: that draws to the screen,
/// and the table is somewhere else. Fifteen a second is enough for sand to be seen falling and little enough to leave
/// the phone room to track the table.
///
/// ## Not tested on a phone
///
/// Built on a machine with no camera and no ARKit, and the checks' Macs have neither. Whether it finds a table has not
/// been seen yet.
struct OnYourTable: View {
    let model: SimulationModel
    let onClose: () -> Void

    @State private var placed = false

    var body: some View {
        ZStack(alignment: .top) {
            if ARWorldTrackingConfiguration.isSupported {
                TableARView(model: model, placed: $placed)
                    .ignoresSafeArea()
            } else {
                Palette.background.ignoresSafeArea()
                Text("This phone cannot put things on a table: it has no way to track the room.")
                    .font(.labBody(13))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .padding(40)
                    .frame(maxHeight: .infinity)
            }
            HStack {
                Text(placed ? "Walk round it. Tap somewhere else to move it." : "Point at a table and tap it.")
                    .font(.labBody(12, .medium))
                    .foregroundStyle(Palette.foreground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Palette.elevated.opacity(0.85)))
                    .accessibilityIdentifier("table.hint")
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.labBody(14, .medium))
                        .foregroundStyle(Palette.foreground)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Palette.elevated.opacity(0.85)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("table.close")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .preferredColorScheme(.dark)
    }
}

/// The camera's view of the room, with the world put on whatever the finger taps.
struct TableARView: UIViewRepresentable {
    let model: SimulationModel
    @Binding var placed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, placed: $placed)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.automaticallyUpdatesLighting = true
        view.scene = SCNScene()
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        view.session.run(configuration)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.start(on: view)
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {}

    static func dismantleUIView(_ view: ARSCNView, coordinator: Coordinator) {
        coordinator.stop()
        view.session.pause()
    }

    @MainActor
    final class Coordinator: NSObject {
        private let model: SimulationModel
        private var placed: Binding<Bool>
        private weak var view: ARSCNView?
        private var slab: SCNNode?
        private var link: CADisplayLink?
        private var lastPicture = 0.0

        /// How wide the world is on the table, in metres: about the size of a tray.
        static let width: CGFloat = 0.32

        init(model: SimulationModel, placed: Binding<Bool>) {
            self.model = model
            self.placed = placed
        }

        func start(on view: ARSCNView) {
            self.view = view
            let link = CADisplayLink(target: self, selector: #selector(frame))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 15)
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        func stop() {
            link?.invalidate()
            link = nil
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let point = gesture.location(in: view)
            guard let query = view.raycastQuery(from: point, allowing: .estimatedPlane, alignment: .horizontal),
                  let hit = view.session.raycast(query).first
            else { return }
            let node = slab ?? makeSlab()
            node.simdTransform = hit.worldTransform
            if slab == nil {
                view.scene.rootNode.addChildNode(node)
                slab = node
            }
            placed.wrappedValue = true
            Haptics.firm()
        }

        private func makeSlab() -> SCNNode {
            let grid = model.gridSize
            let aspect = CGFloat(max(1, grid.height)) / CGFloat(max(1, grid.width))
            // Standing up from the table like a picture in a frame, a little tipped back, so it is looked at rather
            // than looked down on.
            let box = SCNBox(width: Self.width, height: Self.width * aspect, length: 0.012, chamferRadius: 0.002)
            let face = SCNMaterial()
            face.lightingModel = .constant
            let edge = SCNMaterial()
            edge.diffuse.contents = UIColor(white: 0.08, alpha: 1)
            // Front, right, back, left, top, bottom.
            box.materials = [face, edge, edge, edge, edge, edge]
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(0, Float(Self.width * aspect / 2), 0)
            node.eulerAngles.x = -0.15
            let holder = SCNNode()
            holder.addChildNode(node)
            return holder
        }

        @objc private func frame() {
            guard let slab, let box = slab.childNodes.first?.geometry else { return }
            let now = CACurrentMediaTime()
            guard now - lastPicture >= 1.0 / 15 else { return }
            lastPicture = now
            if let picture = model.snapshot() {
                box.materials.first?.diffuse.contents = picture
            }
        }
    }
}
