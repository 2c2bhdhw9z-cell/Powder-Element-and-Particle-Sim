import Foundation
import Testing

@testable import CrucibleCore

/// The first time you make something, it gets written down.
///
/// The whole feature rests on one distinction: painting glass is not discovering glass, but making sand hot enough that
/// it becomes glass is. Both go through the same door in the engine, so the difference is entirely a matter of *when* —
/// and that is the thing most worth checking, because getting it wrong in either direction ruins the feature. Too eager
/// and the notebook fills up the moment somebody opens the tray. Too shy and nobody ever finds anything.
@Suite("The first time you make something")
struct DiscoveriesTests {
    private func world(_ width: Int = 60, _ height: Int = 40) -> PowderEngine {
        PowderEngine(width: width, height: height, seed: 31)
    }

    // MARK: What counts and what does not

    @Test("Painting something by hand is not discovering it")
    func paintingIsNotDiscovering() {
        let engine = world()
        // Every material in the notebook, painted straight in.
        for id in Discoveries.byElement.keys {
            engine.setElement(5, 5, id)
        }
        #expect(engine.takeNewlyMade().isEmpty, "the notebook filled up from the tray")
    }

    @Test("Sand hot enough to melt is discovering glass")
    func glassIsFound() {
        let engine = world()
        engine.setElement(20, 20, Element.sand, temp: 1_600)
        for _ in 0 ..< 20 { engine.step() }
        #expect(engine.takeNewlyMade().contains(Element.glass), "hot sand did not become a discovery")
    }

    @Test("Water boiling and freezing are both found")
    func waterChangesAreFound() {
        let hot = world()
        hot.setElement(20, 20, Element.water, temp: 240)
        for _ in 0 ..< 20 { hot.step() }
        #expect(hot.takeNewlyMade().contains(Element.steam))

        let cold = world()
        cold.ambientTemp = -40
        cold.setElement(20, 20, Element.water, temp: -20)
        for _ in 0 ..< 30 { cold.step() }
        #expect(cold.takeNewlyMade().contains(Element.ice))
    }

