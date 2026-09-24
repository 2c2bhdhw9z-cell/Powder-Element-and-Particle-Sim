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

    var body: some View {
        NavigationStack {
            Form {
                if let report {
                    verdict(report)
                    world(report)
                    heat(report)
                    problems(report)
                }
                repairs
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Check again") { refresh() }
                        .font(.labBody(13, .medium))
                }
            }
        }
        .onAppear { refresh() }
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.background)
        .tint(Palette.primary)
        .preferredColorScheme(.dark)
    }

    private func refresh() {
        report = model.inspect()
    }

    // MARK: Sections

    private func verdict(_ report: PowderDiagnostics) -> some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: report.isHealthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.labBody(18, .medium))
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
            }
            .padding(.vertical, 2)
        }
    }

    private func world(_ report: PowderDiagnostics) -> some View {
        Section {
            row("Size", "\(report.width)×\(report.height)")
            row("Filled", "\(report.activeCells.formatted()) of \(report.totalCells.formatted())")
            row("Load", "\(report.loadPercentage)%")
            row("Memory", "\((report.memoryBytes / 1024).formatted()) KB")
            row("Ticks", report.frameCount.formatted())
        } header: {
            Text("World")
        }
    }

    private func heat(_ report: PowderDiagnostics) -> some View {
        Section {
            row("Coldest", "\(report.minTemp)°C")
            row("Hottest", "\(report.maxTemp)°C")
            row("Average", "\(report.avgTemp)°C")
        } header: {
            Text("Heat")
        }
    }

    @ViewBuilder
    private func problems(_ report: PowderDiagnostics) -> some View {
        if !report.issues.isEmpty {
            Section {
                ForEach(report.issues, id: \.self) { issue in
                    Text(issue)
                        .font(.labBody(12))
                        .foregroundStyle(Palette.foreground)
                }
            } header: {
                Text("Found")
            }
        }
    }

    private var repairs: some View {
        Section {
            repair("Unstick everything", "Clears cells that cannot move or be read") {
                "\(model.flushStuckCells()) cells cleared"
            }
            repair("Fix temperatures", "Replaces readings that are not numbers") {
                "\(model.normaliseTemperatures()) temperatures fixed"
            }
            repair("Put out fires", "Every flame, and the heat it left") {
                "\(model.extinguishFires()) fires out"
            }
            repair("Neutralise acid", "Turns it back into water") {
                "\(model.neutraliseAcids()) cells neutralised"
            }
            repair("Cool right down", "Everything back to room temperature") {
                model.coolAllCells()
                return "the world is at room temperature"
            }
        } header: {
            Text("Repairs")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let lastRepair {
                    Text(lastRepair)
                        .font(.labBody(11, .medium))
                        .foregroundStyle(Palette.ok)
                }
                Text("Each of these changes the world and is one undo away.")
                    .font(.labBody(11))
            }
        }
    }

    // MARK: Pieces

    private func repair(
        _ title: String,
        _ explanation: String,
        action: @escaping () -> String
    ) -> some View {
        Button {
            // An undo point per repair. Several of these remove a lot at once, and finding out
            // afterwards that it was the wrong one should not be permanent.
            model.beginStroke()
            lastRepair = action()
            refresh()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Palette.foreground)
                Text(explanation)
                    .font(.labBody(11))
                    .foregroundStyle(Palette.subtleForeground)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Palette.foreground)
            Spacer()
            Text(value)
                .font(.labNumeric(12))
                .foregroundStyle(Palette.muted)
        }
    }
}
