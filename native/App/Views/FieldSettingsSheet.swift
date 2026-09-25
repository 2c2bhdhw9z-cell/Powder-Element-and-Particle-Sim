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
            liquid
            pull
            wind
            written
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

    /// The liquid.
    ///
    /// Only shown when it is switched on, because five sliders that do nothing are worse than no sliders
    /// — and this switch in particular was decoration for a long time, which is the fault this section
    /// exists to finish undoing.
    @ViewBuilder
    private var liquid: some View {
        if model.fluidEnabled {
            LabGroup(
                "Liquid",
                footnote: "Spacing is the one to reach for first: it is how far apart the liquid wants to "
                    + "sit, and it decides how much of it a field this size will hold. Reach is how far "
                    + "each body looks for its neighbours — wider is smoother and costs more."
            ) {
                LabSlider(
                    label: "Spacing",
                    value: Binding(
                        get: { (1 / max(1e-6, model.fluidRestDensity)).squareRoot() },
                        set: { model.fluidRestDensity = 1 / max(1e-6, $0 * $0) }
                    ),
                    range: 2 ... 20,
                    step: 0.5
                ) { "\($0.formatted(.number.precision(.fractionLength(1)))) px" }
                LabDivider()
                LabSlider(label: "Reach", value: bind(\.fluidSmoothing), range: 4 ... 48, step: 1) {
                    "\($0.formatted(.number.precision(.fractionLength(0)))) px"
                }
                LabDivider()
                LabSlider(label: "Springiness", value: bind(\.fluidStiffness), range: 0 ... 8, step: 0.1) {
                    $0.formatted(.number.precision(.fractionLength(1)))
                }
                LabDivider()
                LabSlider(label: "Thickness", value: bind(\.fluidViscosity), range: 0 ... 0.6, step: 0.01) {
                    $0.formatted(.number.precision(.fractionLength(2)))
                }
                LabDivider()
                LabSlider(label: "Beading", value: bind(\.fluidCohesion), range: 0 ... 1.2, step: 0.05) {
                    $0.formatted(.number.precision(.fractionLength(2)))
                }
            }
        }
    }

    /// The pull between bodies.
    @ViewBuilder
    private var pull: some View {
        if model.nbodyEnabled {
            LabGroup(
                "Gravity between bodies",
                footnote: "Everything pulls on everything. Closest approach is how near two bodies may get "
                    + "before the pull stops growing — without it, a pair that touches is flung apart at a "
                    + "speed that means nothing."
            ) {
                LabSlider(
                    label: "Strength",
                    value: bind(\.bodyGravityStrength),
                    range: 0 ... 12,
                    step: 0.1
                ) { $0.formatted(.number.precision(.fractionLength(1))) }
                LabDivider()
                LabSlider(
                    label: "Closest approach",
                    value: bind(\.bodyGravitySoftening),
                    range: 1 ... 60,
                    step: 1
                ) { "\($0.formatted(.number.precision(.fractionLength(0)))) px" }
            }
        }
    }

    /// The wind.
    @ViewBuilder
    private var wind: some View {
        if model.flowEnabled {
            LabGroup(
                "Wind",
                footnote: "A pattern of motion filling the whole field, with eddies and channels and calm "
                    + "patches. Eddy size decides how many of them fit across the screen; drift is how "
                    + "fast the pattern itself changes, and at nought the crowd finds the channels and "
                    + "then follows them forever."
            ) {
                LabSlider(label: "Strength", value: bind(\.flowStrength), range: 0 ... 3, step: 0.05) {
                    $0.formatted(.number.precision(.fractionLength(2)))
                }
                LabDivider()
                LabSlider(label: "Eddy size", value: bind(\.flowScale), range: 20 ... 600, step: 10) {
                    "\($0.formatted(.number.precision(.fractionLength(0)))) px"
                }
                LabDivider()
                LabSlider(label: "Drift", value: bind(\.flowDrift), range: 0 ... 1, step: 0.02) {
                    $0 == 0 ? "still" : $0.formatted(.number.precision(.fractionLength(2)))
                }
            }
        }
    }

    /// A force somebody writes themselves.
    ///
    /// Always shown, unlike the wind and the liquid, because there is no switch for it — an empty box
    /// means no force, so the boxes *are* the switch.
    private var written: some View {
        LabGroup(
            "Write your own force",
            footnote: "Two sums, worked out for every body. `x` and `y` run from 0 to 1 across the field, "
                + "`vx` and `vy` are how fast it is going, `r` is how far it is from the middle and `t` is "
                + "seconds. Try `sin(y * 8) * 2` sideways for a standing wave, or `0 - vy * 0.4` downward "
                + "for drag that only acts vertically."
        ) {
            expressionBox(
                label: "Sideways",
                text: Binding(
                    get: { model.writtenForceAcross },
                    set: { model.writtenForceAcross = $0 }
                ),
                problem: model.writtenForceAcrossProblem
            )
            LabDivider()
            expressionBox(
                label: "Downward",
                text: Binding(
                    get: { model.writtenForceDown },
                    set: { model.writtenForceDown = $0 }
                ),
                problem: model.writtenForceDownProblem
            )
            LabDivider()
            LabSlider(
                label: "Strength",
                value: bind(\.writtenForceStrength),
                range: -4 ... 4,
                step: 0.1
            ) { "\($0.formatted(.number.precision(.fractionLength(1))))×" }
        }
    }

    /// One box to write a sum in, with whatever is wrong with it underneath.
    ///
    /// The explanation matters. The reference implementation this was merged from turns every mistake into
    /// silence — a typo there produces no force and no message, so the only symptom is that nothing
    /// happens, and there is no way to tell a wrong sum from a sum that correctly does nothing.
    private func expressionBox(label: String, text: Binding<String>, problem: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.labBody(13))
                .foregroundStyle(Palette.foreground)
            TextField("", text: text, prompt: Text("no force").foregroundStyle(Palette.subtleForeground))
                .font(.labNumeric(13))
                .foregroundStyle(Palette.foreground)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .stroke(problem == nil ? Color.clear : Palette.warn.opacity(0.65), lineWidth: 1)
                )
            if let problem {
                Text(problem)
                    .font(.labBody(11))
                    .foregroundStyle(Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
