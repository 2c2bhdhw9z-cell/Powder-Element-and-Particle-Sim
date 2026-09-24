import CrucibleCore
import SwiftUI

/// Which scale temperatures are shown in.
///
/// A real preference rather than a nicety: the readouts here run from −328 to over five thousand, and a
/// number that large in an unfamiliar scale carries no meaning at all.
enum TemperatureUnit: String, CaseIterable, Identifiable, Codable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }

    /// A temperature as it should be read.
    ///
    /// The rounding happens in the engine, where it is tested — JavaScript and Swift disagree about
    /// every negative half, and this simulation is full of negative temperatures.
    func format(celsius value: Double) -> String {
        guard value.isFinite else { return "—" }
        switch self {
        case .celsius:
            return "\(Int(Temperature.celsius(value)))°C"
        case .fahrenheit:
            return "\(Int(Temperature.fahrenheit(fromCelsius: value)))°F"
        }
    }
}

/// What is under your finger, floating at the top of the world.
///
/// The one piece of feedback the canvas gives about itself. Without it a world is opaque: there is no
/// way to tell hot lava from cool, no way to see which way a fan is pointing, and no way to find out
/// what that material you painted an hour ago actually was.
///
/// Tapping it opens the material's card, which is how someone gets from "what is this" to "what does
/// it do" without going looking.
struct InspectChip: View {
    let model: SimulationModel
    let unit: TemperatureUnit
    let glass: GlassLevel
    let onOpenCard: (ElementID) -> Void

    var body: some View {
        if let found = model.inspected {
            Button {
                // Air has no card worth reading, so tapping over empty space offers the material you
                // are holding instead — which is almost certainly what you wanted to know about.
                onOpenCard(found.elementID == Element.empty ? model.brushElement : found.elementID)
            } label: {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(model.color(of: found.elementID))
                        .frame(width: 9, height: 9)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                        )
                    Text(found.name)
                        .font(.labBody(11, .medium))
                        .foregroundStyle(Palette.foreground)
                    if let arrow = found.fanArrow {
                        // A fan keeps its direction where everything else keeps a countdown, so without
                        // this a row of fans is four identical squares doing four different things.
                        Text(arrow)
                            .font(.labBody(11, .semiBold))
                            .foregroundStyle(Palette.primary)
                    }
                    Text("·")
                        .foregroundStyle(Palette.subtleForeground)
                    Text(unit.format(celsius: found.celsius))
                        .font(.labNumeric(11))
                        .foregroundStyle(temperatureTint(found.celsius))
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
            }
            .buttonStyle(.plain)
            .glassPanel(glass, in: Capsule())
            .accessibilityLabel("\(found.name), \(unit.format(celsius: found.celsius))")
            .accessibilityHint("Opens what this material does")
        }
    }

    /// Warm colours for hot, cool for cold, with the thresholds at the points where the chemistry
    /// actually changes rather than at round numbers.
    private func temperatureTint(_ celsius: Double) -> Color {
        guard celsius.isFinite else { return Palette.danger }
        // Above the point where wood ignites and water has long since boiled.
        if celsius >= 300 { return Palette.danger }
        if celsius >= 100 { return Palette.warn }
        // Below freezing.
        if celsius <= 0 { return Color(hex: 0x7DA8C4) }
        return Palette.muted
    }
}
