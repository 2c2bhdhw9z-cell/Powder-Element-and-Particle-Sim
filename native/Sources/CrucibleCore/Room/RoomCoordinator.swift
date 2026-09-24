// The decisions a shared room has to make, kept where they can be tested.
//
// ## Why this is not in the app
//
// The room's transport is MultipeerConnectivity, which exists only on Apple's platforms and cannot be
// exercised without two real devices in the same place. Nothing about it can be tested here.
//
// But almost none of the *thinking* is about MultipeerConnectivity. Deciding which peer is in charge,
// deciding when the next world frame may go out, reading a room code somebody typed with the wrong
// case — these are arithmetic and string handling, and every one of them is a place where being subtly
// wrong produces a room that half works. So they live here, with tests, and the app layer is left as
// the thin part that plugs them into Apple's classes.
//
// The same split as the tilt sensor, the sound design and the screenshot export. It is the only reason
// any of this is verifiable at all, given the app itself cannot even be compiled on the machine it is
// written on.

// MARK: - Which channel a message arrived on

/// The two kinds of traffic a room carries.
///
/// Separate because they want completely different encodings. Control messages are small and rare, so
/// being able to read them is worth more than the bytes; world frames are large and constant, so they
/// are packed bytes with no room for politeness. One leading byte says which.
public enum RoomChannel: UInt8, Sendable, CaseIterable {
    /// A ``RoomMessage``, as JSON.
    case control = 0
    /// A ``RoomWorld`` frame, as its own binary format.
    case world = 1
}

/// Putting a channel marker on a payload, and taking it off again.
public enum RoomPacket {
    /// Prefixes a payload with its channel.
    public static func wrap(_ channel: RoomChannel, _ payload: [UInt8]) -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(payload.count + 1)
        bytes.append(channel.rawValue)
        bytes.append(contentsOf: payload)
        return bytes
    }

    /// Reads the channel off a payload.
    ///
    /// - Returns: `nil` for an empty packet or an unknown channel. An unknown channel means a build that
    ///   knows something this one does not; ignoring it is right, and guessing which of the two existing
    ///   channels it resembles is not — a world frame read as JSON produces a decoding error, but JSON
    ///   read as a world frame could conceivably decode into a world nobody sent.
    public static func unwrap(_ bytes: [UInt8]) -> (channel: RoomChannel, payload: [UInt8])? {
        guard let first = bytes.first, let channel = RoomChannel(rawValue: first) else { return nil }
        return (channel, Array(bytes.dropFirst()))
    }
}

// MARK: - Which of two frames is the newer

/// Comparing frame numbers.
///
/// Needed because "is this frame newer than the one I am showing?" is not `>`. The number wraps, so a
/// plain comparison decides that frame 1 is older than frame 4,294,967,295 — and a follower that reached
/// the wrap would then refuse every frame from then on and sit frozen forever, with the link working
/// perfectly.
///
/// Four and a half years of continuous play to reach that, so this is not about the wrap being likely.
/// It is about the alternative being three lines and correct.
public enum RoomSequence {
    /// Whether `candidate` is newer than `current`.
    ///
    /// Nought means nothing has been shown yet, so anything is newer. Otherwise the two are compared by
    /// the distance between them: a gap in the nearer half of the range means forward, and in the further
    /// half means a frame that arrived late and has already been overtaken.
    public static func isNewer(_ candidate: UInt32, than current: UInt32) -> Bool {
        guard current != 0 else { return true }
        guard candidate != current else { return false }
        return candidate &- current < UInt32.max / 2
    }
}

// MARK: - Who is in charge

/// Deciding which peer owns the world.
///
/// One peer has to simulate and the others have to watch, so somebody must be chosen — and the choice
/// has to be made *without* asking, because a handshake to elect a host is one more thing to go wrong on
/// a link that is already the least reliable part of the feature.
///
/// So: the peer whose identifier sorts lowest, among itself and everyone it can see. Every peer computes
/// it from the same list and reaches the same answer with no messages exchanged at all, and when the host
/// leaves, everyone left re-computes and agrees on the next one just as silently.
public enum RoomHost {
    /// Whether this peer is the host.
    ///
    /// - Parameters:
    ///   - me: this peer's identifier.
    ///   - peers: the identifiers of everyone currently connected, not including this peer.
    ///
    /// Alone in a room, a peer is its own host. That is what makes a room work before anyone else has
    /// arrived — the world runs, and the first person to join is shown it.
    public static func isHost(me: String, peers: [String]) -> Bool {
        for peer in peers where peer < me { return false }
        return true
    }

