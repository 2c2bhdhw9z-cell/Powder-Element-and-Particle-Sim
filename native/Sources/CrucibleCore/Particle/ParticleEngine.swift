/// The particle field: free-moving bodies, springs, and a million-body swarm.
///
/// The other half of the lab. Where the powder world is a fixed grid of cells that
/// swap places, this is a list of bodies with positions and velocities that push and
/// pull on each other.
///
/// ## Two stores, on purpose
///
/// ``particles`` holds object bodies — each one carries a dozen properties and can
/// be a black hole, a cloth corner, or part of a helix. ``swarm`` holds bodies that
/// are only a position, a velocity and a colour, of which there may be a million.
/// Keeping them separate lets each be stored the way it wants to be.
///
/// ## Removal goes through one door
///
/// Springs remember the particles they join by position in the list, so anything
/// that removes or reorders particles has to keep them in step. In the web
/// implementation six separate places filtered or sliced the list directly, and
/// every spring below a removal silently re-attached to a different pair — which
/// sheared cloth and fed energy into the scene on every later frame. Here every
/// removal goes through ``removeParticles(where:)``.
public final class ParticleEngine {
    // MARK: - Contents

    /// The object bodies.
    ///
    /// Writable inside the engine only. Springs remember the bodies they join by
    /// position in this list, so anything that shortens or reorders it has to go
    /// through ``removeParticles(where:)``; nothing outside the engine may touch it at
    /// all.
    public internal(set) var particles: [ParticleObject] = []
    /// Distance constraints between pairs of ``particles``, by index.
    public internal(set) var springs: [Spring] = []
    /// The high-count body store.
    public let swarm: Swarm

    // MARK: - World

    public private(set) var width: Double
    public private(set) var height: Double

    public var gravityX: Double = 0
    public var gravityY: Double = 0.3
    /// Air friction, applied to everything that does not ignore gravity.
    public var damping: Double = 0.99
    /// How much speed survives a bounce off the world's edge.
    public var elasticity: Double = 0.8
    /// Strength of the attraction and repulsion between charged bodies.
    public var electrostaticFactor: Double = 100
    /// Strength of a swirl about the centre of the world. Zero disables it.
    public var vortexForce: Double = 0
    /// Global speed limit.
    ///
    /// Applies to every body, object and swarm alike. In the web implementation the
    /// clamp sat inside the branch for orbital particles, so it only ever reached
    /// them: every ordinary particle was uncapped despite the interface offering one
    /// slider, and the swarm had no limit at all. Uncapped speed is also what let
    /// bodies cross a whole world in a single tick and escape a wrapping boundary.
    public var maxSpeed: Double = 30
    public var boundaryMode: ParticleBoundaryMode = .bounce

    // MARK: - Input

    public var mouseMode: ParticleMouseMode = .attract
    public var mouseRadius: Double = 120
    public var mouseForceMultiplier: Double = 1.0
    public private(set) var lastMouseX: Double = 0
    public private(set) var lastMouseY: Double = 0
    /// How far into the screen the finger was last, in a field with depth: the depth of the place under it
    /// that tools like the emitter put things at. Nought on a flat field.
    public private(set) var lastMouseZ: Double = 0
    public private(set) var lastMouseActive: Bool = false
    /// Where the finger points, in a field with depth. Set by the app from its camera before each moment
    /// while a finger is down, since only the camera knows where the eye is. Ignored on a flat field.
    ///
    /// When nothing has set it, a finger at a place is taken as looking straight at the box from the front.
    public var fingerRay: ParticleFingerRay?
    /// The line this moment's tools act along: the one set, or the straight-on one. Nothing while no finger is
    /// down, or on a flat field.
    var activeFingerRay: ParticleFingerRay?

    // MARK: - Presentation and limits

