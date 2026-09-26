import Testing

@testable import CrucibleCore

/// The frame a host sends many times a second.
///
/// Two quite different things are being tested here, and it is worth being clear about which is which.
///
/// **That it is correct.** A frame is the only place in the app where bytes arrive from a device nobody
/// controls, so every test that feeds it something malformed is testing a real path. The bar is that a
/// bad frame is *refused*, and that refusing it leaves the receiving player's world exactly as it was —
/// not cleared, not half-written.
///
/// **That it is small enough.** This is not a nicety. The whole design rests on a world being cheap
/// enough to send dozens of times a second over a phone-to-phone link; if the compression does not pay
/// off on realistic worlds then followers watch a slideshow and the feature is not worth having. So the
/// sizes below are measured against worlds built and simulated the way a real one is, and asserted
/// against the budget the transport actually has.
@Suite("The world frame")
struct RoomWorldTests {
    // MARK: Building worlds worth measuring

    /// A world with terrain, materials, and some physics already run.
    ///
    /// Simulated rather than freshly painted on purpose. A painted world is unrealistically tidy —
    /// neat blocks of one material, which run-length encoding flatters. Letting the sand fall and the
    /// water spread breaks the runs up, which is the case the size budget has to survive.
    private func busyWorld(width: Int, height: Int, ticks: Int = 40) -> PowderEngine {
        let engine = PowderEngine(width: width, height: height, seed: 7)

        for x in 0 ..< width {
            engine.setElement(x, height - 1, Element.bedrock)
            // Rolling stone terrain, so the floor is not one long run.
            let depth = 2 + ((x / 7) % 5)
            for y in (height - 1 - depth) ..< (height - 1) {
                engine.setElement(x, y, Element.stone)
            }
        }

        engine.drawBrush(
            centerX: width / 4, centerY: height / 3, radius: max(3, height / 8),
            elementID: Element.sand, shape: .circle
        )
        engine.drawBrush(
            centerX: width / 2, centerY: height / 4, radius: max(3, height / 10),
            elementID: Element.water, shape: .circle
        )
        engine.drawBrush(
            centerX: (width * 3) / 4, centerY: height / 3, radius: max(2, height / 12),
            elementID: Element.oil, shape: .circle
        )
        engine.drawBrush(
            centerX: width / 2, centerY: (height * 2) / 3, radius: max(2, height / 14),
            elementID: Element.lava, shape: .circle
        )

        for _ in 0 ..< ticks { engine.step() }
        return engine
    }

    /// Sends a world the whole way round: packed, decoded, applied.
    private func transmit(_ host: PowderEngine, to guest: PowderEngine, sequence: UInt32 = 1) throws {
        let frame = try #require(host.captureRoomWorld(sequence: sequence).encoded())
        let received = try #require(RoomWorld.decode(frame))
        #expect(guest.apply(roomWorld: received))
    }

    // MARK: It arrives intact

    @Test("A busy world arrives cell for cell")
    func busyWorldArrivesIntact() throws {
        let host = busyWorld(width: 180, height: 140)
        let guest = PowderEngine(width: 8, height: 8, seed: 1)

        try transmit(host, to: guest)

        #expect(guest.width == host.width)
        #expect(guest.height == host.height)
        var differences = 0
        for i in 0 ..< host.cellCount where guest.type[i] != host.type[i] { differences += 1 }
        #expect(differences == 0, "\(differences) of \(host.cellCount) cells differ")
    }

    @Test("An empty world arrives, and is not mistaken for a broken frame")
    func emptyWorldArrives() throws {
        let host = PowderEngine(width: 64, height: 64, seed: 1)
        let guest = busyWorld(width: 40, height: 40)

        try transmit(host, to: guest)

        #expect(guest.width == 64)
        var occupied = 0
        for i in 0 ..< guest.cellCount where guest.type[i] != Element.empty { occupied += 1 }
        #expect(occupied == 0, "an empty world should arrive empty, \(occupied) cells were not")
    }

    /// One cell is the smallest world the engine will make, and the smallest frame there is. Worth its
    /// own test because off-by-one handling in a run-length encoder tends to fail at exactly this size.
    @Test("A world one cell across survives the trip")
    func singleCellWorld() throws {
        let host = PowderEngine(width: 1, height: 1, seed: 1)
        host.setElement(0, 0, Element.sand)
        let guest = PowderEngine(width: 30, height: 30, seed: 1)

        try transmit(host, to: guest)
        #expect(guest.cellCount == 1)
        #expect(guest.type[0] == Element.sand)
    }

