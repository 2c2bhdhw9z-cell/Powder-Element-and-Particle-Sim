import Foundation
import Testing

@testable import CrucibleCore

/// The two things you draw into the world with a finger.
///
/// Everything else in the field is a setting that applies everywhere at once. These are *places* — wind that
/// exists here and not there, a barrier along this line and nowhere else — which is why they were the two
/// biggest omissions on the gap audit, and why they get tested hardest.
struct ParticleDrawnWorldTests {
    private func swarm(_ points: [(Double, Double)], velocities: [(Double, Double)]? = nil) -> Swarm {
        let result = Swarm()
        var rng = Mulberry32(seed: 1)
        result.spawn(
            count: points.count,
            width: 400,
            height: 700,
            color: 0xFFFF_FFFF,
            budget: 40_000,
            rng: &rng
        )
        for (index, point) in points.enumerated() {
            result.positions[index * 2] = Float(point.0)
            result.positions[index * 2 + 1] = Float(point.1)
            let velocity = velocities?[index] ?? (0, 0)
            result.velocities[index * 2] = Float(velocity.0)
            result.velocities[index * 2 + 1] = Float(velocity.1)
        }
        return result
    }

    // MARK: - A painted current

    @Test("A fresh current is empty and pushes nothing")
    func freshCurrentIsEmpty() {
        let field = ParticleCurrentField()
        #expect(field.isEmpty)
        let sampled = field.sample(atFractionX: 0.5, y: 0.5)
        #expect(sampled.x == 0 && sampled.y == 0)
    }

    @Test("Painting puts a push where it was painted and not elsewhere")
    func paintingIsLocal() {
        // The whole point of it being a place rather than a setting.
        var field = ParticleCurrentField()
        field.paint(
            atFractionX: 0.25, y: 0.25, directionX: 1, directionY: 0, radius: 0.1, strength: 1
        )
        #expect(!field.isEmpty)

        let painted = field.sample(atFractionX: 0.25, y: 0.25)
        #expect(painted.x > 0.5, "the painted place should push, found \(painted.x)")
        #expect(abs(painted.y) < 0.2)

        let elsewhere = field.sample(atFractionX: 0.8, y: 0.8)
        #expect(abs(elsewhere.x) < 0.01, "somewhere else should be untouched")
        #expect(abs(elsewhere.y) < 0.01)
    }

    @Test("How fast the finger moves does not change how hard the current pushes")
    func speedOfStrokeDoesNotMatter() {
        // Otherwise a quick flick paints a gale and a careful stroke almost nothing, which makes the tool
        // impossible to aim.
        var slow = ParticleCurrentField()
        slow.paint(atFractionX: 0.5, y: 0.5, directionX: 0.01, directionY: 0, radius: 0.2, strength: 1)
        var fast = ParticleCurrentField()
        fast.paint(atFractionX: 0.5, y: 0.5, directionX: 90, directionY: 0, radius: 0.2, strength: 1)

        let slowPush = slow.sample(atFractionX: 0.5, y: 0.5)
        let fastPush = fast.sample(atFractionX: 0.5, y: 0.5)
        #expect(abs(slowPush.x - fastPush.x) < 1e-9, "\(slowPush.x) against \(fastPush.x)")
    }

    @Test("Painting the same place repeatedly settles rather than piling up")
    func paintingSaturates() {
        // Adding would mean a slow careful stroke produces a hurricane and there is no way to paint gently.
        var field = ParticleCurrentField()
        var previous = 0.0
        for _ in 0 ..< 60 {
            field.paint(
                atFractionX: 0.5, y: 0.5, directionX: 1, directionY: 0, radius: 0.2, strength: 0.4
            )
            let now = field.sample(atFractionX: 0.5, y: 0.5).x
            #expect(now >= previous - 1e-9, "the push went backwards")
            previous = now
        }
        #expect(previous <= 1.0001, "a repeated stroke reached \(previous), which should stop at one")
        #expect(previous > 0.95, "and it should get most of the way there")
    }

