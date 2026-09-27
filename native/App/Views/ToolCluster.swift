import SwiftUI
// For UIImage, which a picture of the world is returned as.
import UIKit

/// The floating tools at the top-left of the canvas: undo, redo, shake, turn over, and the speed dial.
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
    /// Whether a poster or a plotter drawing is being made.
    @State private var isPreparing = false

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
            // Turns the whole world over, as you would an hourglass: what was on the floor is now at the top, and falls.
            toolButton("arrow.up.arrow.down", "Turn the world upside down") {
                model.flipUpsideDown()
            }
            camera
            RecordButton(recorder: recorder)
        }
        .solidPanel()
    }

    /// A picture, with two more things to hold behind a long press: a poster to print, and a line drawing for a pen
    /// plotter.
    ///
    /// A tap is still just the picture, so nothing changes for anybody who never presses and holds.
    private var camera: some View {
        Menu {
            Button {
                takePicture()
            } label: {
                Label("Picture", systemImage: "camera")
            }
            Button {
                prepare(.poster)
            } label: {
                Label("Poster to print", systemImage: "photo.artframe")
            }
            Button {
                prepare(.plotterDrawing)
            } label: {
                Label("Line drawing for a pen plotter", systemImage: "pencil.and.outline")
            }
        } label: {
            ZStack {
                if isPreparing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Palette.muted)
                } else {
                    Image(systemName: "camera")
                        .font(.labBody(14, .medium))
                        .foregroundStyle(Palette.muted)
                }
            }
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
        } primaryAction: {
            takePicture()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(isPreparing)
        .accessibilityLabel("Take a picture")
        .accessibilityHint("Touch and hold for a poster to print, or a line drawing for a pen plotter")
    }

    /// The ordinary picture: from the engine's own pixels rather than a screen grab. The view does nothing but stretch
    /// these without smoothing, so this is what is on screen — and it works while paused, and at a crisper size than
    /// the screen shows.
    private func takePicture() {
        Haptics.tap()
        guard let image = model.snapshot(),
              let url = LabSnapshot.write(image, named: LabSnapshot.fileName())
        else { return }
        shareTarget = ShareTarget(url: url)
    }

    /// The two larger things to hold.
    private enum Keepsake {
        case poster
        case plotterDrawing
    }

    /// Makes one of the larger things to hold, which takes long enough to show that it is happening, and offers it on.
    private func prepare(_ keepsake: Keepsake) {
        guard !isPreparing else { return }
        Haptics.tap()
        isPreparing = true
        Task { @MainActor in
            var url: URL?
            switch keepsake {
            case .poster: url = await model.posterFile()
            case .plotterDrawing: url = await model.plotterFile()
            }
            isPreparing = false
            if let url {
                Haptics.success()
                shareTarget = ShareTarget(url: url)
            } else {
                Haptics.refused()
            }
        }
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
