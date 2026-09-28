import CrucibleCore
import Foundation

/// What the lab book's card on the world shows, in the three stages an experiment goes through.
///
/// A plain value, copied out of the running experiment only when one of these things changes, so the card is redrawn
/// a handful of times per experiment and not every time the world is looked at.
struct LabBookCard: Equatable {
    enum Stage: Equatable {
        /// The question is up and the world is waiting for a guess.
        case guessing
        /// The guess is in and the world is running; the task is on the card.
        case doing
        /// The world has answered, and the card explains.
        case answered
    }

    var id: String
    var title: String
    var question: String
    var guesses: [String]
    var task: String
    var stage: Stage
    var guess: Int?
    /// Whether "Show me" is offered yet. Only once somebody has had a fair go.
    var offersHelp: Bool
    var wasShown: Bool
    var verdict: String
    var guessedRight: Bool?
    var explanation: [String]
}

extension SimulationModel {
    /// Sets an experiment up in the world and asks its question.
    ///
    /// The world it replaces is one undo away, as with a scene. The world is held still until a guess is made, so
    /// nothing happens before anybody has thought about what will.
    func beginExperiment(_ experiment: LabExperiment) {
        endParallel(keepSecond: false)
        cancelPendingEvent()
        toolsBeforeWorldReplaced()
        recordUndoPoint()
        let run = LabBookRun(experiment, in: engine)
        labRun = run
        labLookedAt = engine.frameCount
        if let material = experiment.material { brushElement = material }
        brushShape = .circle
        brushTint = 0
        isRunning = false
        refreshCounts()
        publishLabBook()
    }

    /// Takes a guess — or none, for somebody who would rather just see — and lets the world run.
    func guessExperiment(_ guess: Int?) {
        guard var run = labRun else { return }
        run.start(guessing: guess)
        labRun = run
        labStartedAt = worldSeconds
        isRunning = true
        publishLabBook()
    }

    /// Does the task for somebody who is stuck.
    func showMeExperiment() {
        guard var run = labRun, !run.isAnswered else { return }
        run.showMe(in: engine)
        labRun = run
        isRunning = true
        refreshCounts()
        publishLabBook()
    }

    /// Puts the lab book away. The world stays as it is, to go on playing with.
    func endExperiment() {
        guard labRun != nil else { return }
        labRun = nil
        labBook = nil
    }

    /// Looks at the world for the running experiment, if enough moments have passed since the last look.
    func lookAtExperiment() {
        guard var run = labRun, !run.isAnswered else { return }
        // Nothing to judge until the question has been answered with a guess: the world is still, and a look now
        // would only record the set-up again.
        guard run.hasStarted else { return }
        guard engine.frameCount - labLookedAt >= run.experiment.lookEvery else { return }
        labLookedAt = engine.frameCount
        let answeredNow = run.look(at: engine)
        let helpNow = offersHelp(run)
        labRun = run
        if answeredNow {
            Haptics.firm()
            onLabBookAnswered?(run)
            publishLabBook()
        } else if helpNow != labBook?.offersHelp {
            publishLabBook()
        }
    }

    /// Whether somebody has had a fair go: the world's own seconds, or real seconds of it running, whichever comes
    /// first. The world's seconds alone fall behind on a slow or hot phone, where a step takes longer than it should.
    private func offersHelp(_ run: LabBookRun) -> Bool {
        run.readings.seconds >= run.experiment.patience
            || (run.hasStarted && worldSeconds - labStartedAt >= run.experiment.patience)
    }

    /// Copies what the card shows out of the running experiment.
    private func publishLabBook() {
        guard let run = labRun else {
            labBook = nil
            return
        }
        let experiment = run.experiment
        let stage: LabBookCard.Stage = run.isAnswered ? .answered : run.hasStarted ? .doing : .guessing
        let card = LabBookCard(
            id: experiment.id,
            title: experiment.title,
            question: experiment.question,
            guesses: experiment.guesses,
            task: experiment.task,
            stage: stage,
            guess: run.guess,
            offersHelp: offersHelp(run),
            wasShown: run.wasShown,
            verdict: run.verdict,
            guessedRight: run.guessedRight,
            explanation: run.explanation
        )
        if labBook != card { labBook = card }
    }
}
