@testable import CrucibleCore
import Testing

@Suite("Talking to the lab")
struct VoiceCommandsTests {
    static let materials = VoiceCommands.materialNames(DefaultElements.all)
    static let arrangements = ParticleArrangement.all.map { VoiceCommands.Name($0.name, id: $0.id) }
    static let scenes = allPowderRecipes.map { VoiceCommands.Name($0.name, id: $0.id) }

    static func understand(_ said: String) -> LabVoiceCommand? {
        VoiceCommands.understand(said, materials: materials, arrangements: arrangements, scenes: scenes)
    }

    @Test("Sentences people actually say", arguments: [
        ("Make it rain", LabVoiceCommand.pour(Element.water)),
        ("give me some lava please", .choose(Element.lava)),
        ("Boom!", .explode),
        ("blow it up", .explode),
        ("turn it upside down", .flip),
        ("pause", .pause),
        ("okay carry on", .play),
        ("clear the sand", .clear),
        ("undo that", .undo),
        ("pour lots of sand", .pour(Element.sand)),
        ("salt water", .choose(Element.saltWater)),
        ("salt", .choose(Element.salt)),
        ("electricity", .choose(Element.spark)),
        ("C4", .choose(Element.c4)),
        ("it is snowing", .pour(Element.snow)),
        ("slow motion", .slower),
        ("speed up", .faster),
        ("bigger brush", .biggerBrush),
        ("show me the galaxy", .arrangement("galaxy")),
        ("go to the particle field", .fieldChamber),
        ("back to the powder world", .powderChamber),
    ])
    func sentences(said: String, meant: LabVoiceCommand) {
        #expect(Self.understand(said) == meant, "\(said) was heard as \(String(describing: Self.understand(said)))")
    }

    @Test("Things that are not commands are left alone")
    func notCommands() {
        for said in ["", "hmm", "what a lovely day", "I wonder how this works"] {
            #expect(Self.understand(said) == nil, "\(said)")
        }
    }

    @Test("Every scene can be asked for by its name")
    func everyScene() {
        for recipe in allPowderRecipes {
            #expect(Self.understand("load the \(recipe.name) scene") == .scene(recipe.id), "\(recipe.name)")
        }
    }

    @Test("A sentence heard as it grows is acted on once, not every time the guess improves")
    func growingSentence() {
        var listener = VoiceCommandListener()
        func hear(_ words: String) -> LabVoiceCommand? {
            listener.heard(words, materials: Self.materials, arrangements: Self.arrangements, scenes: Self.scenes)
        }
        #expect(hear("make") == nil)
        #expect(hear("make it") == nil)
        #expect(hear("make it rain") == .pour(Element.water))
        #expect(hear("make it rain") == nil, "the same words again are not a second command")
        #expect(hear("make it rain and then boom") == .explode)
        listener.newSentence()
        #expect(hear("boom") == .explode)
    }

    @Test("What the lab says back names the material")
    func saidBack() {
        let said = LabVoiceCommand.pour(Element.water).said { id in id == Element.water ? "Water" : "?" }
        #expect(said == "Pouring water")
    }

    @Test("A material called two things answers to either")
    func twoNames() {
        let names = Self.materials.filter { $0.0 == Element.spark }.map(\.1)
        #expect(names.contains("Spark") && names.contains("Electricity"))
    }
}
