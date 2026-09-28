import CrucibleCore
import SwiftUI

/// The Field's physics controls: collisions, trails, liquid, flocking, pull between bodies, drawn things and wind.
///
/// These used to be one enormous computed view inside `FieldDock`. Opening them closed the app on a real iPhone
/// (never on the simulator), both from the old tray and from the Physics page of the list menu. A real phone's main
/// thread has far less stack than the simulator's, and one giant nested view is exactly the kind of thing that runs
/// out of it. So every part here is its own small view with its own body, and SwiftUI builds each one separately.
///
/// Every slider also keeps its value inside its range and every number shown is converted safely, so an odd saved
/// value can never trap while the page is drawn.
struct FieldPhysicsControls: View {
    let model: ParticleFieldModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PHYSICS")
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)
            PhysicsCollideSection(model: model)
            PhysicsTrailsSection(model: model)
            PhysicsFluidSection(model: model)
            PhysicsFlockSection(model: model)
            PhysicsPullSection(model: model)
            PhysicsPaintedWindSection(model: model)
            PhysicsSourcesSection(model: model)
            PhysicsWallsSection(model: model)
            PhysicsWindSection(model: model)
        }
    }
}

// MARK: - Safe numbers

/// Whole-number text that never traps, whatever the value.
func physicsWhole(_ value: Double) -> String {
    guard value.isFinite else { return "0" }
    let clamped = max(-1_000_000_000, min(1_000_000_000, value.rounded()))
    return String(Int(clamped))
}

/// Decimal text that never traps.
func physicsDecimals(_ value: Double, _ places: Int) -> String {
    guard value.isFinite else { return "0" }
    return value.formatted(.number.precision(.fractionLength(places)))
}

// MARK: - Shared pieces

/// A small slider with its label and value. Its own view, so each one is built on its own.
struct PhysicsSlider: View {
    let label: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    init(
        _ label: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String = { physicsDecimals($0, 2) }
    ) {
        self.label = label
        self.value = value
        self.range = range
        self.step = step
        self.format = format
    }

    init(
        _ label: String,
        model: ParticleFieldModel,
        _ path: ReferenceWritableKeyPath<ParticleFieldModel, Double>,
        _ range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String = { physicsDecimals($0, 2) }
    ) {
        self.init(
            label,
            Binding(get: { model[keyPath: path] }, set: { model[keyPath: path] = $0 }),
            range,
            step: step,
            format: format
        )
    }

    /// The value held inside the range, and never NaN or infinite.
    private var safeValue: Binding<Double> {
        let range = range
        let value = value
        return Binding(
            get: {
                let raw = value.wrappedValue
                guard raw.isFinite else { return range.lowerBound }
                return max(range.lowerBound, min(range.upperBound, raw))
            },
            set: { newValue in
                guard newValue.isFinite else { return }
                value.wrappedValue = max(range.lowerBound, min(range.upperBound, newValue))
            }
        )
    }

    var body: some View {
        let shown = safeValue.wrappedValue
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.labBody(11))
                    .foregroundStyle(Palette.muted)
                Spacer(minLength: 8)
                Text(format(shown))
                    .font(.labNumeric(11))
                    .foregroundStyle(Palette.subtleForeground)
            }
            Slider(value: safeValue, in: range, step: step) { Text(label) }
                .tint(Palette.primary)
                .accessibilityIdentifier("slider.\(label)")
        }
        .padding(.vertical, 1)
    }
}

/// The thin line and indent that show a set of numbers belongs to the thing above it.
private struct PhysicsIndented<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            content
        }
        .padding(.leading, 10)
        .padding(.top, 2)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Palette.primary.opacity(0.35))
                .frame(width: 1.5)
        }
    }
}

/// A switch, with its own numbers folded in underneath it while it is on.
private struct PhysicsSwitch<Numbers: View>: View {
    let label: String
    let isOn: Binding<Bool>
    @ViewBuilder let numbers: Numbers

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: isOn) {
                Text(label)
                    .font(.labBody(11))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(Palette.primary)

            if isOn.wrappedValue {
                PhysicsIndented { numbers }
            }
        }
    }
}