    @Test("Painting the other way rubs out what was there")
    func paintingCanBeUndone() {
        // How somebody expects a brush to work: going back over a stroke the other way removes it.
        var field = ParticleCurrentField()
        for _ in 0 ..< 20 {
            field.paint(atFractionX: 0.5, y: 0.5, directionX: 1, directionY: 0, radius: 0.2, strength: 0.5)
        }
        #expect(field.sample(atFractionX: 0.5, y: 0.5).x > 0.9)

        for _ in 0 ..< 20 {
            field.paint(atFractionX: 0.5, y: 0.5, directionX: -1, directionY: 0, radius: 0.2, strength: 0.5)
        }
        #expect(field.sample(atFractionX: 0.5, y: 0.5).x < -0.9, "painting back should reverse it")
    }

    @Test("The current is smooth between squares, with no creases")
    func currentIsSmooth() {
        // Taken from the nearest square instead, a body crossing from one to the next would change direction
        // instantly — and a field of those is a grid of creases the crowd collects along.
        var field = ParticleCurrentField()
        field.paint(atFractionX: 0.5, y: 0.5, directionX: 1, directionY: 1, radius: 0.3, strength: 1)

        var worstJump = 0.0
        var previous = field.sample(atFractionX: 0, y: 0.5)
        var across = 0.0
        while across < 1 {
            across += 0.002
            let here = field.sample(atFractionX: across, y: 0.5)
            let jump = ((here.x - previous.x) * (here.x - previous.x)
                + (here.y - previous.y) * (here.y - previous.y)).squareRoot()
            worstJump = max(worstJump, jump)
            previous = here
        }
        #expect(worstJump < 0.05, "the current jumps by \(worstJump) over a five-hundredth of the world")
    }

    @Test("Making it finer keeps what was painted")
    func resolutionChangeKeepsTheStroke() {
        // Somebody who has painted a current and wants it finer is asking to refine what they have, not to
        // start again.
        var field = ParticleCurrentField(resolution: 12)
        field.paint(atFractionX: 0.3, y: 0.7, directionX: 0, directionY: -1, radius: 0.2, strength: 1)
        let before = field.sample(atFractionX: 0.3, y: 0.7)

        field.setResolution(48)
        #expect(field.resolution == 48)
        let after = field.sample(atFractionX: 0.3, y: 0.7)
        #expect(abs(after.y - before.y) < 0.2, "\(before.y) became \(after.y)")
        #expect(after.y < -0.5, "and it should still be pushing upward")
    }

    @Test("Resolution stays within what the field can hold")
    func resolutionIsClamped() {
        #expect(ParticleCurrentField(resolution: 0).resolution == ParticleCurrentField.minimumResolution)
        #expect(ParticleCurrentField(resolution: 9_999).resolution == ParticleCurrentField.maximumResolution)
        var field = ParticleCurrentField()
        field.setResolution(-4)
        #expect(field.resolution == ParticleCurrentField.minimumResolution)
    }

    @Test("Clearing empties it")
    func clearingWorks() {
        var field = ParticleCurrentField()
        field.paint(atFractionX: 0.5, y: 0.5, directionX: 1, directionY: 0, radius: 0.3, strength: 1)
        #expect(!field.isEmpty)
        field.clear()
        #expect(field.isEmpty)
    }

    @Test("Nonsense strokes are ignored")
    func badStrokesAreIgnored() {
        var field = ParticleCurrentField()
        // A direction of nothing has no direction to paint.
        field.paint(atFractionX: 0.5, y: 0.5, directionX: 0, directionY: 0, radius: 0.2, strength: 1)
        #expect(field.isEmpty)
        field.paint(atFractionX: .nan, y: 0.5, directionX: 1, directionY: 0, radius: 0.2, strength: 1)
        #expect(field.isEmpty)
        field.paint(atFractionX: 0.5, y: 0.5, directionX: .nan, directionY: 0, radius: 0.2, strength: 1)
        #expect(field.isEmpty)
        field.paint(atFractionX: 0.5, y: 0.5, directionX: 1, directionY: 0, radius: 0.2, strength: 0)
        #expect(field.isEmpty)
    }

    @Test("Sampling outside the world is safe")
    func samplingOutsideIsSafe() {
        var field = ParticleCurrentField()
        field.paint(atFractionX: 0.5, y: 0.5, directionX: 1, directionY: 1, radius: 0.4, strength: 1)
        for point in [(-4.0, -4.0), (9.0, 9.0), (Double.nan, 0.5), (0.5, Double.infinity)] {
            let sampled = field.sample(atFractionX: point.0, y: point.1)
            #expect(sampled.x.isFinite && sampled.y.isFinite, "at \(point)")
        }
    }

