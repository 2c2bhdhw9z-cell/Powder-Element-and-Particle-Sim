import CrucibleCore
import Observation
import SwiftUI

/// Owns the particle field and drives it forward.
///
/// The counterpart to `SimulationModel`, which owns the powder grid. They are kept apart
/// because they have almost nothing in common: one is a grid of cells stepped bottom-up, the
/// other a list of bodies with forces between them, and the only thing they share is that
/// something has to tick them and draw them.
@MainActor
@Observable
final class ParticleFieldModel {
    /// The engine keeps its own undo record, which already knows to capture the springs, the
    /// swarm and the toggles alongside the bodies — so there is nothing for this to duplicate.
    private let engine: ParticleEngine

    var isRunning = true

    /// How fast time runs. One is real time.
    var speed: Double = 1

    /// What decides each body's colour.
    var colorMode: ParticleColorMode {
        get { engine.colorMode }
        set { engine.colorMode = newValue }
    }

    /// What a touch does.
    var mouseMode: ParticleMouseMode {
        get { engine.mouseMode }
        set { engine.mouseMode = newValue }
    }

    /// How far a touch reaches.
    var mouseRadius: Double {
        get { engine.mouseRadius }
        set { engine.mouseRadius = newValue }
    }

    /// What happens at the edges of the world.
    var boundaryMode: ParticleBoundaryMode {
        get { engine.boundaryMode }
        set { engine.boundaryMode = newValue }
    }

    var gravityX: Double {
        get { engine.gravityX }
        set {
            engine.gravityX = newValue
            manualGravityX = newValue
        }
    }

    var gravityY: Double {
        get { engine.gravityY }
        set {
            engine.gravityY = newValue
            manualGravityY = newValue
        }
    }

    /// Whether the phone's tilt is currently deciding which way is down.
    private(set) var isSteeredByTilt = false

    /// Where tilt readings come from. Shared with the powder chamber — one phone, one sensor.
    var tilt: TiltSensor?

    /// Gravity as last set by hand, restored when tilt is switched off.
    ///
    /// The resting value is the field's own gentle default rather than the powder world's full
    /// strength: a field of free bodies under real gravity just falls to the floor and stops.
    private var manualGravityX: Double = 0
    private var manualGravityY: Double = 0.28

    /// Hands gravity over to the phone's tilt, or takes it back.
    ///
    /// The field gets a fraction of the tilt the powder world does, for the same reason its
    /// resting gravity is gentler. See ``TiltMapping``.
    func steer(with tilt: TiltMapping?) {
        guard let tilt else {
            if isSteeredByTilt {
                isSteeredByTilt = false
                engine.gravityX = manualGravityX
                engine.gravityY = manualGravityY
            }
            return
        }

        if !isSteeredByTilt {
            isSteeredByTilt = true
            manualGravityX = engine.gravityX
            manualGravityY = engine.gravityY
        }

        engine.gravityX = tilt.particleGravityX
        engine.gravityY = tilt.particleGravityY
    }

    /// The field as something that can be written to a file.
    func captureState() -> ParticleState {
        engine.captureState()
    }

    /// Puts a saved field back.
    ///
    /// - Returns: whether it was applied. `false` leaves the current field alone.
    @discardableResult
    func apply(_ state: ParticleState) -> Bool {
        // An undo point first, so loading the wrong scene is recoverable.
        recordUndoPoint()
        let applied = engine.apply(state)
        bodyCount = engine.bodyCount
        return applied
    }

    var showTrails: Bool {
        get { engine.showTrails }
        set { engine.showTrails = newValue }
    }

    var collisionsEnabled: Bool {
        get { engine.collisionsEnabled }
        set { engine.collisionsEnabled = newValue }
    }

    /// How wide a body is drawn, in pixels.
    var particleSize: Double {
        get { engine.particleSize }
        set { engine.particleSize = newValue }
    }

    private(set) var ticksPerSecond = 0
    private(set) var millisecondsPerTick: Double = 0
    private(set) var bodyCount = 0

    private var ticksSinceSample = 0
    private var simulationSeconds: Double = 0
    private var lastSampleTime = CFAbsoluteTimeGetCurrent()
    private var stepCredit: Double = 0

