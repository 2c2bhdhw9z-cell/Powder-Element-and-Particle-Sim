import Testing

@testable import CrucibleCore

/// The decisions a room makes, none of which can be checked by running the app.
///
/// The transport needs two phones in the same place, so it will be tested by using it. Everything here
/// is the part that does not: who is in charge, when the next frame may go, and what a typed code means.
/// Each one is a place where being subtly wrong gives a room that half works — the host quietly falling
/// behind, two peers both believing they are in charge, somebody joining a stranger's world — and none
/// of those announce themselves.
@Suite("The room's decisions")
struct RoomCoordinatorTests {
    // MARK: Which channel a packet arrived on

    @Test("A packet keeps its payload and its channel")
    func packetRoundTrips() throws {
        for channel in RoomChannel.allCases {
            let payload: [UInt8] = [9, 8, 7, 0, 255, 1]
            let wrapped = RoomPacket.wrap(channel, payload)
            let unwrapped = try #require(RoomPacket.unwrap(wrapped))
            #expect(unwrapped.channel == channel)
            #expect(unwrapped.payload == payload)
        }
    }

    @Test("A packet with an empty payload is still readable")
    func emptyPayloadRoundTrips() throws {
        let unwrapped = try #require(RoomPacket.unwrap(RoomPacket.wrap(.control, [])))
        #expect(unwrapped.channel == .control)
        #expect(unwrapped.payload.isEmpty)
    }

    /// A channel this build does not know means a newer one is saying something new. Ignored, rather
    /// than guessed at — reading JSON as a world frame could conceivably produce a world nobody sent.
    @Test("A packet on an unknown channel is ignored rather than guessed at")
    func unknownChannelIgnored() {
        #expect(RoomPacket.unwrap([]) == nil, "an empty packet was read as something")
        #expect(RoomPacket.unwrap([2, 1, 2, 3]) == nil)
        #expect(RoomPacket.unwrap([255]) == nil)
    }

    // MARK: Which frame is the newer

    @Test("A later frame is newer, and an overtaken one is not")
    func newerFramesRecognised() {
        #expect(RoomSequence.isNewer(1, than: 0), "nothing shown yet, so anything is newer")
        #expect(RoomSequence.isNewer(2, than: 1))
        #expect(RoomSequence.isNewer(1000, than: 1))
        #expect(!RoomSequence.isNewer(1, than: 2), "a frame that arrived late was treated as newer")
        #expect(!RoomSequence.isNewer(5, than: 5), "the same frame is not newer than itself")
    }

    /// The reason this is not a plain comparison. Four and a half years of continuous play to reach the
    /// wrap, and if it were `>` the follower would then refuse every frame from then on and sit frozen
    /// forever while the link worked perfectly.
    @Test("The comparison survives the numbering wrapping round")
    func wrapIsHandled() {
        let last = UInt32.max
        #expect(RoomSequence.isNewer(1, than: last), "the frame after the wrap was rejected as old")
        #expect(RoomSequence.isNewer(3, than: last - 2))
        #expect(!RoomSequence.isNewer(last, than: 1), "a pre-wrap frame was accepted after the wrap")
        #expect(!RoomSequence.isNewer(last - 2, than: 3))
    }