    /// Who the host is, for saying so in the interface.
    public static func identifier(me: String, peers: [String]) -> String {
        var lowest = me
        for peer in peers where peer < lowest { lowest = peer }
        return lowest
    }
}

// MARK: - How often the world goes out

/// Deciding when to send the next world frame.
///
/// ## The failure this exists to prevent
///
/// The obvious approach is a timer: send the world thirty times a second. It fails badly, and quietly.
/// If the link cannot carry thirty frames a second — and at the app's largest world it cannot — then
/// frames are handed to the transport faster than it can deliver them, and it queues them. The follower
/// is then shown a world that is half a second old, then a second, then two, falling further behind
/// forever while the host thinks everything is fine. Nothing reports it. It just gets worse.
///
/// ## What this does instead
///
/// A frame goes out. The follower, having drawn it, says so. Only then does the next one go.
///
/// The rate is then whatever the link can actually manage, decided by the link rather than guessed at.
/// A fast connection with a small world runs at the ceiling below; a slow one with a large world sends
/// fewer, *current* frames. There is no queue to grow, and no way to fall behind.
///
/// Two adjustments make it usable:
///
///   - **A ceiling.** Without one, a quick link would send as fast as the processor can pack worlds,
///     spending the frame budget of the simulation itself on frames nobody can perceive.
///   - **A deadline.** A follower that has stopped answering — backgrounded the app, walked out of
///     range, crashed — must not hold up everyone else. After the deadline the next frame goes anyway.
public struct RoomPacer: Sendable {
    /// The fastest frames will go out, even on an idle link.
    ///
    /// Thirty a second. The simulation runs at up to a hundred and twenty, so a follower sees roughly
    /// every fourth tick — which for falling sand reads as continuous motion, and is a quarter of the
    /// traffic that matching the tick rate would cost for no visible gain.
    public var minimumInterval: Double

    /// How long to wait for a straggler before sending anyway.
    public var acknowledgementDeadline: Double

    /// The last frame handed to the transport. Nought means none yet.
    public private(set) var lastSentSequence: UInt32 = 0
    private var lastSentAt: Double = -.greatestFiniteMagnitude
    /// The newest frame each peer has confirmed drawing.
    private var acknowledged: [String: UInt32] = [:]
    /// Set when somebody has asked for a frame and cannot wait for the ordinary rhythm.
    private var someoneIsWaiting = false

    public init(minimumInterval: Double = 1.0 / 30, acknowledgementDeadline: Double = 0.5) {
        self.minimumInterval = minimumInterval
        self.acknowledgementDeadline = acknowledgementDeadline
    }

    /// Records that a peer has drawn a frame.
    public mutating func acknowledge(peer: String, sequence: UInt32) {
        acknowledged[peer] = sequence
    }

    /// Notes that somebody needs a frame now rather than in due course.
    ///
    /// Sent by a peer that has just joined and has nothing to show, or one whose last frame failed to
    /// decode. It skips the wait for acknowledgements but **not** the rate ceiling — otherwise a peer
    /// repeating the request, whether through a bug or on purpose, would have the host packing worlds as
    /// fast as it could manage and starve the simulation.
    public mutating func requestFrame() {
        someoneIsWaiting = true
    }

    /// Forgets peers who have left, so a departed one cannot hold the rhythm up forever.
    public mutating func retain(peers: [String]) {
        guard !acknowledged.isEmpty else { return }
        var kept: [String: UInt32] = [:]
        kept.reserveCapacity(peers.count)
        for peer in peers {
            if let sequence = acknowledged[peer] { kept[peer] = sequence }
        }
        acknowledged = kept
    }

