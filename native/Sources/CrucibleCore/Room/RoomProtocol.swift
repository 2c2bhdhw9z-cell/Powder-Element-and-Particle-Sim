// What two phones say to each other when they share a world.
//
// ## Why the protocol is in the engine
//
// None of this touches a network — there is no transport here, no sockets, nothing that could reach
// another device. What is here is the *vocabulary*: what a message can say, how it turns into bytes, and
// what applying one does to a world.
//
// That belongs with the simulation for the same reason the save format does. A message is a description
// of a change to a world, and whether two implementations agree about what a given message means is
// exactly the sort of thing that cannot be established by reading. It can be established by a test.
//
// ## The shape of the thing
//
// One peer is the host and owns the world. Everyone can paint; a stroke travels to the host, the host
// applies it, and the host's world is the truth.
//
// **Followers do not simulate.** They cannot: the physics draws thousands of random numbers a tick from
// each engine's own stream, so two engines stepping the same world come apart inside a single frame.
// So the host sends the whole world, continuously, and the follower displays it.
//
// An earlier version of this comment claimed the opposite — that the world went out once and strokes
// then kept the two in step, with a fingerprint to catch drift. That scheme cannot work, and the test
// named `scatteringBrushDrifts` below is the proof: one spray of sand puts the two worlds permanently
// out of agreement, and every tick of ordinary physics does the same thing. Continuous is not a
// concession, it is the only correct arrangement.
//
// What that leaves each message doing:
//
//   - **World frames** carry the grid and dominate the link, so they do not travel as JSON at all. See
//     `RoomWorld.swift` for the binary frame and the compression that makes the rate affordable.
//   - **Acknowledgements** let the host pace itself. Sending at a fixed rate down a link that cannot
//     keep up is the worst available failure: the frames queue and the follower falls further behind
//     with every one. Waiting for the last frame to be acknowledged makes the rate the link's to
//     choose.
//   - **Strokes** still travel, in both directions. A follower's painting has to reach the host to
//     exist at all, and the follower also applies it locally straight away so the brush feels
//     connected to the finger instead of lagging a frame behind the network.
//   - **The fingerprint** is no longer load-bearing for correctness — the world arrives whole and
//     often. It is what the interface uses to tell someone whether they are seeing the host's world or
//     something stale.
//
// It is worth knowing that ``PowderEngine/hashLite()`` was once broken in a way that made sharing a
// world fail completely: it mixed the raw cell values while the compact format sent something narrower,
// so the two never agreed, the "have we drifted?" test was permanently true, and the whole grid was
// resent every single tick. The fix is in that method's comment, and the frame now carries the sender's
// fingerprint so a receiver checks its own work every time.

/// A brush stroke, as it travels between peers.
///
/// Deliberately the *instruction* rather than its result. Sending the cells it changed would be larger,
/// would not compose with anything else happening at the same moment, and would make a stroke
/// impossible to undo as a unit on the receiving side.
public struct RoomStroke: Codable, Sendable, Hashable {
    public var x: Int
    public var y: Int
    public var radius: Int
    public var elementID: ElementID
    public var shape: BrushShape
    /// The material being replaced, for the replace brush. Absent for every other shape.
    public var targetElementID: ElementID?

    public init(
        x: Int,
        y: Int,
        radius: Int,
        elementID: ElementID,
        shape: BrushShape,
        targetElementID: ElementID? = nil
    ) {
        self.x = x
        self.y = y
        self.radius = radius
        self.elementID = elementID
        self.shape = shape
        self.targetElementID = targetElementID
    }
}

/// The world settings a peer needs to match.
///
/// Small enough to send with every fingerprint rather than tracking which have changed.
public struct RoomSettings: Codable, Sendable, Hashable {
    public var gravityX: Double
    public var gravityY: Double
    public var windX: Double
    public var ambientTemp: Double

    public init(gravityX: Double, gravityY: Double, windX: Double, ambientTemp: Double) {
        self.gravityX = gravityX
        self.gravityY = gravityY
        self.windX = windX
        self.ambientTemp = ambientTemp
    }
}

