import SwiftUI

/// The floating tools at the top-left of the canvas: undo, redo, shake, and the speed dial.
///
/// Two separate pills rather than one long bar, matching the web version — actions on the
/// left, speed on the right — so the speed readout has its own edge to align against and the
/// undo pair stays where the thumb expects it.
struct ToolCluster: View {
    let model: SimulationModel
    let glass: GlassLevel

    private static let speeds: [Double] = [0.25, 0.5, 1, 2, 4]

    var body: some View {
        GlassGroup(level: glass) {
            HStack(alignment: .top, spacing: 6) {
                actions
                speedDial
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 0) {
            toolButton("arrow.uturn.backward", "Undo", enabled: model.canUndo) {
                model.undo()
            }
            toolButton("arrow.uturn.forward", "Redo", enabled: model.canRedo) {
                model.redo()
            }
            toolButton("waveform", "Shake") {
                model.jostle()
            }
        }
        .glassPanel(glass)
    }

    private var speedDial: some View {
        HStack(spacing: 0) {
            ForEach(Self.speeds, id: \.self) { value in
                Button {
                    model.speed = value
                } label: {
                    Text(Self.label(for: value))
                        .font(.labNumeric(11))
                        // Monospaced digits so the pill does not change width as the
                        // selection moves, which would shuffle the layout under your thumb.
                        .foregroundStyle(
                            model.speed == value ? Palette.foreground : Palette.muted
                        )
                        .frame(minWidth: 34, minHeight: 40)
                }
                .buttonStyle(.plain)
            }
        }
        .glassPanel(glass)
    }

    private static func label(for value: Double) -> String {
        ToolClusterLabels.speed(value)
    }

    private func toolButton(
        _ symbol: String,
        _ label: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(enabled ? Palette.muted : Palette.subtleForeground)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }
}
