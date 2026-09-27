import Testing

@testable import CrucibleCore

/// A shared room over a link that loses, delays, reorders and duplicates what is sent.
///
/// ## Why this is worth its own suite
///
/// Everything else about a room is tested on a perfect link: a frame goes out, arrives whole, and is acknowledged. That
/// is not what two phones on a café's wifi do. The interesting failures are all about what happens when the link is bad
/// — a follower drifting an entire world behind, a backlog that grows for ever because the host keeps sending faster
/// than anything arrives, an older world landing on top of a newer one and the picture jumping backwards, a peer that
/// walks out of range holding up everybody else.
///
/// So this runs the real thing: the real pacer deciding when to send, the real codec, real packets through wrap and
/// unwrap, and a link in the middle that is deliberately awful. What is asserted is not "it is identical" but the three
/// promises a room makes: what arrives is never older than what is already showing, nothing piles up without end, and
/// somebody who stops answering is passed rather than waited for.
@Suite("A room over a bad link")
struct BadLinkTests {
    /// A link that delays everything, loses some of it, and sometimes hands over two copies or two frames out of order.
    ///
    /// Deterministic: every decision comes from a seeded generator, so a failure here can be run again and will do the
    /// same thing.
    struct BadLink {
        /// One thing in flight.
        struct InFlight {
            var bytes: [UInt8]
            var arrivesAt: Double
        }

        /// The share of packets that never arrive.
        var loss: Double
        /// How long a packet takes, at least and at most.
        var shortestDelay: Double
        var longestDelay: Double
        /// The share of packets that arrive twice.
        var duplication: Double
        var random: Mulberry32

        private var flying: [InFlight] = []
        /// How many were sent and how many arrived, for saying what the link did.
        private(set) var sent = 0
        private(set) var delivered = 0
        private(set) var lost = 0

        init(
            loss: Double,
            shortestDelay: Double = 0.01,
            longestDelay: Double = 0.2,
            duplication: Double = 0,
            seed: UInt32 = 7
        ) {
            self.loss = loss
            self.shortestDelay = shortestDelay
            self.longestDelay = longestDelay
            self.duplication = duplication
            random = Mulberry32(seed: seed)
        }

        /// Puts something on the link. It may never arrive.
        mutating func send(_ bytes: [UInt8], now: Double) {
            sent += 1
            guard random.next() >= loss else {
                lost += 1
                return
            }
            let delay = shortestDelay + random.next() * (longestDelay - shortestDelay)
            flying.append(InFlight(bytes: bytes, arrivesAt: now + delay))
            // Some links hand the same packet over twice. A room must not care.
            if random.next() < duplication {
                flying.append(InFlight(bytes: bytes, arrivesAt: now + delay + 0.01))
            }
        }

        /// Everything that has arrived by now, in the order it arrived — which is not the order it was sent.
        mutating func arrivals(now: Double) -> [[UInt8]] {
            let ready = flying.filter { $0.arrivesAt <= now }
            flying.removeAll { $0.arrivesAt <= now }
            delivered += ready.count
            return ready.sorted { $0.arrivesAt < $1.arrivesAt }.map(\.bytes)
        }

        /// How many are still on their way.
        var inFlight: Int { flying.count }
    }

