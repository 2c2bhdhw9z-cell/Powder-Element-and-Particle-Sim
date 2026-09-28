@testable import CrucibleCore
import Foundation
import Testing

@Suite("The guided lab book")
struct PowderLabBookTests {
    /// Two shapes of world the lab really runs at: a phone held upright on the lightest detail, and a wide one.
    static let sizes: [(Int, Int)] = [(160, 240), (320, 220)]

    /// Sets an experiment up, lets it sit for half a second, and then either does it the way "Show me" does or leaves
    /// it alone, and runs the world until it answers or the time runs out.
    static func run(_ experiment: LabExperiment, width: Int, height: Int, doIt: Bool = true, limit: Double = 40)
        -> (run: LabBookRun, engine: PowderEngine, doneAt: Double)
    {
        let engine = PowderEngine(width: width, height: height, seed: 7)
        var run = LabBookRun(experiment, in: engine)
        run.start(guessing: 0)
        for moment in 0 ..< 30 {
            engine.step()
            if moment % experiment.lookEvery == 0 { run.look(at: engine) }
        }
        let doneAt = run.seconds(in: engine)
        if doIt { run.showMe(in: engine) }
        for moment in 0 ..< Int(limit * 60) {
            engine.step()
            if moment % experiment.lookEvery == 0, run.look(at: engine) { break }
        }
        return (run, engine, doneAt)
    }

    @Test("Every experiment reaches its answer once it is done, on both shapes of world, in reasonable time",
          arguments: LabBook.experiments.map(\.id))
    func everyExperimentFinishes(id: String) throws {
        let experiment = try #require(LabBook.named(id))
        for (width, height) in Self.sizes {
            let (run, _, doneAt) = Self.run(experiment, width: width, height: height)
            #expect(run.isAnswered, "\(id) on \(width)×\(height) was never answered")
            // Offering "Show me" before the world could have answered by itself would be offering help too soon.
            let took = run.readings.seconds - doneAt
            #expect(took < experiment.patience, "\(id) on \(width)×\(height) took \(took) seconds")
            #expect(run.wasShown)
            #expect(run.explanation.count >= 3, "\(id) explained itself in \(run.explanation.count) paragraphs")
            // Numbers that came from the world, not a script: every explanation quotes at least one.
            #expect(run.explanation.joined().contains { $0.isNumber }, "\(id) quoted no numbers from the world")
            // And none of the tell-tales of a reading that was never taken.
            let text = run.explanation.joined(separator: " ")
            #expect(!text.contains("nan") && !text.contains("inf"), "\(id): \(text)")
            #expect(!text.contains(" 0 cells of your"), "\(id) described nothing happening: \(text)")
        }
    }

    @Test("No experiment answers itself: left alone, the world does not get there", arguments: LabBook.experiments.map(\.id))
    func nothingAnswersItself(id: String) throws {
        let experiment = try #require(LabBook.named(id))
        let (run, _, _) = Self.run(experiment, width: 160, height: 240, doIt: false, limit: 20)
        #expect(!run.isAnswered, "\(id) answered itself: \(run.explanation.first ?? "")")
    }

    @Test("Each experiment is asked properly: a right answer among its guesses, a task and a unique name")
    func experimentsAreWellFormed() {
        let ids = LabBook.experiments.map(\.id)
        #expect(Set(ids).count == ids.count)
        for experiment in LabBook.experiments {
            #expect(experiment.guesses.indices.contains(experiment.answer), "\(experiment.id)")
            #expect(experiment.guesses.count >= 3, "\(experiment.id) is not much of a question")
            #expect(!experiment.task.isEmpty && !experiment.question.isEmpty)
            #expect(experiment.lookEvery >= 1)
            if let material = experiment.material {
                #expect(DefaultElements.all.contains { $0.id == material }, "\(experiment.id) hands over nothing")
            }
        }
    }