/// A drawn thing: what it is, its numbers, and a way to remove it.
private struct PhysicsDrawn<Numbers: View>: View {
    let title: String
    let detail: String
    let clearTitle: String
    let canClear: Bool
    let clear: () -> Void
    @ViewBuilder let numbers: Numbers

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.labBody(11, .semiBold))
                        .foregroundStyle(Palette.foreground)
                    Text(detail)
                        .font(.labBody(10))
                        .foregroundStyle(Palette.subtleForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if canClear {
                    Button(action: clear) {
                        Text(clearTitle)
                            .font(.labBody(10, .semiBold))
                            .foregroundStyle(Palette.warn)
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(Capsule().fill(Palette.warn.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }
            PhysicsIndented { numbers }
        }
    }
}

// MARK: - The parts

private struct PhysicsCollideSection: View {
    let model: ParticleFieldModel

    var body: some View {
        PhysicsSwitch(
            label: "Collide — bodies push each other apart",
            isOn: Binding(get: { model.collisionsEnabled }, set: { model.collisionsEnabled = $0 })
        ) {
            PhysicsSlider("How wide they count as", model: model, \.contactSize, 0 ... 24, step: 0.5) {
                $0 <= 0 ? "automatic" : "\(physicsDecimals($0, 1)) px"
            }
            PhysicsSlider("Bounciness", model: model, \.contactBounciness, 0 ... 1, step: 0.02)
            PhysicsSlider("Friction", model: model, \.contactFriction, 0 ... 1, step: 0.02)
            PhysicsSlider("Firmness", model: model, \.contactPasses, 1 ... 6, step: 1) {
                let passes = physicsWhole($0)
                return "\(passes) pass\(passes == "1" ? "" : "es")"
            }
        }
    }
}

private struct PhysicsTrailsSection: View {
    let model: ParticleFieldModel

    var body: some View {
        PhysicsSwitch(
            label: "Trails — bodies leave a fading streak",
            isOn: Binding(get: { model.showTrails }, set: { model.showTrails = $0 })
        ) {
            // Phrased as length rather than as the fade it really is.
            PhysicsSlider("How long they last", model: model, \.trailFade, 0.01 ... 1, step: 0.01) {
                "\(physicsWhole(1 / max(0.01, $0))) frames"
            }
            PhysicsSlider("How solid", model: model, \.trailOpacity, 0.02 ... 1, step: 0.02)
            PhysicsSlider("How thick", model: model, \.trailWidth, 0.1 ... 3, step: 0.1)
            PhysicsSlider("Stretch with speed", model: model, \.streakLength, 0 ... 16, step: 0.5) {
                $0 == 0 ? "round dots" : "\(physicsDecimals($0, 1)) moments"
            }
        }
    }
}

private struct PhysicsFluidSection: View {
    let model: ParticleFieldModel

    var body: some View {
        PhysicsSwitch(
            label: "Fluid — the crowd holds itself apart, and holds a surface",
            isOn: Binding(get: { model.fluidEnabled }, set: { model.fluidEnabled = $0 })
        ) {
            // Spacing rather than the crowding figure it is stored as.
            PhysicsSlider(
                "Spacing",
                Binding(
                    get: {
                        let density = model.fluidRestDensity
                        guard density.isFinite, density > 0 else { return 20 }
                        return (1 / density).squareRoot()
                    },
                    set: { model.fluidRestDensity = 1 / max(1e-6, $0 * $0) }
                ),
                2 ... 20,
                step: 0.5
            ) { "\(physicsDecimals($0, 1)) px" }
            PhysicsSlider("Reach", model: model, \.fluidSmoothing, 4 ... 48, step: 1) {
                "\(physicsWhole($0)) px"
            }
            PhysicsSlider("Springiness", model: model, \.fluidStiffness, 0 ... 8, step: 0.1)
            PhysicsSlider("Thickness", model: model, \.fluidViscosity, 0 ... 0.6, step: 0.01)
            PhysicsSlider("Beading", model: model, \.fluidCohesion, 0 ... 1.2, step: 0.05)
        }
    }
}

private struct PhysicsFlockSection: View {
    let model: ParticleFieldModel

    var body: some View {
        PhysicsSwitch(
            label: "Flock — bodies steer by their neighbours",
            isOn: Binding(get: { model.flockEnabled }, set: { model.flockEnabled = $0 })
        ) {
            PhysicsSlider("Keep apart", model: model, \.flockSeparation, 0 ... 1, step: 0.01)
            PhysicsSlider("Match direction", model: model, \.flockAlignment, 0 ... 0.3, step: 0.005)
            PhysicsSlider("Stay together", model: model, \.flockCohesion, 0 ... 0.02, step: 0.0005) {
                physicsDecimals($0, 4)
            }
            PhysicsSlider("How far they see", model: model, \.flockVision, 10 ... 300, step: 5) {
                "\(physicsWhole($0)) px"
            }
            PhysicsSlider("Personal space", model: model, \.flockPersonalSpace, 2 ... 200, step: 2) {
                "\(physicsWhole($0)) px"
            }
            PhysicsSlider("How many take part", model: model, \.flockLimit, 20 ... 1200, step: 20) {
                $0.isFinite ? Int(max(0, min(1_000_000, $0.rounded()))).formattedWithSeparators : "0"
            }
        }
    }
}

private struct PhysicsPullSection: View {
    let model: ParticleFieldModel

    var body: some View {
        PhysicsSwitch(
            label: "Gravity between bodies — everything pulls on everything",
            isOn: Binding(get: { model.nbodyEnabled }, set: { model.nbodyEnabled = $0 })
        ) {
            PhysicsSlider("Strength", model: model, \.bodyGravityStrength, 0 ... 12, step: 0.1)
            PhysicsSlider("Closest approach", model: model, \.bodyGravitySoftening, 1 ... 60, step: 1) {
                "\(physicsWhole($0)) px"
            }
        }
    }
}

/// Shown whenever there is wind painted, or the tool is in hand.
private struct PhysicsPaintedWindSection: View {
    let model: ParticleFieldModel

    var body: some View {
        if model.mouseMode == .current || model.hasPaintedCurrent {
            PhysicsDrawn(
                title: "Painted wind",
                detail: model.hasPaintedCurrent
                    ? "Drag across the field to paint which way the crowd should go."
                    : "Drag across the field to paint. Nothing is painted yet.",
                clearTitle: "Wipe the wind",
                canClear: model.hasPaintedCurrent,
                clear: { model.clearCurrent() }
            ) {
                PhysicsSlider("How hard it pushes", model: model, \.currentStrength, 0 ... 6, step: 0.05)
                PhysicsSlider("Brush width", model: model, \.currentBrushRadius, 0.02 ... 0.6, step: 0.01)
                PhysicsSlider("Brush strength", model: model, \.currentBrushStrength, 0.02 ... 1, step: 0.02)
                PhysicsSlider("How finely", model: model, \.currentResolution, 4 ... 64, step: 4) {
                    "\(physicsWhole($0)) across"
                }
            }
        }
    }
}

private struct PhysicsSourcesSection: View {
    let model: ParticleFieldModel

    var body: some View {
        let count = model.emitterCount
        if model.mouseMode == .source || count > 0 {
            PhysicsDrawn(
                title: "Sources",
                detail: count > 0
                    ? "\(count) pouring. Drag on the field to place another, aimed the way you drag."
                    : "Drag on the field to place one, aimed the way you drag. It keeps pouring after you let go.",
                clearTitle: "Remove them all",
                canClear: count > 0,
                clear: { model.clearEmitters() }
            ) {
                PhysicsSourceNumbers(model: model)
                if count > 0 {
                    PhysicsSourceList(model: model)
                }
            }
        }
    }
}

private struct PhysicsSourceNumbers: View {
    let model: ParticleFieldModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            PhysicsSlider("How fast it pours", model: model, \.sourceRate, 0 ... 1_200, step: 10) {
                "\(physicsWhole($0))/s"
            }
            PhysicsSlider("How wide a fan", model: model, \.sourceSpread, 0 ... 3.14, step: 0.02) {
                "\(physicsWhole($0 * 57.2958))°"
            }
            PhysicsSlider("How fast they leave", model: model, \.sourceSpeed, 0 ... 30, step: 0.5)
            PhysicsSlider("Speed varies by", model: model, \.sourceSpeedVariation, 0 ... 1, step: 0.02)
            PhysicsSlider("How long they last", model: model, \.sourceLifespan, 0 ... 600, step: 10) {
                $0 <= 0 ? "forever" : "\(physicsWhole($0)) moments"
            }
            PhysicsSlider("How heavy", model: model, \.sourceWeight, 0.05 ... 12, step: 0.05)
            PhysicsSlider("Colour", model: model, \.sourceHue, -1 ... 359, step: 1) {
                $0 < 0 ? "a mixture" : "\(physicsWhole($0))°"
            }
        }
    }
}