    public var colorMode: ParticleColorMode = .native
    /// Whether ``palette`` replaces the hue arithmetic that ``colorMode`` would otherwise use.
    ///
    /// Off by default. The six modes were built as hue sums — speed times twenty subtracted from
    /// 240, position modulo 360 — which gives six looks and no room for a seventh. A palette keeps
    /// what each mode *means* and changes which colours say it.
    public var paletteEnabled: Bool = false
    /// What is drawn behind the field. Reached through ``backdrop``.
    var storedBackdrop: ParticleBackdrop = .none
    /// How brightly that is drawn. Reached through ``backdropStrength``.
    var storedBackdropStrength: Double = 1
    /// How brightly the field glows. Reached through ``glow``.
    var storedGlow: ParticleGlow = .default
    /// Which colours the field is drawn in when ``paletteEnabled`` is set.
    public var palette: ParticlePaletteSpec = .default
    /// What silhouette bodies are drawn as.
    ///
    /// A disc by default, which is what the field has always drawn. The other nine are additions: a
    /// field of sparks, of rings or of confetti reads completely differently, and none of those can be
    /// had from a circle.
    public var particleShape: ParticleShape = .circle
    /// Drawn radius for bodies that do not specify one.
    public var particleSize: Double = 2
    /// Upper bound on the whole field, objects and swarm together.
    ///
    /// The web implementation applied this to each store independently, so the two
    /// together could exceed it, and lowering it trimmed only the objects.
    public private(set) var maxParticles: Int = 1_000_000
    public var showTrails: Bool = true
    /// When greater than zero, bodies without a lifetime are given one.
    public var decaySpeed: Double = 0

    public var collisionsEnabled: Bool = true
    /// Whether boids-style flocking runs.
    public var flockEnabled: Bool = false

    /// Whether the swarm behaves like a liquid — crowding turned into pressure, plus thickness and a
    /// surface. See ``SwarmFluid``.
    ///
    /// This and ``nbodyEnabled`` were reserved for a long time: the interface showed both, scenes saved
    /// both, clearing the field reset both, and no physics read either. They do something now.
    public var fluidEnabled: Bool = false
    /// How the liquid behaves.
    public var fluidSettings: SwarmFluid.Settings = .default
    /// Whether every body in the swarm pulls on every other. See ``SwarmGravity``.
    public var nbodyEnabled: Bool = false
    /// How strong that pull is.
    public var bodyGravitySettings: SwarmGravity.Settings = .default

    /// Whether the liquid found more bodies in one place than it can represent.
    ///
    /// Past that point the crowding is under-counted, so the fluid reads as thinner than it is and stops
    /// holding itself apart. Reported so the interface can say so rather than quietly showing something
    /// wrong — which is what the reference implementation does.
    public var fluidIsOverCrowded: Bool { fluid.isOverCrowded }

    /// Which arrangement the field is showing. Reached through ``arrangement``.
    var storedArrangement: String?
    /// Moments since the arrangement was laid out, for the ones that keep doing something — a storm that
    /// strikes again, a fireworks display that keeps launching.
    var arrangementAge: Int = 0
    /// The ramp baked into a table, and what it was baked from, so drawing does not rebake it every frame.
    var cachedLookup: [UInt32] = []
    var cachedLookupKey: ParticlePaletteSpec?
    /// Where the ramp's colours are worked out before fading, kept between frames.
    var drawColorScratch: [UInt32] = []
    /// Whether sources pour bodies that join the arrangement. Reached through ``joinsArrangement``.
    var storedJoinsArrangement = false
    /// Whether bodies added to an arrangement take the size of its own bodies. Reached through
    /// ``matchesArrangementSize``.
    var storedMatchesArrangementSize = true
    /// The screen the field is shown on, in the world's pixels. Reached through ``screenWidth`` and
    /// ``screenHeight``; nought means the whole world.
    var storedScreenWidth = 0.0
    var storedScreenHeight = 0.0
    /// Whether the field is in 3D. Reached through ``depthEnabled``; changed through ``setDepthEnabled(_:)``,
    /// which also rebuilds what is showing in its other form.
    var storedDepthEnabled = false
    /// How deep the box is, as a share of the world's shorter side. Reached through ``depthRatio``.
    var storedDepthRatio = 1.0
    /// The liquid and the pull between bodies, as they work in depth. See `SwarmDepth.swift`.
    let depthFluid = SwarmDepthFluid()
    let depthGravity = SwarmDepthGravity()