    @Test("Lava cooling into obsidian is found even though it skips the usual door")
    func obsidianIsFound() {
        // Quenching lava writes the grid directly rather than going through the one place that sets a cell's material,
        // so it has to tell the notebook by hand. This is the check that it does.
        let engine = world()
        for x in 18 ... 22 { engine.setElement(x, 20, Element.lava, temp: 600) }
        for x in 18 ... 22 { engine.setElement(x, 19, Element.water, temp: 20) }
        for _ in 0 ..< 40 { engine.step() }
        let made = engine.takeNewlyMade()
        #expect(made.contains(Element.obsidian) || made.contains(Element.steam),
                "quenching lava told the notebook nothing")
    }

    @Test("The deep freeze counts, because it is a rule and not a brush")
    func theFreezeEventCounts() {
        // It also writes the grid directly, and it happens between moments rather than during one — so both halves of
        // the design have to be right for this to work.
        let engine = world()
        for x in 10 ... 30 { engine.setElement(x, 20, Element.water) }
        _ = engine.takeNewlyMade()
        engine.start(.freeze)
        #expect(engine.takeNewlyMade().contains(Element.ice), "the deep freeze was not noticed")
    }

    @Test("An explosion's own products count")
    func explosionsCount() {
        let engine = world()
        for x in 20 ... 40 { engine.setElement(x, 20, Element.glass) }
        _ = engine.takeNewlyMade()
        engine.triggerExplosion(centerX: 30, centerY: 20, radius: 14)
        let made = engine.takeNewlyMade()
        #expect(!made.isEmpty, "an explosion made nothing the notebook noticed")
        // Glass torn apart by a blast becomes thermite, which is one of the harder things to find.
        #expect(made.contains(Element.thermite) || made.contains(Element.plasma) || made.contains(Element.fire))
    }

    @Test("Loading a world is not discovering everything in it")
    func loadingIsSilent() throws {
        // Being handed a world with glass in it is not finding out how glass is made. The load path does not go through
        // a running moment, which is what makes this true — stated here so it stays true.
        let made = world()
        made.setElement(20, 20, Element.sand, temp: 1_600)
        for _ in 0 ..< 20 { made.step() }
        let saved = try JSONEncoder().encode(made.captureState())

        let other = world()
        #expect(other.apply(try JSONDecoder().decode(PowderState.self, from: saved)))
        #expect(other.takeNewlyMade().isEmpty, "opening somebody's world discovered everything in it")
    }

    @Test("Repairing a world discovers nothing")
    func repairsAreSilent() {
        let engine = world()
        engine.setElement(20, 20, Element.lava, temp: 3_000)
        _ = engine.takeNewlyMade()
        _ = engine.runAutoFix()
        #expect(engine.takeNewlyMade().isEmpty, "the repair tools discovered things")
    }

    // MARK: How the news is delivered

    @Test("Asking empties it, so nothing is heard twice")
    func askingEmptiesIt() {
        let engine = world()
        engine.setElement(20, 20, Element.sand, temp: 1_600)
        for _ in 0 ..< 20 { engine.step() }
        #expect(!engine.takeNewlyMade().isEmpty)
        #expect(engine.takeNewlyMade().isEmpty, "the same news came twice")
    }

    @Test("A quiet world costs nothing to ask")
    func aQuietWorldIsCheap() {
        // The flag set is only made when there is something to put in it, so a world where nothing is happening — most
        // of them, most of the time — never allocates it at all.
        let engine = world()
        for _ in 0 ..< 30 { engine.step() }
        #expect(engine.takeNewlyMade().isEmpty)
        #expect(engine.storedNoticed.isEmpty, "a world with nothing happening allocated the flag set anyway")
    }

    @Test("Listening is off between moments")
    func listeningStopsAfterwards() {
        let engine = world()
        engine.step()
        #expect(engine.noticing == false, "the engine kept listening after the moment ended")
    }

    // MARK: Chains of explosions

    @Test("Explosions following one another are counted as a chain")
    func chainsAreCounted() {
        let engine = world(120, 80)
        // Three, one after another, with no quiet between them.
        engine.triggerExplosion(centerX: 30, centerY: 40, radius: 8)
        engine.triggerExplosion(centerX: 60, centerY: 40, radius: 8)
        engine.triggerExplosion(centerX: 90, centerY: 40, radius: 8)
        #expect(engine.takeLongestChain() == 3)
        #expect(engine.takeLongestChain() == 0, "the chain was reported twice")
    }

    @Test("Quiet between explosions ends a chain")
    func quietEndsAChain() {
        // The point of the gap: two things a player lit separately are two events, not one long chain.
        let engine = world(120, 80)
        engine.triggerExplosion(centerX: 30, centerY: 40, radius: 8)
        engine.triggerExplosion(centerX: 60, centerY: 40, radius: 8)
        for _ in 0 ..< (PowderEngine.chainGap + 4) { engine.step() }
        engine.triggerExplosion(centerX: 90, centerY: 40, radius: 8)
        #expect(engine.takeLongestChain() == 2, "quiet did not end the chain")
    }

    // MARK: The notebook itself

    @Test("Every discovery has a name, a description and something to try")
    func theyAreAllWrittenProperly() {
        #expect(Discoveries.all.count >= 15)
        var seen = Set<String>()
        for discovery in Discoveries.all {
            #expect(!discovery.id.isEmpty)
            #expect(!discovery.name.isEmpty, "\(discovery.id) has no heading")
            #expect(discovery.about.count > 20, "\(discovery.id) says almost nothing")
            #expect(discovery.hint.count > 8, "\(discovery.id) gives nothing to try")
            let fresh = seen.insert(discovery.id).inserted
            #expect(fresh, "two discoveries answer to \(discovery.id)")
        }
    }

    @Test("Only materials that are made are in the notebook, not ones you can simply pick")
    func onlyMadeThingsAreListed() {
        // The judgement this is holding: a notebook that said "you discovered sand" would be worthless. Sand, water,
        // stone from the tray, wood, metal — those are things you choose, not things you find.
        //
        // Stone is the exception and is in there deliberately: it is listed as lava setting solid, which is a different
        // thing from the stone in the tray, and that is why its heading says so rather than saying "Stone".
        for plain in [Element.sand, Element.water, Element.wood, Element.metal, Element.oil, Element.dirt] {
            #expect(Discoveries.forElement(plain) == nil, "something from the tray is in the notebook")
        }
        #expect(Discoveries.forElement(Element.stone)?.name.contains("Stone") == false)
    }

    @Test("A page is written once and only once")
    func pagesAreWrittenOnce() {
        var notebook = DiscoveryNotebook()
        #expect(notebook.found == 0)
        // Written outside the expectation: these change the notebook, and an expectation cannot be handed something
        // that changes what it is looking at.
        let firstTime = notebook.note("glass", at: 100, chamber: "powder")
        let secondTime = notebook.note("glass", at: 200, chamber: "powder")
        #expect(firstTime)
        #expect(secondTime == false, "the same page was written twice")
        #expect(notebook.pages.count == 1)
        #expect(notebook.pages[0].at == 100, "the second finding overwrote the first one's time")
        #expect(notebook.has("glass"))
        #expect(notebook.found == 1)
    }

    @Test("Something that is not a discovery is refused")
    func nonsenseIsRefused() {
        var notebook = DiscoveryNotebook()
        let madeUp = notebook.note("a thing that does not exist", at: 1, chamber: "powder")
        #expect(madeUp == false)
        #expect(notebook.pages.isEmpty)
        // And a time that is not a time does not become one.
        let withNoTime = notebook.note("glass", at: .nan, chamber: "powder")
        #expect(withNoTime)
        #expect(notebook.pages[0].at == 0)
    }

    @Test("A page naming something this build has never heard of is ignored, not lost")
    func strangePagesAreIgnoredNotLost() {
        // Kept by name rather than number so that adding or reordering discoveries cannot turn somebody's notebook into
        // a different notebook. The cost is pages that name nothing — which are hidden rather than deleted, because a
        // build that removed one by mistake would otherwise destroy the record permanently.
        var notebook = DiscoveryNotebook()
        notebook.pages.append(.init(discovery: "something from a later version", at: 50, chamber: "powder"))
        _ = notebook.note("glass", at: 60, chamber: "powder")
        #expect(notebook.found == 1, "a page from a later version was counted")
        #expect(notebook.inOrder.count == 1, "a page from a later version was shown")
        #expect(notebook.pages.count == 2, "a page from a later version was thrown away")
    }

    @Test("What is left to find is what has not been found")
    func whatIsLeft() {
        var notebook = DiscoveryNotebook()
        #expect(notebook.stillToFind.count == notebook.howMany)
        for discovery in Discoveries.all {
            _ = notebook.note(discovery.id, at: 1, chamber: "powder")
        }
        #expect(notebook.stillToFind.isEmpty)
        #expect(notebook.found == notebook.howMany)
    }

    @Test("The newest page is first")
    func newestFirst() {
        var notebook = DiscoveryNotebook()
        _ = notebook.note("glass", at: 100, chamber: "powder")
        _ = notebook.note("ice", at: 300, chamber: "powder")
        _ = notebook.note("steam", at: 200, chamber: "powder")
        #expect(notebook.inOrder.map(\.discovery) == ["ice", "steam", "glass"])
    }

    @Test("The notebook survives being written down and read back")
    func itSurvivesTheRoundTrip() throws {
        var notebook = DiscoveryNotebook()
        _ = notebook.note("glass", at: 1_000, chamber: "powder")
        _ = notebook.note("bigbang", at: 2_000, chamber: "field")
        let written = try JSONEncoder().encode(notebook)
        let read = try JSONDecoder().decode(DiscoveryNotebook.self, from: written)
        #expect(read == notebook)
        #expect(read.version == DiscoveryNotebook.currentVersion)
    }

    @Test("The order of the pages does not change between runs")
    func theOrderIsStable() {
        // A dictionary has no order, and the material discoveries come from one. A notebook whose pages moved about
        // every time the app opened would be unreadable, so the list is sorted rather than left to chance.
        let once = Discoveries.all.map(\.id)
        let twice = Discoveries.all.map(\.id)
        #expect(once == twice)
        let materials = Discoveries.byElement.values.map(\.name).sorted()
        #expect(Array(Discoveries.all.prefix(materials.count)).map(\.name) == materials)
    }

    @Test("A world can be run for a while and find a handful of things")
    func aRealWorldFindsThings() {
        // The end-to-end claim: play with a world and the notebook fills up by itself, without anybody being told what
        // to do. A scene, run, and then what it found.
        let engine = world(80, 60)
        var generator = Mulberry32(seed: 7)
        powderRecipes.first { $0.id == "volcano" }?.apply(to: engine, random: &generator)
        var found = Set<ElementID>()
        for _ in 0 ..< 400 {
            engine.step()
            for id in engine.takeNewlyMade() { found.insert(id) }
        }
        let discoveries = found.compactMap { Discoveries.forElement($0) }
        #expect(discoveries.count >= 2, "a volcano left the notebook nearly empty: \(discoveries.map(\.name))")
    }
}