    @Test("Oil really does end up above the water, by the readings")
    func oilFloatsByTheReadings() throws {
        let (run, _, _) = Self.run(try #require(LabBook.named("floating")), width: 160, height: 240)
        let oil = try #require(run.readings.heightOf[Element.oil])
        let water = try #require(run.readings.heightOf[Element.water])
        #expect(oil > water)
    }

    @Test("Boiling is caught near a hundred degrees and never beyond it")
    func boilingIsCaughtNearTheTop() throws {
        let (run, _, _) = Self.run(try #require(LabBook.named("boiling")), width: 160, height: 240)
        let hottest = try #require(run.readings.hottestOf[Element.water])
        #expect(hottest >= 95 && hottest < 100.5, "the hottest water was \(hottest)°C")
    }

    @Test("The explanation is fixed at the moment of answering, and later looks change nothing")
    func answeringFreezesTheExplanation() throws {
        var (run, engine, _) = Self.run(try #require(LabBook.named("dissolving")), width: 160, height: 240)
        let said = run.explanation
        let readings = run.readings
        for _ in 0 ..< 120 { engine.step() }
        let answeredAgain = run.look(at: engine)
        #expect(!answeredAgain)
        #expect(run.explanation == said)
        #expect(run.readings == readings)
    }

    @Test("A reading notices what arrived, what went, and the hottest and coldest of each")
    func readingsKeepTrack() {
        let engine = PowderEngine(width: 20, height: 20, seed: 1)
        engine.setElement(5, 5, Element.water, temp: 30)
        engine.setElement(6, 5, Element.water, temp: 50)
        var readings = LabReadings()
        readings.look(at: engine, seconds: 0)
        #expect(readings.start[Element.water] == 2)
        #expect(readings.hottestOf[Element.water] == 50)
        #expect(readings.coldestOf[Element.water] == 30)
        #expect(readings.warmthOf[Element.water] == 40)

        engine.setElement(6, 5, Element.empty)
        engine.setElement(9, 9, Element.sand)
        readings.look(at: engine, seconds: 1.5)
        #expect(readings.lost(Element.water) == 1)
        #expect(readings.gained(Element.sand) == 1)
        #expect(readings.firstSeen[Element.sand] == 1.5)
        #expect(readings.firstSeen[Element.water] == nil)
        // Still the hottest it ever was, though that cell has gone.
        #expect(readings.hottestOf[Element.water] == 50)

        engine.setElement(5, 5, Element.empty)
        readings.look(at: engine, seconds: 2)
        #expect(readings.count(Element.water) == 0)
        #expect(readings.lost(Element.water) == 2, "gone altogether counts as none, not as missing")
    }

    @Test("A guess is judged and said plainly")
    func verdicts() throws {
        let engine = PowderEngine(width: 80, height: 60, seed: 1)
        let experiment = try #require(LabBook.named("floating"))
        var run = LabBookRun(experiment, in: engine)
        #expect(run.guessedRight == nil)
        #expect(!run.hasStarted)
        run.start(guessing: nil)
        #expect(run.hasStarted)
        #expect(run.verdict.hasPrefix("The answer: "))
        run.start(guessing: 99)
        #expect(run.guess == nil, "a guess that is not one of the choices is no guess")
        run.start(guessing: experiment.answer)
        #expect(run.guessedRight == true)
        #expect(run.verdict.hasSuffix("right."))
        run.start(guessing: (experiment.answer + 1) % experiment.guesses.count)
        #expect(run.guessedRight == false)
        #expect(run.verdict.contains("The answer is"))
    }

    @Test("Progress keeps the better result, survives being written down, and ignores experiments that are gone")
    func progress() throws {
        var progress = LabBookProgress()
        progress.finish("floating", guessedRight: true, at: 1)
        progress.finish("floating", guessedRight: false, at: 2)
        progress.finish("boiling", guessedRight: false, at: 3)
        progress.finish("an experiment that has since been taken out", guessedRight: true, at: 4)
        #expect(progress.isDone("floating") && progress.wasRight("floating"))
        #expect(progress.isDone("boiling") && !progress.wasRight("boiling"))
        #expect(!progress.isDone("acid"))
        #expect(progress.doneCount == 2)
        let data = try JSONEncoder().encode(progress)
        #expect(try JSONDecoder().decode(LabBookProgress.self, from: data) == progress)
    }

    @Test("Setting an experiment up replaces the world rather than adding to it")
    func setUpReplacesTheWorld() throws {
        let engine = PowderEngine(width: 120, height: 90, seed: 1)
        for x in 0 ..< 120 { engine.setElement(x, 10, Element.gunpowder) }
        _ = LabBookRun(try #require(LabBook.named("floating")), in: engine)
        var gunpowder = 0
        for index in 0 ..< engine.cellCount where engine.type[index] == Element.gunpowder { gunpowder += 1 }
        #expect(gunpowder == 0)
    }
}