    /// Sources pouring into the world. Reached through ``emitters``.
    var storedEmitters: [ParticleEmitter] = []
    /// What a newly placed source will be like. Reached through ``emitterTemplate``.
    var storedEmitterTemplate = ParticleEmitter(atFractionX: 0.5, atFractionY: 0.15)

    /// Wind painted into the world. Reached through ``current``.
    var storedCurrent = ParticleCurrentField()
    /// How hard it pushes. Reached through ``currentSettings``.
    var storedCurrentSettings: CurrentSettings = .default
    /// Walls drawn into the world. Reached through ``walls``.
    var storedWalls: [ParticleWall] = []
    /// How they behave. Reached through ``wallSettings``.
    var storedWallSettings: WallSettings = .default

    /// Where every swarm body was before the last move, for catching a body that has crossed a wall.
    ///
    /// Only kept when there are walls to check against. At a million bodies this is eight megabytes, and
    /// carrying it for a field with no walls in it would be eight megabytes copied every tick for nothing.
    var previousSwarmPositions: [Float] = []

    /// How bodies steer by their neighbours. Reached through ``flockSettings``.
    var storedFlockSettings: FlockSettings = .default
    /// How motion trails behave. Reached through ``trailSettings``.
    var storedTrailSettings: TrailSettings = .default
    /// How bodies in the crowd meet one another. Reached through ``contactSettings``.
    var storedContactSettings: ContactSettings = .default

    /// The recorded changes over time. Reached through ``timeline``.
    var storedTimeline = ParticleTimeline()
    /// Where those have got to. Reached through ``playhead``.
    var storedPlayhead = ParticlePlayhead()

    /// Whether the wind blows. Reached through ``flowEnabled``.
    var storedFlowEnabled: Bool = false
    /// How the wind behaves. Reached through ``flowSettings``.
    var storedFlowSettings: SwarmFlow.Settings = .default

    /// A force somebody wrote, for the sideways direction.
    ///
    /// Empty means no force, which is what an empty box in the interface should mean.
    public var writtenForceAcross: ParticleForceExpression = .blank
    /// The same, for the vertical direction.
    public var writtenForceDown: ParticleForceExpression = .blank
    /// How hard a written force pushes.
    public var writtenForceStrength: Double = 1

    /// How long the field has been running, in seconds.
    ///
    /// Counted from the ticks rather than read from a clock, because the engine deliberately has no clock
    /// — and because a written force that reads the time has to see it advance in step with the physics
    /// rather than with the wall, or a paused field would still have a moving force acting on it.
    public private(set) var elapsedSeconds: Double = 0

    /// The liquid's working state. Held here so its buffers survive between ticks.
    let fluid = SwarmFluid()
    /// The wind's working state.
    let flow = SwarmFlow()
    /// The written force's working state.
    let writtenForce = SwarmCustomForce()
    /// The pull's working state, likewise.
    let bodyGravity = SwarmGravity()

    /// Called at the end of every tick, so the app can sample telemetry.
    public var onAfterStep: (() -> Void)?

    /// The random stream. Owned by the engine so a field plus a seed replays exactly.
    public var rng: Mulberry32

    // MARK: - Internals

    /// Source of particle identifiers.
    ///
    /// Monotonic and never reused. The web implementation built batch identifiers from
    /// the list's length plus a loop counter, and since the length grew with each push
    /// they skipped values and collided outright between two batches.
    private var nextSerial: Int = 0

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private let maximumUndoSteps = 20
    /// Set while a change made of several steps is under way. See ``pushUndo()``.
    var undoSuppressed = false

    // MARK: - Lifetime

    public init(width: Double = 800, height: Double = 600, seed: UInt32? = nil) {
        self.width = max(0, width)
        self.height = max(0, height)
        self.rng = seed.map(Mulberry32.init(seed:)) ?? Mulberry32()
        // The swarm draws from this engine's stream rather than one of its own, so the
        // whole field replays from a single seed.
        self.swarm = Swarm()
    }

