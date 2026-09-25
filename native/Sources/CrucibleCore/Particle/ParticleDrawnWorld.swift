/// Two things you draw into the world with a finger.
///
/// Everything else in the field is a setting: a number somewhere that applies to the whole world at once.
/// These two are different in kind — they are *places*. A painted current is wind that exists here and not
/// there; a wall is a barrier that exists along this line and nowhere else. That difference is why they
/// matter more than another slider would: they are the only way to make one part of the field behave
/// differently from another by hand.
///
/// Both were described in detail in the read of the reference implementation and then not built. See the
/// gap audit in `HELION-MERGE.md`.

// MARK: - A painted current

/// Wind you paint, held as a coarse grid of directions.
///
/// Coarse on purpose. A current painted at the resolution of the screen would be a photograph of a finger
/// stroke rather than a flow — every wobble of the hand becomes a feature the crowd has to negotiate. At a
/// few dozen squares across, a stroke becomes a broad push in a direction, which is what somebody painting
/// wind is actually asking for.
///
/// Stored in fractions of the world rather than in pixels, so a current painted on one screen means the
/// same thing on another, and so it survives the world growing when the camera pulls back.
public struct ParticleCurrentField: Sendable, Hashable, Codable {
    /// How many squares across and down.
    public static let defaultResolution = 24
    /// The coarsest and finest it may be.
    public static let minimumResolution = 4
    public static let maximumResolution = 64

    public private(set) var resolution: Int
    /// Two numbers per square — how far across and how far down it pushes — laid out row by row.
    public private(set) var vectors: [Double]

    public init(resolution: Int = ParticleCurrentField.defaultResolution) {
        let size = max(Self.minimumResolution, min(Self.maximumResolution, resolution))
        self.resolution = size
        self.vectors = [Double](repeating: 0, count: size * size * 2)
    }

    /// Whether anything has been painted.
    ///
    /// Tracked by looking rather than by a flag, because a flag would have to be kept right through
    /// painting, clearing, loading and resizing, and the scan is a few thousand numbers once a tick.
    public var isEmpty: Bool {
        for value in vectors where value != 0 { return false }
        return true
    }

    /// Wipes it.
    public mutating func clear() {
        for index in vectors.indices { vectors[index] = 0 }
    }

    /// Changes how fine it is, keeping roughly what was painted.
    ///
    /// Resampled rather than wiped. Somebody who has painted a current and then wants it finer is asking to
    /// refine what they have, not to start again — and starting again is what a wipe would make them do.
    public mutating func setResolution(_ requested: Int) {
        let size = max(Self.minimumResolution, min(Self.maximumResolution, requested))
        guard size != resolution else { return }
        var resampled = [Double](repeating: 0, count: size * size * 2)
        for row in 0 ..< size {
            for column in 0 ..< size {
                // The middle of each new square, asked of the old grid.
                let acrossFraction = (Double(column) + 0.5) / Double(size)
                let downFraction = (Double(row) + 0.5) / Double(size)
                let sampled = self.sample(atFractionX: acrossFraction, y: downFraction)
                let at = (row * size + column) * 2
                resampled[at] = sampled.x
                resampled[at + 1] = sampled.y
            }
        }
        resolution = size
        vectors = resampled
    }

    /// Paints a push in a direction, softly, around a place.
    ///
    /// - Parameters:
    ///   - x: Where, across the world, from nought to one.
    ///   - y: Where, down the world, from nought to one.
    ///   - directionX: Which way to push. Need not be a unit length; it is normalised here.
    ///   - directionY: See above.
    ///   - radius: How far the stroke reaches, as a fraction of the world.
    ///   - strength: How much of the way toward the painted direction each square moves.
    ///
    /// The stroke moves each square *toward* the painted direction rather than adding to it. That is the
    /// important choice: adding means painting over the same place twice gives twice the push and a third
    /// time gives three times, so a slow careful stroke produces a hurricane and there is no way to paint
    /// gently. Moving toward it means repeated strokes converge on what was asked for and stop there, and
    /// painting the opposite way rubs the old direction out, which is how somebody expects a brush to work.
    ///
    /// The direction is normalised so that how *fast* the finger moves does not change how hard the current
    /// pushes. Otherwise a quick flick would paint a gale and a careful stroke almost nothing, which makes
    /// the tool impossible to aim.
    public mutating func paint(
        atFractionX x: Double,
        y: Double,
        directionX: Double,
        directionY: Double,
        radius: Double,
        strength: Double
    ) {
        guard x.isFinite, y.isFinite, directionX.isFinite, directionY.isFinite else { return }
        let length = (directionX * directionX + directionY * directionY).squareRoot()
        guard length > 1e-9 else { return }
        let towardX = directionX / length
        let towardY = directionY / length

        let reach = max(1e-4, radius.isFinite ? radius : 0.1)
        let amount = max(0, min(1, strength.isFinite ? strength : 0.5))
        guard amount > 0 else { return }

        for row in 0 ..< resolution {
            for column in 0 ..< resolution {
                let squareX = (Double(column) + 0.5) / Double(resolution)
                let squareY = (Double(row) + 0.5) / Double(resolution)
                let dx = squareX - x
                let dy = squareY - y
                let distance = (dx * dx + dy * dy).squareRoot()
                guard distance <= reach else { continue }
                // Strongest at the middle of the stroke, nothing at its edge.
                let weight = (1 - distance / reach) * amount
                let at = (row * resolution + column) * 2
                vectors[at] += (towardX - vectors[at]) * weight
                vectors[at + 1] += (towardY - vectors[at + 1]) * weight
            }
        }
    }

