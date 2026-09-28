import CrucibleCore
import SwiftUI

/// Chooses the one thing that will differ between two parallel worlds.
struct ParallelWorldsSheet: View {
    let onChoose: (PowderParallelChange) -> Void

    var body: some View {
        LabSheet(title: "Parallel worlds", subtitle: "The same world twice, with one thing changed") {
            LabGroup(
                footnote: "The world is copied exactly as it is now — down to the dice it rolls — and both copies run "
                    + "side by side. Anything that happens differently in the second is because of the one thing you "
                    + "chose. Touching is off while they run, so that stays the only difference."
            ) {
                VStack(spacing: 0) {
                    ForEach(Array(PowderParallelChange.allCases.enumerated()), id: \.element) { index, change in
                        if index > 0 { LabDivider() }
                        Button {
                            Haptics.selection()
                            onChoose(change)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(change.title)
                                    .font(.labBody(13, .medium))
                                    .foregroundStyle(Palette.foreground)
                                Text(change.about)
                                    .font(.labBody(11))
                                    .foregroundStyle(Palette.subtleForeground)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("parallel.\(change.rawValue)")
                    }
                }
            }
        }
    }
}

/// Two parallel worlds on screen at once, each the whole world rather than half of it, and how different they are.
///
/// ## Why neither world is resized to fit its half
///
/// The world is sized from the space it is drawn in, and halving that space would crop away half of each world —
/// the half somebody was probably watching. So both are drawn whole, shrunk to fit, side by side when the world is
/// taller than it is wide and one above the other when it is wider.
struct ParallelPowderView: View {
    let first: SimulationModel
    let second: SimulationModel
    let change: PowderParallelChange

    var body: some View {
        GeometryReader { space in
            let grid = first.gridSize
            let aspect = CGFloat(max(1, grid.width)) / CGFloat(max(1, grid.height))
            let sideBySide = aspect < 1
            VStack(spacing: 8) {
                Spacer(minLength: 0)
                if sideBySide {
                    HStack(spacing: 6) {
                        pane(first, "As it was", aspect: aspect, id: "world.parallel.first")
                        pane(second, change.title, aspect: aspect, id: "world.parallel.second")
                    }
                } else {
                    VStack(spacing: 6) {
                        pane(first, "As it was", aspect: aspect, id: "world.parallel.first")
                        pane(second, change.title, aspect: aspect, id: "world.parallel.second")
                    }
                }
                footer
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .frame(width: space.size.width, height: space.size.height)
        }
    }

    private func pane(_ model: SimulationModel, _ title: String, aspect: CGFloat, id: String) -> some View {
        SimulationSurface(model: model)
            .aspectRatio(aspect, contentMode: .fit)
            // Watched, not touched: a stroke in one would be a second difference.
            .allowsHitTesting(false)
            .overlay(alignment: .topLeading) {
                Text(title)
                    .font(.labBody(10, .semiBold))
                    .foregroundStyle(Palette.foreground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Palette.elevated.opacity(Palette.overWorld(0.8))))
                    .padding(6)
            }
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.border))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue("\(model.activeCells.formatted()) cells filled")
            .accessibilityIdentifier(id)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Text(differenceLine)
                .font(.labBody(12, .medium))
                .foregroundStyle(Palette.foreground)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("parallel.difference")
            HStack(spacing: 8) {
                keep("Keep the first", id: "parallel.keep.first") { first.endParallel(keepSecond: false) }
                keep("Keep the second", id: "parallel.keep.second") { first.endParallel(keepSecond: true) }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .solidPanel(in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    private var differenceLine: String {
        let share = first.parallelDifference
        if share <= 0 { return "The two worlds are still exactly the same." }
        let percent = share * 100
        let said = percent < 1 ? "Less than 1%" : "\(Int(percent.rounded()))%"
        return "\(said) of what is in them is different now."
    }

    private func keep(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.firm()
            withAnimation(.easeOut(duration: 0.2)) { action() }
        } label: {
            Text(title)
                .font(.labBody(12, .semiBold))
                .foregroundStyle(Palette.foreground)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