    /// How many bodies exist in total.
    public var bodyCount: Int {
        particles.count + swarm.count
    }

    /// Changes the world size. Contents keep their positions.
    public func resize(width newWidth: Double, height newHeight: Double) {
        let safeWidth = max(0, newWidth)
        let safeHeight = max(0, newHeight)
        if safeWidth == width && safeHeight == height { return }
        width = safeWidth
        height = safeHeight
    }

    /// Changes the size of the world, keeping whatever is in it where it looks.
    ///
    /// The plain resize above leaves every body at the coordinates it had, which is right when the screen
    /// itself has changed shape — the world and the view are the same thing then, so a body at the middle
    /// of the old view should end up at the same place in pixels.
    ///
    /// It is wrong when the world is deliberately *grown* to make more room, which is what zooming out
    /// does. Left alone, everything would stay bunched in the top-left corner of the new larger world while
    /// the empty space appeared below and to the right. Everything is shifted by half the growth instead,
    /// so the scene stays in the middle and the new room appears evenly all round it — which is what
    /// "zoom out for more space" has to mean to be any use.
    public func resizeKeepingContentsCentred(width newWidth: Double, height newHeight: Double) {
        let safeWidth = max(0, newWidth)
        let safeHeight = max(0, newHeight)
        guard safeWidth > 0, safeHeight > 0 else { return }
        if safeWidth == width && safeHeight == height { return }

        let shiftX = (safeWidth - width) * 0.5
        let shiftY = (safeHeight - height) * 0.5
        let oldWidth = width
        let oldHeight = height
        width = safeWidth
        height = safeHeight

        // What was drawn into the world is kept in fractions of it, so it has to be refitted or it would
        // stretch out across the new room while the bodies it was drawn for stayed in the middle: a wall
        // drawn under a pile of bodies would end up somewhere else entirely.
        if oldWidth > 0, oldHeight > 0 {
            func across(_ fraction: Double) -> Double { (fraction * oldWidth + shiftX) / safeWidth }
            func down(_ fraction: Double) -> Double { (fraction * oldHeight + shiftY) / safeHeight }
            func refit(_ walls: [ParticleWall]) -> [ParticleWall] {
                walls.map { wall in
                    ParticleWall(
                        fromX: across(wall.fromX), fromY: down(wall.fromY), toX: across(wall.toX), toY: down(wall.toY)
                    )
                }
            }
            func refit(_ emitters: [ParticleEmitter]) -> [ParticleEmitter] {
                emitters.map { emitter in
                    var moved = emitter
                    moved.atFractionX = across(emitter.atFractionX)
                    moved.atFractionY = down(emitter.atFractionY)
                    return moved
                }
            }
            func refit(_ current: ParticleCurrentField) -> ParticleCurrentField {
                current.refitted(
                    fromWidth: oldWidth,
                    fromHeight: oldHeight,
                    toWidth: safeWidth,
                    toHeight: safeHeight,
                    shiftX: shiftX,
                    shiftY: shiftY
                )
            }
            storedWalls = refit(storedWalls)
            storedEmitters = refit(storedEmitters)
            storedCurrent = refit(storedCurrent)

            // And every point undo and redo can go back to, which were all written in the old world's places.
            // Left as they were, undoing after zooming out brought the field back up and to the left of the
            // middle — where it had been in the smaller world — and after zooming in, partly outside it.
            func recentred(_ snapshot: Snapshot) -> Snapshot {
                var moved = snapshot
                moved.particles = snapshot.particles.map { body in
                    var shifted = body
                    shifted.x += shiftX
                    shifted.y += shiftY
                    if let originX = body.originX { shifted.originX = originX + shiftX }
                    if let originY = body.originY { shifted.originY = originY + shiftY }
                    shifted.trail.removeAll()
                    return shifted
                }
                moved.swarm?.translate(dx: shiftX, dy: shiftY)
                moved.walls = refit(snapshot.walls)
                moved.emitters = refit(snapshot.emitters)
                moved.current = refit(snapshot.current)
                return moved
            }
            if !undoStack.isEmpty { undoStack = undoStack.map(recentred) }
            if !redoStack.isEmpty { redoStack = redoStack.map(recentred) }
        }

        guard shiftX != 0 || shiftY != 0 else { return }
        for index in particles.indices {
            particles[index].x += shiftX
            particles[index].y += shiftY
            // Anything anchored to a place has to follow, or a lattice snaps back to where the world used
            // to be the moment it is touched.
            if let originX = particles[index].originX { particles[index].originX = originX + shiftX }
            if let originY = particles[index].originY { particles[index].originY = originY + shiftY }
            // And the remembered positions, or every body draws a trail from where it used to be to where
            // it now is — one long streak across the field on the frame the world changed size.
            particles[index].trail.removeAll()
        }
        swarm.translate(dx: shiftX, dy: shiftY)
    }