    /// A host, a follower, and a bad link between them, run for a while.
    ///
    /// - Returns: what happened, for the tests to make their claims about.
    private func run(
        link: inout BadLink,
        seconds: Double,
        acknowledges: Bool = true,
        width: Int = 40,
        height: Int = 30
    ) -> (applied: [UInt32], refused: Int, host: PowderEngine, follower: PowderEngine, pacer: RoomPacer) {
        let host = PowderEngine(width: width, height: height, seed: 3)
        for x in 0 ..< width { host.setElement(x, height - 1, Element.bedrock) }
        host.drawBrush(centerX: width / 2, centerY: 4, radius: 5, elementID: Element.sand, shape: .circle)
        let follower = PowderEngine(width: width, height: height, seed: 9)

        var pacer = RoomPacer(minimumInterval: 1.0 / 30, acknowledgementDeadline: 0.5)
        var applied: [UInt32] = []
        var refused = 0
        var newest: UInt32 = 0
        let peers = ["follower"]

        // A frame every sixtieth of a second of wall time, which is what the app's own tick offers the room.
        var now = 0.0
        while now < seconds {
            now += 1.0 / 60
            host.step()

            if let sequence = pacer.nextFrame(now: now, peers: peers) {
                let frame = host.captureRoomWorld(sequence: sequence)
                link.send(RoomPacket.wrap(.world, frame.encoded() ?? []), now: now)
            }

            for bytes in link.arrivals(now: now) {
                guard let packet = RoomPacket.unwrap(bytes), packet.channel == .world,
                      let frame = RoomWorld.decode(packet.payload)
                else {
                    refused += 1
                    continue
                }
                // The one rule a follower must never break: never go backwards.
                guard RoomSequence.isNewer(frame.sequence, than: newest) || newest == 0 else {
                    refused += 1
                    continue
                }
                guard follower.apply(roomWorld: frame) else {
                    refused += 1
                    continue
                }
                newest = frame.sequence
                applied.append(frame.sequence)
                if acknowledges { pacer.acknowledge(peer: "follower", sequence: frame.sequence) }
            }
        }
        return (applied, refused, host, follower, pacer)
    }

