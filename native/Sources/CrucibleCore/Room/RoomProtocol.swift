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
// applies it, and the host's world is the truth. Followers do not simulate independently — they are
// shown the host's world.
//
// The obvious design is for the host to broadcast the whole grid continuously. That is what the
// reference does, and it is why it sends a hundred and fifty kilobytes every tenth of a second. Instead
// the full world goes out once, strokes go out as they happen, and a cheap fingerprint of the world
// goes out periodically — when a follower's fingerprint disagrees, and only then, it asks for the whole
// world again.
//
// That is what ``PowderEngine/hashLite()`` was built for, and it is worth knowing that it was once
// broken in a way that made this exact scheme fail: the fingerprint mixed the raw cell values while the
// compact format sent something narrower, so the two never agreed, the "have we drifted?" test was
// permanently true, and the whole grid was resent every single tick. The fix is in that method's
// comment.

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
    /// Sent on joining: who this is.
    case hello(name: String)
    /// The whole world. Sent once on joining, and again whenever a peer reports drift.
    case world(PowderLiteState)
    /// Someone painted.
    case stroke(RoomStroke)
    /// The world's settings changed.
    case settings(RoomSettings)
    /// The host's fingerprint, for followers to compare against their own.
    case fingerprint(value: Int32, frame: Int)
    /// A follower asking for the whole world, because its fingerprint disagreed.
    case needWorld
    /// The world was cleared or replaced wholesale.
    case reset

    // MARK: Coding

    private enum Kind: String, Codable {
        case hello, world, stroke, settings, fingerprint, needWorld, reset
    }

    private enum CodingKeys: String, CodingKey {
        case kind, name, world, stroke, settings, value, frame
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .hello(name):
            try container.encode(Kind.hello, forKey: .kind)
            try container.encode(name, forKey: .name)
        case let .world(state):
            try container.encode(Kind.world, forKey: .kind)
            try container.encode(state, forKey: .world)
        case let .stroke(stroke):
            try container.encode(Kind.stroke, forKey: .kind)
            try container.encode(stroke, forKey: .stroke)
        case let .settings(settings):
            try container.encode(Kind.settings, forKey: .kind)
            try container.encode(settings, forKey: .settings)
        case let .fingerprint(value, frame):
            try container.encode(Kind.fingerprint, forKey: .kind)
            try container.encode(value, forKey: .value)
            try container.encode(frame, forKey: .frame)
        case .needWorld:
            try container.encode(Kind.needWorld, forKey: .kind)
        case .reset:
            try container.encode(Kind.reset, forKey: .kind)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .hello:
            self = .hello(name: try container.decode(String.self, forKey: .name))
        case .world:
            self = .world(try container.decode(PowderLiteState.self, forKey: .world))
        case .stroke:
            self = .stroke(try container.decode(RoomStroke.self, forKey: .stroke))
        case .settings:
            self = .settings(try container.decode(RoomSettings.self, forKey: .settings))
        case .fingerprint:
            self = .fingerprint(
                value: try container.decode(Int32.self, forKey: .value),
                frame: try container.decode(Int.self, forKey: .frame)
            )
        case .needWorld:
            self = .needWorld
        case .reset:
            self = .reset
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
