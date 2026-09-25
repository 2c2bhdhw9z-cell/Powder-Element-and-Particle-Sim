import CrucibleCore
import SwiftUI

/// The health report for the powder world, and the tools that repair it.
///
/// The engine can already inspect itself and fix what it finds — that work is done and tested,
/// twenty-five behavioural tests' worth — and until now there was no way to ask it to. This is
/// that, and nothing more: it reads what `inspect()` reports and calls the repairs.
///
/// ## Why this is worth a screen
///
/// A world can become quietly wrong in ways that do not look wrong. A cell holding an element
/// that does not exist behaves as air while still counting as material; a temperature that is not
/// a number spreads through heat diffusion until it has poisoned everything it touches; a
/// scene loaded from a damaged file can arrive with either. None of that is visible. The report
/// is how it becomes visible, and the repairs are how it gets undone without throwing the world
/// away.
///
/// The repair buttons are deliberately separate rather than hidden behind one "fix it" — several
/// of them are destructive in their own right, and "seal the borders" in particular walls the
/// world in, which is not something to do by surprise.
struct DiagnosticsSheet: View {
    let model: SimulationModel

    /// Read once when the sheet opens and again on demand, not continuously.
    ///
    /// Inspecting is a full pass over the grid. Doing it every frame to keep a panel live would
    /// cost more than the simulation does, to watch numbers that barely move.
    @State private var report: PowderDiagnostics?
    @State private var lastRepair: String?

    /// The scale the reader prefers, so the health report agrees with the chip on the canvas.
    let unit: TemperatureUnit

    var body: some View {
        LabSheet(title: "Health", subtitle: "What the world looks like from inside") {
            if let report {
                verdict(report)
                world(report)
                heat(report)
                problems(report)
            }
            repairs
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        report = model.inspect()
    }

    // MARK: Sections

    private func verdict(_ report: PowderDiagnostics) -> some View {
        HStack(spacing: 11) {
            Image(systemName: report.isHealthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.labBody(20, .medium))
                .foregroundStyle(report.isHealthy ? Palette.ok : Palette.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text(report.isHealthy ? "Nothing wrong" : "\(report.issues.count) to look at")
                    .font(.labDisplay(15))
                    .foregroundStyle(Palette.foreground)
                Text(report.isHealthy
                    ? "The world is in good order."
                    : "None of this stops the world running.")
                    .font(.labBody(11))
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            Button { refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.labBody(13, .medium))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Check again")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func world(_ report: PowderDiagnostics) -> some View {
        LabGroup("World") {
            LabRow(label: "Size", value: "\(report.width)×\(report.height)")
            LabDivider()
            LabRow(
                label: "Filled",
                value: "\(report.activeCells.formatted()) of \(report.totalCells.formatted())"
            )
            LabDivider()
            LabRow(label: "Load", value: "\(report.loadPercentage)%")
            LabDivider()
            LabRow(label: "Memory", value: "\((report.memoryBytes / 1024).formatted()) KB")
            LabDivider()
            LabRow(label: "Moments", value: report.frameCount.formatted())
        }
    }

    private func heat(_ report: PowderDiagnostics) -> some View {
        LabGroup("Heat") {
            LabRow(label: "Coldest", value: unit.format(celsius: Double(report.minTemp)))
            LabDivider()
            LabRow(label: "Hottest", value: unit.format(celsius: Double(report.maxTemp)))
            LabDivider()
            LabRow(label: "Average", value: unit.format(celsius: Double(report.avgTemp)))
        }
    }

    @ViewBuilder
    private func problems(_ report: PowderDiagnostics) -> some View {
        if !report.issues.isEmpty {
            LabGroup("Found") {
                ForEach(Array(report.issues.enumerated()), id: \.offset) { index, issue in
                    if index > 0 { LabDivider() }
                    Text(issue)
                        .font(.labBody(12))
                        .foregroundStyle(Palette.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var repairs: some View {
        LabGroup(
            "Repairs",
            footnote: lastRepair ?? "Each of these changes the world and is one undo away."
        ) {
            repair("Unstick everything", "Clears cells that cannot move or be read") {
                "\(model.flushStuckCells()) cells cleared"
            }
            LabDivider()
            repair("Fix temperatures", "Replaces readings that are not numbers") {
                "\(model.normaliseTemperatures()) temperatures fixed"
            }
            LabDivider()
            repair("Put out fires", "Every flame, and the heat it left") {
                "\(model.extinguishFires()) fires out"
            }
            LabDivider()
            repair("Neutralise acid", "Turns it back into water") {
                "\(model.neutraliseAcids()) cells neutralised"
            }
            LabDivider()
            repair("Cool right down", "Everything back to room temperature") {
                model.coolAllCells()
                return "the world is at room temperature"
            }
        }
    }

    // MARK: Pieces

    private func repair(
        _ title: String,
        _ explanation: String,
        action: @escaping () -> String
    ) -> some View {
        LabAction(label: title, detail: explanation) {
            // An undo point per repair. Several of these remove a lot at once, and finding out
            // afterwards that it was the wrong one should not be permanent.
            model.recordUndoPoint()
            lastRepair = action()
            refresh()
        }
    }
}