    /// Where the touch is, and whether it is down. Read by the tick.
    private var touchX: Double = 0
    private var touchY: Double = 0
    private var touchActive = false

    var canUndo: Bool { engine.canUndo }
    var canRedo: Bool { engine.canRedo }
    var worldSize: (width: Double, height: Double) { (engine.width, engine.height) }

    init() {
        engine = ParticleEngine(width: 400, height: 700)
        engine.spawnGalaxy(count: 400)
        bodyCount = engine.bodyCount
    }

    // MARK: - Time

    func tick(now: Double) {
        // Before the pause check, so tipping the phone still turns the field while time is
        // stopped. See the same note in SimulationModel.
        steer(with: tilt?.isSteering == true ? tilt?.mapping : nil)

        guard isRunning else { return }
        stepCredit += max(0, speed)
        var steps = Int(stepCredit)
        stepCredit -= Double(steps)
        // Capped so a high speed on a crowded field cannot spend an unbounded amount of time
        // inside one frame and freeze the interface.
        steps = min(steps, 6)
        guard steps > 0 else { return }

        let startedAt = CFAbsoluteTimeGetCurrent()
        for _ in 0 ..< steps {
            engine.step(
                mouseX: touchActive ? touchX : nil,
                mouseY: touchActive ? touchY : nil,
                mouseActive: touchActive,
                now: now
            )
        }
        simulationSeconds += CFAbsoluteTimeGetCurrent() - startedAt

        ticksSinceSample += steps
        let sampledAt = CFAbsoluteTimeGetCurrent()
        let elapsed = sampledAt - lastSampleTime
        if elapsed >= 1 {
            ticksPerSecond = Int((Double(ticksSinceSample) / elapsed).rounded())
            millisecondsPerTick = ticksSinceSample > 0
                ? simulationSeconds / Double(ticksSinceSample) * 1000
                : 0
            bodyCount = engine.bodyCount
            ticksSinceSample = 0
            simulationSeconds = 0
            lastSampleTime = sampledAt
        }
    }

    // MARK: - What the renderer needs

    /// Everything the renderer reads in one go, so it makes a single call per frame.
    struct Frame {
        var worldWidth: Double
        var worldHeight: Double
        var bodyCount: Int
        var springCount: Int
        var pointSize: Double
        var swarmCount: Int
        /// How many line segments of trail there are to draw. Two points and two colours each.
        var trailSegmentCount: Int
        /// Where the ring should be drawn, or nothing while no finger is down.
        var touchRing: TouchRing?
    }

    /// The ring round a finger.
    struct TouchRing {
        var x: Double
        var y: Double
        var radius: Double
        var strokeWidth: Double
        var centreDotRadius: Double
        var red: Double
        var green: Double
        var blue: Double
        var strokeOpacity: Double
        var fillOpacity: Double
    }

