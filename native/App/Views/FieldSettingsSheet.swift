import CrucibleCore
import SwiftUI

/// The particle field's own settings.
///
/// Separate from the powder world's sheet because almost nothing carries over: there are no cells
/// here, no temperature, no wind. What there is instead is a set of forces, and the interesting thing
/// about them is that they interact — turning the drag up while the swirl is strong produces something
/// quite different from either alone. So they are all in one place, with what each actually does
/// spelled out, rather than hidden behind separate panels.
struct FieldSettingsSheet: View {
    let model: ParticleFieldModel
    let glass: GlassLevel

    var body: some View {
        LabSheet(title: "Field", subtitle: "Forces, edges and touch", glass: glass) {
            gravity
            forces
            edges
            appearance
        }
    }

    // MARK: Sections

    private var gravity: some View {
        LabGroup(
            "Gravity",
            footnote: model.isSteeredByTilt
                ? "The phone's tilt is setting these. Tap Tilt twice more to take them back."
                : "Negative values pull the other way. Nought leaves everything weightless."
        ) {
            LabSlider(label: "Sideways", value: bind(\.gravityX), range: -1.2 ... 1.2, step: 0.05) {
                $0.formatted(.number.precision(.fractionLength(2)))
            }
            LabDivider()
            LabSlider(label: "Downward", value: bind(\.gravityY), range: -1.2 ... 1.2, step: 0.05) {
                $0.formatted(.number.precision(.fractionLength(2)))
            }
        }
        .disabled(model.isSteeredByTilt)
        .opacity(model.isSteeredByTilt ? 0.4 : 1)
    }

    private var forces: some View {
        LabGroup(
            "Forces",
            footnote: "Drag is how much speed survives each moment — at none, nothing ever slows "
                + "down. The speed limit is what stops a close encounter flinging something off "
                + "the screen."
        ) {
            LabSlider(label: "Drag", value: bind(\.damping), range: 0.9 ... 1, step: 0.005) {
                $0 >= 1 ? "none" : $0.formatted(.number.precision(.fractionLength(3)))
            }
            LabDivider()
            LabSlider(label: "Charge", value: bind(\.electrostaticFactor), range: 0 ... 400, step: 10) {
                $0 == 0 ? "off" : $0.formatted(.number.precision(.fractionLength(0)))
            }
            LabDivider()
            LabSlider(label: "Swirl", value: bind(\.vortexForce), range: -8 ... 8, step: 0.1) {
                $0 == 0 ? "none" : $0.formatted(.number.precision(.fractionLength(1)))
            }
            LabDivider()
            LabSlider(label: "Speed limit", value: bind(\.maxSpeed), range: 4 ... 80, step: 1) {
                $0.formatted(.number.precision(.fractionLength(0)))
            }
        }
    }

    private var edges: some View {
        LabGroup("Edges") {
            LabChoice(
                label: "At the edges",
                selection: bind(\.boundaryMode),
                options: [
                    (.bounce, "Bounce"),
                    (.wrap, "Wrap around"),
                    (.void, "Disappear"),
                ]
            )
            LabDivider()
            LabSlider(label: "Bounciness", value: bind(\.elasticity), range: 0 ... 1, step: 0.05) {
                $0.formatted(.number.precision(.fractionLength(2)))
            }
            .disabled(model.boundaryMode != .bounce)
            .opacity(model.boundaryMode == .bounce ? 1 : 0.4)
        }
    }

    private var appearance: some View {
        LabGroup(
            "Touch and looks",
            footnote: "At the top of the reach, everything in the field is pulled however far away "
                + "it is — and the ring on screen grows to say so."
        ) {
            LabSlider(label: "Your reach", value: bind(\.mouseRadius), range: 20 ... 800, step: 10) {
                model.hasUnlimitedReach
                    ? "everything"
                    : $0.formatted(.number.precision(.fractionLength(0)))
            }
            LabDivider()
            LabSlider(
                label: "Your strength",
                value: bind(\.mouseForceMultiplier),
                range: 0.2 ... 4,
                step: 0.1
            ) { "\($0.formatted(.number.precision(.fractionLength(1))))×" }
            LabDivider()
            LabSlider(label: "Particle size", value: bind(\.particleSize), range: 1 ... 8, step: 0.5) {
                $0.formatted(.number.precision(.fractionLength(1)))
            }
            LabDivider()
            LabSlider(label: "Fade away", value: bind(\.decaySpeed), range: 0 ... 10, step: 1) {
                $0 == 0 ? "never" : "\($0.formatted(.number.precision(.fractionLength(0))))×"
            }
        }
    }

    // MARK: Pieces

    /// A binding straight onto one of the model's properties.
    ///
    /// The model already reads and writes the engine, so there is nothing to mirror here — which is
    /// what keeps a slider from ever showing a value the simulation is not actually using.
    private func bind<T>(_ path: ReferenceWritableKeyPath<ParticleFieldModel, T>) -> Binding<T> {
        Binding(
            get: { model[keyPath: path] },
            set: { model[keyPath: path] = $0 }
        )
    }

}
