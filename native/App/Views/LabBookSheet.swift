import CrucibleCore
import SwiftUI

/// The lab book: a list of experiments to do with your own hands.
///
/// Each one sets the world up, asks a question, and waits for a guess before anything moves. Then it hands over the
/// material and says what to do — and when the world has answered, it explains what happened using the numbers the
/// world itself produced. Nothing here is a quiz with a mark at the end; the guess is there so there is something to
/// be surprised by.
struct LabBookSheet: View {
    let store: LabBookStore
    let onChoose: (LabExperiment) -> Void

    var body: some View {
        LabSheet(title: "Lab book", subtitle: "\(store.progress.doneCount) of \(LabBook.experiments.count) done") {
            LabGroup(
                footnote: "Each experiment sets the world up and asks a question. Guess, do it, and the world "
                    + "answers — then the lab book explains what happened with the numbers from your world. Choosing "
                    + "one replaces the world; undo brings it back."
            ) {
                VStack(spacing: 0) {
                    ForEach(Array(LabBook.experiments.enumerated()), id: \.element.id) { index, experiment in
                        if index > 0 { LabDivider() }
                        row(experiment)
                    }
                }
            }
            if let problem = store.lastProblem {
                Text(problem)
                    .font(.labBody(10))
                    .foregroundStyle(Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ experiment: LabExperiment) -> some View {
        Button {
            Haptics.selection()
            onChoose(experiment)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: experiment.symbol)
                    .font(.labBody(14, .medium))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 22)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(experiment.title)
                        .font(.labBody(13, .medium))
                        .foregroundStyle(Palette.foreground)
                    Text(experiment.question)
                        .font(.labBody(11))
                        .foregroundStyle(Palette.subtleForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                status(experiment)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("labbook.\(experiment.id)")
    }

    @ViewBuilder
    private func status(_ experiment: LabExperiment) -> some View {
        if store.progress.isDone(experiment.id) {
            Image(systemName: store.progress.wasRight(experiment.id) ? "star.fill" : "checkmark")
                .font(.labBody(11, .semiBold))
                .foregroundStyle(store.progress.wasRight(experiment.id) ? Palette.warn : Palette.ok)
                .accessibilityLabel(store.progress.wasRight(experiment.id) ? "Done, guessed right" : "Done")
        }
    }
}

/// The card on the world while an experiment is being done: the question, then the task, then the answer.
///
/// On the world rather than in a panel, because the world is where the answer is. It sits under the tools at the top,
/// which is the one part of the world every experiment leaves empty — they are all built from the middle down.
struct LabBookCardView: View {
    let model: SimulationModel
    /// Starts the next experiment in the book, if there is one after this.
    let onNext: ((LabExperiment) -> Void)?

    var body: some View {
        if let card = model.labBook {
            VStack(alignment: .leading, spacing: 10) {
                header(card)
                switch card.stage {
                case .guessing: guessing(card)
                case .doing: doing(card)
                case .answered: answered(card)
                }
            }
            .padding(14)
            .frame(maxWidth: 460, alignment: .leading)
            .solidPanel(in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .padding(.horizontal, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("labbook.card")
        }
    }

    private func header(_ card: LabBookCard) -> some View {
        HStack(spacing: 8) {
            Text("LAB BOOK · \(card.title.uppercased())")
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                Haptics.tap()
                withAnimation(.easeOut(duration: 0.2)) { model.endExperiment() }
            } label: {
                Image(systemName: "xmark")
                    .font(.labBody(11, .medium))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Put the lab book away")
            .accessibilityIdentifier("labbook.stop")
        }
    }

    private func guessing(_ card: LabBookCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.question)
                .font(.labBody(14, .semiBold))
                .foregroundStyle(Palette.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Text("What do you think? The world is waiting.")
                .font(.labBody(11))
                .foregroundStyle(Palette.muted)
            LabFlow(spacing: 6) {
                ForEach(Array(card.guesses.enumerated()), id: \.offset) { index, guess in
                    Button {
                        Haptics.selection()
                        withAnimation(.easeOut(duration: 0.2)) { model.guessExperiment(index) }
                    } label: {
                        Text(guess)
                            .font(.labBody(12, .medium))
                            .foregroundStyle(Palette.foreground)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("labbook.guess.\(index)")
                }
            }
            Button {
                withAnimation(.easeOut(duration: 0.2)) { model.guessExperiment(nil) }
            } label: {
                Text("No guess — just let me try it")
                    .font(.labBody(11, .medium))
                    .foregroundStyle(Palette.subtleForeground)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("labbook.skip")
        }
    }

    private func doing(_ card: LabBookCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.task)
                .font(.labBody(14, .semiBold))
                .foregroundStyle(Palette.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("labbook.task")
            Text(card.guess.map { "You guessed: \(card.guesses[$0].lowercased()). The world will say." }
                ?? "The world will say when it has the answer.")
                .font(.labBody(11))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if card.offersHelp, !card.wasShown {
                Button {
                    Haptics.tap()
                    model.showMeExperiment()
                } label: {
                    Label("Show me", systemImage: "hand.point.up.left")
                        .font(.labBody(12, .medium))
                        .foregroundStyle(Palette.primaryForeground)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Capsule().fill(Palette.primary))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("labbook.showme")
            }
        }
    }

    private func answered(_ card: LabBookCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.verdict)
                .font(.labBody(14, .semiBold))
                .foregroundStyle(card.guessedRight == false ? Palette.warn : Palette.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("labbook.verdict")
            // Scrolls rather than growing without end, because it sits over the world the explanation is about.
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(card.explanation.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.labBody(12))
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if card.wasShown {
                        Text("The lab book did this one for you. Try it again yourself — the numbers will be different.")
                            .font(.labBody(11))
                            .foregroundStyle(Palette.subtleForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            .scrollBounceBehavior(.basedOnSize)
            .labScrollEdges()
            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    withAnimation(.easeOut(duration: 0.2)) { model.endExperiment() }
                } label: {
                    Text("Done")
                        .font(.labBody(12, .semiBold))
                        .foregroundStyle(Palette.primaryForeground)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Capsule().fill(Palette.primary))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("labbook.done")
                if let next = nextExperiment(after: card.id), let onNext {
                    Button {
                        Haptics.selection()
                        onNext(next)
                    } label: {
                        Text("Next: \(next.title)")
                            .font(.labBody(12, .medium))
                            .foregroundStyle(Palette.foreground)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("labbook.next")
                }
            }
        }
    }

    private func nextExperiment(after id: String) -> LabExperiment? {
        guard let index = LabBook.experiments.firstIndex(where: { $0.id == id }),
              index + 1 < LabBook.experiments.count
        else { return nil }
        return LabBook.experiments[index + 1]
    }
}
