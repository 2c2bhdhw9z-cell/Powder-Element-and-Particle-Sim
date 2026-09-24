import Testing

@testable import CrucibleCore

/// The optimisation that lets the tick skip looking for exit portals.
///
/// Finding every exit portal used to mean reading all several million cells on every
/// tick, for something a world almost never contains. ``PowderEngine/portalBMayExist``
/// removes that pass, and its correctness rests on a claim that has to be defended:
/// **every route by which a portal can enter the grid sets the flag.**
///
/// The danger is entirely one-sided. A flag left needlessly `true` costs one wasted pass
/// and then corrects itself. A flag wrongly `false` makes teleportation stop working —
/// silently, with no error, in a world that looks perfectly normal. So the tests here are
/// **behavioural**: each one puts a portal pair into the world by a different route and
/// then checks that something actually travels through it. Asserting on the flag's value
/// would only prove the flag is what I set it to.
///
/// The cell-for-cell comparison against the web engine already covers plain placement,
/// through its `portals-teleport` scenario. What it does not cover is the routes that
/// bypass placement — loading a file, receiving a world from another player, undoing, and
/// resizing — which is what these are for.
@Suite("Skipping the portal scan cannot break teleportation")
struct PortalScanTests {
    /// A world where exactly one grain can make exactly one trip.
    ///
    /// A grain of sand rests on the entrance at the left. The exit sits well over to the
    /// right with clear space around it, so a successful trip is unmistakable: the grain
    /// leaves the left of the world entirely and turns up on the right.
    ///
    /// The floor is bedrock so that a grain which fails to travel stays where it is
    /// instead of tumbling somewhere that might be mistaken for an arrival.
    private static func makeWorld() -> PowderEngine {
        let engine = PowderEngine(width: 24, height: 24, seed: 99)
        for x in 0 ..< engine.width {
            engine.setElement(x, engine.height - 1, Element.bedrock)
        }
        engine.setElement(5, 10, Element.portalA)
        engine.setElement(5, 9, Element.sand)
        engine.setElement(18, 10, Element.portalB)
        return engine
    }

    /// Where the sand is, if there is exactly one grain of it.
    private static func sandPosition(_ engine: PowderEngine) -> (x: Int, y: Int)? {
        var found: (x: Int, y: Int)?
        var count = 0
        for y in 0 ..< engine.height {
            for x in 0 ..< engine.width where engine.type[engine.index(x, y)] == Element.sand {
                found = (x, y)
                count += 1
            }
        }
        return count == 1 ? found : nil
    }

    /// Steps the world until the grain has crossed to the right-hand side, or gives up.
    ///
    /// A handful of ticks rather than one, because the entrance picks its exit at random
    /// and the exit it picks may momentarily have no free cell beside it.
    private static func travelled(_ engine: PowderEngine, within ticks: Int = 12) -> Bool {
        for _ in 0 ..< ticks {
            engine.step()
            if let sand = Self.sandPosition(engine), sand.x >= 15 { return true }
        }
        return false
    }

    // MARK: - The control

    /// Establishes that the test can tell a trip from a non-trip.
    ///
    /// Without this, every test below could pass on a world where nothing ever moved.
    @Test("A grain placed beside an entrance travels to the exit")
    func placementTeleports() {
        let engine = Self.makeWorld()
        #expect(Self.travelled(engine))
    }

    /// The other half of the control: the same world with the exit taken out must fail,
    /// or "arrived on the right" is not measuring arrival at all.
    @Test("With no exit, the grain stays where it was")
    func withoutAnExitNothingTravels() {
        let engine = Self.makeWorld()
        engine.setElement(18, 10, Element.empty)
        #expect(!Self.travelled(engine))
        // Still on the left where it started. Not pinned to the exact cell it was placed
        // in: sand resting on top of a solid is entitled to topple a cell sideways, and
        // it does. What matters is that it did not cross the world.
        let sand = Self.sandPosition(engine)
        let x = sand?.x ?? -1
        #expect(x >= 3 && x <= 7)
    }

    // MARK: - Routes that bypass placement

    @Test("Teleporting still works in a world loaded from a save")
    func loadedWorldTeleports() {
        let saved = Self.makeWorld().captureState()

        let engine = PowderEngine(width: 8, height: 8, seed: 99)
        #expect(engine.apply(saved))
        #expect(Self.travelled(engine))
    }

    @Test("Teleporting still works in a world received from another player")
    func sharedWorldTeleports() {
        let shared = Self.makeWorld().captureLiteState()

        let engine = PowderEngine(width: 8, height: 8, seed: 99)
        #expect(engine.apply(lite: shared))
        #expect(Self.travelled(engine))
    }

    @Test("Teleporting still works after undoing back to a world that had portals")
    func undoneWorldTeleports() {
        let engine = Self.makeWorld()
        let history = PowderHistory(maximumSteps: 5)

        history.push(engine)
        // Something that removes the portals, as clearing the world does.
        engine.resetGrid()
        #expect(!engine.portalBMayExist)

        #expect(history.undo(engine))
        #expect(Self.travelled(engine))
    }

    @Test("Teleporting still works after the world is resized")
    func resizedWorldTeleports() {
        let engine = Self.makeWorld()
        engine.resize(width: 30, height: 28)
        #expect(engine.width == 30)
        #expect(Self.travelled(engine))
    }

    // MARK: - Coming back to the fast path

    /// Painting a portal and then erasing it must not leave the world paying for the scan
    /// for the rest of the session.
    @Test("Erasing the last portal returns the world to the cheap path")
    func erasingThePortalClearsTheFlag() {
        let engine = Self.makeWorld()
        engine.step()
        #expect(engine.portalBMayExist)

        engine.setElement(18, 10, Element.empty)
        // One tick to notice: the scan still runs, finds nothing, and switches itself off.
        engine.step()
        #expect(!engine.portalBMayExist)
    }

    @Test("A fresh world does not look for portals")
    func freshWorldSkipsTheScan() {
        let engine = PowderEngine(width: 16, height: 16, seed: 1)
        #expect(!engine.portalBMayExist)
        engine.setElement(4, 4, Element.sand)
        engine.step()
        #expect(!engine.portalBMayExist)
    }

    /// An entrance on its own is not a reason to scan — only an exit is, and the scan is
    /// what collects the exits.
    @Test("An entrance with no exit does not switch the scan on")
    func entranceAloneSkipsTheScan() {
        let engine = PowderEngine(width: 16, height: 16, seed: 1)
        engine.setElement(4, 4, Element.portalA)
        engine.step()
        #expect(!engine.portalBMayExist)
    }
}
