import CrucibleCore
import SwiftUI

/// A small line chart of a rolling history.
///
/// Drawn with a path rather than a chart library: it is a couple of dozen points a few dozen pixels
/// tall, and it wants to look like part of this interface rather than like a chart.
struct Sparkline: View {
    let values: [Float]
    let tint: Color
    /// A line across the chart at a value worth comparing against — a frame budget, usually.
    var budget: Float?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            // The range the chart is scaled to. Includes the budget line, so a value comfortably under
            // budget still shows as comfortably under rather than filling the chart.
            let highest = max(values.max() ?? 0, budget ?? 0)
            // Never zero, or every point would divide by nothing and land in the same place.
            let scale = highest > 0 ? highest : 1

            ZStack {
                if let budget, budget > 0, budget <= scale {
                    let y = size.height - CGFloat(budget / scale) * size.height
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    .stroke(
                        Palette.borderStrong,
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
                }

                if values.count > 1 {
                    Path { path in
                        for (index, value) in values.enumerated() {
                            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                            let y = size.height - CGFloat(max(0, value) / scale) * size.height
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(height: 34)
    }
}

/// One measurement: its name, its current value, and where it has been.
struct MeasureCard: View {
    let label: String
    let value: String
    let history: SampleHistory
    var tint: Color = Palette.primary
    var budget: Float?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.labBody(10, .medium))
                .foregroundStyle(Palette.subtleForeground)
            Text(value)
                .font(.labNumeric(15))
                .foregroundStyle(tint)
            Sparkline(values: history.values, tint: tint, budget: budget)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}

/// How hard the lab is working, over the last couple of minutes.
///
/// ## Why history rather than just the current numbers
///
/// The detail panel already shows what a moment costs right now. This exists because the interesting
/// performance questions are all about *change*: did it get slower when I set that off, is it creeping
/// up as the world fills, was that stutter real or did I imagine it. A single number cannot answer any
/// of those, and by the time someone opens a panel to look, the moment they were asking about has gone.
///
/// Two minutes at one reading a second, which is long enough to see a slowdown build and short enough
/// to still be about what just happened.
struct PerformanceSheet: View {
    let powder: SimulationModel
    let field: ParticleFieldModel
    let chamber: Chamber
    let unit: TemperatureUnit
    /// How warm the phone is, and what the lab is costing the battery.
    let power: PowerSense
    /// Whether the lab eases off when the phone is hot or nearly empty.
    @Binding var mindsThePhone: Bool
    /// The field on a television, with the phone keeping the controls.
    let bigScreen: BigScreen

    /// A frame at the display's full rate, and at half it.
    private static let fastFrame = 1000.0 / 120
    private static let slowFrame = 1000.0 / 60

    var body: some View {
        LabSheet(
            title: "Performance",
            subtitle: "The last two minutes"
        ) {
            hero
            phone
            television
            switch chamber {
            case .powder: powderMeasures
            case .field: fieldMeasures
            }
            notes
        }
    }

    // MARK: The phone itself

    /// What the phone is doing about its own heat and charge, and what that is costing.
    ///
    /// Worth showing rather than hiding: when a phone gets hot it slows itself down, and an app that says nothing then
    /// simply looks as though it has gone bad. The line at the top says what is being given up and why, in the app's
    /// own words, and the figure underneath is measured from the charge falling rather than guessed.
    private var phone: some View {
        LabGroup(
            "The phone",
            footnote: power.inEffect.reason
                ?? "Nothing is being held back. When the phone gets hot, is asked to save power, or is nearly empty, "
                    + "the lab eases off — the frame rate first, then the shadows and the glow, and only last how much "
                    + "of the world is worked out each frame."
        ) {
            LabRow(label: "Temperature", value: power.heatInWords, tint: heatTint)
            LabDivider()
            LabRow(label: "Low Power Mode", value: power.readings.lowPower ? "on" : "off")
            LabDivider()
            LabRow(
                label: "Battery",
                value: power.readings.charge.map { "\(Int(($0 * 100).rounded()))%\(power.readings.isCharging ? ", on charge" : "")" }
                    ?? "not saying"
            )
            LabDivider()
            LabRow(label: "Drawing", value: "\(power.inEffect.framesPerSecond) times a second")
            LabDivider()
            // Measured from the charge falling while the app is on screen, which is the only honest way a phone will
            // tell an app what it costs. A phone reports its charge in whole percents, so the first figure takes a
            // couple of minutes to arrive.
            Text(power.costInWords)
                .font(.labBody(11))
                .foregroundStyle(Palette.subtleForeground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            LabDivider()
            LabToggle(label: "Ease off when the phone struggles", isOn: $mindsThePhone)
        }
    }

    private var heatTint: Color {
        switch power.readings.heat {
        case .nominal: Palette.ok
        case .fair: Palette.warn
        case .serious, .critical: Palette.danger
        }
    }

    // MARK: The television

    /// The field on a second screen.
    ///
    /// In this panel rather than the field's own, because what it is really about is where the work is being drawn — and
    /// because the line underneath says what the screen is, which is the only thing a television tells an app about
    /// itself.
    private var television: some View {
        LabGroup(
            "The television",
            footnote: bigScreen.isShowing
                ? "The field is on the second screen at its own size and refresh rate, and the phone keeps the tray and "
                    + "the tools. The powder world stays on the phone: it is drawn one grain to a pixel, so a television "
                    + "would mean a grid several times the size and a moment several times the cost."
                : "Plug in a screen, or mirror to one, and the field can fill it while the phone keeps the controls. "
                    + "Nothing is installed and nothing extra is signed."
        ) {
            LabRow(label: "Second screen", value: bigScreen.isAvailable ? "connected" : "none")
            LabDivider()
            LabAction(
                label: bigScreen.isShowing ? "Take it off the screen" : "Put the field on the screen",
                detail: bigScreen.summary,
                symbol: bigScreen.isShowing ? "tv.slash" : "tv"
            ) {
                if bigScreen.isShowing { bigScreen.stop() } else { bigScreen.start() }
            }
            .disabled(!bigScreen.isAvailable && !bigScreen.isShowing)
            .opacity(bigScreen.isAvailable || bigScreen.isShowing ? 1 : 0.45)
        }
    }

    // MARK: The headline

    private var hero: some View {
        let rate = chamber == .powder ? powder.ticksPerSecond : field.ticksPerSecond
        let cost = chamber == .powder ? powder.millisecondsPerTick : field.millisecondsPerTick

        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(rate)")
                .font(.labDisplay(34))
                .foregroundStyle(rateTint(rate))
            VStack(alignment: .leading, spacing: 2) {
                Text("moments a second")
                    .font(.labBody(11))
                    .foregroundStyle(Palette.muted)
                Text("\(cost.formatted(.number.precision(.fractionLength(2)))) ms each")
                    .font(.labNumeric(11))
                    .foregroundStyle(Palette.subtleForeground)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: Measures

    private var powderMeasures: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            MeasureCard(
                label: "MOMENTS A SECOND",
                value: "\(powder.ticksPerSecond)",
                history: powder.rateHistory,
                tint: rateTint(powder.ticksPerSecond),
                // The rate a display without ProMotion would run at, as something to compare against.
                budget: 60
            )
            MeasureCard(
                label: "COST OF A MOMENT",
                value: "\(powder.millisecondsPerTick.formatted(.number.precision(.fractionLength(2)))) ms",
                history: powder.costHistory,
                tint: costTint(powder.millisecondsPerTick),
                // A whole frame at the full refresh rate. Crossing it means the rate has to fall.
                budget: Float(Self.fastFrame)
            )
            MeasureCard(
                label: "HOW FULL",
                value: "\((powder.fillFraction * 100).formatted(.number.precision(.fractionLength(1))))%",
                history: powder.fillHistory
            )
            MeasureCard(
                label: "HOTTEST",
                value: unit.format(celsius: Double(powder.heatHistory.latest ?? 0)),
                history: powder.heatHistory,
                tint: Palette.warn
            )
        }
    }

    private var fieldMeasures: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            MeasureCard(
                label: "MOMENTS A SECOND",
                value: "\(field.ticksPerSecond)",
                history: field.rateHistory,
                tint: rateTint(field.ticksPerSecond),
                budget: 60
            )
            MeasureCard(
                label: "COST OF A MOMENT",
                value: "\(field.millisecondsPerTick.formatted(.number.precision(.fractionLength(2)))) ms",
                history: field.costHistory,
                tint: costTint(field.millisecondsPerTick),
                budget: Float(Self.fastFrame)
            )
            MeasureCard(
                label: "BODIES",
                value: field.bodyCount.formatted(),
                history: field.populationHistory
            )
            MeasureCard(
                label: "FASTEST BODY",
                value: (Double(field.speedHistory.latest ?? 0))
                    .formatted(.number.precision(.fractionLength(1))),
                history: field.speedHistory,
                tint: Palette.warn
            )
        }
    }

    // MARK: Notes

    private var notes: some View {
        LabGroup("What these mean") {
            LabRow(
                label: "A whole frame",
                value: "\(Self.fastFrame.formatted(.number.precision(.fractionLength(1)))) ms"
            )
            LabDivider()
            LabRow(
                label: "Grid",
                value: chamber == .powder
                    ? "\(powder.gridSize.width) × \(powder.gridSize.height)"
                    : "\(Int(field.worldSize.width)) × \(Int(field.worldSize.height))"
            )
            LabDivider()
            LabRow(
                label: "Speed",
                value: ToolClusterLabels.speed(chamber == .powder ? powder.speed : field.speed)
            )
            LabDivider()
            Text(
                "The dashed line on the cost chart is one whole frame at the display's full rate. "
                    + "Crossing it means the motion has to slow down, because there is no more time in "
                    + "the frame to give. The dashed line on the rate chart is sixty a second.\n\n"
                    + "The simulation does not get a whole frame to itself — drawing and the interface "
                    + "need a share — so staying comfortably under that line is the aim rather than "
                    + "touching it."
            )
            .font(.labBody(11))
            .foregroundStyle(Palette.subtleForeground)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
        }
    }

    // MARK: Tints

    private func rateTint(_ rate: Int) -> Color {
        if rate >= 100 { return Palette.ok }
        if rate >= 50 { return Palette.warn }
        return Palette.danger
    }

    private func costTint(_ cost: Double) -> Color {
        if cost <= Self.fastFrame / 2 { return Palette.ok }
        if cost <= Self.fastFrame { return Palette.warn }
        return Palette.danger
    }
}
