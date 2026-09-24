import SwiftUI

/// A readout of what the simulation is actually doing, for while the app is being built.
///
/// ## Temporary
///
/// This is scaffolding. It exists so that performance can be judged on the device instead of
/// guessed at from a development machine, and it is meant to come out before release. It is
/// off by default and lives behind a switch in the settings tray — nothing else depends on it,
/// so removing it later means deleting this file, the switch, and the two lines that place it.
///
/// Separate from Apple's own Metal overlay, which is controlled by iOS's developer settings
/// and is left entirely alone. The two can be used together; this one reports on the
/// simulation, which Apple's cannot see.
struct DebugOverlay: View {
    let model: SimulationModel
    let glass: GlassLevel

    /// A 120Hz frame in milliseconds, and a 60Hz one, so the figures have something to mean.
    private static let fastFrameBudget = 1000.0 / 120
    private static let slowFrameBudget = 1000.0 / 60

    /// Checked once when the readout appears rather than every frame — the answer cannot
    /// change while the app is running, since fonts register at launch.
    private let missingFaces = LabFonts.missingFaces()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("fps", "\(model.ticksPerSecond)", tint: frameRateTint)
            row("ms/tick", model.millisecondsPerTick.formatted(.number.precision(.fractionLength(2))), tint: tickCostTint)
            row("grid", "\(model.gridSize.width)×\(model.gridSize.height)")
            row("cells", model.activeCells.formatted())
            row("fill", (model.fillFraction * 100).formatted(.number.precision(.fractionLength(1))) + "%")
            row("speed", ToolClusterLabels.speed(model.speed))

            Divider()
                .overlay(Palette.border)
                .padding(.vertical, 2)

            // What fraction of a frame the simulation is eating. The useful number, because it
            // is the one that decides whether there is room for anything else.
            row(
                "of 120Hz",
                (model.millisecondsPerTick / Self.fastFrameBudget * 100)
                    .formatted(.number.precision(.fractionLength(0))) + "%",
                tint: tickCostTint
            )

            // A typeface that failed to load does not announce itself — the app simply draws
            // in the system face and still looks perfectly tidy, just not like Crucible. This
            // is the only place that difference becomes visible rather than merely felt.
            if !missingFaces.isEmpty {
                Divider()
                    .overlay(Palette.border)
                    .padding(.vertical, 2)
                row("fonts", "\(missingFaces.count) missing", tint: Palette.danger)
                ForEach(missingFaces, id: \.self) { face in
                    Text(face)
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: 160, alignment: .trailing)
                }
            }
        }
        .font(.labNumeric(10))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassPanel(glass, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .fixedSize()
    }

    /// Green while there is headroom, amber once a frame is tight, red once it is being missed.
    private var frameRateTint: Color {
        if model.ticksPerSecond >= 100 { Palette.ok }
        else if model.ticksPerSecond >= 55 { Palette.warn }
        else { Palette.danger }
    }

    private var tickCostTint: Color {
        let cost = model.millisecondsPerTick
        if cost <= Self.fastFrameBudget * 0.5 { return Palette.ok }
        if cost <= Self.slowFrameBudget * 0.5 { return Palette.warn }
        return Palette.danger
    }

    private func row(_ label: String, _ value: String, tint: Color = Palette.foreground) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .foregroundStyle(Palette.subtleForeground)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(tint)
        }
        .frame(minWidth: 120)
    }
}

/// Shared so the speed reads the same in the debug panel as on the dial itself.
enum ToolClusterLabels {
    static func speed(_ value: Double) -> String {
        value == value.rounded()
            ? "\(Int(value))×"
            : "\(value.formatted(.number.precision(.fractionLength(0 ... 2))))×"
    }
}