    /// Empties the field and returns its settings to their defaults.
    ///
    /// The settings matter as much as the contents. The web implementation left
    /// gravity, the vortex, the decay rate and the boundary rule exactly as the
    /// previous preset had set them — and since only one of fourteen presets sets the
    /// vortex explicitly, switching from a swirling scene into a calm one left it
    /// spinning. "Clear" meant different things depending on what came before it.
    public func clear() {
        pushUndo()
        particles.removeAll(keepingCapacity: true)
        springs.removeAll(keepingCapacity: true)
        swarm.removeAll()
        // Both of these are things somebody drew, so clearing the field has to clear them too — a wall left
        // behind across an empty world is the kind of thing that reads as a fault rather than as a leftover.
        storedWalls = []
        storedCurrent.clear()
        storedEmitters.removeAll()
        storedArrangement = nil
        arrangementAge = 0
        // A recording left playing would overwrite, on the very next moment, whatever the field is about to
        // be set up as. Paused rather than deleted: it is somebody's work.
        storedPlayhead.isPlaying = false
        flockEnabled = false
        nbodyEnabled = false
        fluidEnabled = false
        vortexForce = 0
        decaySpeed = 0
        boundaryMode = .bounce
    }

    // MARK: - Adding and removing

    /// Adds a body, evicting the oldest if the field is already full.
    @discardableResult
    public func addParticle(
        x: Double? = nil,
        y: Double? = nil,
        velocityX: Double? = nil,
        velocityY: Double? = nil,
        radius: Double? = nil,
        mass: Double = 1,
        charge: Double? = nil,
        color: PackedColor? = nil,
        lifespan: Int? = nil,
        maxLife: Int? = nil,
        isFixed: Bool = false,
        ignoresGravity: Bool = false,
        originX: Double? = nil,
        originY: Double? = nil,
        latticeBound: Bool = false,
        helixStrand: Double? = nil,
        kind: ParticleKind = .standard,
        z: Double = 0,
        velocityZ: Double = 0,
        originZ: Double = 0
    ) -> Int {
        if bodyCount >= maxParticles, !particles.isEmpty {
            // Evicted through removeParticles so spring endpoints follow the shift.
            // Dropping the first element directly renumbered every particle and left
            // every spring pointing one place too high.
            let oldestID = particles[0].id
            removeParticles { $0.id == oldestID }
        }

        let id = nextSerial
        nextSerial += 1

        let resolvedColor = color ?? PackedColor(hue: rng.next() * 360, saturation: 0.85, lightness: 0.65)

        var particle = ParticleObject(
            id: id,
            x: x ?? width / 2,
            y: y ?? height / 2,
            velocityX: velocityX ?? (rng.next() - 0.5) * 4,
            velocityY: velocityY ?? (rng.next() - 0.5) * 4,
            // An explicit radius of zero is a legitimate value. The web implementation
            // used a truthiness test here and replaced it with a random size.
            radius: radius ?? (rng.next() * 3 + 2),
            mass: mass,
            charge: charge ?? (rng.next() > 0.5 ? 1 : -1),
            color: resolvedColor,
            lifespan: lifespan,
            maxLife: maxLife ?? lifespan,
            isFixed: isFixed,
            ignoresGravity: ignoresGravity,
            originX: originX,
            originY: originY,
            latticeBound: latticeBound,
            helixStrand: helixStrand,
            kind: kind
        )
        particle.z = z.isFinite ? z : 0
        particle.velocityZ = velocityZ.isFinite ? velocityZ : 0
        particle.originZ = originZ.isFinite ? originZ : 0
        particles.append(particle)
        return id
    }