    @Test("Every field in the header survives the trip")
    func headerSurvives() throws {
        let host = busyWorld(width: 40, height: 30)
        // Values chosen to catch a field written or read at the wrong width or the wrong sign.
        host.gravityX = -0.3752
        host.gravityY = 1.9375

        let world = host.captureRoomWorld(sequence: 4_294_967_295)
        // Two statements rather than one: `#require` cannot be nested inside another `#require`.
        let frame = try #require(world.encoded())
        let received = try #require(RoomWorld.decode(frame))

        #expect(received.sequence == 4_294_967_295, "the sequence number wrapped or was narrowed")
        #expect(received.width == 40)
        #expect(received.height == 30)
        #expect(received.gravityX == -0.3752, "gravity came back changed, so precision was lost")
        #expect(received.gravityY == 1.9375)
        #expect(received.fingerprint == world.fingerprint)
        #expect(received.cells == world.cells)
    }

    /// The fingerprint is a check on this code rather than on the link: a frame that decodes at all
    /// arrived intact, so a fingerprint that disagrees means the world was *built* wrong.
    @Test("The receiver's own fingerprint matches the one the host sent")
    func fingerprintAgrees() throws {
        for size in [(24, 18), (61, 47), (180, 140)] {
            let host = busyWorld(width: size.0, height: size.1)
            let guest = PowderEngine(width: 8, height: 8, seed: 2)
            let world = host.captureRoomWorld()

            #expect(guest.apply(roomWorld: world))
            #expect(
                guest.hashLite() == world.fingerprint,
                "at \(size.0)x\(size.1) the receiver built a world the host did not describe"
            )
            #expect(guest.hashLite() == host.hashLite())
        }
    }

    /// The frame carries no temperatures and no lifetimes — they would multiply its size for information
    /// that reconverges within a few ticks. So they have to be rebuilt from each element's own defaults
    /// on arrival, and when they were not, incoming ice landed at the temperature of whatever it replaced
    /// and melted on the spot while incoming fire arrived with no lifetime and vanished next tick.
    @Test("Arriving materials get their own starting temperature and lifetime")
    func arrivingCellsAreUsable() throws {
        let host = PowderEngine(width: 30, height: 30, seed: 1)
        host.drawBrush(centerX: 8, centerY: 8, radius: 3, elementID: Element.ice, shape: .circle)
        host.drawBrush(centerX: 22, centerY: 8, radius: 3, elementID: Element.fire, shape: .circle)

        // A world already full of lava, so an arriving cell that kept its predecessor's temperature
        // would be unmistakably too hot.
        let guest = PowderEngine(width: 30, height: 30, seed: 1)
        guest.drawBrush(centerX: 15, centerY: 15, radius: 20, elementID: Element.lava, shape: .square)

        try transmit(host, to: guest)

        var ice = 0
        var fire = 0
        for i in 0 ..< guest.cellCount {
            if guest.type[i] == Element.ice {
                ice += 1
                #expect(guest.temperature[i] < 0, "ice arrived warm and will melt on the spot")
            }
            if guest.type[i] == Element.fire {
                fire += 1
                #expect(guest.life[i] > 0, "fire arrived with no lifetime and will vanish next tick")
            }
        }
        #expect(ice > 0, "no ice arrived at all")
        #expect(fire > 0, "no fire arrived at all")
    }

    /// Arriving over the wire is one of the ways a portal can enter a world, and the engine skips its
    /// portal scan entirely unless it has been told one might exist. Miss this and teleporting silently
    /// stops working in a shared world while working perfectly in a local one.
    @Test("A portal that arrives in a frame still teleports")
    func arrivingPortalsWork() throws {
        let host = PowderEngine(width: 20, height: 20, seed: 1)
        host.setElement(4, 4, Element.portalA)
        host.setElement(15, 15, Element.portalB)

        let guest = PowderEngine(width: 8, height: 8, seed: 1)
        try transmit(host, to: guest)

        #expect(guest.portalBMayExist, "the world arrived with a portal and the engine was not told")
    }

    // MARK: It is small enough

    /// The measurement the whole design rests on.
    ///
    /// The transport sends a frame, waits for it to be acknowledged, then sends the next, so the rate is
    /// whatever the link can carry. For a smooth picture that wants to be around twenty frames a second,
    /// and a phone-to-phone link is good for a few hundred kilobytes a second — so a frame needs to be
    /// in the tens of kilobytes, not the hundreds.
    ///
    /// Measured, at each of the app's four detail settings, on worlds built and simulated the way a real
    /// one is:
    ///
    /// | detail          | cells   | empty          | busy       | settled    |
    /// |-----------------|---------|----------------|------------|------------|
    /// | low 300×200     | 60,000  | 502 B (119×)   | 8.6 KB     | 3.3 KB     |
    /// | medium 500×300  | 150,000 | 1.2 KB (124×)  | 18 KB      | 9.4 KB     |
    /// | high 720×445    | 320,400 | 2.5 KB (125×)  | 33 KB      | 24 KB      |
    /// | ultra 1000×600  | 600,000 | 4.7 KB (126×)  | 49 KB      | 55 KB      |
    ///
    /// So the middle setting is comfortable at twenty frames a second and the largest is not — at 55 KB
    /// a frame it would want a megabyte a second. That is not a failure: the acknowledgement pacing means
    /// the largest world simply updates less often rather than queueing up frames and falling behind.
    ///
    /// The thresholds below are the budget with room for a real regression to show, not the measured
    /// numbers pinned in place.
    @Test("A busy world at the app's middle detail fits the link's budget")
    func busyWorldFitsBudget() throws {
        // 500x300 is 150,000 cells — the app's middle detail setting. Measured at 18 KB.
        let host = busyWorld(width: 500, height: 300)
        let frame = try #require(host.captureRoomWorld().encoded())

        #expect(
            frame.count < 32 * 1024,
            "a busy 150,000-cell world packed to \(frame.count) bytes, over the 32,768 budget"
        )
        // And it must still be a real saving, not a frame that quietly fell back to plain bytes.
        #expect(
            frame.count < host.cellCount / 4,
            "packing 150,000 cells into \(frame.count) bytes is not a saving worth the code"
        )
    }

    /// The largest world the app will make, left to settle — which is where the frame is at its biggest,
    /// and is *not* the same as the busiest-looking world. At the largest size a settled world encodes
    /// larger than a freshly disturbed one, because the material has had time to spread out and break the
    /// runs up. Worth having its own test so the worst case is the one being measured.
    @Test("The largest world the app can make still fits in a sendable frame")
    func largestWorldStillFits() throws {
        // 1000x600 is 600,000 cells — the app's most detailed setting. Measured at 55 KB.
        let host = busyWorld(width: 1000, height: 600, ticks: 400)
        let frame = try #require(host.captureRoomWorld().encoded())

        #expect(
            frame.count < 96 * 1024,
            "a settled 600,000-cell world packed to \(frame.count) bytes, over the 98,304 budget"
        )
        #expect(frame.count < host.cellCount / 4, "\(frame.count) bytes is not a saving worth the code")
    }

    /// The emptiest worlds compress best, which is the case that matters most: it is the moment someone
    /// has just joined and is waiting to see anything at all.
    @Test("An empty world packs into almost nothing")
    func emptyWorldIsTiny() throws {
        let host = PowderEngine(width: 500, height: 300, seed: 1)
        let frame = try #require(host.captureRoomWorld().encoded())

        // 150,000 cells of air, in runs of at most 255, measured at 1,208 bytes.
        #expect(frame.count < 2048, "an empty world packed to \(frame.count) bytes")
    }

    /// A run longer than a single count byte has to be split across several. Getting this wrong produces
    /// a world that is right for the first 255 cells and wrong after.
    @Test("Runs longer than 255 cells are split and rejoined correctly")
    func longRunsSplit() throws {
        let host = PowderEngine(width: 100, height: 100, seed: 1)
        // Ten thousand identical cells: forty-odd runs of 255, and one short one.
        host.drawBrush(centerX: 50, centerY: 50, radius: 200, elementID: Element.stone, shape: .square)
        let guest = PowderEngine(width: 8, height: 8, seed: 1)

        try transmit(host, to: guest)

        var wrong = 0
        for i in 0 ..< guest.cellCount where guest.type[i] != Element.stone { wrong += 1 }
        #expect(wrong == 0, "\(wrong) cells of a 10,000-cell run came back wrong")
    }

    /// The worst case, and the reason the frame has a flag for it.
    ///
    /// A world where no two neighbouring cells match encodes to twice its size. The encoder notices and
    /// sends the plain bytes instead, so the worst case is the header rather than double the world.
    @Test("A world that cannot be compressed is sent plainly, not doubled")
    func incompressibleWorldFallsBack() throws {
        let host = PowderEngine(width: 120, height: 120, seed: 1)
        // Alternating materials, so every cell differs from the one before it.
        for y in 0 ..< host.height {
            for x in 0 ..< host.width {
                host.setElement(x, y, (x + y) % 2 == 0 ? Element.sand : Element.stone)
            }
        }

        let frame = try #require(host.captureRoomWorld().encoded())
        #expect(
            frame.count <= RoomWorld.headerSize + host.cellCount,
            "an incompressible world grew to \(frame.count) bytes from \(host.cellCount) cells"
        )

        // And it still arrives correctly, which is the part that would be easy to lose.
        let guest = PowderEngine(width: 8, height: 8, seed: 1)
        try transmit(host, to: guest)
        var differences = 0
        for i in 0 ..< host.cellCount where guest.type[i] != host.type[i] { differences += 1 }
        #expect(differences == 0, "\(differences) cells differ in a plainly-sent world")
    }

    /// Both branches of the fallback have to be exercised by the suite, or half the codec is untested
    /// whichever way the decision happens to fall. This asserts which branch each world takes.
    @Test("The encoder chooses compression for a real world and plain bytes for a hostile one")
    func fallbackChoosesCorrectly() {
        let real = busyWorld(width: 120, height: 90)
        var realCells = [UInt8](repeating: 0, count: real.cellCount)
        for i in 0 ..< real.cellCount { realCells[i] = PowderEngine.liteByte(real.type[i]) }
        #expect(RoomWorldCodec.encodeBody(realCells).runLengthEncoded, "a real world should compress")

        let alternating = (0 ..< 10_000).map { UInt8($0 % 2 == 0 ? 3 : 9) }
        let hostile = RoomWorldCodec.encodeBody(alternating)
        #expect(!hostile.runLengthEncoded, "alternating cells should fall back to plain bytes")
        #expect(hostile.body == alternating, "the fallback should send the original bytes untouched")
    }

    // MARK: It refuses what it cannot trust

    @Test("A frame too short to hold a header is refused")
    func shortFrameRefused() {
        for length in 0 ..< RoomWorld.headerSize {
            #expect(
                RoomWorld.decode([UInt8](repeating: 0, count: length)) == nil,
                "a \(length)-byte frame was accepted"
            )
        }
    }

    /// Truncation is the ordinary failure on a bad link, so every possible cut is tried rather than one
    /// representative one.
    @Test("A frame cut short at any point is refused")
    func truncatedFrameRefused() throws {
        let host = busyWorld(width: 60, height: 45)
        let frame = try #require(host.captureRoomWorld().encoded())

        var accepted: [Int] = []
        for length in 0 ..< frame.count {
            if RoomWorld.decode(Array(frame[0 ..< length])) != nil { accepted.append(length) }
        }
        #expect(accepted.isEmpty, "frames cut to these lengths were accepted: \(accepted)")
        // And the whole frame is fine, so the test above is not passing by refusing everything.
        #expect(RoomWorld.decode(frame) != nil, "the intact frame should decode")
    }

    /// A frame with extra bytes on the end is as wrong as one missing them: it means the sender and this
    /// build disagree about the format.
    @Test("A frame with trailing rubbish is refused")
    func overlongFrameRefused() throws {
        let host = busyWorld(width: 60, height: 45)
        let frame = try #require(host.captureRoomWorld().encoded())
        #expect(RoomWorld.decode(frame + [0]) == nil)
        #expect(RoomWorld.decode(frame + [7, 7, 7, 7]) == nil)
    }

    @Test("A frame from a different version of the format is refused, not guessed at")
    func wrongVersionRefused() throws {
        let host = busyWorld(width: 40, height: 30)
        var frame = try #require(host.captureRoomWorld().encoded())
        #expect(RoomWorld.decode(frame) != nil)

        frame[0] = RoomWorld.version + 1
        #expect(RoomWorld.decode(frame) == nil, "a newer frame was read as though it were this version")
        frame[0] = 0
        #expect(RoomWorld.decode(frame) == nil)
    }

    /// A flag this build does not know means a newer one is describing the body differently. Reading it
    /// as though the flag were absent produces a plausible, wrong world.
    @Test("A frame with an unknown flag is refused")
    func unknownFlagRefused() throws {
        let host = busyWorld(width: 40, height: 30)
        var frame = try #require(host.captureRoomWorld().encoded())
        frame[1] |= 1 << 3
        #expect(RoomWorld.decode(frame) == nil)
    }

    @Test("A frame claiming an impossible world size is refused")
    func impossibleSizeRefused() throws {
        let host = busyWorld(width: 40, height: 30)
        let original = try #require(host.captureRoomWorld().encoded())

        // Width zero.
        var zeroWidth = original
        zeroWidth[6] = 0
        zeroWidth[7] = 0
        #expect(RoomWorld.decode(zeroWidth) == nil)

        // Height zero.
        var zeroHeight = original
        zeroHeight[8] = 0
        zeroHeight[9] = 0
        #expect(RoomWorld.decode(zeroHeight) == nil)

        // A size past what the engine will build.
        var huge = original
        huge[6] = 0xFF
        huge[7] = 0xFF
        #expect(RoomWorld.decode(huge) == nil)
    }

    /// The defence against a stranger on the local network asking for a very large allocation with a very
    /// small message. The dimensions alone are inside what the engine would build; the area is not.
    @Test("A tiny frame claiming millions of cells is refused before anything is allocated")
    func hostileCellCountRefused() {
        var frame = [UInt8](repeating: 0, count: RoomWorld.headerSize)
        frame[0] = RoomWorld.version
        frame[1] = RoomWorld.runLengthEncodedFlag
        // 8000 x 8000 is sixty-four million cells — inside the engine's per-side limit, far outside what
        // a frame may claim.
        frame[6] = UInt8(8000 & 0xFF)
        frame[7] = UInt8(8000 >> 8)
        frame[8] = UInt8(8000 & 0xFF)
        frame[9] = UInt8(8000 >> 8)

        #expect(RoomWorld.decode(frame) == nil)
        #expect(8000 * 8000 > RoomWorld.maximumCells, "the test's premise")
        // The engine now refuses the area too, so a save file cannot ask for it either — the frame check is
        // no longer the only thing standing between a tiny message and a gigabyte.
        #expect(!PowderEngine.isValidSize(width: 8000, height: 8000), "the engine accepted sixty-four million cells")
    }

    @Test("A body describing the wrong number of cells is refused")
    func wrongCellCountRefused() {
        let tooFew: [UInt8] = [10, 3]
        #expect(
            RoomWorldCodec.decodeBody(tooFew[...], runLengthEncoded: true, expectedCount: 25) == nil,
            "a body describing ten of twenty-five cells was accepted"
        )

        let tooMany: [UInt8] = [200, 3]
        #expect(
            RoomWorldCodec.decodeBody(tooMany[...], runLengthEncoded: true, expectedCount: 25) == nil,
            "a body describing two hundred of twenty-five cells was accepted"
        )

        // The premise: a body describing exactly the right number is accepted, so the two above are
        // being refused for the reason claimed rather than because nothing is ever accepted.
        let exact: [UInt8] = [25, 3]
        let decoded = RoomWorldCodec.decodeBody(exact[...], runLengthEncoded: true, expectedCount: 25)
        #expect(decoded?.count == 25)

        let plainShort = [UInt8](repeating: 3, count: 24)
        #expect(
            RoomWorldCodec.decodeBody(plainShort[...], runLengthEncoded: false, expectedCount: 25) == nil,
            "a plain body one byte short was accepted"
        )
    }

    /// A pair is two bytes, so an odd body is truncated or corrupt.
    @Test("A run-length body of odd length is refused")
    func oddBodyRefused() {
        let odd: [UInt8] = [10, 3, 5]
        #expect(RoomWorldCodec.decodeBody(odd[...], runLengthEncoded: true, expectedCount: 15) == nil)
    }

    /// A run of zero makes no progress. Before this was checked it was an endless loop, which on a phone
    /// means the app stops responding until it is killed — reachable by one malformed message.
    @Test("A run of zero is refused rather than looping forever")
    func zeroRunRefused() {
        let leadingZero: [UInt8] = [0, 3]
        #expect(RoomWorldCodec.decodeBody(leadingZero[...], runLengthEncoded: true, expectedCount: 10) == nil)

        let zeroInTheMiddle: [UInt8] = [5, 3, 0, 4, 5, 3]
        #expect(
            RoomWorldCodec.decodeBody(zeroInTheMiddle[...], runLengthEncoded: true, expectedCount: 10) == nil,
            "a zero run in the middle of an otherwise valid body was accepted"
        )
    }

    // MARK: A refused frame changes nothing

    /// The point of deciding before clearing. One unreadable message from a peer on a different build
    /// must not wipe the world the player is looking at.
    @Test("A refused world leaves the existing world exactly as it was")
    func refusedWorldChangesNothing() {
        let engine = busyWorld(width: 60, height: 45)
        let before = Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount))
        let gravityXBefore = engine.gravityX
        let gravityYBefore = engine.gravityY
        let fingerprintBefore = engine.hashLite()

        let bad: [RoomWorld] = [
            // Cells that do not fill the world they claim.
            RoomWorld(width: 60, height: 45, gravityX: 9, gravityY: 9, cells: [1, 2, 3]),
            // A size the engine will not build.
            RoomWorld(width: 0, height: 45, gravityX: 9, gravityY: 9, cells: []),
            RoomWorld(width: 60, height: -1, gravityX: 9, gravityY: 9, cells: []),
            // Cells for a world of a different shape.
            RoomWorld(
                width: 30, height: 20, gravityX: 9, gravityY: 9,
                cells: [UInt8](repeating: 3, count: 60 * 45)
            ),
        ]

        for world in bad {
            #expect(!engine.apply(roomWorld: world), "a \(world.width)x\(world.height) frame was applied")
        }

        #expect(Array(UnsafeBufferPointer(start: engine.type, count: engine.cellCount)) == before)
        #expect(engine.gravityX == gravityXBefore, "a refused frame changed gravity")
        #expect(engine.gravityY == gravityYBefore, "a refused frame changed gravity")
        #expect(engine.hashLite() == fingerprintBefore)
    }

    /// Gravity that is not a number reaches every position in the world and nothing recovers from it.
    @Test("Gravity that is not a number is ignored rather than adopted")
    func nonsenseGravityIgnored() {
        let engine = busyWorld(width: 40, height: 30)
        engine.gravityX = 0.5
        engine.gravityY = 1

        let world = RoomWorld(
            width: 40, height: 30,
            gravityX: .nan, gravityY: .infinity,
            cells: [UInt8](repeating: 0, count: 40 * 30)
        )
        #expect(engine.apply(roomWorld: world), "the cells were fine, so the frame should apply")

        #expect(engine.gravityX == 0.5, "a gravity that is not a number was adopted")
        #expect(engine.gravityY == 1)
        #expect(!engine.gravityX.isNaN)
        #expect(!engine.gravityY.isNaN)
    }

    /// An element identifier this build does not have becomes air rather than sitting in the grid as a
    /// cell that behaves like nothing while counting as a real particle forever.
    @Test("A cell naming a material this build does not have becomes air")
    func unknownMaterialBecomesAir() {
        let engine = PowderEngine(width: 10, height: 10, seed: 1)
        var cells = [UInt8](repeating: 0, count: 100)
        cells[0] = 250
        cells[1] = UInt8(Element.sand)

        #expect(engine.apply(roomWorld: RoomWorld(
            width: 10, height: 10, gravityX: 0, gravityY: 1, cells: cells
        )))
        #expect(engine.type[0] == Element.empty, "an unknown material was kept in the grid")
        #expect(engine.type[1] == Element.sand, "a known material next to it was lost")
    }

    /// A world that cannot be represented is refused at the sending end too, rather than going out with
    /// a truncated width and arriving as a world sheared diagonally that passes every check.
    @Test("A world that will not fit the header refuses to encode")
    func unrepresentableWorldRefusesToEncode() {
        #expect(RoomWorld(width: 0, height: 10, gravityX: 0, gravityY: 1, cells: []).encoded() == nil)
        #expect(
            RoomWorld(
                width: 10, height: 10, gravityX: 0, gravityY: 1, cells: [1, 2, 3]
            ).encoded() == nil,
            "a world whose cells do not fill it was encoded anyway"
        )
        // Checked before the cells are looked at, so this needs no nine-million-byte array to prove it.
        #expect(
            RoomWorld(width: 3000, height: 3000, gravityX: 0, gravityY: 1, cells: []).encoded() == nil,
            "a nine-million-cell world was encoded, past what a frame may carry"
        )
    }
}
