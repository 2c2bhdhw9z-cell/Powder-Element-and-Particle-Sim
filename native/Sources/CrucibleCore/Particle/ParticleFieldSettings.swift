/// The numbers behind the switches that used to be only switches.
///
/// Flocking, trails and collisions were each a single on-and-off toggle with everything about how they
/// behaved written into the code as a constant. That is the wrong shape for this app: the whole point of
/// a sandbox is that the person using it decides, and a switch with no numbers behind it is a decision
/// somebody else already made.
///
/// Every figure here was previously a literal buried in a loop. The defaults are those same literals, so
/// nothing changes until somebody moves something.

// MARK: - Flocking

/// How bodies steer by their neighbours.
///
/// Three urges pulling against one another, which is the whole of it: go where the others are going, go
/// where the others *are*, and don't crowd them. The character of a flock is entirely in the balance
/// between those three, so all three need to be reachable — a flock with cohesion turned up and
/// separation turned down is a swarm of bees, and the reverse is a shoal scattering from something.
public struct FlockSettings: Sendable, Hashable, Codable {
    /// How hard bodies avoid crowding their neighbours.
    public var separation: Double = 0.24
    /// How hard they match their neighbours' direction.
    public var alignment: Double = 0.04
    /// How hard they move toward the middle of their neighbours.
    public var cohesion: Double = 0.002
    /// How far a body can see, in pixels.
    public var vision: Double = 60
    /// How close is too close, in pixels. Inside this, bodies push apart.
    public var personalSpace: Double = 20
    /// How many bodies take part.
    ///
    /// Every body considers every other, so the work grows with the square of this — three hundred and
    /// sixty bodies is about sixty-five thousand comparisons a tick, which is the point at which it stops
    /// being free. Left reachable anyway, because somebody with a hundred bodies can afford far more and
    /// should not be held to a limit set for somebody with a million.
    public var limit: Int = 360

    public init(
        separation: Double = 0.24,
        alignment: Double = 0.04,
        cohesion: Double = 0.002,
        vision: Double = 60,
        personalSpace: Double = 20,
        limit: Int = 360
    ) {
        self.separation = separation
        self.alignment = alignment
        self.cohesion = cohesion
        self.vision = vision
        self.personalSpace = personalSpace
        self.limit = limit
    }

    public static let `default` = FlockSettings()

    /// The settings with every number pulled into a range the step can work in.
    public var sanitized: FlockSettings {
        FlockSettings(
            separation: Self.clamp(separation, 0, 2, fallback: 0.24),
            alignment: Self.clamp(alignment, 0, 0.5, fallback: 0.04),
            cohesion: Self.clamp(cohesion, 0, 0.05, fallback: 0.002),
            vision: Self.clamp(vision, 4, 400, fallback: 60),
            // Never wider than the vision: bodies cannot avoid what they cannot see, and a personal space
            // larger than the sight range would mean the avoidance applied to every neighbour equally,
            // which is a plain repulsion rather than flocking.
            personalSpace: min(
                Self.clamp(personalSpace, 2, 400, fallback: 20),
                Self.clamp(vision, 4, 400, fallback: 60)
            ),
            limit: min(2_000, max(2, limit))
        )
    }

    private static func clamp(
        _ value: Double,
        _ low: Double,
        _ high: Double,
        fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return max(low, min(high, value))
    }
}

// MARK: - Trails

/// How motion trails behave.
///
/// Trails are two separate things in this field, and both needed reaching. There is the short line drawn
/// behind each body from the positions it remembers, and there is the fact that the picture is dimmed
/// rather than erased between frames — which is what makes a trail last a dozen frames rather than the
/// six positions a body actually keeps. The second is the one that decides how long a trail *looks*, and
/// it was a constant.
public struct TrailSettings: Sendable, Hashable, Codable {
    /// How much of the previous frame is replaced each time, from nearly nothing to all of it.
    ///
    /// This is the length control, even though it is phrased the other way round. A quarter — the old
    /// constant — fades to nothing over about a dozen frames. A fortieth takes a couple of hundred, which
    /// is a long smear; three quarters is barely a trail at all.
    public var fade: Double = 0.25
    /// How solid the line behind a body is.
    public var opacity: Double = 0.3
    /// How thick that line is, relative to the body.
    public var width: Double = 0.8
    /// How far a body is stretched along its own direction of travel. Nought draws it as a dot.
    ///
    /// A different thing from the trail behind it, and worth having as well: a trail says where something has
    /// been, a streak says how fast it is going *now*. A field of fast bodies drawn as dots reads as a static
    /// scatter no matter how quickly it is actually moving, because a dot has no direction.
    ///
    /// Measured in moments — a streak of four is how far the body will travel in the next four moments — so a
    /// fast body streaks further than a slow one without anything having to scale it.
    public var streak: Double = 0
    /// Above this many bodies the lines are not drawn at all.
    ///
    /// Not the dimming — that costs the same whatever the crowd — only the lines, which are two more
    /// points to place per body. At a thousand bodies the picture is too dense to read them anyway.
    public var lineLimit: Int = 1_000

