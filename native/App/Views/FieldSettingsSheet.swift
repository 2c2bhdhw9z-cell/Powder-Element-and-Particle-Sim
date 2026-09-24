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

    var body: some View {
        NavigationStack {
            Form {
                gravity
                forces
                edges
                appearance
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Field")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.background)
        .tint(Palette.primary)
        .preferredColorScheme(.dark)
    }

    // MARK: Sections

    private var gravity: some View {
        Section {
            slider("Sideways", value: bind(\.gravityX), range: -1.2 ... 1.2, step: 0.05) {
                $0.formatted(.number.precision(.fractionLength(2)))
            }
            slider("Downward", value: bind(\.gravityY), range: -1.2 ... 1.2, step: 0.05) {
                $0.formatted(.number.precision(.fractionLength(2)))
            }
        } header: {
            Text("Gravity")
        } footer: {
            Text(
                model.isSteeredByTilt
                    ? "The phone's tilt is setting these. Tap Tilt twice more to take them back."
                    : "Negative values pull the other way. Nought leaves everything weightless."
            )
            .font(.labBody(11))
        }
        .disabled(model.isSteeredByTilt)
        .opacity(model.isSteeredByTilt ? 0.4 : 1)
    }

    private var forces: some View {
        Section {
            slider("Drag", value: bind(\.damping), range: 0.9 ... 1, step: 0.005) {
                $0 >= 1 ? "none" : $0.formatted(.number.precision(.fractionLength(3)))
            }
            slider("Charge", value: bind(\.electrostaticFactor), range: 0 ... 400, step: 10) {
                $0 == 0 ? "off" : $0.formatted(.number.precision(.fractionLength(0)))
            }
            slider("Swirl", value: bind(\.vortexForce), range: -8 ... 8, step: 0.1) {
                $0 == 0 ? "none" : $0.formatted(.number.precision(.fractionLength(1)))
            }
            slider("Speed limit", value: bind(\.maxSpeed), range: 4 ... 80, step: 1) {
                $0.formatted(.number.precision(.fractionLength(0)))
            }
        } header: {
            Text("Forces")
        } footer: {
            Text(
                "Drag is how much speed survives each moment — at one, nothing ever slows down. The "
                    + "speed limit is what stops a close encounter flinging something off the screen."
            )
            .font(.labBody(11))
        }
    }

    private var edges: some View {
        Section {
            Picker("At the edges", selection: bind(\.boundaryMode)) {
                Text("Bounce").tag(ParticleBoundaryMode.bounce)
                Text("Wrap around").tag(ParticleBoundaryMode.wrap)
                Text("Disappear").tag(ParticleBoundaryMode.void)
            }
            .pickerStyle(.segmented)

            slider("Bounciness", value: bind(\.elasticity), range: 0 ... 1, step: 0.05) {
                $0.formatted(.number.precision(.fractionLength(2)))
            }
            .disabled(model.boundaryMode != .bounce)
            .opacity(model.boundaryMode == .bounce ? 1 : 0.4)
        } header: {
            Text("Edges")
        }
    }

    private var appearance: some View {
        Section {
            slider("Your reach", value: bind(\.mouseRadius), range: 20 ... 800, step: 10) {
                // Said in words at the top of the range, because a number there is misleading — the
                // pull genuinely has no limit, and the ring on screen grows to say so.
                model.hasUnlimitedReach ? "everything" : $0.formatted(.number.precision(.fractionLength(0)))
            }
            slider("Your strength", value: bind(\.mouseForceMultiplier), range: 0.2 ... 4, step: 0.1) {
                "\($0.formatted(.number.precision(.fractionLength(1))))×"
            }
            slider("Body size", value: bind(\.particleSize), range: 1 ... 8, step: 0.5) {
                $0.formatted(.number.precision(.fractionLength(1)))
            }
            slider("Fade away", value: bind(\.decaySpeed), range: 0 ... 10, step: 1) {
                $0 == 0 ? "never" : "\($0.formatted(.number.precision(.fractionLength(0))))×"
            }
        } header: {
            Text("Touch and looks")
        } footer: {
            Text("At the top of the reach, everything in the field is pulled however far away it is.")
                .font(.labBody(11))
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

    private func slider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(.labNumeric(12))
                    .foregroundStyle(Palette.muted)
            }
            Slider(value: value, in: range, step: step) { Text(label) }
        }
    }
}