    /// The direction at a place, blended between the four surrounding squares.
    ///
    /// Blended rather than taken from the nearest square, because a body crossing from one square to the
    /// next would otherwise change direction instantly — and a field of those is a grid of visible creases
    /// that the crowd collects along.
    public func sample(atFractionX x: Double, y: Double) -> (x: Double, y: Double) {
        guard x.isFinite, y.isFinite, resolution > 0 else { return (0, 0) }
        let last = resolution - 1

        // Measured between the middles of the squares, which is where the values actually live.
        let acrossPosition = max(0, min(Double(last), x * Double(resolution) - 0.5))
        let downPosition = max(0, min(Double(last), y * Double(resolution) - 0.5))
        let leftColumn = min(last, max(0, Int(acrossPosition)))
        let topRow = min(last, max(0, Int(downPosition)))
        let rightColumn = min(last, leftColumn + 1)
        let bottomRow = min(last, topRow + 1)
        let acrossFraction = acrossPosition - Double(leftColumn)
        let downFraction = downPosition - Double(topRow)

        func at(_ column: Int, _ row: Int) -> (x: Double, y: Double) {
            let index = (row * resolution + column) * 2
            return (vectors[index], vectors[index + 1])
        }

        let topLeft = at(leftColumn, topRow)
        let topRight = at(rightColumn, topRow)
        let bottomLeft = at(leftColumn, bottomRow)
        let bottomRight = at(rightColumn, bottomRow)

        let topX = topLeft.x + (topRight.x - topLeft.x) * acrossFraction
        let topY = topLeft.y + (topRight.y - topLeft.y) * acrossFraction
        let bottomX = bottomLeft.x + (bottomRight.x - bottomLeft.x) * acrossFraction
        let bottomY = bottomLeft.y + (bottomRight.y - bottomLeft.y) * acrossFraction

        return (
            x: topX + (bottomX - topX) * downFraction,
            y: topY + (bottomY - topY) * downFraction
        )
    }
}

// MARK: - A drawn wall

/// A straight barrier the crowd cannot pass through.
///
/// Held in fractions of the world, like the current, so a wall drawn on one screen is in the same place on
/// another and stays where it was drawn when the world grows.
public struct ParticleWall: Sendable, Hashable, Codable {
    public var fromX: Double
    public var fromY: Double
    public var toX: Double
    public var toY: Double

    public init(fromX: Double, fromY: Double, toX: Double, toY: Double) {
        self.fromX = fromX
        self.fromY = fromY
        self.toX = toX
        self.toY = toY
    }

    /// Whether this is long enough to be worth keeping.
    ///
    /// A wall of no length has no direction, so there is no side to bounce off. They arrive constantly —
    /// every tap that does not turn into a drag is one.
    public var isUsable: Bool {
        guard fromX.isFinite, fromY.isFinite, toX.isFinite, toY.isFinite else { return false }
        let dx = toX - fromX
        let dy = toY - fromY
        return dx * dx + dy * dy > 1e-8
    }
}

/// How the walls behave, and what happens at them.
public struct WallSettings: Sendable, Hashable, Codable {
    /// How much speed survives hitting one.
    public var bounciness: Double = 0.5
    /// How much sideways speed is rubbed off sliding along one.
    public var friction: Double = 0.1
    /// How thick a wall is, in pixels — how close a body has to get before it is stopped.
    public var thickness: Double = 3

    public init(bounciness: Double = 0.5, friction: Double = 0.1, thickness: Double = 3) {
        self.bounciness = bounciness
        self.friction = friction
        self.thickness = thickness
    }

    public static let `default` = WallSettings()