    @Test("A painted current pushes the crowd where it was painted")
    func currentMovesTheCrowd() {
        var field = ParticleCurrentField()
        // Only the left half of the world.
        field.paint(atFractionX: 0.2, y: 0.5, directionX: 0, directionY: -1, radius: 0.2, strength: 1)

        let inside = swarm([(80, 350)])
        let outside = swarm([(340, 350)])
        for crowd in [inside, outside] {
            SwarmDrawnWorld.applyCurrent(
                field, to: crowd, settings: .default, width: 400, height: 700
            )
        }
        #expect(Double(inside.velocities[1]) < -0.5, "the painted side should be pushed upward")
        #expect(abs(Double(outside.velocities[1])) < 0.01, "the other side should be untouched")
    }

    @Test("A current with no strength does nothing")
    func currentRespectsItsStrength() {
        var field = ParticleCurrentField()
        field.paint(atFractionX: 0.5, y: 0.5, directionX: 1, directionY: 0, radius: 0.4, strength: 1)
        let crowd = swarm([(200, 350)])
        SwarmDrawnWorld.applyCurrent(
            field,
            to: crowd,
            settings: CurrentSettings(strength: 0),
            width: 400,
            height: 700
        )
        #expect(Double(crowd.velocities[0]) == 0)
    }

    // MARK: - Drawn walls

    @Test("A wall of no length is not kept")
    func zeroLengthWallsAreRejected() {
        // They arrive constantly — every tap that does not turn into a drag is one — and a wall with no
        // length has no direction, so there is no side to bounce off.
        #expect(!ParticleWall(fromX: 0.5, fromY: 0.5, toX: 0.5, toY: 0.5).isUsable)
        #expect(!ParticleWall(fromX: .nan, fromY: 0, toX: 1, toY: 1).isUsable)
        #expect(ParticleWall(fromX: 0.2, fromY: 0.5, toX: 0.8, toY: 0.5).isUsable)

        let field = ParticleEngine(width: 400, height: 700, seed: 1)
        field.addWall(fromFractionX: 0.5, y: 0.5, toFractionX: 0.5, y: 0.5)
        #expect(field.walls.isEmpty)
    }

    @Test("A body heading into a wall is stopped and turned around")
    func wallsStopBodies() {
        // A horizontal wall across the middle, with a body falling onto it.
        let walls = [ParticleWall(fromX: 0.1, fromY: 0.5, toX: 0.9, toY: 0.5)]
        let crowd = swarm([(200, 360)], velocities: [(0, 8)])
        let previous: [Float] = [200, 340]

        previous.withUnsafeBufferPointer { was in
            SwarmDrawnWorld.applyWalls(
                walls,
                to: crowd,
                previousPositions: was.baseAddress,
                settings: .default,
                width: 400,
                height: 700
            )
        }

        #expect(Double(crowd.positions[1]) < 350, "the body should be put back above the wall")
        #expect(Double(crowd.velocities[1]) < 0, "and sent back the way it came")
    }

    @Test("A fast body cannot pass through a wall between frames")
    func wallsCatchFastBodies() {
        // The reason both the closeness and the crossing are checked. A body moving faster than the wall is
        // thick would otherwise be on one side one frame and the other side the next, having never been near
        // enough to notice.
        let walls = [ParticleWall(fromX: 0, fromY: 0.5, toX: 1, toY: 0.5)]
        let crowd = swarm([(200, 500)], velocities: [(0, 200)])
        let previous: [Float] = [200, 300]

        previous.withUnsafeBufferPointer { was in
            SwarmDrawnWorld.applyWalls(
                walls,
                to: crowd,
                previousPositions: was.baseAddress,
                settings: .default,
                width: 400,
                height: 700
            )
        }
        #expect(Double(crowd.positions[1]) < 360, "it went through to \(crowd.positions[1])")
        #expect(Double(crowd.velocities[1]) < 0)
    }

    @Test("A body moving along a wall is not stopped by it")
    func wallsDoNotBlockSliding() {
        // Separating the part heading into the wall from the part sliding along it is what makes a wall
        // something a body can slide down rather than only bounce off.
        let walls = [ParticleWall(fromX: 0, fromY: 0.5, toX: 1, toY: 0.5)]
        let crowd = swarm([(200, 349)], velocities: [(6, 0)])
        let previous: [Float] = [194, 349]

        previous.withUnsafeBufferPointer { was in
            SwarmDrawnWorld.applyWalls(
                walls,
                to: crowd,
                previousPositions: was.baseAddress,
                settings: WallSettings(bounciness: 0.5, friction: 0, thickness: 3),
                width: 400,
                height: 700
            )
        }
        #expect(Double(crowd.velocities[0]) > 5, "sliding speed was \(crowd.velocities[0])")
    }

