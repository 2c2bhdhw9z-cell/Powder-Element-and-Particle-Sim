import Foundation
import Testing

@testable import CrucibleCore

/// Two worlds, one room.
///
/// These are the tests that decide whether sharing a world works, and they are written as a pair of
/// engines talking to each other rather than as assertions about message fields. A protocol can be
/// perfectly well-formed and still fail to make two worlds agree, which is the only thing anyone cares
/// about.
///
/// The whole scheme rests on the fingerprint being trustworthy. It was once not: it mixed the raw cell
/// values while the compact format sent something narrower, so the two never agreed, the "have we
/// drifted?" test was permanently true, and the entire grid was resent every tick. That bug is why the
/// convergence tests below check the fingerprint *and* the cells.
@Suite("Two peers sharing a world")
struct RoomProtocolTests {
    /// A world with enough different things in it that a mistake shows.
    private func makeWorld(width: Int = 48, height: Int = 32, seed: UInt32 = 5) -> PowderEngine {
        let engine = PowderEngine(width: width, height: height, seed: seed)
        for x in 0 ..< width { engine.setElement(x, height - 1, Element.bedrock) }
        engine.setElement(5, 5, Element.sand)
        engine.setElement(10, 8, Element.water)
        engine.setElement(20, 12, Element.lava, temp: 1400)
        engine.setElement(30, 4, Element.fire)
        engine.setElement(40, 20, Element.fan)
        engine.gravityX = 0.25
        engine.setWind(2)
        engine.ambientTemp = 18
        return engine
    }

    private func roundTrip(_ message: RoomMessage) throws -> RoomMessage {
        let data = try JSONEncoder().encode(message)
        return try JSONDecoder().decode(RoomMessage.self, from: data)
    }