    @Test("On a link losing a third of everything, the follower keeps up with fresh worlds and nothing piles up")
    func lossyLinkStaysFresh() {
        var link = BadLink(loss: 1.0 / 3, duplication: 0.1, seed: 11)
        let outcome = run(link: &link, seconds: 6)

        // The pacer waits for each world to be acknowledged before sending the next, so six seconds is a couple of
        // dozen worlds rather than hundreds — and a third of those is what is lost.
        #expect(link.sent >= 10, "the host only sent \(link.sent) worlds")
        #expect(link.lost >= 3, "the link did not actually lose anything: \(link.lost) of \(link.sent)")
        #expect(!outcome.applied.isEmpty, "nothing arrived at all")
        // Every world applied was newer than the one before it. This is the promise that stops the picture jumping
        // backwards when two frames cross on the way.
        for (earlier, later) in zip(outcome.applied, outcome.applied.dropFirst()) {
            #expect(RoomSequence.isNewer(later, than: earlier), "a world older than the one showing was applied")
        }
        // Nothing piles up: at the end, what is still on its way is a frame or two, not six seconds' worth.
        #expect(link.inFlight <= 3, "\(link.inFlight) worlds were still in flight at the end")
        // And the follower is showing something recent rather than the first thing that happened to arrive.
        let last = outcome.applied.last ?? 0
        #expect(
            last >= outcome.pacer.lastSentSequence - 3,
            "the follower is showing frame \(last) while the host has sent \(outcome.pacer.lastSentSequence)"
        )
        // The world that arrived is the world that was sent: the codec survived a bad link.
        #expect(outcome.follower.width == outcome.host.width && outcome.follower.height == outcome.host.height)
        #expect(outcome.follower.activeParticleCount > 0, "the follower's world is empty")
    }

    @Test("A duplicate world changes nothing, and a world from the past is refused")
    func duplicatesAndStragglers() {
        let host = PowderEngine(width: 30, height: 20, seed: 5)
        host.drawBrush(centerX: 15, centerY: 5, radius: 4, elementID: Element.water, shape: .circle)
        let follower = PowderEngine(width: 30, height: 20, seed: 6)

        let first = host.captureRoomWorld(sequence: 1).encoded() ?? []
        for _ in 0 ..< 20 { host.step() }
        let second = host.captureRoomWorld(sequence: 2).encoded() ?? []

        func apply(_ bytes: [UInt8]) -> Bool {
            guard let frame = RoomWorld.decode(bytes) else { return false }
            return follower.apply(roomWorld: frame)
        }
        #expect(apply(second))
        let afterSecond = Array(UnsafeBufferPointer(start: follower.type, count: follower.cellCount))
        // The same frame again: allowed, and it changes nothing.
        #expect(apply(second))
        #expect(Array(UnsafeBufferPointer(start: follower.type, count: follower.cellCount)) == afterSecond)
        // The straggler is older, and the sequence guard is what refuses it — the world itself would apply happily,
        // which is exactly why the guard has to be in front of it.
        #expect(!RoomSequence.isNewer(1, than: 2), "an older frame was called newer")
        #expect(RoomWorld.decode(first) != nil, "the older frame was not even readable")
    }

    @Test("A peer that walks away is passed rather than waited for")
    func silentPeerIsPassed() {
        var link = BadLink(loss: 0, seed: 3)
        // Nothing is acknowledged: the peer has walked out of range with the app still open.
        let outcome = run(link: &link, seconds: 3, acknowledges: false)
        // The host keeps sending, at the deadline's rate rather than the full one: about two a second for three
        // seconds. Without the deadline it would have sent exactly one frame and then waited for ever.
        #expect(outcome.pacer.lastSentSequence >= 4, "the host sent \(outcome.pacer.lastSentSequence) frames and gave up")
        #expect(
            outcome.pacer.lastSentSequence <= 12,
            "the host sent \(outcome.pacer.lastSentSequence) frames to somebody who never answered"
        )
    }

    @Test("A frame cut short, scrambled or truncated is refused rather than applied in part")
    func brokenFramesAreRefused() {
        let host = PowderEngine(width: 30, height: 20, seed: 5)
        host.drawBrush(centerX: 15, centerY: 5, radius: 4, elementID: Element.lava, shape: .circle)
        let whole = host.captureRoomWorld(sequence: 1).encoded() ?? []
        #expect(RoomWorld.decode(whole) != nil)

        // Every length short of the whole thing.
        for length in 0 ..< whole.count {
            let cut = Array(whole.prefix(length))
            if let frame = RoomWorld.decode(cut) {
                // A shorter frame may still decode if it happens to describe a smaller world, but it must never
                // describe *this* world with missing cells.
                #expect(
                    frame.cells.count == frame.width * frame.height,
                    "a frame cut to \(length) bytes described \(frame.width)×\(frame.height) with \(frame.cells.count) cells"
                )
            }
        }

        // And one byte in the middle changed: whatever comes out, it is a whole world or nothing.
        var scrambled = whole
        for at in stride(from: 8, to: scrambled.count, by: max(1, scrambled.count / 40)) {
            let was = scrambled[at]
            scrambled[at] = was ^ 0xFF
            if let frame = RoomWorld.decode(scrambled) {
                #expect(frame.cells.count == frame.width * frame.height, "a scrambled frame described a partial world")
                let follower = PowderEngine(width: 30, height: 20, seed: 1)
                // Applying it must either work or be refused — never leave a half-built world behind.
                if follower.apply(roomWorld: frame) {
                    #expect(follower.cellCount == follower.width * follower.height)
                }
            }
            scrambled[at] = was
        }
    }

    @Test("A link so slow that nothing is acknowledged in time still sends fresh worlds, not a queue of old ones")
    func slowLinkSendsFewerFresherFrames() {
        // Every packet takes longer than the acknowledgement deadline.
        var link = BadLink(loss: 0, shortestDelay: 0.6, longestDelay: 0.9, seed: 21)
        let outcome = run(link: &link, seconds: 5)

        // What the follower applied is the newest thing that had arrived each time, and the numbers it applied are
        // spread out — proof that the host slowed down to the link rather than filling it with a backlog.
        #expect(outcome.applied.count >= 2, "nothing arrived over the slow link")
        let gaps = zip(outcome.applied, outcome.applied.dropFirst()).map { Int($1) - Int($0) }
        #expect(gaps.allSatisfy { $0 > 0 }, "the follower applied worlds out of order: \(outcome.applied)")
        #expect(link.inFlight <= 2, "\(link.inFlight) worlds were queued on a slow link")
        // Roughly two a second at the deadline's rate, so ten or so in five seconds — not the three hundred a full
        // rate would have produced.
        #expect(
            outcome.pacer.lastSentSequence <= 20,
            "the host sent \(outcome.pacer.lastSentSequence) worlds over a link that could carry about eight"
        )
    }
}