/// One thing a peer can say.
///
/// Encoded with a discriminator rather than relying on which fields are present, so an unknown kind from
/// a newer build is recognisably unknown rather than silently decoding as something else.
public enum RoomMessage: Codable, Sendable {
    /// A follower confirming it has received and drawn a world frame.
    ///
    /// This is what lets the host pace itself. It sends the next frame once the last one has been
    /// acknowledged, so a slow link produces fewer, current frames rather than a growing queue of stale
    /// ones. The whole world is *not* here — world frames are bytes, not JSON. See `RoomWorld.swift`.
    case worldAck(sequence: UInt32)
    /// Someone painted.
    case stroke(RoomStroke)
    /// The world's settings changed.
    ///
    /// Only wind and the ambient temperature really need this — gravity is in every world frame — but
    /// all four travel together because comparing four numbers is cheaper than tracking which of them
    /// changed.
    case settings(RoomSettings)
    /// A follower asking for a frame right now.
    ///
    /// Sent on joining, so the first world arrives immediately instead of after however long the host's
    /// pacing would have taken, and again after a gap — a frame that failed to decode, or a stretch with
    /// nothing arriving at all.
    case needWorld

    // Four messages, and every one of them is sent. There were briefly three more — an introduction, the
    // host's fingerprint, and a notice that the world had been cleared — and all three were dead weight.
    // The fingerprint travels inside the world frame, where the receiver can check its own work against
    // it; a cleared world is simply the next frame; and an introduction carried nothing the transport
    // does not already say. Protocol vocabulary that nothing speaks is worse than none, because the next
    // person here would build against a message that is never sent.

    // MARK: Coding

    private enum Kind: String, Codable {
        case worldAck, stroke, settings, needWorld
    }

    private enum CodingKeys: String, CodingKey {
        case kind, sequence, stroke, settings
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .worldAck(sequence):
            try container.encode(Kind.worldAck, forKey: .kind)
            try container.encode(sequence, forKey: .sequence)
        case let .stroke(stroke):
            try container.encode(Kind.stroke, forKey: .kind)
            try container.encode(stroke, forKey: .stroke)
        case let .settings(settings):
            try container.encode(Kind.settings, forKey: .kind)
            try container.encode(settings, forKey: .settings)
        case .needWorld:
            try container.encode(Kind.needWorld, forKey: .kind)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .worldAck:
            self = .worldAck(sequence: try container.decode(UInt32.self, forKey: .sequence))
        case .stroke:
            self = .stroke(try container.decode(RoomStroke.self, forKey: .stroke))
        case .settings:
            self = .settings(try container.decode(RoomSettings.self, forKey: .settings))
        case .needWorld:
            self = .needWorld
        }
    }
}

extension PowderEngine {
    /// The settings a peer needs to match this world.
    public func roomSettings() -> RoomSettings {
        RoomSettings(
            gravityX: gravityX,
            gravityY: gravityY,
            windX: windX,
            ambientTemp: ambientTemp
        )
    }

    /// Adopts settings from another peer.
    ///
    /// Every value is checked. A peer on a damaged build, or a packet that arrived corrupt, could
    /// otherwise put a value that is not a number into gravity — from where it reaches every position
    /// in the world and nothing recovers.
    public func apply(_ settings: RoomSettings) {
        if settings.gravityX.isFinite { gravityX = settings.gravityX }
        if settings.gravityY.isFinite { gravityY = settings.gravityY }
        // Through the clamp, like every other writer.
        if settings.windX.isFinite { setWind(settings.windX) }
        if settings.ambientTemp.isFinite { ambientTemp = settings.ambientTemp }
    }

    /// Applies a stroke that came from another peer.
    ///
    /// - Parameter now: the clock the brush reads, for the tools that vary with time.
    /// - Returns: whether it was applied. A stroke naming a material this build does not have, or a
    ///   radius that is not usable, is refused rather than guessed at — quietly substituting air would
    ///   punch a hole in someone else's world.
    @discardableResult
    public func apply(_ stroke: RoomStroke, now: Double = 0) -> Bool {
        guard stroke.radius >= 0, stroke.radius <= 512 else { return false }
        guard stroke.elementID <= Element.customIDEnd else { return false }
        if let target = stroke.targetElementID, target > Element.customIDEnd { return false }
        // A coordinate far outside the world is not an error — a peer with a larger world can
        // legitimately paint past this one's edge — but a nonsensical one is.
        guard abs(stroke.x) < 1_000_000, abs(stroke.y) < 1_000_000 else { return false }

        drawBrush(
            centerX: stroke.x,
            centerY: stroke.y,
            radius: stroke.radius,
            elementID: stroke.elementID,
            shape: stroke.shape,
            targetElementID: stroke.targetElementID,
            now: now
        )
        return true
    }
}