    /// Sends the host's world to a peer the long way round — packed into a frame, decoded again, then
    /// applied — because that is the only path the app ever uses, and shortcutting it in a test would
    /// stop testing the thing that can break.
    private func send(_ host: PowderEngine, to guest: PowderEngine, sequence: UInt32 = 1) throws {
        let frame = try #require(host.captureRoomWorld(sequence: sequence).encoded())
        let received = try #require(RoomWorld.decode(frame))
        #expect(guest.apply(roomWorld: received))
        #expect(
            guest.hashLite() == received.fingerprint,
            "the peer built a world the host did not describe"
        )
    }

    // MARK: The vocabulary survives the trip

    @Test("Every kind of message survives being encoded and decoded")
    func messagesRoundTrip() throws {
        let stroke = RoomStroke(
            x: 12,
            y: 34,
            radius: 5,
            elementID: Element.sand,
            shape: .spray,
            targetElementID: Element.water
        )
        let settings = RoomSettings(gravityX: 0.5, gravityY: -1, windX: 3, ambientTemp: 42)

        switch try roundTrip(.hello(name: "Someone")) {
        case let .hello(name): #expect(name == "Someone")
        default: Issue.record("hello came back as something else")
        }

        switch try roundTrip(.stroke(stroke)) {
        case let .stroke(decoded): #expect(decoded == stroke)
        default: Issue.record("stroke came back as something else")
        }

        switch try roundTrip(.settings(settings)) {
        case let .settings(decoded): #expect(decoded == settings)
        default: Issue.record("settings came back as something else")
        }

        switch try roundTrip(.fingerprint(value: -12345, frame: 678)) {
        case let .fingerprint(value, frame):
            #expect(value == -12345)
            #expect(frame == 678)
        default: Issue.record("fingerprint came back as something else")
        }

        switch try roundTrip(.worldAck(sequence: 4_000_000_001)) {
        case let .worldAck(sequence):
            // Deliberately a value past the middle of the range, so a field silently narrowed to a
            // signed type would show up here rather than after four billion frames.
            #expect(sequence == 4_000_000_001)
        default: Issue.record("worldAck came back as something else")
        }

        switch try roundTrip(.needWorld) {
        case .needWorld: break
        default: Issue.record("needWorld came back as something else")
        }

        switch try roundTrip(.reset) {
        case .reset: break
        default: Issue.record("reset came back as something else")
        }
    }

    /// World frames are bytes rather than JSON, so they are not part of the message enum at all. The
    /// frame has its own suite — ``RoomWorldTests`` — and this only checks that the two halves of the
    /// protocol meet: a world captured on one engine arrives whole on another.
    @Test("A whole world survives the trip between two engines")
    func worldRoundTrips() throws {
        let source = makeWorld()
        let frame = try #require(source.captureRoomWorld(sequence: 7).encoded())
        let received = try #require(RoomWorld.decode(frame))

        let target = PowderEngine(width: 8, height: 8, seed: 99)
        #expect(target.apply(roomWorld: received))
        #expect(target.width == source.width)
        #expect(target.height == source.height)
        #expect(received.sequence == 7)

        var differences = 0
        for i in 0 ..< source.cellCount where target.type[i] != source.type[i] { differences += 1 }
        #expect(differences == 0, "\(differences) cells differ after a trip through the wire")
        #expect(
            target.hashLite() == received.fingerprint,
            "the receiver built a world the sender did not describe"
        )
    }

    /// The reason the kind is written out rather than inferred from which fields are present. A message
    /// from a newer build must be recognisably unreadable, not silently decode as something else and be
    /// acted upon.
    @Test("A message of an unknown kind is refused rather than misread")
    func unknownKindIsRefused() {
        let future = #"{"kind":"somethingNew","name":"x"}"#.data(using: .utf8)!
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(RoomMessage.self, from: future)
        }
    }

    // MARK: Peers converging

    @Test("A joining peer ends up with the host's exact world")
    func joiningPeerMatches() throws {
        let host = makeWorld()
        let guest = PowderEngine(width: 8, height: 8, seed: 1234)

        try send(host, to: guest)
        guest.apply(host.roomSettings())

        #expect(guest.hashLite() == host.hashLite(), "the fingerprints should agree after joining")
        #expect(guest.gravityX == host.gravityX)
        #expect(guest.windX == host.windX)
        #expect(guest.ambientTemp == host.ambientTemp)
    }

    /// A stroke described once and applied twice produces the same world on both sides.
    ///
    /// This is what makes the brush feel attached to the finger. The follower does not wait for the
    /// host's next world frame to show what it just painted — it paints locally at once, and the frame
    /// that arrives shortly after should agree with what it drew rather than visibly correcting it.
    @Test("A stroke applied on both sides leaves both worlds identical")
    func strokeKeepsPeersTogether() throws {
        let host = makeWorld()
        let guest = PowderEngine(width: 48, height: 32, seed: 999)
        try send(host, to: guest)

        let strokes = [
            RoomStroke(x: 12, y: 10, radius: 4, elementID: Element.sand, shape: .circle),
            RoomStroke(x: 30, y: 15, radius: 3, elementID: Element.water, shape: .square),
            RoomStroke(x: 20, y: 20, radius: 6, elementID: Element.stone, shape: .circle),
            RoomStroke(x: 5, y: 5, radius: 2, elementID: Element.empty, shape: .circle),
        ]

        for stroke in strokes {
            // Through the wire on the guest's side, as it would really arrive.
            guard case let .stroke(received) = try roundTrip(.stroke(stroke)) else {
                Issue.record("a stroke did not survive the trip")
                return
            }
            #expect(host.apply(stroke))
            #expect(guest.apply(received))
        }

        var differences = 0
        for i in 0 ..< host.cellCount where host.type[i] != guest.type[i] { differences += 1 }
        #expect(differences == 0, "\(differences) cells differ after four shared strokes")
        #expect(host.hashLite() == guest.hashLite())
    }

    /// Spray scatters its cells at random, so two peers applying "the same" spray stroke do *not* match.
    ///
    /// This is the test that settles the design. If replaying strokes could keep two worlds in step,
    /// the host could send the world once and then say nothing but strokes. It cannot: one spray puts
    /// them permanently out of agreement, and every tick of ordinary physics does the same thing for the
    /// same reason — two engines, two random streams. Hence the world arrives whole, continuously, and
    /// a local stroke is a prediction that the next frame overwrites.
    @Test("A scattering brush drifts, which is why the world is sent rather than replayed")
    func scatteringBrushDrifts() throws {
        let host = makeWorld()
        let guest = PowderEngine(width: 48, height: 32, seed: 999)
        try send(host, to: guest)
        #expect(host.hashLite() == guest.hashLite(), "they should start together")

        let spray = RoomStroke(x: 24, y: 16, radius: 8, elementID: Element.sand, shape: .spray)
        #expect(host.apply(spray))
        #expect(guest.apply(spray))

        // Different random streams, so the scatter differs. The fingerprint has to notice.
        #expect(
            host.hashLite() != guest.hashLite(),
            "a scattering brush should be detected as drift rather than silently disagreeing"
        )

        // And the recovery works: the host sends the world, and they are together again.
        try send(host, to: guest, sequence: 2)
        #expect(host.hashLite() == guest.hashLite(), "sending the world should bring them back together")
    }

    /// The fingerprint has to be usable as a drift test, which means it must not report a match for
    /// worlds that differ. A single changed cell is the hardest case.
    @Test("The fingerprint notices a single changed cell")
    func fingerprintNoticesOneCell() {
        let a = makeWorld(width: 40, height: 30)
        let b = makeWorld(width: 40, height: 30)
        #expect(a.hashLite() == b.hashLite(), "identical worlds should agree")

        // A cell the fingerprint definitely samples. It samples at a stride, so the first one always is.
        b.setElement(0, 0, Element.stone)
        #expect(a.hashLite() != b.hashLite(), "a changed cell went unnoticed")
    }

    @Test("The fingerprint notices a different world size and a different gravity")
    func fingerprintNoticesShape() {
        let a = makeWorld(width: 40, height: 30)
        let b = makeWorld(width: 30, height: 40)
        #expect(a.hashLite() != b.hashLite(), "a different shape went unnoticed")

        let c = makeWorld(width: 40, height: 30)
        let d = makeWorld(width: 40, height: 30)
        #expect(c.hashLite() == d.hashLite())
        d.gravityY = -1
        // Two worlds differing only in which way is down are utterly different simulations, and the
        // fingerprint originally missed it — so the drift test stayed false forever while the two
        // diverged.
        #expect(c.hashLite() != d.hashLite(), "inverted gravity went unnoticed")
    }

    // MARK: Refusing bad messages

    /// A peer on a damaged build, or a packet that arrived corrupt, must not be able to reach into a
    /// world and break it. Every one of these is refused rather than guessed at.
    @Test("A nonsensical stroke is refused rather than applied")
    func nonsenseStrokesRefused() {
        let engine = makeWorld()
        let before = engine.hashLite()

        // A material this build does not have. Substituting air would punch a hole in someone's world.
        #expect(!engine.apply(RoomStroke(x: 5, y: 5, radius: 3, elementID: 250, shape: .circle)))
        // A radius that would take minutes to draw.
        #expect(!engine.apply(RoomStroke(x: 5, y: 5, radius: 100_000, elementID: Element.sand, shape: .circle)))
        #expect(!engine.apply(RoomStroke(x: 5, y: 5, radius: -1, elementID: Element.sand, shape: .circle)))
        // A position that is not a position.
        #expect(!engine.apply(RoomStroke(x: 99_999_999, y: 0, radius: 2, elementID: Element.sand, shape: .circle)))
        // A replace target that does not exist.
        #expect(!engine.apply(RoomStroke(
            x: 5, y: 5, radius: 2, elementID: Element.sand, shape: .replace, targetElementID: 200
        )))

        #expect(engine.hashLite() == before, "a refused stroke should change nothing")
    }

    @Test("Settings that are not numbers are ignored rather than adopted")
    func nonsenseSettingsRefused() {
        let engine = makeWorld()
        let gravityX = engine.gravityX
        let ambient = engine.ambientTemp

        engine.apply(RoomSettings(gravityX: .nan, gravityY: .infinity, windX: .nan, ambientTemp: .nan))

        // Unchanged. A gravity that is not a number reaches every position in the world and nothing
        // recovers from it.
        #expect(engine.gravityX == gravityX)
        #expect(engine.ambientTemp == ambient)
        #expect(!engine.gravityX.isNaN)
        #expect(!engine.gravityY.isNaN)
    }

    @Test("Wind arrives through the clamp, like every other writer")
    func windIsClamped() {
        let engine = makeWorld()
        engine.apply(RoomSettings(gravityX: 0, gravityY: 1, windX: 500, ambientTemp: 20))
        #expect(engine.windX == 5, "wind should be clamped to the range the physics is tuned for")
    }

    /// A peer with a differently sized world is a normal thing — two phones with different detail
    /// settings. Painting past this world's edge has to be harmless rather than a crash.
    @Test("A stroke from a peer with a bigger world is clipped, not fatal")
    func strokeFromLargerWorldIsClipped() {
        let engine = makeWorld(width: 40, height: 30)
        // Well outside this world, but a plausible position in a larger one.
        #expect(engine.apply(RoomStroke(x: 500, y: 400, radius: 5, elementID: Element.sand, shape: .circle)))
        // Nothing was placed, and nothing broke.
        #expect(engine.cellCount == 40 * 30)
    }

    // MARK: The size of it

    /// Why a stroke is described rather than sent as the cells it changed, and why the world gets a
    /// binary frame of its own while everything else can afford to be readable JSON.
    @Test("A stroke is tiny next to a world")
    func strokesAreSmall() throws {
        let engine = PowderEngine(width: 400, height: 380, seed: 1)
        for x in 0 ..< engine.width { engine.setElement(x, engine.height - 1, Element.bedrock) }

        let worldBytes = try #require(engine.captureRoomWorld().encoded()).count
        let strokeBytes = try JSONEncoder().encode(
            RoomMessage.stroke(RoomStroke(x: 10, y: 10, radius: 4, elementID: Element.sand, shape: .circle))
        ).count

        #expect(strokeBytes < 200, "a stroke should be tiny, was \(strokeBytes) bytes")
        #expect(
            worldBytes > strokeBytes * 10,
            "a world (\(worldBytes)) should dwarf a stroke (\(strokeBytes))"
        )
    }

    /// The acknowledgement has to be cheap, because one goes back for every frame that goes out. If it
    /// were not, the pacing scheme would spend the bandwidth it exists to save.
    @Test("An acknowledgement is tiny")
    func acknowledgementIsTiny() throws {
        let bytes = try JSONEncoder().encode(RoomMessage.worldAck(sequence: 123_456)).count
        #expect(bytes < 100, "an acknowledgement should be tiny, was \(bytes) bytes")
    }

    /// And the fingerprint is smaller still, which is what makes it affordable to send often.
    @Test("A fingerprint is tiny")
    func fingerprintIsTiny() throws {
        let bytes = try JSONEncoder().encode(RoomMessage.fingerprint(value: 12345, frame: 678)).count
        #expect(bytes < 100, "a fingerprint should be tiny, was \(bytes) bytes")
    }
}