    /// Removes every body matching the predicate, keeping springs consistent.
    ///
    /// Spring endpoints are remapped to their new positions, and any spring that lost
    /// an end is dropped. Every removal path in the engine comes through here; see the
    /// type's documentation for why.
    ///
    /// - Returns: how many bodies were removed.
    @discardableResult
    public func removeParticles(where shouldRemove: (ParticleObject) -> Bool) -> Int {
        let before = particles.count
        guard before > 0 else { return 0 }

        var remap = [Int](repeating: -1, count: before)
        var survivors: [ParticleObject] = []
        survivors.reserveCapacity(before)
        for index in 0 ..< before {
            if shouldRemove(particles[index]) { continue }
            remap[index] = survivors.count
            survivors.append(particles[index])
        }

        let removed = before - survivors.count
        guard removed > 0 else { return 0 }

        particles = survivors
        if !springs.isEmpty {
            springs = springs.compactMap { spring in
                guard spring.a >= 0, spring.a < before, spring.b >= 0, spring.b < before else { return nil }
                let a = remap[spring.a]
                let b = remap[spring.b]
                guard a >= 0, b >= 0 else { return nil }
                return Spring(a: a, b: b, rest: spring.rest, k: spring.k)
            }
        }
        return removed
    }

    /// Adds a spring between two bodies, ignoring an out-of-range request.
    public func addSpring(a: Int, b: Int, rest: Double, k: Double) {
        guard a >= 0, a < particles.count, b >= 0, b < particles.count, a != b else { return }
        springs.append(Spring(a: a, b: b, rest: rest, k: k))
    }

    /// Replaces the whole spring set, dropping anything that does not refer to a real
    /// pair of bodies.
    public func setSprings(_ next: [Spring]) {
        springs = next.filter { spring in
            spring.a >= 0 && spring.a < particles.count
                && spring.b >= 0 && spring.b < particles.count
                && spring.a != spring.b
        }
    }

    /// Sets the limit on the whole field and trims whatever now exceeds it.
    @discardableResult
    public func setMaxParticles(_ limit: Int) -> Int {
        let next = max(1000, min(Swarm.maximumCount, limit))
        maxParticles = next

        if particles.count > next {
            // Trim the newest, through removeParticles so springs stay consistent.
            let keptIDs = Set(particles.prefix(next).map(\.id))
            removeParticles { !keptIDs.contains($0.id) }
        }
        // The swarm has to respect the limit too. Lowering it from a million to a
        // thousand used to leave the swarm untouched while the diagnostics panel
        // advertised the smaller figure.
        let roomForSwarm = max(0, next - particles.count)
        if swarm.count > roomForSwarm { swarm.trim(to: roomForSwarm) }
        return next
    }

    /// Mutates a body in place.
    ///
    /// The list is deliberately not writable from outside: springs depend on its
    /// order, so it can only be changed through the methods that keep them valid.
    public func withParticle(at index: Int, _ body: (inout ParticleObject) -> Void) {
        guard index >= 0, index < particles.count else { return }
        body(&particles[index])
    }

    /// Replaces the entire body list, discarding every spring.
    ///
    /// Used when loading a scene. Springs are cleared rather than kept, because
    /// indices from another world mean nothing here — keeping them is how the web
    /// implementation ended up with springs indexing a list they were never built for.
    public func replaceParticles(_ next: [ParticleObject]) {
        particles = next
        springs.removeAll(keepingCapacity: true)
        for index in particles.indices {
            particles[index].id = nextSerial
            nextSerial += 1
        }
    }

    // MARK: - Undo

