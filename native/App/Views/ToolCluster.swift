import SwiftUI
// For UIImage, which a picture of the world is returned as.
import UIKit

/// The floating tools at the top-left of the canvas: undo, redo, shake, and the speed dial.
///
/// Two separate pills rather than one long bar, matching the web version — actions on the
/// left, speed on the right — so the speed readout has its own edge to align against and the
/// undo pair stays where the thumb expects it.
struct ToolCluster: View {
    let model: SimulationModel
    let tilt: TiltSensor
    let recorder: ScreenRecorder
    /// Somewhere to send a picture once one has been taken.
    @Binding var shareTarget: ShareTarget?

    private static let speeds: [Double] = [0.25, 0.5, 1, 2, 4]

    /// Two rows, not one, and this is the whole reason the file needed changing.
    ///
    /// On one row these came to about 446 points: five 40-point buttons, five 34-point speed steps and
    /// the tilt button. A large iPhone is 440 points wide. So the row ran off the right-hand edge —
    /// the fastest speed and the tilt button were simply not on the screen — and on the way there it
    /// slid underneath the readout in the opposite corner, which the comment beside that readout
    /// confidently described as impossible.
    ///
    /// Split this way the widest row is about 240, which leaves the readout its corner on every phone
    /// rather than only on the largest one.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            actions
            HStack(spacing: 6) {
                speedDial
                TiltButton(tilt: tilt)
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
            toolButton("camera", "Take a picture") {
                // From the engine's own pixels rather than a screen grab. The view does nothing but
                // stretch these without smoothing, so this is what is on screen — and it works
                // while paused, and at a crisper size than the screen shows.
                guard let image = model.snapshot(),
                      let url = LabSnapshot.write(image, named: LabSnapshot.fileName())
                else { return }
                shareTarget = ShareTarget(url: url)
            }
            RecordButton(recorder: recorder)
        }
        .solidPanel()
    }

    /// The five speeds.
    ///
    /// Every step is the **same** width, and that is the fix rather than a detail. They were a minimum
    /// width, so each step took whatever its text needed: "0.25×" and "0.5×" ended up crushed together
    /// while "1×", "2×" and "4×" sat in the middle of great pools of space. It read as a row that had
    /// been assembled carelessly, which is exactly what it was.
    ///
    /// The pill also has padding of its own now, so the first label is not pressed against the screen's
    /// edge with nothing between the two.
    private var speedDial: some View {
        HStack(spacing: 0) {
            ForEach(Self.speeds, id: \.self) { value in
                Button {
                    Haptics.selection()
                    model.speed = value
                } label: {
                    Text(Self.label(for: value))
                        .font(.labNumeric(11))
                        // Monospaced digits so the pill does not change width as the
                        // selection moves, which would shuffle the layout under your thumb.
                        .foregroundStyle(
                            model.speed == value ? Palette.foreground : Palette.muted
                        )
                        .frame(width: 42, height: 40)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 5)
        .solidPanel()
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
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.labBody(14, .medium))
                .foregroundStyle(enabled ? Palette.muted : Palette.subtleForeground)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }
}

/// Starts and stops a recording.
///
/// Its own view because the state it reflects is not the simulation's, and because it needs three
/// appearances rather than two: available, running, and unavailable. A button that looks live and
/// then fails when pressed is worse than one that says it cannot.
struct RecordButton: View {
    let recorder: ScreenRecorder

    var body: some View {
        Button {
            recorder.toggle()
        } label: {
            Image(systemName: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                .font(.labBody(14, .medium))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .disabled(!recorder.isAvailable && !recorder.isRecording)
        .opacity(recorder.isAvailable || recorder.isRecording ? 1 : 0.3)
        .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Record a clip")
    }

    /// Red while running, which is the one convention worth borrowing from every other recorder.
    private var tint: Color {
        if recorder.isRecording { return Palette.danger }
        return recorder.isAvailable ? Palette.muted : Palette.subtleForeground
    }
}