    @Test("Friction slows something sliding along a wall")
    func wallFrictionBites() {
        func slidingSpeed(friction: Double) -> Double {
            let walls = [ParticleWall(fromX: 0, fromY: 0.5, toX: 1, toY: 0.5)]
            let crowd = swarm([(200, 349)], velocities: [(6, 1)])
            let previous: [Float] = [194, 347]
            previous.withUnsafeBufferPointer { was in
                SwarmDrawnWorld.applyWalls(
                    walls,
                    to: crowd,
                    previousPositions: was.baseAddress,
                    settings: WallSettings(bounciness: 0.2, friction: friction, thickness: 3),
                    width: 400,
                    height: 700
                )
            }
            return Double(crowd.velocities[0])
        }
        #expect(slidingSpeed(friction: 0.8) < slidingSpeed(friction: 0))
    }

    @Test("Bounciness decides how much comes back")
    func wallBouncinessBites() {
        func reboundSpeed(bounciness: Double) -> Double {
            let walls = [ParticleWall(fromX: 0, fromY: 0.5, toX: 1, toY: 0.5)]
            let crowd = swarm([(200, 352)], velocities: [(0, 10)])
            let previous: [Float] = [200, 340]
            previous.withUnsafeBufferPointer { was in
                SwarmDrawnWorld.applyWalls(
                    walls,
                    to: crowd,
                    previousPositions: was.baseAddress,
                    settings: WallSettings(bounciness: bounciness, friction: 0, thickness: 3),
                    width: 400,
                    height: 700
                )
            }
            return abs(Double(crowd.velocities[1]))
        }
        #expect(reboundSpeed(bounciness: 1) > reboundSpeed(bounciness: 0.2))
        #expect(reboundSpeed(bounciness: 0) < 0.01, "no bounce should mean no rebound")
    }

    @Test("Walls work with nothing remembered about where bodies were")
    func wallsWorkWithoutHistory() {
        // The remembered positions are only kept when there are walls, so the very first tick after one is
        // drawn has none — and that tick must not let everything through.
        let walls = [ParticleWall(fromX: 0, fromY: 0.5, toX: 1, toY: 0.5)]
        let crowd = swarm([(200, 351)], velocities: [(0, 5)])
        SwarmDrawnWorld.applyWalls(
            walls, to: crowd, previousPositions: nil, settings: .default, width: 400, height: 700
        )
        for index in 0 ..< crowd.count {
            #expect(Double(crowd.positions[index * 2]).isFinite)
            #expect(Double(crowd.velocities[index * 2]).isFinite)
        }
    }

    @Test("Walls are capped, and the oldest goes")
    func wallsAreCapped() {
        // Every body is tested against every wall, so this is the number that decides whether walls are
        // affordable at all.
        let field = ParticleEngine(width: 400, height: 700, seed: 1)
        for index in 0 ..< (SwarmDrawnWorld.wallLimit + 40) {
            let at = Double(index) / Double(SwarmDrawnWorld.wallLimit + 40)
            field.addWall(fromFractionX: 0.1, y: at, toFractionX: 0.9, y: at)
        }
        #expect(field.walls.count == SwarmDrawnWorld.wallLimit)
        // The last one drawn must have survived — dropping the newest would mean drawing does nothing once
        // the list is full, which looks broken.
        #expect((field.walls.last?.fromY ?? 0) > 0.9)
    }

    @Test("Nonsense wall settings are pulled into range")
    func wallSettingsAreSanitized() {
        let broken = WallSettings(bounciness: .nan, friction: .nan, thickness: .nan).sanitized
        #expect(broken.bounciness == 0.5)
        #expect(broken.friction == 0.1)
        #expect(broken.thickness == 3)
        let huge = WallSettings(bounciness: 99, friction: 99, thickness: 99).sanitized
        #expect(huge.bounciness <= 1)
        #expect(huge.friction <= 1)
        #expect(huge.thickness <= 40)
    }

    // MARK: - Joined up with the engine