    /// One undo entry: the whole field, not just the bodies.
    ///
    /// The web implementation snapshotted only the object list, yet clearing the field
    /// takes a snapshot and then wipes the springs, the swarm and three toggles — so
    /// undoing a clear returned loose beads with no structure and an empty swarm.
    public struct Snapshot: Sendable {
        public var particles: [ParticleObject]
        public var springs: [Spring]
        public var swarm: Swarm.Snapshot?
        public var flockEnabled: Bool
        public var nbodyEnabled: Bool
        public var fluidEnabled: Bool
        public var vortexForce: Double
        public var decaySpeed: Double
        public var boundaryMode: ParticleBoundaryMode
        /// Everything below was missing, so undoing a clear brought the bodies back but left the walls,
        /// the sources and the painted wind gone — and undoing a scene that set gravity left the gravity.
        public var gravityX: Double = 0
        public var gravityY: Double = 0.3
        public var collisionsEnabled: Bool = true
        public var flowEnabled: Bool = false
        public var walls: [ParticleWall] = []
        public var emitters: [ParticleEmitter] = []
        public var current: ParticleCurrentField = ParticleCurrentField()
        public var arrangement: String?
        public var arrangementAge: Int = 0
        /// Whether the field was in 3D, so undoing the switch puts the field back the way it was and not
        /// flat bodies in a 3D box.
        public var depthEnabled: Bool = false
    }

    /// Largest swarm that is worth copying into an undo entry.
    ///
    /// Copying a million bodies on every brush stroke would cost more than the feature
    /// is worth, so above this the swarm is left out and an undo restores the bodies
    /// and structure but not the crowd.
    private static let undoSwarmLimit = 200_000

    private func makeSnapshot() -> Snapshot {
        Snapshot(
            particles: particles,
            springs: springs,
            swarm: swarm.count > 0 && swarm.count <= Self.undoSwarmLimit ? swarm.snapshot() : nil,
            flockEnabled: flockEnabled,
            nbodyEnabled: nbodyEnabled,
            fluidEnabled: fluidEnabled,
            vortexForce: vortexForce,
            decaySpeed: decaySpeed,
            boundaryMode: boundaryMode,
            gravityX: gravityX,
            gravityY: gravityY,
            collisionsEnabled: collisionsEnabled,
            flowEnabled: storedFlowEnabled,
            walls: storedWalls,
            emitters: storedEmitters,
            current: storedCurrent,
            arrangement: storedArrangement,
            arrangementAge: arrangementAge,
            depthEnabled: storedDepthEnabled
        )
    }

    private func apply(_ snapshot: Snapshot) {
        particles = snapshot.particles
        springs = snapshot.springs
        flockEnabled = snapshot.flockEnabled
        nbodyEnabled = snapshot.nbodyEnabled
        fluidEnabled = snapshot.fluidEnabled
        vortexForce = snapshot.vortexForce
        decaySpeed = snapshot.decaySpeed
        boundaryMode = snapshot.boundaryMode
        gravityX = snapshot.gravityX
        gravityY = snapshot.gravityY
        collisionsEnabled = snapshot.collisionsEnabled
        storedFlowEnabled = snapshot.flowEnabled
        storedWalls = snapshot.walls
        storedEmitters = snapshot.emitters
        storedCurrent = snapshot.current
        storedArrangement = snapshot.arrangement
        arrangementAge = snapshot.arrangementAge
        storedDepthEnabled = snapshot.depthEnabled
        if let swarmSnapshot = snapshot.swarm {
            swarm.restore(from: swarmSnapshot, budget: max(0, maxParticles - particles.count))
        } else {
            swarm.removeAll()
        }
    }

    /// Records the current field as an undo point. Call before mutating.
    public func pushUndo() {
        // While one change is being made of several steps — turning 3D on rebuilds the arrangement, which
        // clears the field — only its first point is kept, so undo takes it back in one press.
        guard !undoSuppressed else { return }
        // Cleared first, so a failure while capturing cannot leave a redo entry
        // describing a future that never happened.
        redoStack.removeAll(keepingCapacity: true)
        undoStack.append(makeSnapshot())
        if undoStack.count > maximumUndoSteps { undoStack.removeFirst() }
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    @discardableResult
    public func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(makeSnapshot())
        if redoStack.count > maximumUndoSteps { redoStack.removeFirst() }
        apply(previous)
        return true
    }