    public init(
        fade: Double = 0.25,
        opacity: Double = 0.3,
        width: Double = 0.8,
        streak: Double = 0,
        lineLimit: Int = 1_000
    ) {
        self.fade = fade
        self.opacity = opacity
        self.width = width
        self.streak = streak
        self.lineLimit = lineLimit
    }

    public static let `default` = TrailSettings()

    public var sanitized: TrailSettings {
        TrailSettings(
            // Never nought: a fade of nothing never clears the picture at all, so every frame is added to
            // the last forever and the screen fills with solid colour within a few seconds.
            fade: Self.clamp(fade, 0.01, 1, fallback: 0.25),
            opacity: Self.clamp(opacity, 0.02, 1, fallback: 0.3),
            width: Self.clamp(width, 0.1, 4, fallback: 0.8),
            streak: Self.clamp(streak, 0, 24, fallback: 0),
            lineLimit: min(20_000, max(0, lineLimit))
        )
    }

    private static func clamp(
        _ value: Double,
        _ low: Double,
        _ high: Double,
        fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return max(low, min(high, value))
    }
}

// MARK: - Contact

/// How bodies in the crowd meet one another.
public struct ContactSettings: Sendable, Hashable, Codable {
    /// How wide a body counts as, for touching, in pixels. Nought means work it out from the crowd.
    ///
    /// Separate from how large it is *drawn*, deliberately. Making them the same sounds tidier and is
    /// worse: the drawn size is a matter of taste and the contact size decides how the crowd packs, so
    /// tying them together means you cannot make a fine mist of large soft dots or a tight gravel of small
    /// hard ones.
    ///
    /// Nought by default, meaning the field picks it as it always has — from the size of the search squares,
    /// which themselves get coarser as the crowd grows. That keeps the recorded comparison against the
    /// reference implementation exact, and it means somebody who never touches this gets the behaviour the
    /// field has always had rather than a number I chose.
    public var size: Double = 0
    /// How many times a tick the crowd is pushed apart.
    ///
    /// One pass leaves stacks overlapping, because moving one pair apart pushes each of them into
    /// somebody else. Two firms it up, which was the old fixed behaviour. More is stiffer and costs
    /// proportionally more.
    public var passes: Int = 2
    /// How much speed survives a collision.
    public var bounciness: Double = 0.92
    /// How much sideways speed is rubbed off when two bodies scrape past each other.
    public var friction: Double = 0.18

    public init(
        size: Double = 0,
        passes: Int = 2,
        bounciness: Double = 0.92,
        friction: Double = 0.18
    ) {
        self.size = size
        self.passes = passes
        self.bounciness = bounciness
        self.friction = friction
    }

    public static let `default` = ContactSettings()

    public var sanitized: ContactSettings {
        ContactSettings(
            // Nought is allowed through, because nought means "work it out" rather than "no size".
            size: size.isFinite ? (size <= 0 ? 0 : max(1, min(40, size))) : 0,
            passes: min(6, max(1, passes)),
            bounciness: Self.clamp(bounciness, 0, 1, fallback: 0.92),
            friction: Self.clamp(friction, 0, 1, fallback: 0.18)
        )
    }

    private static func clamp(
        _ value: Double,
        _ low: Double,
        _ high: Double,
        fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return max(low, min(high, value))
    }
}

extension ParticleEngine {
    /// How bodies steer by their neighbours.
    public var flockSettings: FlockSettings {
        get { storedFlockSettings }
        set { storedFlockSettings = newValue }
    }

    /// How motion trails behave.
    public var trailSettings: TrailSettings {
        get { storedTrailSettings }
        set { storedTrailSettings = newValue }
    }

    /// How bodies in the crowd meet one another.
    public var contactSettings: ContactSettings {
        get { storedContactSettings }
        set { storedContactSettings = newValue }
    }
}