    public var sanitized: WallSettings {
        WallSettings(
            bounciness: Self.clamp(bounciness, 0, 1, fallback: 0.5),
            friction: Self.clamp(friction, 0, 1, fallback: 0.1),
            thickness: Self.clamp(thickness, 1, 40, fallback: 3)
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

/// How hard a painted current pushes, and how finely it is painted.
public struct CurrentSettings: Sendable, Hashable, Codable {
    /// How hard the current pushes the crowd.
    public var strength: Double = 1.2
    /// How wide a stroke is, as a fraction of the world.
    public var brushRadius: Double = 0.12
    /// How much of the way toward the painted direction one stroke moves each square.
    public var brushStrength: Double = 0.35

    public init(strength: Double = 1.2, brushRadius: Double = 0.12, brushStrength: Double = 0.35) {
        self.strength = strength
        self.brushRadius = brushRadius
        self.brushStrength = brushStrength
    }

    public static let `default` = CurrentSettings()

    public var sanitized: CurrentSettings {
        CurrentSettings(
            strength: Self.clamp(strength, 0, 8, fallback: 1.2),
            brushRadius: Self.clamp(brushRadius, 0.02, 0.6, fallback: 0.12),
            brushStrength: Self.clamp(brushStrength, 0.02, 1, fallback: 0.35)
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

// MARK: - Applying them to the crowd

/// Pushes the crowd along a painted current, and stops it at the walls.
public enum SwarmDrawnWorld {
    /// How many walls may exist.
    ///
    /// A hundred and twenty. Every body is tested against every wall, so this is the number that decides
    /// whether walls are affordable — a hundred and twenty against a hundred thousand bodies is twelve
    /// million tests, which is about the same as one pass of the crowd pushing itself apart. Past that the
    /// oldest is dropped, which is both what the reference implementation does and the only thing that can
    /// be done without refusing to draw.
    public static let wallLimit = 120

    /// Pushes every body along the current.
    public static func applyCurrent(
        _ field: ParticleCurrentField,
        to swarm: Swarm,
        settings: CurrentSettings,
        width: Double,
        height: Double
    ) {
        let bodies = swarm.count
        guard bodies > 0, width > 0, height > 0, !field.isEmpty else { return }
        let tuned = settings.sanitized
        guard tuned.strength > 0 else { return }

        let positions = swarm.positions
        let velocities = swarm.velocities
        let inverseWidth = 1 / width
        let inverseHeight = 1 / height

        for index in 0 ..< bodies {
            let pair = index * 2
            let x = Double(positions[pair])
            let y = Double(positions[pair + 1])
            guard x.isFinite, y.isFinite else { continue }
            let push = field.sample(atFractionX: x * inverseWidth, y: y * inverseHeight)
            guard push.x != 0 || push.y != 0 else { continue }
            let velX = Double(velocities[pair])
            let velY = Double(velocities[pair + 1])
            guard velX.isFinite, velY.isFinite else { continue }
            velocities[pair] = JS.toFloat32(velX + push.x * tuned.strength)
            velocities[pair + 1] = JS.toFloat32(velY + push.y * tuned.strength)
        }
    }

    /// Stops every body that has run into a wall.
    ///
    /// Run after the bodies have moved, because a wall is about where something has *got to* rather than
    /// where it was going. Both the crossing and the closeness are checked: the closeness catches a body
    /// resting against a wall, and the crossing catches a fast one that would otherwise have gone from one
    /// side to the other between two frames without ever being near it.
    public static func applyWalls(
        _ walls: [ParticleWall],
        to swarm: Swarm,
        previousPositions: UnsafePointer<Float>?,
        settings: WallSettings,
        width: Double,
        height: Double
    ) {
        let bodies = swarm.count
        guard bodies > 0, !walls.isEmpty, width > 0, height > 0 else { return }
        let tuned = settings.sanitized
        let positions = swarm.positions
        let velocities = swarm.velocities

        // Turned into pixels once, rather than for every body against every wall.
        struct Segment {
            var fromX: Double
            var fromY: Double
            var alongX: Double
            var alongY: Double
            var lengthSquared: Double
            var normalX: Double
            var normalY: Double
        }
        var segments: [Segment] = []
        segments.reserveCapacity(walls.count)
        for wall in walls where wall.isUsable {
            let fromX = wall.fromX * width
            let fromY = wall.fromY * height
            let alongX = wall.toX * width - fromX
            let alongY = wall.toY * height - fromY
            let lengthSquared = alongX * alongX + alongY * alongY
            guard lengthSquared > 1e-9 else { continue }
            let length = lengthSquared.squareRoot()
            segments.append(Segment(
                fromX: fromX,
                fromY: fromY,
                alongX: alongX,
                alongY: alongY,
                lengthSquared: lengthSquared,
                // Square to the wall, either way round — which way is decided per body, by which side it
                // came from.
                normalX: -alongY / length,
                normalY: alongX / length
            ))
        }
        guard !segments.isEmpty else { return }

        let thickness = tuned.thickness
        let thicknessSquared = thickness * thickness
        let bounciness = tuned.bounciness
        let friction = tuned.friction

        for index in 0 ..< bodies {
            let pair = index * 2
            var x = Double(positions[pair])
            var y = Double(positions[pair + 1])
            var velX = Double(velocities[pair])
            var velY = Double(velocities[pair + 1])
            guard x.isFinite, y.isFinite, velX.isFinite, velY.isFinite else { continue }

            let cameFromX = previousPositions.map { Double($0[pair]) } ?? x
            let cameFromY = previousPositions.map { Double($0[pair + 1]) } ?? y

            for segment in segments {
                // The nearest point on the wall to where the body is.
                let toBodyX = x - segment.fromX
                let toBodyY = y - segment.fromY
                let along = max(0, min(1, (toBodyX * segment.alongX + toBodyY * segment.alongY)
                    / segment.lengthSquared))
                let nearestX = segment.fromX + segment.alongX * along
                let nearestY = segment.fromY + segment.alongY * along
                let gapX = x - nearestX
                let gapY = y - nearestY
                let gapSquared = gapX * gapX + gapY * gapY

                // Which side of the wall the body was on before it moved. That is what decides which way
                // "out" is — using the current side would push a body that has already gone through even
                // further through.
                let wasSide = (cameFromX - segment.fromX) * segment.normalX
                    + (cameFromY - segment.fromY) * segment.normalY
                let side: Double = wasSide >= 0 ? 1 : -1
                let outX = segment.normalX * side
                let outY = segment.normalY * side

                let nowSide = gapX * outX + gapY * outY
                // Either resting against it, or it has crossed to the other side since the last frame.
                let touching = gapSquared < thicknessSquared
                let crossed = nowSide < 0 && wasSide != 0
                guard touching || crossed else { continue }

                // Put back onto the near face.
                x = nearestX + outX * thickness
                y = nearestY + outY * thickness

                // And turned around, if it was heading in.
                let intoWall = velX * outX + velY * outY
                if intoWall < 0 {
                    // The part heading into the wall is reversed and reduced; the part sliding along it is
                    // reduced by the friction. Separating the two is what makes a wall something a body can
                    // slide down rather than only bounce off.
                    let alongVelX = velX - outX * intoWall
                    let alongVelY = velY - outY * intoWall
                    velX = alongVelX * (1 - friction) - outX * intoWall * bounciness
                    velY = alongVelY * (1 - friction) - outY * intoWall * bounciness
                }
            }

            positions[pair] = JS.toFloat32(x)
            positions[pair + 1] = JS.toFloat32(y)
            velocities[pair] = JS.toFloat32(velX)
            velocities[pair + 1] = JS.toFloat32(velY)
        }
    }
}

extension ParticleEngine {
    /// Wind painted into the world.
    public var current: ParticleCurrentField {
        get { storedCurrent }
        set { storedCurrent = newValue }
    }

    /// How hard the painted current pushes.
    public var currentSettings: CurrentSettings {
        get { storedCurrentSettings }
        set { storedCurrentSettings = newValue }
    }

    /// The walls drawn into the world.
    public var walls: [ParticleWall] {
        get { storedWalls }
        set {
            // Capped, because every body is tested against every wall. The oldest goes, which is the only
            // thing that can be done without refusing to draw.
            let usable = newValue.filter(\.isUsable)
            storedWalls = usable.count <= SwarmDrawnWorld.wallLimit
                ? usable
                : Array(usable.suffix(SwarmDrawnWorld.wallLimit))
        }
    }

    /// How the walls behave.
    public var wallSettings: WallSettings {
        get { storedWallSettings }
        set { storedWallSettings = newValue }
    }

    /// Adds a wall, in fractions of the world.
    public func addWall(fromFractionX: Double, y fromY: Double, toFractionX: Double, y toY: Double) {
        let wall = ParticleWall(fromX: fromFractionX, fromY: fromY, toX: toFractionX, toY: toY)
        guard wall.isUsable else { return }
        walls = storedWalls + [wall]
    }

    /// Removes every wall.
    public func clearWalls() {
        storedWalls = []
    }

    /// Paints into the current, at a place in the world measured in pixels.
    public func paintCurrent(
        atX x: Double,
        y: Double,
        directionX: Double,
        directionY: Double
    ) {
        guard width > 0, height > 0 else { return }
        let tuned = currentSettings.sanitized
        storedCurrent.paint(
            atFractionX: x / width,
            y: y / height,
            directionX: directionX,
            directionY: directionY,
            radius: tuned.brushRadius,
            strength: tuned.brushStrength
        )
    }

    /// Wipes the painted current.
    public func clearCurrent() {
        storedCurrent.clear()
    }
}