    @discardableResult
    public func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(makeSnapshot())
        if undoStack.count > maximumUndoSteps { undoStack.removeFirst() }
        apply(next)
        return true
    }

    public func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    // MARK: - The tick

    /// Advances the field one tick.
    ///
    /// - Parameters:
    ///   - mouseX: Where the finger is, if it is down.
    ///   - mouseY: Where the finger is, if it is down.
    ///   - mouseActive: Whether the finger is down.
    ///   - now: Current time in milliseconds, used only by the painter tool to cycle
    ///     its hue. Supplied by the caller because the engine has no clock of its own
    ///     — a simulation that reads the wall clock cannot be replayed.
    public func step(mouseX: Double? = nil, mouseY: Double? = nil, mouseActive: Bool = false, now: Double = 0) {
        var mouseX = mouseX
        var mouseY = mouseY
        // In depth, the place under the finger is where its line reaches the middle of what is being looked
        // at, which the ray carries. Tools that put something at a place — the emitter, the drawing tools —
        // use that; the tools that push use the whole line.
        activeFingerRay = nil
        if storedDepthEnabled, mouseActive {
            if let ray = fingerRay {
                activeFingerRay = ray
            } else if let mouseX, let mouseY {
                activeFingerRay = .straightIn(x: mouseX, y: mouseY, fromDepth: -halfDepth - 10)
            }
            if let ray = activeFingerRay {
                let cursor = ray.cursor
                mouseX = cursor.x
                mouseY = cursor.y
                lastMouseZ = cursor.z
            }
        } else if !storedDepthEnabled {
            lastMouseZ = 0
        }
        if let mouseX { lastMouseX = mouseX }
        if let mouseY { lastMouseY = mouseY }
        lastMouseActive = mouseActive

        // A sixtieth of a second per tick, which is what the field's numbers are tuned around — the step
        // has no time in it at all, so one tick *is* the unit of time here. Counted rather than read from
        // a clock, so a written force or a wind that reads the time advances in step with the physics
        // rather than with the wall.
        elapsedSeconds += 1.0 / 60.0

        // Before the forces, so a moment's physics uses the settings the timeline has just chosen for it
        // rather than the previous moment's.
        advanceTimeline()

        // Whatever the arrangement does by itself — a storm striking again, another shell going up.
        stepArrangement()

        if mouseActive, mouseMode == .emitter, let mouseX, let mouseY {
            if storedDepthEnabled {
                spawnEmitterInDepth(at: mouseX, y: mouseY, z: lastMouseZ)
            } else {
                spawnEmitter(at: mouseX, y: mouseY)
            }
        }

        // In 3D, passes of their own — see `ParticleStepDepth.swift` for why they are kept apart.
        if !particles.isEmpty {
            if storedDepthEnabled {
                stepParticlesInDepth(mouseActive: mouseActive, now: now)
                stepSpringsInDepth()
                if flockEnabled { stepFlockInDepth() }
            } else {
                stepParticles(mouseX: mouseX, mouseY: mouseY, mouseActive: mouseActive, now: now)
                stepSprings()
                if flockEnabled { stepFlock() }
            }
        }

        // Before the crowd moves, so a body poured this moment is carried along by this moment's forces
        // rather than sitting still for one frame and then starting.
        if storedDepthEnabled { stepEmittersInDepth() } else { stepEmitters() }

        // Before the swarm moves, so the walls can tell which side of themselves each body came from.
        rememberSwarmPositions()
        if storedDepthEnabled {
            stepSwarmInDepth(mouseActive: mouseActive, now: now)
        } else {
            stepSwarm(mouseX: mouseX, mouseY: mouseY, mouseActive: mouseActive, now: now)
        }

        // The colour ramp is no longer painted into the crowd here: it is worked out as each picture is
        // drawn, so the bodies keep their own colours. See `fillSwarmDrawColors`.

        onAfterStep?()
    }
}