/// One row per source, so a stray one can be stopped or removed without clearing them all.
private struct PhysicsSourceList: View {
    let model: ParticleFieldModel

    var body: some View {
        let summaries = model.emitterSummaries
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(summaries.enumerated()), id: \.offset) { entry in
                PhysicsSourceRow(model: model, index: entry.offset, summary: entry.element)
            }
        }
    }
}

private struct PhysicsSourceRow: View {
    let model: ParticleFieldModel
    let index: Int
    let summary: String

    var body: some View {
        let stopped = summary.hasSuffix("stopped")
        HStack(spacing: 8) {
            Text(summary)
                .font(.labBody(10))
                .foregroundStyle(Palette.subtleForeground)
            Spacer(minLength: 8)
            Button {
                model.setEmitterRunning(stopped, at: index)
            } label: {
                Image(systemName: stopped ? "play.fill" : "pause.fill")
                    .font(.labBody(10, .semiBold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            Button {
                model.removeEmitter(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.labBody(10, .semiBold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 1)
    }
}

private struct PhysicsWallsSection: View {
    let model: ParticleFieldModel

    var body: some View {
        let count = model.wallCount
        if model.mouseMode == .wall || count > 0 {
            PhysicsDrawn(
                title: "Walls",
                detail: count > 0
                    ? "\(count) drawn. Drag across the field to add another."
                    : "Drag across the field to draw one.",
                clearTitle: "Remove them all",
                canClear: count > 0,
                clear: { model.clearWalls() }
            ) {
                PhysicsSlider("Bounciness", model: model, \.wallBounciness, 0 ... 1, step: 0.02)
                PhysicsSlider("Friction", model: model, \.wallFriction, 0 ... 1, step: 0.02)
                PhysicsSlider("Thickness", model: model, \.wallThickness, 1 ... 20, step: 0.5) {
                    "\(physicsDecimals($0, 1)) px"
                }
            }
        }
    }
}

private struct PhysicsWindSection: View {
    let model: ParticleFieldModel

    var body: some View {
        PhysicsSwitch(
            label: "Wind — eddies and channels filling the field",
            isOn: Binding(get: { model.flowEnabled }, set: { model.flowEnabled = $0 })
        ) {
            PhysicsSlider("Strength", model: model, \.flowStrength, 0 ... 3, step: 0.05)
            PhysicsSlider("Eddy size", model: model, \.flowScale, 20 ... 600, step: 10) { "\(physicsWhole($0)) px" }
            PhysicsSlider("How fast it changes", model: model, \.flowDrift, 0 ... 1, step: 0.02) {
                $0 == 0 ? "still" : physicsDecimals($0, 2)
            }
        }
    }
}
