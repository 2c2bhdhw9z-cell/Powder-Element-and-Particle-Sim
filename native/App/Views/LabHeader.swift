import CrucibleCore
import SwiftUI

/// The bar across the top.
///
/// Matched to the web version line for line, because its absence was most of why the app did not look
/// like Crucible. The app used to float a small pill over the canvas instead, which reads as a
/// utility with a control stuck on it rather than as a place with a name.
///
/// The measurements are the reference's, converted from its stylesheet:
///
///   - the bar is black at four tenths with a heavy blur, and a hairline under it at twelve percent
///     white — not the fifteen percent the floating panels use, so the bar reads as further back;
///   - the name is the display face at sixteen points, semibold, tightened;
///   - the subtitle is eleven points in the muted grey, and it names the chamber rather than
///     repeating the app;
///   - the two round buttons are forty-four points across on an eight percent white fill, with
///     sixteen-point glyphs;
///   - the chamber switch below is a thirty-six point pill inside a six percent white trough with a
///     twelve percent outline, and the selected half is the near-white accent.
struct LabHeader: View {
    let chamber: Chamber
    let isRunning: Bool
    let framesPerSecond: Int
    let glass: GlassLevel

    let onToggleRunning: () -> Void
    let onSelectChamber: (Chamber) -> Void
    let onShowMenu: () -> Void
    let onShowPerformance: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            chamberRow
        }
        .background(headerBackground)
        .overlay(alignment: .bottom) {
            // Twelve percent, deliberately weaker than the fifteen the floating panels use, so the
            // bar sits behind them rather than competing.
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
        }
    }

    // MARK: Rows

    private var titleRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Crucible")
                    .font(.labDisplay(16))
                    .tracking(-0.4)
                    .foregroundStyle(Palette.foreground)
                Text(chamber.subtitle)
                    .font(.labBody(11))
                    .foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            roundButton(
                isRunning ? "pause.fill" : "play.fill",
                label: isRunning ? "Pause" : "Play",
                action: onToggleRunning
            )
            roundButton("line.3.horizontal", label: "Menu", action: onShowMenu)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var chamberRow: some View {
        HStack(spacing: 4) {
            chamberSwitch
            Spacer(minLength: 0)
            frameRateChip
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var chamberSwitch: some View {
        HStack(spacing: 0) {
            ForEach(Chamber.allCases, id: \.rawValue) { option in
                let selected = chamber == option
                Button {
                    onSelectChamber(option)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.symbol)
                            .font(.labBody(12, .medium))
                        Text(option.title)
                            .font(.labBody(12, .medium))
                    }
                    .foregroundStyle(selected ? Palette.primaryForeground : Palette.muted)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Capsule().fill(selected ? Palette.primary : Color.clear))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        )
    }

    /// The frame rate, tinted by whether it is keeping up, and the way into the graphs.
    ///
    /// In the header rather than tucked away, because it is the one number that explains why something
    /// feels heavy — and on a simulation people are going to push until it struggles, that is worth
    /// seeing at a glance. Tapping it opens the history, which is where the useful questions live:
    /// whether it is creeping up, and whether that stutter was real.
    private var frameRateChip: some View {
        Button(action: onShowPerformance) {
            HStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg")
                    .font(.labBody(10, .medium))
                Text("\(framesPerSecond) fps")
                    .font(.labNumeric(11))
            }
            .foregroundStyle(frameRateTint)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(framesPerSecond) frames per second")
        .accessibilityHint("Opens the performance history")
    }

    private var frameRateTint: Color {
        if framesPerSecond >= 100 { return Palette.ok }
        if framesPerSecond >= 50 { return Palette.warn }
        return Palette.danger
    }

    // MARK: Pieces

    /// The bar's own backdrop.
    ///
    /// Not routed through the shared panel treatment, because that draws an outline on all four
    /// sides and this is a bar with one edge. It still honours the glass setting: turned all the way
    /// down there is no blur here either, which is the point of that setting.
    @ViewBuilder
    private var headerBackground: some View {
        switch glass {
        case .flat:
            Palette.background
        case .subtle:
            Color.black.opacity(0.4).background(.ultraThinMaterial)
        case .full:
            Color.black.opacity(0.4).background(.regularMaterial)
        }
    }

    private func roundButton(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.labBody(16, .medium))
                .foregroundStyle(Palette.muted)
                // Forty-four points, which is the smallest a target should be on a touch screen and
                // exactly what the reference uses.
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension Chamber {
    /// What the header says underneath the app's name.
    var subtitle: String {
        switch self {
        case .powder: "Powder world"
        case .field: "Particle field"
        }
    }
}