    /// Walking the whole way round, which is the only way to be sure the halfway point is not where it
    /// goes wrong.
    @Test("Stepping through the wrap, every frame in turn is the newer one")
    func steppingThroughTheWrap() {
        var current: UInt32 = UInt32.max - 20
        for _ in 0 ..< 40 {
            var next = current &+ 1
            if next == 0 { next = 1 }
            #expect(
                RoomSequence.isNewer(next, than: current),
                "frame \(next) was not recognised as newer than \(current)"
            )
            #expect(
                !RoomSequence.isNewer(current, than: next),
                "frame \(current) was recognised as newer than \(next)"
            )
            current = next
        }
    }

    // MARK: Who is in charge

    @Test("A peer alone in a room is its own host")
    func aloneIsHost() {
        #expect(RoomHost.isHost(me: "anybody", peers: []))
        #expect(RoomHost.identifier(me: "anybody", peers: []) == "anybody")
    }

    @Test("The lowest identifier is the host")
    func lowestIsHost() {
        #expect(RoomHost.isHost(me: "alice", peers: ["bob", "carol"]))
        #expect(!RoomHost.isHost(me: "bob", peers: ["alice", "carol"]))
        #expect(!RoomHost.isHost(me: "carol", peers: ["alice", "bob"]))
        #expect(RoomHost.identifier(me: "carol", peers: ["alice", "bob"]) == "alice")
    }

    /// The property the whole arrangement depends on, and the reason it needs no handshake: every peer
    /// works it out from its own view of the room and they all reach the same answer. Exactly one host,
    /// always. Two would mean two worlds each overwriting the other; none would mean a room where
    /// nothing moves.
    @Test("Every peer reaches the same answer, with no messages exchanged")
    func everyoneAgreesOnOneHost() {
        let rooms = [
            ["iPhone-7Q2M", "iPhone-K4XB"],
            ["A", "B", "C", "D", "E"],
            ["zebra", "aardvark", "moose"],
            ["same-prefix-1", "same-prefix-2", "same-prefix-10"],
            ["Ada", "ada", "ADA"],
            ["  leading space", "trailing space  ", "middle space"],
        ]

        for room in rooms {
            let hosts = room.filter { me in
                RoomHost.isHost(me: me, peers: room.filter { $0 != me })
            }
            #expect(hosts.count == 1, "\(room) elected \(hosts.count) hosts: \(hosts)")

            // And everyone names the same one, so the interface can say who it is.
            let named = Set(room.map { me in
                RoomHost.identifier(me: me, peers: room.filter { $0 != me })
            })
            #expect(named.count == 1, "\(room) could not agree who the host was: \(named)")
            #expect(named.first == hosts.first)
        }
    }

    /// When the host leaves, everyone left has to agree on the next one — again with no negotiation,
    /// because the peer that would have run the negotiation is the one that just disappeared.
    @Test("The room re-elects silently when the host leaves")
    func reElectsWhenHostLeaves() {
        var room = ["bravo", "alpha", "charlie", "delta"]
        var elected: [String] = []

        while !room.isEmpty {
            let hosts = room.filter { me in RoomHost.isHost(me: me, peers: room.filter { $0 != me }) }
            #expect(hosts.count == 1, "\(room) elected \(hosts.count) hosts")
            guard let host = hosts.first else { return }
            elected.append(host)
            room.removeAll { $0 == host }
        }

        #expect(elected == ["alpha", "bravo", "charlie", "delta"], "the succession was \(elected)")
    }

    // MARK: When the world goes out

    @Test("Nothing is sent to an empty room")
    func nothingSentToNobody() {
        var pacer = RoomPacer()
        #expect(pacer.nextFrame(now: 0, peers: []) == nil)
        #expect(pacer.nextFrame(now: 100, peers: []) == nil)
        // And the numbering has not been burned through, so the first peer to arrive gets frame one.
        #expect(pacer.nextFrame(now: 200, peers: ["a"]) == 1)
    }

    @Test("The first frame goes out at once, and the second waits to be acknowledged")
    func firstFrameIsImmediate() {
        var pacer = RoomPacer()
        #expect(pacer.nextFrame(now: 0, peers: ["a"]) == 1)

        // Past the rate ceiling, but nobody has confirmed drawing frame one.
        #expect(pacer.nextFrame(now: 0.1, peers: ["a"]) == nil)

        pacer.acknowledge(peer: "a", sequence: 1)
        #expect(pacer.nextFrame(now: 0.11, peers: ["a"]) == 2)
    }

    @Test("A frame waits for every peer, not just the quickest")
    func waitsForEveryone() {
        var pacer = RoomPacer()
        #expect(pacer.nextFrame(now: 0, peers: ["a", "b"]) == 1)

        pacer.acknowledge(peer: "a", sequence: 1)
        #expect(pacer.nextFrame(now: 0.1, peers: ["a", "b"]) == nil, "sent while b had not answered")

        pacer.acknowledge(peer: "b", sequence: 1)
        #expect(pacer.nextFrame(now: 0.11, peers: ["a", "b"]) == 2)
    }

    /// An acknowledgement for a frame that has already been overtaken must not count as an answer to
    /// the current one, or a peer one frame behind would look permanently up to date.
    @Test("A stale acknowledgement does not count")
    func staleAcknowledgementIgnored() {
        var pacer = RoomPacer()
        #expect(pacer.nextFrame(now: 0, peers: ["a"]) == 1)
        pacer.acknowledge(peer: "a", sequence: 1)
        #expect(pacer.nextFrame(now: 0.1, peers: ["a"]) == 2)

        // Still answering frame one.
        pacer.acknowledge(peer: "a", sequence: 1)
        #expect(pacer.nextFrame(now: 0.2, peers: ["a"]) == nil, "an old acknowledgement released a frame")
    }

    /// A peer that has stopped answering — backgrounded, out of range, crashed — must not hold up the
    /// room forever.
    @Test("A silent peer is given a deadline and then sent past")
    func silentPeerIsSentPast() {
        var pacer = RoomPacer(minimumInterval: 1.0 / 30, acknowledgementDeadline: 0.5)
        #expect(pacer.nextFrame(now: 0, peers: ["a"]) == 1)

        #expect(pacer.nextFrame(now: 0.4, peers: ["a"]) == nil, "gave up before the deadline")
        #expect(pacer.nextFrame(now: 0.5, peers: ["a"]) == 2, "never gave up on a silent peer")
    }

    @Test("A peer that has left is not waited for at all")
    func departedPeerNotWaitedFor() {
        var pacer = RoomPacer()
        #expect(pacer.nextFrame(now: 0, peers: ["a", "b"]) == 1)
        pacer.acknowledge(peer: "a", sequence: 1)

        // b leaves before answering. Without dropping it, the room would wait out the deadline on every
        // single frame from here on — for a peer that is not there.
        pacer.retain(peers: ["a"])
        #expect(pacer.nextFrame(now: 0.1, peers: ["a"]) == 2, "still waiting on a peer that left")
    }

    @Test("Someone who has just joined gets a frame without waiting for the rhythm")
    func joiningPeerGetsAFrameAtOnce() {
        var pacer = RoomPacer()
        #expect(pacer.nextFrame(now: 0, peers: ["a"]) == 1)
        // a has not answered, so ordinarily nothing would go out.
        #expect(pacer.nextFrame(now: 0.1, peers: ["a"]) == nil)

        pacer.requestFrame()
        #expect(pacer.nextFrame(now: 0.11, peers: ["a", "b"]) == 2, "a joining peer was left with nothing")
    }

    /// The request skips the wait for acknowledgements. It must not skip the rate ceiling, or a peer
    /// repeating it — through a bug or on purpose — would have the host packing worlds as fast as it can
    /// and starve the simulation of the frame budget.
    @Test("Asking for a frame repeatedly cannot drive the rate past the ceiling")
    func repeatedRequestsCannotFlood() {
        var pacer = RoomPacer(minimumInterval: 1.0 / 30, acknowledgementDeadline: 0.5)
        var now = 0.0
        var sent = 0

        // A second of asking as fast as the app's own clock ticks.
        while now < 1.0 {
            pacer.requestFrame()
            if pacer.nextFrame(now: now, peers: ["a"]) != nil { sent += 1 }
            now += 1.0 / 240
        }

        // The ceiling is the point of the test. The lower bound is loose on purpose: the clock here
        // advances in steps of a 240th and the interval is a 30th, so accumulated floating-point error
        // pushes the occasional frame a step late. That is the test's arithmetic, not the pacer's.
        #expect(sent <= 31, "\(sent) frames in a second, past the ceiling of thirty")
        #expect(sent >= 26, "only \(sent) frames in a second, so the ceiling is throttling too hard")
    }

    /// The whole point of the design, tested as a behaviour rather than as a rule.
    ///
    /// A link that takes two hundred milliseconds to carry a frame and answer should produce about five
    /// frames a second — and, crucially, should *never* have two frames outstanding at once. A timer
    /// would have handed over thirty a second regardless, the transport would have queued them, and the
    /// follower would have fallen further behind every second with nothing reporting it.
    @Test("A slow link gets fewer current frames, never a backlog")
    func slowLinkNeverBacklogs() {
        var pacer = RoomPacer(minimumInterval: 1.0 / 30, acknowledgementDeadline: 0.5)
        let latency = 0.2
        var now = 0.0
        var inFlight: (sequence: UInt32, arrivesAt: Double)?
        var sent = 0
        var overlaps = 0

        while now < 5.0 {
            if let flight = inFlight, flight.arrivesAt <= now {
                pacer.acknowledge(peer: "a", sequence: flight.sequence)
                inFlight = nil
            }
            if let sequence = pacer.nextFrame(now: now, peers: ["a"]) {
                if inFlight != nil { overlaps += 1 }
                inFlight = (sequence, now + latency)
                sent += 1
            }
            now += 1.0 / 120
        }

        #expect(overlaps == 0, "\(overlaps) frames went out while another was still in flight")
        // Five seconds at one frame every 200ms.
        #expect(sent >= 20 && sent <= 30, "\(sent) frames over five seconds, expected about 25")
    }

    /// And the same measurement on a link slower than the deadline, where the pacing deliberately gives
    /// up waiting. The rate then falls to the deadline rather than to nothing, which is the intended
    /// degradation: a peer that may be gone must not stop the room.
    @Test("A link slower than the deadline falls back to the deadline's rate")
    func linkSlowerThanDeadline() {
        var pacer = RoomPacer(minimumInterval: 1.0 / 30, acknowledgementDeadline: 0.5)
        var now = 0.0
        var sent = 0

        // Nothing is ever acknowledged at all: the worst case.
        while now < 5.0 {
            if pacer.nextFrame(now: now, peers: ["a"]) != nil { sent += 1 }
            now += 1.0 / 120
        }

        // One at the start, then one every half second.
        #expect(sent >= 9 && sent <= 12, "\(sent) frames over five seconds, expected about ten")
    }

    @Test("Frames are numbered in order, and the numbering never reaches nought")
    func numberingIsOrderly() {
        var pacer = RoomPacer(minimumInterval: 0, acknowledgementDeadline: 0)
        var previous: UInt32 = 0
        for i in 0 ..< 50 {
            guard let sequence = pacer.nextFrame(now: Double(i), peers: ["a"]) else {
                Issue.record("nothing sent on step \(i)")
                return
            }
            #expect(sequence == previous &+ 1, "frame \(i) was numbered \(sequence) after \(previous)")
            #expect(sequence != 0, "nought is reserved for having sent nothing")
            previous = sequence
        }
    }

    // MARK: The code people read out

    @Test("A generated code is always readable and always valid")
    func generatedCodesAreValid() {
        var generator = Mulberry32(seed: 12345)
        for _ in 0 ..< 2000 {
            let code = RoomCode.generate(using: &generator)
            #expect(code.count == RoomCode.length, "generated \"\(code)\"")
            #expect(RoomCode.normalise(code) == code, "the app cannot read back its own code \"\(code)\"")
        }
    }

    /// Every character has to be reachable. A modulo done wrong narrows the alphabet without any other
    /// symptom — the codes still look fine, there are simply far fewer of them than intended.
    @Test("Every character in the alphabet actually gets used")
    func wholeAlphabetIsReachable() {
        var generator = Mulberry32(seed: 99)
        var seen = Set<Character>()
        for _ in 0 ..< 20_000 {
            for character in RoomCode.generate(using: &generator) { seen.insert(character) }
        }
        let missing = RoomCode.alphabet.filter { !seen.contains($0) }
        #expect(missing.isEmpty, "these characters can never appear in a code: \(missing)")
    }

    /// The five characters left out, and why. Somebody reads this code off their screen to the person
    /// next to them; a code containing both `O` and `0` is a code that gets typed wrong.
    @Test("The confusable characters are not in the alphabet")
    func confusablesExcluded() {
        for character in "ILO01" {
            #expect(
                !RoomCode.alphabet.contains(character),
                "\"\(character)\" is confusable and should not be in a code"
            )
        }
    }

    @Test("A code typed the way a phone types it is accepted")
    func forgivingAboutTyping() {
        #expect(RoomCode.normalise("ab2c") == "AB2C")
        #expect(RoomCode.normalise("AB2C") == "AB2C")
        #expect(RoomCode.normalise(" AB2C ") == "AB2C")
        #expect(RoomCode.normalise("AB-2C") == "AB2C")
        #expect(RoomCode.normalise("a b 2 c") == "AB2C")
    }

    /// Strict about everything else, and for a specific reason: a code that is nearly right must be
    /// refused rather than corrected, because correcting it into a *different* valid code means joining
    /// a stranger's room and painting in their world.
    @Test("Anything that is not a code is refused rather than corrected")
    func strictAboutEverythingElse() {
        #expect(RoomCode.normalise("") == nil)
        #expect(RoomCode.normalise("AB2") == nil, "too short")
        #expect(RoomCode.normalise("AB2CD") == nil, "too long")
        #expect(RoomCode.normalise("AB2!") == nil, "a symbol")
        #expect(RoomCode.normalise("AB2 C D") == nil, "too long once the spaces are dropped")
        // The excluded characters are refused rather than quietly read as their look-alikes.
        #expect(RoomCode.normalise("AB2O") == nil, "the letter O")
        #expect(RoomCode.normalise("AB20") == nil, "the digit zero")
        #expect(RoomCode.normalise("AB2I") == nil)
        #expect(RoomCode.normalise("AB21") == nil)
        #expect(RoomCode.normalise("AB2L") == nil)
        // Something that is not a code at all, and something that changes length when uppercased.
        #expect(RoomCode.normalise("🙂🙂🙂🙂") == nil)
        #expect(RoomCode.normalise("aßcd") == nil, "ß uppercases to two characters")
        #expect(
            RoomCode.normalise(String(repeating: "A", count: 100_000)) == nil,
            "a very long paste"
        )
    }
}