    @Test("The drawing tools change the world rather than pushing the bodies")
    func drawingToolsDoNotApplyForces() {
        // Otherwise drawing a wall would also drag every body near the line along with it.
        let drawing: Set<ParticleMouseMode> = [.current, .wall, .source]
        for mode in drawing {
            #expect(mode.drawsIntoTheWorld, "\(mode.rawValue) should draw into the world")
        }
        for mode in ParticleMouseMode.allCases where !drawing.contains(mode) {
            #expect(!mode.drawsIntoTheWorld, "\(mode.rawValue) should not draw into the world")
        }
    }

    @Test("A painted current reaches the crowd through the engine's own tick")
    func currentIsWiredToTheTick() {
        let field = ParticleEngine(width: 400, height: 700, seed: 5)
        field.setMaxParticles(40_000)
        field.gravityX = 0
        field.gravityY = 0
        field.collisionsEnabled = false
        field.spawnBatch(count: 5_000, color: PackedColor(r: 255, g: 255, b: 255))

        let before = (0 ..< 60).map { field.swarm.positions[$0 * 2 + 1] }
        field.paintCurrent(atX: 200, y: 350, directionX: 0, directionY: -1)
        field.currentSettings.strength = 3
        for _ in 0 ..< 6 { field.step() }
        let after = (0 ..< 60).map { field.swarm.positions[$0 * 2 + 1] }

        #expect(before != after, "the painted current did nothing")
        for value in after { #expect(Double(value).isFinite) }
    }

    @Test("A drawn wall stops the crowd through the engine's own tick")
    func wallsAreWiredToTheTick() {
        let field = ParticleEngine(width: 400, height: 700, seed: 5)
        field.setMaxParticles(40_000)
        field.gravityY = 1
        field.collisionsEnabled = false
        field.boundaryMode = .bounce
        field.addWall(fromFractionX: 0, y: 0.5, toFractionX: 1, y: 0.5)
        field.spawnBatch(count: 4_000, color: PackedColor(r: 255, g: 255, b: 255))

        // Everything starts in the upper half, and gravity pulls it down onto the wall.
        for index in 0 ..< field.swarm.count {
            field.swarm.positions[index * 2 + 1] = Float(20 + Double(index % 200))
            field.swarm.velocities[index * 2 + 1] = 0
        }
        for _ in 0 ..< 120 { field.step() }

        var through = 0
        for index in 0 ..< field.swarm.count where Double(field.swarm.positions[index * 2 + 1]) > 370 {
            through += 1
        }
        #expect(through == 0, "\(through) bodies got through the wall")
    }

    @Test("Clearing the field removes what was drawn into it")
    func clearingRemovesDrawings() {
        // A wall left behind across an empty world reads as a fault rather than as a leftover.
        let field = ParticleEngine(width: 400, height: 700, seed: 1)
        field.addWall(fromFractionX: 0.1, y: 0.5, toFractionX: 0.9, y: 0.5)
        field.paintCurrent(atX: 200, y: 350, directionX: 1, directionY: 0)
        #expect(!field.walls.isEmpty)
        #expect(!field.current.isEmpty)

        field.clear()
        #expect(field.walls.isEmpty)
        #expect(field.current.isEmpty)
    }

    @Test("Both survive being written down and read back")
    func typesRoundTrip() throws {
        var field = ParticleCurrentField(resolution: 16)
        field.paint(atFractionX: 0.4, y: 0.6, directionX: 1, directionY: -1, radius: 0.2, strength: 0.7)
        let fieldBytes = try JSONEncoder().encode(field)
        #expect(try JSONDecoder().decode(ParticleCurrentField.self, from: fieldBytes) == field)

        let walls = [ParticleWall(fromX: 0.1, fromY: 0.2, toX: 0.8, toY: 0.9)]
        let wallBytes = try JSONEncoder().encode(walls)
        #expect(try JSONDecoder().decode([ParticleWall].self, from: wallBytes) == walls)

        let settings = WallSettings(bounciness: 0.8, friction: 0.3, thickness: 6)
        #expect(
            try JSONDecoder().decode(WallSettings.self, from: JSONEncoder().encode(settings)) == settings
        )
        let currentSettings = CurrentSettings(strength: 2, brushRadius: 0.3, brushStrength: 0.6)
        #expect(
            try JSONDecoder().decode(
                CurrentSettings.self, from: JSONEncoder().encode(currentSettings)
            ) == currentSettings
        )
    }
}
