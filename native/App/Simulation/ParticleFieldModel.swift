import CrucibleCore
import Observation
import SwiftUI
// For UIImage, which a picture of the world is returned as.
import UIKit

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
    /// The field.
    ///
    /// Reachable from elsewhere in the app only so that `Hybrid` can bridge the two chambers — see the
    /// longer note on the powder model's. Nothing else should reach for it.
    let engine: ParticleEngine

    var isRunning = true

    /// How fast time runs. One is real time.
    var speed: Double = 1

    // MARK: - Making the engine's settings visible to the interface

    /// Bumped whenever anything the engine holds is written through this model.
    ///
    /// ## Why this has to exist
    ///
    /// Every setting below is a property that simply forwards to the engine — one place where a value
    /// lives, which is the right arrangement and is the reason a slider can never show a number the
    /// simulation is not using.
    ///
    /// But the engine is deliberately not observable. It imports nothing at all, Observation included,
    /// so that the physics compiles and is tested on any machine. And SwiftUI's observation only watches
    /// **stored** properties: a computed one that reads `engine.something` registers no dependency when
    /// it is read, and notifies nobody when it is written.
    ///
    /// The result was a settings panel that did nothing. You dragged Bounciness from one end to the
    /// other and the number beside it never moved — not because the value had not changed, but because
    /// nothing told the screen to look again. The slider's knob stayed where your finger left it, since
    /// nothing redrew it either, so it looked exactly like a control that had been ignored. Every slider
    /// in the field's panel behaved that way, and so did the choice of what happens at the edges.
    ///
    /// So this is one stored property that every one of them reads on the way in and bumps on the way
    /// out. Coarser than per-property tracking — a change to any of them refreshes anything reading any
    /// of them — which costs nothing, because all of these change only when somebody moves a control.
    ///
    /// **The per-frame paths must not go through these properties.** Tilt steering and the chamber
    /// bridges write `engine.…` directly, which is what keeps this out of the render loop.
    private(set) var engineRevision = 0

    /// Records a dependency on the engine's settings. Called by every forwarding getter.
    private func observeEngine() {
        // Reading it is the entire point: that is what registers the dependency.
        _ = engineRevision
    }

    /// Records that one of the engine's settings has changed. Called by every forwarding setter.
    private func engineDidChange() {
        engineRevision &+= 1
    }

    /// What decides each body's colour.
    var colorMode: ParticleColorMode {
        get { observeEngine(); return engine.colorMode }
        set { engine.colorMode = newValue; engineDidChange() }
    }

    /// What a touch does.
    var mouseMode: ParticleMouseMode {
        get { observeEngine(); return engine.mouseMode }
        set { engine.mouseMode = newValue; engineDidChange() }
    }

    /// How far a touch reaches.
    var mouseRadius: Double {
        get { observeEngine(); return engine.mouseRadius }
        set { engine.mouseRadius = newValue; engineDidChange() }
    }

    /// What happens at the edges of the world.
    var boundaryMode: ParticleBoundaryMode {
        get { observeEngine(); return engine.boundaryMode }
        set { engine.boundaryMode = newValue; engineDidChange() }
    }

    var gravityX: Double {
        get { observeEngine(); return engine.gravityX }
        set {
            engine.gravityX = newValue
            manualGravityX = newValue
            engineDidChange()
        }
    }

    var gravityY: Double {
        get { observeEngine(); return engine.gravityY }
        set {
            engine.gravityY = newValue
            manualGravityY = newValue
            engineDidChange()
        }
    }

    /// Whether the phone's tilt is currently deciding which way is down.
    private(set) var isSteeredByTilt = false

    /// Where tilt readings come from. Shared with the powder chamber — one phone, one sensor.
    var tilt: TiltSensor?

    /// Something else to step whenever this one steps. See the note on the powder model's.
    var alsoStep: (@MainActor () -> Void)?

    /// Whether a step is already under way.
    ///
    /// Insurance rather than a mechanism. Only one chamber is ever given a companion, but if both
    /// were, they would step each other back and forth until the app hung — and a wiring mistake
    /// should not be able to do that.
    private var isStepping = false

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

    /// How much speed survives each moment. One is frictionless; below about 0.97 the field
    /// visibly congeals.
    var damping: Double {
        get { observeEngine(); return engine.damping }
        set { engine.damping = newValue; engineDidChange() }
    }

    /// How much of its speed a body keeps when it bounces off a wall.
    var elasticity: Double {
        get { observeEngine(); return engine.elasticity }
        set { engine.elasticity = newValue; engineDidChange() }
    }

    /// How strongly charged bodies push and pull on one another.
    var electrostaticFactor: Double {
        get { observeEngine(); return engine.electrostaticFactor }
        set { engine.electrostaticFactor = newValue; engineDidChange() }
    }

    /// A whole-field swirl. Negative spins the other way.
    var vortexForce: Double {
        get { observeEngine(); return engine.vortexForce }
        set { engine.vortexForce = newValue; engineDidChange() }
    }

    /// The fastest anything may travel, which is what stops a close encounter flinging a body off
    /// the screen.
    var maxSpeed: Double {
        get { observeEngine(); return engine.maxSpeed }
        set { engine.maxSpeed = newValue; engineDidChange() }
    }

    /// How hard a finger pulls or pushes.
    var mouseForceMultiplier: Double {
        get { observeEngine(); return engine.mouseForceMultiplier }
        set { engine.mouseForceMultiplier = newValue; engineDidChange() }
    }

    /// How quickly bodies with a lifespan fade away. Zero means they never do.
    var decaySpeed: Double {
        get { observeEngine(); return engine.decaySpeed }
        set { engine.decaySpeed = newValue; engineDidChange() }
    }

    /// Whether the reach is effectively unlimited, so the interface can say so rather than showing a
    /// number that suggests a boundary.
    var hasUnlimitedReach: Bool {
        observeEngine()
        return ParticleOverlayStyle.isUnlimited(reach: engine.mouseRadius)
    }

    /// Where a picture of the field comes from.
    ///
    /// Set by the Metal view when it appears, because the field is drawn as real geometry on the GPU
    /// — discs, trails, springs and the ring — and none of that exists anywhere the simulation can
    /// reach. The powder chamber needs no such arrangement: its renderer produces finished pixels,
    /// so a picture of it can be made from the engine alone.
    ///
    /// Optional, so the model works with no view attached, which is what every test does.
    /// Marked as belonging to the main actor, because drawing is: the closure reaches a Metal view.
    /// Left unannotated, a stored closure could in principle be called from anywhere.
    var snapshotProvider: (@MainActor () -> UIImage?)?

    /// A picture of the field exactly as it appears, or nothing if there is no view to ask.
    func snapshot() -> UIImage? {
        snapshotProvider?()
    }

    /// Lays out the arrangement everybody gets today.
    ///
    /// - Returns: its name.
    @discardableResult
    func loadDailyArrangement(day: String) -> String {
        recordUndoPoint()
        let choice = DailyWorld.applyParticle(forDay: day, to: engine)
        bodyCount = engine.bodyCount
        return choice.name
    }

    var showTrails: Bool {
        get { observeEngine(); return engine.showTrails }
        set { engine.showTrails = newValue; engineDidChange() }
    }

    /// Whether bodies behave as a fluid, pressing on one another like water.
    ///
    /// A genuinely different physics rather than a visual option — it is what makes the pouring
    /// arrangement look like water instead of like falling beads. Expensive, and off by default, which
    /// is why the arrangements that want it switch it on themselves.
    var fluidEnabled: Bool {
        get { observeEngine(); return engine.fluidEnabled }
        set { engine.fluidEnabled = newValue; engineDidChange() }
    }

    /// Whether bodies steer by their neighbours, as a flock of birds does.
    var flockEnabled: Bool {
        get { observeEngine(); return engine.flockEnabled }
        set { engine.flockEnabled = newValue; engineDidChange() }
    }

    /// Whether every body pulls on every other, as masses do.
    ///
    /// The most expensive thing here by a wide margin: the work grows with the square of the number of
    /// bodies, so it is meant for a few hundred rather than a few hundred thousand.
    var nbodyEnabled: Bool {
        get { observeEngine(); return engine.nbodyEnabled }
        set { engine.nbodyEnabled = newValue; engineDidChange() }
    }

    /// Drops a gravity well wherever the last touch was, or in the middle if there has not been one.
    ///
    /// A well is a body like any other as far as the field is concerned; it simply pulls hard enough to
    /// organise everything around it, which is the quickest way to turn a scattered field into
    /// something worth watching.
    func dropWell() {
        recordUndoPoint()
        let x = engine.lastMouseActive || engine.lastMouseX != 0 ? engine.lastMouseX : engine.width / 2
        let y = engine.lastMouseActive || engine.lastMouseY != 0 ? engine.lastMouseY : engine.height / 2
        engine.placeWell(x: x, y: y)
        bodyCount = engine.bodyCount
    }

    var collisionsEnabled: Bool {
        get { observeEngine(); return engine.collisionsEnabled }
        set { engine.collisionsEnabled = newValue; engineDidChange() }
    }

    /// How wide a body is drawn, in pixels.
    var particleSize: Double {
        get { observeEngine(); return engine.particleSize }
        set { engine.particleSize = newValue; engineDidChange() }
    }

    private(set) var ticksPerSecond = 0
    private(set) var millisecondsPerTick: Double = 0
    private(set) var bodyCount = 0

    /// A couple of minutes of readings, for the graphs.
    private(set) var rateHistory = SampleHistory()
    private(set) var costHistory = SampleHistory()
    private(set) var populationHistory = SampleHistory()
    private(set) var speedHistory = SampleHistory()

    private var ticksSinceSample = 0
    private var simulationSeconds: Double = 0
    private var lastSampleTime = CFAbsoluteTimeGetCurrent()
    private var stepCredit: Double = 0

    /// Where the touch is, and whether it is down. Read by the tick.
    private var touchX: Double = 0
    private var touchY: Double = 0
    private var touchActive = false

    var canUndo: Bool {
        observeEngine()
        return engine.canUndo
    }

    var canRedo: Bool {
        observeEngine()
        return engine.canRedo
    }

    var worldSize: (width: Double, height: Double) {
        observeEngine()
        return (engine.width, engine.height)
    }

    init() {
        engine = ParticleEngine(width: 400, height: 700)
        engine.spawnGalaxy(count: 400)
        bodyCount = engine.bodyCount
    }

    // MARK: - Time

    func tick(now: Double) {
        guard !isStepping else { return }
        isStepping = true
        defer { isStepping = false }

        // Before the pause check, so tipping the phone still turns the field while time is
        // stopped. See the same note in SimulationModel.
        steer(with: tilt?.isSteering == true ? tilt?.mapping : nil)

        // Before this chamber's own pause is honoured, so each chamber's pause means only itself. The
        // companion decides for itself whether it is running.
        alsoStep?()

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

            rateHistory.record(Double(ticksPerSecond))
            costHistory.record(millisecondsPerTick)
            populationHistory.record(Double(bodyCount))
            speedHistory.record(fastestBody)

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

    /// The limit on how many bodies the field will hold.
    ///
    /// Read-only through the engine, because lowering it has to trim what is already there — and the
    /// swarm as well as the objects, which the reference forgot.
    var maxBodies: Int {
        get { observeEngine(); return engine.maxParticles }
        set {
            engine.setMaxParticles(newValue)
            bodyCount = engine.bodyCount
            engineDidChange()
        }
    }

    /// The choices offered for the limit, as round numbers.
    static let bodyCapChoices = [50_000, 100_000, 250_000, 500_000, 1_000_000]

    /// The choices offered for how many to add at once.
    static let batchChoices = [1_000, 10_000, 50_000, 100_000, 500_000]

    /// Scatters more bodies into the field.
    ///
    /// Asks for no more than there is room for, so tapping it against the limit does nothing rather
    /// than quietly discarding most of what was asked for.
    func spawn(_ count: Int) {
        let room = max(0, engine.maxParticles - engine.bodyCount)
        guard room > 0 else { return }
        engine.spawnBatch(count: min(count, room))
        bodyCount = engine.bodyCount
    }

    /// How much room is left before the limit.
    var remainingRoom: Int {
        observeEngine()
        return max(0, engine.maxParticles - engine.bodyCount)
    }

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

    /// How fast the quickest body is travelling.
    ///
    /// Worth watching: a field that has gone unstable shows up here long before it looks wrong, as one
    /// body accelerating away while everything else carries on normally.
    private var fastestBody: Double {
        var fastest = 0.0
        for body in engine.particles {
            let speed = body.velocityX * body.velocityX + body.velocityY * body.velocityY
            if speed.isFinite { fastest = max(fastest, speed) }
        }
        return fastest.squareRoot()
    }

    /// Brings the readout back in step after something outside the tick changed the field.
    func refreshCounts() {
        bodyCount = engine.bodyCount
    }

    /// Records a point to come back to, for the chamber bridge.
    ///
    /// The private one is for this model's own actions; this is the same thing spelled out for the one
    /// outside caller that legitimately needs it, rather than opening the private one to everybody.
    func recordUndoPointForBridge() {
        recordUndoPoint()
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