    /// Fills the caller's buffers and reports what it wrote.
    ///
    /// The buffers belong to the renderer, which holds them across frames so that a steady
    /// field allocates nothing. Grown here only when the field outgrows them.
    func fillFrame(
        positions: inout [Float],
        colors: inout [UInt32],
        springPositions: inout [Float],
        swarmPositions: inout [Float],
        swarmColors: inout [UInt32],
        trailPositions: inout [Float],
        trailColors: inout [UInt32]
    ) -> Frame {
        let bodies = engine.particles

        let neededPositions = bodies.count * 2
        if positions.count < neededPositions {
            positions.append(contentsOf: repeatElement(0, count: neededPositions - positions.count))
        }
        engine.fillRenderColors(into: &colors)
        for (index, body) in bodies.enumerated() {
            positions[index * 2] = Float(body.x)
            positions[index * 2 + 1] = Float(body.y)
        }

        // Two ends per spring, as a plain list of line endpoints.
        let springs = engine.springs
        let neededSprings = springs.count * 4
        if springPositions.count < neededSprings {
            springPositions.append(
                contentsOf: repeatElement(0, count: neededSprings - springPositions.count)
            )
        }
        var written = 0
        for spring in springs {
            guard spring.a < bodies.count, spring.b < bodies.count else { continue }
            springPositions[written * 4] = Float(bodies[spring.a].x)
            springPositions[written * 4 + 1] = Float(bodies[spring.a].y)
            springPositions[written * 4 + 2] = Float(bodies[spring.b].x)
            springPositions[written * 4 + 3] = Float(bodies[spring.b].y)
            written += 1
        }

        // The swarm is already stored as the GPU wants it — interleaved pairs of single
        // precision floats — so it is copied straight across rather than converted.
        let swarmCount = engine.swarm.count
        let neededSwarm = swarmCount * 2
        if swarmPositions.count < neededSwarm {
            swarmPositions.append(
                contentsOf: repeatElement(0, count: neededSwarm - swarmPositions.count)
            )
        }
        if swarmColors.count < swarmCount {
            swarmColors.append(
                contentsOf: repeatElement(0, count: swarmCount - swarmColors.count)
            )
        }
        for i in 0 ..< neededSwarm { swarmPositions[i] = engine.swarm.positions[i] }
        for i in 0 ..< swarmCount { swarmColors[i] = engine.swarm.colors[i] }

        let trailSegments = fillTrails(
            positions: &trailPositions,
            colors: &trailColors,
            bodies: bodies
        )

        return Frame(
            worldWidth: engine.width,
            worldHeight: engine.height,
            bodyCount: bodies.count,
            springCount: written,
            pointSize: max(1, engine.particleSize * 2),
            swarmCount: swarmCount,
            trailSegmentCount: trailSegments,
            touchRing: currentTouchRing()
        )
    }

    /// Turns each body's remembered positions into line segments.
    ///
    /// A segment rather than a connected strip, because one draw call cannot hold several separate
    /// polylines without either an index buffer or a restart marker — and a flat list of segments is
    /// simpler than both for something at most six points long.
    ///
    /// Only below the drawing limit, matching the reference implementation: above a thousand bodies
    /// it stops drawing shapes altogether, and a thousand trails would be thousands of lines for a
    /// picture too dense to read anyway.
    private func fillTrails(
        positions: inout [Float],
        colors: inout [UInt32],
        bodies: [ParticleObject]
    ) -> Int {
        guard engine.showTrails, bodies.count <= ParticleEngine.trailDrawingLimit else { return 0 }

        // The colour a trail is drawn in is the body's current colour under whichever colour mode is
        // selected, so a trail agrees with the thing that left it.
        let density = engine.densityGridIfNeeded()
        let opacity = UInt32(
            max(0, min(255, (ParticleOverlayStyle.trailOpacity * 255).rounded()))
        )

        var segments = 0
        for body in bodies {
            let trail = body.trail
            guard trail.count > 1 else { continue }
            // The alpha is baked into the colour rather than set as a pipeline constant, so a single
            // draw call can carry every trail.
            let packed = engine.renderColor(of: body, density: density)
            let colour = UInt32(packed.r) | (UInt32(packed.g) << 8) | (UInt32(packed.b) << 16)
                | (opacity << 24)

            for i in 1 ..< trail.count {
                guard let from = trail.point(at: i - 1), let to = trail.point(at: i) else { continue }
                let needed = (segments + 1) * 4
                if positions.count < needed {
                    positions.append(contentsOf: repeatElement(0, count: needed - positions.count))
                }
                if colors.count < (segments + 1) * 2 {
                    colors.append(
                        contentsOf: repeatElement(0, count: (segments + 1) * 2 - colors.count)
                    )
                }
                positions[segments * 4] = from.x
                positions[segments * 4 + 1] = from.y
                positions[segments * 4 + 2] = to.x
                positions[segments * 4 + 3] = to.y
                colors[segments * 2] = colour
                colors[segments * 2 + 1] = colour
                segments += 1
            }
        }
        return segments
    }