    /// Whether to send now, and what to number it.
    ///
    /// - Parameters:
    ///   - now: the current time in seconds. Passed in rather than read, so this can be tested.
    ///   - peers: who is connected.
    /// - Returns: the sequence number to send, or `nil` to send nothing yet.
    ///
    /// One call that both decides and records, rather than separate "should I?" and "I did" steps. Those
    /// can be got out of step — asked twice, or decided and then not recorded — and either way the
    /// pacing quietly stops working while every individual part still looks right.
    public mutating func nextFrame(now: Double, peers: [String]) -> UInt32? {
        // Nobody to send to. Note this does not advance the sequence: an empty room should not burn
        // through numbers, and the first peer to arrive should get frame one.
        guard !peers.isEmpty else {
            someoneIsWaiting = false
            return nil
        }
        guard now - lastSentAt >= minimumInterval else { return nil }

        if someoneIsWaiting {
            someoneIsWaiting = false
            return advance(now)
        }

        // Nothing sent yet, so there is nothing to be waiting on.
        guard lastSentSequence != 0 else { return advance(now) }

        // Equality rather than "at least", which is both simpler and wrap-safe: the only question is
        // whether this peer has confirmed the *latest* frame. A stale acknowledgement, or one for a
        // frame that was overtaken, correctly does not count.
        var everyoneIsCurrent = true
        for peer in peers where acknowledged[peer] != lastSentSequence {
            everyoneIsCurrent = false
            break
        }
        let deadlinePassed = now - lastSentAt >= acknowledgementDeadline
        guard everyoneIsCurrent || deadlinePassed else { return nil }

        return advance(now)
    }

    private mutating func advance(_ now: Double) -> UInt32 {
        // Wrapping, so a session running for the four and a half years it would take at thirty frames a
        // second does not trap. Nought is reserved for "nothing sent", so it is skipped on the way past.
        lastSentSequence = lastSentSequence &+ 1
        if lastSentSequence == 0 { lastSentSequence = 1 }
        lastSentAt = now
        return lastSentSequence
    }
}

// MARK: - The code people read out to each other

/// The short code that says which room is which.
///
/// Without one, every copy of the app within range of every other would join a single room, and two
/// people sitting near a third would all be painting the same world whether they meant to or not. The
/// code is carried in what a peer advertises, so peers with different codes never connect.
public enum RoomCode {
    /// The characters a code may contain.
    ///
    /// Missing on purpose: `I`, `L`, `O`, `0` and `1`. This is a code somebody reads aloud or copies off
    /// another person's screen, and those five are the pairs that get confused. Thirty-one characters
    /// over four places is about nine hundred thousand codes, which is ample for telling apart the
    /// handful of rooms that could ever be within Bluetooth range of one another.
    public static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    /// How many characters a code has.
    public static let length = 4

    /// Makes a new code.
    ///
    /// - Parameter generator: deliberately passed in, and deliberately not the simulation's. Drawing a
    ///   room code from the physics stream would mean that opening a room changed how the sand fell.
    public static func generate(using generator: inout Mulberry32) -> String {
        var characters = ""
        characters.reserveCapacity(length)
        for _ in 0 ..< length {
            let index = Int(generator.nextBits() % UInt32(alphabet.count))
            characters.append(alphabet[index])
        }
        return characters
    }

    /// Reads a code somebody typed.
    ///
    /// - Returns: the code in the form it is advertised in, or `nil` if it is not a code at all.
    ///
    /// Forgiving about the things a phone keyboard does — lower case, stray spaces — and strict about
    /// everything else. A code that is nearly right must be refused rather than corrected into a
    /// different valid code, because the failure that produces is the worst kind: joining somebody
    /// else's room and painting in their world.
    public static func normalise(_ text: String) -> String? {
        var cleaned = ""
        cleaned.reserveCapacity(length)
        for character in text {
            if character == " " || character == "-" { continue }
            // Each character uppercased individually, because uppercasing the whole string can change
            // its length for some scripts and the length is being checked.
            guard let upper = character.uppercased().first,
                  character.uppercased().count == 1,
                  alphabet.contains(upper)
            else { return nil }
            cleaned.append(upper)
            // Stopped here rather than after the loop, so an absurdly long paste is not walked through
            // in full before being refused.
            if cleaned.count > length { return nil }
        }
        guard cleaned.count == length else { return nil }
        return cleaned
    }
}
