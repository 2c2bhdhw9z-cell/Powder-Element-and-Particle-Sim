import Foundation
import Testing

@testable import CrucibleCore

/// The day's shared world, held to the same choice the web engine makes.
///
/// This matters more than most of the comparisons here. The entire point of the daily world is that
/// everyone gets the same one, and there is no server deciding it — the agreement rests on both
/// implementations hashing the date identically and indexing the same list in the same order.
///
/// If they disagree, the feature is not merely wrong, it is *silently* wrong: both sides confidently
/// show a name, and two people comparing notes would find they had been handed different worlds with
/// nothing to indicate why.
@Suite("The day's world is the same one the web engine picks")
struct DailyWorldTests {
    struct Entry: Decodable, CustomTestStringConvertible {
        var day: String
        var hash: UInt32
        var powderIndex: Int
        var powderId: String
        var powderName: String
        var particleIndex: Int
        var particlePreset: String

        var testDescription: String { day }
    }

    struct Fixture: Decodable {
        var note: String
        var days: [Entry]
    }

    static let fixture: Fixture = {
        guard let url = Bundle.module.url(
            forResource: "web-daily-golden",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) ?? Bundle.module.url(forResource: "web-daily-golden", withExtension: "json") else {
            fatalError("Fixture web-daily-golden.json is missing from the test bundle")
        }
        do {
            return try JSONDecoder().decode(Fixture.self, from: try Data(contentsOf: url))
        } catch {
            fatalError("Could not decode the golden daily fixture: \(error)")
        }
    }()

    // MARK: The hash

    @Test("The date hashes to the same number", arguments: fixture.days)
    func hashMatches(entry: Entry) {
        #expect(
            DailyWorld.hash(forDay: entry.day) == entry.hash,
            "\(entry.day): hashed to \(DailyWorld.hash(forDay: entry.day)), the web engine got \(entry.hash)"
        )
    }

    // MARK: The choices

    @Test("The same scene is chosen", arguments: fixture.days)
    func powderMatches(entry: Entry) {
        let recipe = DailyWorld.powderRecipe(forDay: entry.day)
        #expect(
            recipe.id == entry.powderId,
            "\(entry.day): chose \(recipe.id), the web engine chose \(entry.powderId)"
        )
        #expect(recipe.name == entry.powderName)
    }

    @Test("The same arrangement is chosen", arguments: fixture.days)
    func particleMatches(entry: Entry) {
        let preset = DailyWorld.particlePreset(forDay: entry.day)
        #expect(
            preset == entry.particlePreset,
            "\(entry.day): chose \(preset), the web engine chose \(entry.particlePreset)"
        )
    }

    /// The list's order *is* the contract. Reordering it silently changes which scene a given day gets,
    /// so two people on different versions would disagree about the shared world.
    @Test("The arrangement list is the same length and order the web engine uses")
    func presetListMatches() {
        #expect(DailyWorld.particlePresets.count == 7)
        // Checked through the choices rather than by listing the names again here, which would only
        // restate them. Every index in the fixture has to land on the name the web engine recorded.
        for entry in Self.fixture.days {
            #expect(
                DailyWorld.particlePresets[entry.particleIndex] == entry.particlePreset,
                "index \(entry.particleIndex) should be \(entry.particlePreset)"
            )
        }
    }

    // MARK: Reproducibility

    /// The reason this takes a day rather than reading a clock. One of the thirteen scenes scatters its
    /// material at random, and in the reference it read the global random source — so on roughly one day
    /// in thirteen the "daily" world was different for every player while the interface went on
    /// announcing it by name.
    @Test("The same day builds an identical world, twice")
    func sameDayIsIdentical() {
        // The scattering scene specifically, found by looking for the day that chooses it.
        let day = "2025-06-15"
        #expect(DailyWorld.powderRecipe(forDay: day).id == "remix", "expected the scattering scene")

        let first = PowderEngine(width: 80, height: 60, seed: 1)
        let second = PowderEngine(width: 80, height: 60, seed: 9999)
        DailyWorld.applyPowder(forDay: day, to: first)
        DailyWorld.applyPowder(forDay: day, to: second)

        // Different engine seeds on purpose: the day's world must come from the *day*, not from
        // whatever state the engine happened to be in.
        var differences = 0
        for i in 0 ..< first.cellCount where first.type[i] != second.type[i] {
            differences += 1
        }
        #expect(differences == 0, "\(differences) cells differ between two builds of the same day")
    }

    @Test("Different days build different worlds")
    func differentDaysDiffer() {
        let a = PowderEngine(width: 80, height: 60, seed: 1)
        let b = PowderEngine(width: 80, height: 60, seed: 1)
        DailyWorld.applyPowder(forDay: "2026-09-24", to: a)
        DailyWorld.applyPowder(forDay: "2026-09-25", to: b)

        var differences = 0
        for i in 0 ..< a.cellCount where a.type[i] != b.type[i] {
            differences += 1
        }
        #expect(differences > 0, "two different days produced the same world")
    }

    @Test("A day's choice reports itself")
    func choiceIsReported() {
        let engine = PowderEngine(width: 60, height: 40, seed: 1)
        let choice = DailyWorld.applyPowder(forDay: "2026-09-24", to: engine)
        #expect(choice.day == "2026-09-24")
        #expect(choice.name == "Forest")
        #expect(choice.hash == DailyWorld.hash(forDay: "2026-09-24"))
    }

    @Test("The particle arrangement actually puts something in the field")
    func particleFieldIsFilled() {
        for entry in Self.fixture.days {
            let engine = ParticleEngine(width: 400, height: 800, seed: 5)
            let choice = DailyWorld.applyParticle(forDay: entry.day, to: engine)
            #expect(choice.name == entry.particlePreset)
            #expect(engine.bodyCount > 0, "\(entry.day) produced an empty field")
        }
    }

    /// Every date in the year has to land somewhere valid. An index computed from a hash that slipped
    /// out of range would crash on one particular day — which is the worst possible schedule for a bug.
    @Test("Every day of a year lands on a real scene and arrangement")
    func everyDayIsValid() {
        var scenesSeen: Set<String> = []
        var presetsSeen: Set<String> = []

        for month in 1 ... 12 {
            for dayOfMonth in 1 ... 28 {
                let day = String(format: "2026-%02d-%02d", month, dayOfMonth)
                let recipe = DailyWorld.powderRecipe(forDay: day)
                let preset = DailyWorld.particlePreset(forDay: day)
                #expect(powderRecipes.contains { $0.id == recipe.id })
                #expect(DailyWorld.particlePresets.contains(preset))
                scenesSeen.insert(recipe.id)
                presetsSeen.insert(preset)
            }
        }

        // And the choices genuinely spread out over a year rather than sticking on a favourite.
        #expect(scenesSeen.count >= 8, "only \(scenesSeen.count) scenes came up in a year")
        #expect(presetsSeen.count >= 4, "only \(presetsSeen.count) arrangements came up in a year")
    }
}