    /// The ring, while a finger is down.
    ///
    /// Its size comes from the engine, which knows the rule that stops it lying about how far the
    /// pull reaches — at the top of the range there is no limit, and a modest circle would suggest
    /// there was.
    private func currentTouchRing() -> TouchRing? {
        guard engine.lastMouseActive else { return nil }
        let colour = ParticleOverlayStyle.ringColor
        return TouchRing(
            x: engine.lastMouseX,
            y: engine.lastMouseY,
            radius: ParticleOverlayStyle.ringRadius(
                reach: engine.mouseRadius,
                worldWidth: engine.width,
                worldHeight: engine.height
            ),
            strokeWidth: ParticleOverlayStyle.ringStrokeWidth,
            centreDotRadius: ParticleOverlayStyle.ringCentreDotRadius,
            red: Double(colour.r) / 255,
            green: Double(colour.g) / 255,
            blue: Double(colour.b) / 255,
            strokeOpacity: ParticleOverlayStyle.ringStrokeOpacity,
            fillOpacity: ParticleOverlayStyle.ringFillOpacity
        )
    }

    // MARK: - Touch

    func beginTouch(atFractionX fx: Double, fractionY fy: Double) {
        recordUndoPoint()
        updateTouch(atFractionX: fx, fractionY: fy)
    }

    func updateTouch(atFractionX fx: Double, fractionY fy: Double) {
        touchX = fx * engine.width
        touchY = fy * engine.height
        touchActive = true
    }

    func endTouch() {
        touchActive = false
    }

    // MARK: - Scenes

    /// The presets, in the order the interface shows them.
    static let presets: [(id: String, name: String)] = [
        ("galaxy", "Galaxy"), ("blackhole", "Black hole"), ("vortex", "Double vortex"),
        ("flare", "Solar flare"), ("synchrotron", "Synchrotron"), ("shockwave", "Shockwave"),
        ("fountain", "Cosmic fountain"), ("waterfall", "Waterfall"), ("pour", "Pour"),
        ("lattice", "Quantum lattice"), ("helix", "DNA helix"), ("flock", "Flock"),
        ("nbody", "N-body"), ("cloth", "Cloth"), ("rope", "Rope"), ("blob", "Blob"),
        ("burst", "Burst"), ("swarm", "Swarm"),
    ]

    func loadPreset(_ id: String) {
        // Every preset but the burst clears the field first, and clearing already records an
        // undo point — so one is only needed for the two that do not.
        if id == "burst" { recordUndoPoint() }
        let count = engine.width < 500 ? 220 : 380
        switch id {
        case "galaxy": engine.spawnGalaxy(count: count)
        case "blackhole": engine.spawnBlackHole(count: count)
        case "vortex": engine.spawnDoubleVortex(count: count)
        case "flare": engine.spawnSolarFlare(count: count)
        case "synchrotron": engine.spawnSynchrotron(count: count)
        case "shockwave": engine.spawnShockwave(count: count)
        case "fountain": engine.spawnCosmicFountain(count: count)
        case "waterfall": engine.spawnWaterfall(count: count)
        case "pour": engine.spawnPour(count: count)
        case "lattice": engine.spawnQuantumLattice()
        case "helix": engine.spawnDnaHelix()
        case "flock": engine.spawnFlock()
        case "nbody": engine.spawnNbody()
        case "cloth": engine.spawnCloth()
        case "rope": engine.spawnRope()
        case "blob": engine.spawnBlob()
        case "burst": engine.spawnBurst(count: count)
        case "swarm":
            engine.clear()
            engine.spawnBatch(count: 120_000)
        default: break
        }
        bodyCount = engine.bodyCount
    }

    func clear() {
        recordUndoPoint()
        engine.clear()
        bodyCount = 0
    }

    func undo() {
        _ = engine.undo()
        bodyCount = engine.bodyCount
    }

    func redo() {
        _ = engine.redo()
        bodyCount = engine.bodyCount
    }

    private func recordUndoPoint() {
        engine.pushUndo()
    }

    // MARK: - Size

    func resize(toViewSize size: CGSize, scale: CGFloat) {
        guard size.width > 0, size.height > 0 else { return }
        // Full resolution, unlike the powder grid. The cost here is per body rather than per
        // cell, so a larger world is not a slower one — it is simply more room.
        engine.resize(width: Double(size.width * scale), height: Double(size.height * scale))
    }
}
