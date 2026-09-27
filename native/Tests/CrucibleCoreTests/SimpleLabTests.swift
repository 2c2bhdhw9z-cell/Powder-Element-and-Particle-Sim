import Testing

@testable import CrucibleCore

/// The smaller lab, and the first run.
@Suite("The smaller lab, and what is said first")
struct SimpleLabTests {
    @Test("Everything the smaller lab offers exists, and behaves")
    func theShortListIsReal() {
        let engine = PowderEngine(width: 40, height: 40, seed: 1)
        #expect(SimpleLab.materials.count == 5)
        for id in SimpleLab.materials {
            #expect(engine.registry.table[id].isDefined, "the smaller lab offers a material that does not exist: \(id)")
            // It can be painted, and what is painted is what was asked for.
            engine.setElement(2, 2, id)
            #expect(engine.type[engine.index(2, 2)] == id)
        }
        // Air is always offered, so there is a way to rub something out.
        #expect(SimpleLab.offers(Element.empty))
        #expect(!SimpleLab.offers(Element.c4), "the smaller lab offers C4")
        #expect(SimpleLab.offers(Element.sand))
        #expect(!SimpleLab.shapes.isEmpty)
        #expect(!SimpleLab.shapes.contains(.replace), "the smaller lab offers a brush for building rather than drawing")
        #expect(SimpleLab.events.count == 2)
    }

    @Test("Every scene on the short list is a scene that exists")
    func theScenesAreReal() {
        let found = SimpleLab.scenes
        let missing = SimpleLab.sceneNames.filter { name in !found.contains { $0.name == name } }
        #expect(missing.isEmpty, "the smaller lab names scenes that no longer exist")
        #expect(missing == [], "\(missing)")
        #expect(found.count == SimpleLab.sceneNames.count)
        // And each one lays something out, rather than being a name attached to nothing.
        for recipe in found {
            let engine = PowderEngine(width: 90, height: 140, seed: 3)
            var generator = Mulberry32(seed: 7)
            recipe.apply(to: engine, random: &generator)
            #expect(engine.activeParticleCount > 0, "the \(recipe.name) scene laid out nothing")
        }
    }

    @Test("What is said first covers what nobody would otherwise find")
    func theFirstRunSaysTheRightThings() {
        let steps = LabIntroduction.steps
        #expect(steps.count == 6, "a seventh step is where somebody stops reading")
        for step in steps {
            #expect(!step.title.isEmpty && !step.body.isEmpty && !step.symbol.isEmpty)
            // Long enough to say something, short enough to read on a phone.
            #expect(step.body.count > 60 && step.body.count < 400, "\(step.title): \(step.body.count) characters")
            #expect(step.title.count <= 40)
        }
        let all = steps.map { "\($0.title) \($0.body)" }.joined(separator: " ").lowercased()
        // The five things that are invisible until somebody says them.
        for subject in ["tray", "tilt", "undo", "rewind", "simple"] {
            #expect(all.contains(subject), "the first run never mentions \(subject)")
        }
        #expect(Set(steps.map(\.title)).count == steps.count, "two steps share a heading")
    }
}
