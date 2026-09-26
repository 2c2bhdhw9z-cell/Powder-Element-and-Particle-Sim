/// Saving and loading the particle field.
///
/// The same split as the powder side: the shape of the data and every validation rule live
/// here, and turning it into bytes belongs to whoever owns the file. See
/// `PowderSerialization.swift` for why.
///
/// ## Lossless, deliberately
///
/// The web reference saved a particle's position, velocity, size, colour and little else.
/// Everything left out was either re-rolled at random on load or re-derived from a guess,
/// and the effects were easy to miss and impossible to undo: charge came back scrambled,
/// so an arrangement built around attraction was ruined; pinned particles that were not
/// attractors came back loose; lifespans, origins and the lattice and helix markers were
/// dropped, so anything built to recycle or hold a shape stopped doing either. Springs were
/// omitted entirely, which meant a cloth, a rope or a blob — three of the presets — came
/// back as a handful of loose beads.
///
/// This format carries all of it. The reference has been brought up to match.

/// One body, as saved.
///
/// The short names match the web format so the two can read each other's files. Everything
/// optional is genuinely absent when omitted rather than defaulted to zero: whether a body
/// has a lifespan at all decides which branch of the tick it takes.
public struct ParticleRecord: Codable, Sendable {
    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double
    /// Radius.
    public var r: Double
    /// Colour, as a hex string.
    public var c: String
    /// Kind, omitted when standard.
    public var t: String?
    /// Mass, omitted when one.
    public var m: Double?
    /// Ignores gravity.
    public var g: Int?
    /// Charge, omitted when neutral.
    public var q: Double?
    /// Pinned in place.
    public var f: Int?
    public var life: Int?
    public var maxLife: Int?
    public var ox: Double?
    public var oy: Double?
    /// Held to its origin by the lattice preset.
    public var lat: Int?
    /// Which strand of the helix, if any.
    public var helix: Double?
}

/// A spring, as saved: two positions in the body list, a rest length and a stiffness.
public struct SpringRecord: Codable, Sendable {
    public var a: Int
    public var b: Int
    public var rest: Double
    public var k: Double
}

/// The swarm, as saved: parallel lists rather than interleaved pairs, for readability.
public struct SwarmRecord: Codable, Sendable {
    public var n: Int
    public var x: [Float]
    public var y: [Float]
    public var vx: [Float]
    public var vy: [Float]
    public var c: [UInt32]
    /// Weights. Absent when every body weighs one, which is almost always — and is four megabytes of the
    /// number one at a million bodies.
    public var m: [Float]?
    /// Lifetimes. Absent when nothing expires.
    public var life: [Float]?
    /// How long each started with, so a fading body comes back as faded as it was. Absent when nothing
    /// expires, and in files written before it was kept.
    public var maxLife: [Float]?
    /// What each body does — orbits, holds a place in a shape. Absent when no body has a role.
    public var role: [UInt8]?
    /// Where each shape-holding body belongs, seven numbers a body. Absent when no body has a role.
    public var home: [Float]?
    /// Each body's own size. Absent when none has one.
    public var size: [Float]?
}

/// A whole particle field, as saved.
public struct ParticleState: Codable, Sendable {
    public var width: Double
    public var height: Double
    public var gravityX: Double
    public var gravityY: Double
    public var damping: Double
    public var elasticity: Double
    public var vortexForce: Double
    public var maxSpeed: Double
    public var boundaryMode: String
    public var collisionsEnabled: Bool
    public var maxParticles: Int
    public var flockEnabled: Bool?
    public var nbodyEnabled: Bool?
    public var fluidEnabled: Bool?
    /// How the bodies are coloured. Optional, so files written before palettes existed still load.
    public var colorMode: String?
    /// How the liquid behaves.
    public var fluidSettings: SwarmFluid.Settings?
    /// How strong the pull between bodies is.
    public var bodyGravitySettings: SwarmGravity.Settings?
    /// Sources pouring into the world.
    public var emitters: [ParticleEmitter]?
    /// What a newly placed source will be like.
    public var emitterTemplate: ParticleEmitter?
    /// Wind painted into the world.
    public var current: ParticleCurrentField?
    /// How hard it pushes.
    public var currentSettings: CurrentSettings?
    /// Walls drawn into the world.
    public var walls: [ParticleWall]?
    /// How they behave.
    public var wallSettings: WallSettings?
    /// How bodies steer by their neighbours.
    public var flockSettings: FlockSettings?
    /// How motion trails behave.
    public var trailSettings: TrailSettings?
    /// How bodies in the crowd meet one another.
    public var contactSettings: ContactSettings?
    /// The recorded changes over time.
    public var timeline: ParticleTimeline?
    /// Whether the wind blows.
    public var flowEnabled: Bool?
    /// How the wind behaves.
    public var flowSettings: SwarmFlow.Settings?
    /// A force somebody wrote, sideways. Saved as the text, so it comes back editable rather than as
    /// something already compiled that cannot be read.
    public var writtenForceAcross: String?
    /// The same, vertically.
    public var writtenForceDown: String?
    /// How hard a written force pushes.
    public var writtenForceStrength: Double?
    /// What is drawn behind the field.
    public var backdrop: String?
    /// How brightly that is drawn.
    public var backdropStrength: Double?
    /// How brightly the field glows.
    public var glow: ParticleGlow?
    /// What silhouette bodies are drawn as.
    public var particleShape: String?
    /// Whether a colour ramp replaces the hue arithmetic.
    public var paletteEnabled: Bool?
    /// Which ramp, gradient or fade. Carried in full, including a hand-made gradient's stops —
    /// somebody who built one by hand should get it back, not a nearest named ramp.
    public var palette: ParticlePaletteSpec?
    /// Where the field was being looked at from.
    ///
    /// Saved even though it changes nothing about the simulation, because a tilt and a zoom set up to
    /// show a scene at its best are part of the scene. It lives on the interface's model rather than
    /// in the engine, so it is written and read here but applied by the caller.
    public var camera: ParticleCamera?
    /// Which arrangement the field was showing, so its chip lights up again and adding to it still joins it.
    public var arrangement: String?
    public var swarm: SwarmRecord?
    public var springs: [SpringRecord]?
    public var particles: [ParticleRecord]
}

extension ParticleEngine {
    /// How many object bodies a save file may hold.
    ///
    /// Beyond this the file becomes unwieldy for no benefit — a scene with more bodies than
    /// this is a swarm, and the swarm has its own, far more compact representation.
    public static let saveBodyLimit = 12_000
    /// How many swarm bodies a save file may hold.
    public static let saveSwarmLimit = 24_000

    /// Captures the whole field.
    public func captureState() -> ParticleState {
        let saved = particles.prefix(Self.saveBodyLimit)
        return ParticleState(
            width: width,
            height: height,
            gravityX: gravityX,
            gravityY: gravityY,
            damping: damping,
            elasticity: elasticity,
            vortexForce: vortexForce,
            maxSpeed: maxSpeed,
            boundaryMode: boundaryMode.rawValue,
            collisionsEnabled: collisionsEnabled,
            maxParticles: maxParticles,
            flockEnabled: flockEnabled,
            nbodyEnabled: nbodyEnabled,
            fluidEnabled: fluidEnabled,
            colorMode: colorMode.rawValue,
            fluidSettings: fluidSettings,
            bodyGravitySettings: bodyGravitySettings,
            // Only written when there is something to write, so a scene with nothing drawn into it does not
            // carry a few thousand zeroes around.
            emitters: emitters.isEmpty ? nil : emitters,
            emitterTemplate: emitterTemplate,
            current: current.isEmpty ? nil : current,
            currentSettings: currentSettings,
            walls: walls.isEmpty ? nil : walls,
            wallSettings: wallSettings,
            flockSettings: flockSettings,
            trailSettings: trailSettings,
            contactSettings: contactSettings,
            timeline: timeline.isEmpty ? nil : timeline,
            flowEnabled: flowEnabled,
            flowSettings: flowSettings,
            writtenForceAcross: writtenForceAcross.source,
            writtenForceDown: writtenForceDown.source,
            writtenForceStrength: writtenForceStrength,
            backdrop: backdrop.rawValue,
            backdropStrength: backdropStrength,
            glow: glow,
            particleShape: particleShape.rawValue,
            paletteEnabled: paletteEnabled,
            palette: palette,
            // Filled in by the caller, which is where the camera lives. Left empty here rather than
            // given a default, so "no camera was saved" and "the camera was in its resting position"
            // stay distinguishable.
            camera: nil,
            arrangement: storedArrangement,
            swarm: swarm.count > 0 ? swarmRecord(limit: Self.saveSwarmLimit) : nil,
            // Only springs whose two ends both survived the cap, since a position past the
            // end of what was written is exactly the stale index that makes a reloaded
            // scene shear itself apart.
            springs: springs
                .filter { $0.a < saved.count && $0.b < saved.count }
                .map { SpringRecord(a: $0.a, b: $0.b, rest: $0.rest, k: $0.k) },
            // Every number made writable on the way out. A save file is text, and text has no way to say
            // "not a number" — so one corrupt body used to make the whole save fail, and because the failure
            // was swallowed, autosave simply stopped working with nothing on screen to say so.
            particles: saved.map { body in
                ParticleRecord(
                    x: body.x.isFinite ? body.x : width / 2,
                    y: body.y.isFinite ? body.y : height / 2,
                    vx: body.velocityX.isFinite ? body.velocityX : 0,
                    vy: body.velocityY.isFinite ? body.velocityY : 0,
                    r: body.radius.isFinite ? body.radius : 2,
                    c: body.color.hexString,
                    t: body.kind == .standard ? nil : body.kind.rawValue,
                    m: body.mass == 1 || !body.mass.isFinite ? nil : body.mass,
                    g: body.ignoresGravity ? 1 : nil,
                    q: body.charge == 0 || !body.charge.isFinite ? nil : body.charge,
                    f: body.isFixed ? 1 : nil,
                    life: body.lifespan,
                    maxLife: body.maxLife,
                    ox: body.originX.flatMap { $0.isFinite ? $0 : nil },
                    oy: body.originY.flatMap { $0.isFinite ? $0 : nil },
                    lat: body.latticeBound ? 1 : nil,
                    helix: body.helixStrand
                )
            }
        )
    }

    private func swarmRecord(limit: Int) -> SwarmRecord {
        let taken = min(swarm.count, limit)
        var x = [Float](repeating: 0, count: taken)
        var y = [Float](repeating: 0, count: taken)
        var vx = [Float](repeating: 0, count: taken)
        var vy = [Float](repeating: 0, count: taken)
        var colors = [UInt32](repeating: 0, count: taken)
        for i in 0 ..< taken {
            let pair = i * 2
            let px = swarm.positions[pair]
            let py = swarm.positions[pair + 1]
            let pvx = swarm.velocities[pair]
            let pvy = swarm.velocities[pair + 1]
            x[i] = px.isFinite ? px : Float(width / 2)
            y[i] = py.isFinite ? py : Float(height / 2)
            vx[i] = pvx.isFinite ? pvx : 0
            vy[i] = pvy.isFinite ? pvy : 0
            colors[i] = swarm.colors[i]
        }
        var masses: [Float] = []
        var lives: [Float] = []
        var started: [Float] = []
        var roles: [UInt8] = []
        var homes: [Float] = []
        var ownSizes: [Float] = []
        var anyWeighted = false
        for i in 0 ..< taken where swarm.masses[i] != 1 {
            anyWeighted = true
            break
        }
        if anyWeighted {
            masses = (0 ..< taken).map { swarm.masses[$0] }
        }
        if swarm.hasMortalBodies {
            lives = (0 ..< taken).map { swarm.lives[$0] }
            started = (0 ..< taken).map { swarm.maxLives[$0] }
        }
        if swarm.hasRoles {
            roles = (0 ..< taken).map { swarm.roles[$0] }
            homes = (0 ..< taken * Swarm.homeStride).map { swarm.homes[$0] }
        }
        if swarm.hasSizes {
            ownSizes = (0 ..< taken).map { swarm.sizes[$0] }
        }
        return SwarmRecord(
            n: taken,
            x: x,
            y: y,
            vx: vx,
            vy: vy,
            c: colors,
            m: masses.isEmpty ? nil : masses,
            life: lives.isEmpty ? nil : lives,
            maxLife: started.isEmpty ? nil : started,
            role: roles.isEmpty ? nil : roles,
            home: homes.isEmpty ? nil : homes,
            size: ownSizes.isEmpty ? nil : ownSizes
        )
    }

    /// Loads a whole field.
    ///
    /// - Returns: whether it was loaded. `false` leaves the current field untouched.
    ///
    /// Every setting is checked for being a usable number before it is stored. They used to
    /// be assigned straight from the file, so one `null` for the damping figure turned every
    /// velocity into nonsense on the next step — and because the forces couple every body to
    /// every other, the whole field was unusable one frame later with nothing to point at.
    @discardableResult
    public func apply(_ state: ParticleState) -> Bool {
        guard state.width > 0, state.height > 0, state.width.isFinite, state.height.isFinite else {
            return false
        }

        // The saved canvas size is applied. It was exported and then ignored, so a scene
        // captured on a large display dropped most of its bodies outside a smaller field.
        resize(width: state.width, height: state.height)

        func usable(_ value: Double, _ fallback: Double) -> Double {
            value.isFinite ? value : fallback
        }
        gravityX = usable(state.gravityX, gravityX)
        gravityY = usable(state.gravityY, gravityY)
        damping = usable(state.damping, damping)
        elasticity = usable(state.elasticity, elasticity)
        vortexForce = usable(state.vortexForce, vortexForce)
        maxSpeed = usable(state.maxSpeed, maxSpeed)
        boundaryMode = ParticleBoundaryMode(rawValue: state.boundaryMode) ?? .bounce
        collisionsEnabled = state.collisionsEnabled
        // A colour mode this build does not recognise leaves the current one alone rather than
        // resetting to the body's own colour — a file from a later build should lose the setting it
        // cannot express, not quietly repaint the scene.
        if let saved = state.colorMode, let mode = ParticleColorMode(rawValue: saved) {
            colorMode = mode
        }
        // A shape this build does not recognise leaves the current one alone, for the same reason the
        // colour mode does: a file from a later build should lose the setting it cannot express rather
        // than quietly redrawing the scene as circles.
        if let saved = state.particleShape, let shape = ParticleShape(rawValue: saved) {
            particleShape = shape
        }
        paletteEnabled = state.paletteEnabled ?? false
        if let saved = state.palette { palette = saved }
        // Rebuilt through its own initialiser rather than assigned, so a hand-edited file's keyframes are
        // put in order and pulled into range on the way in.
        // Through the setter, so a hand-edited file's sources are capped on the way in.
        // Each of these is written only when there is something in it, so its absence means "none" — and has
        // to be applied as none. Loading used to keep whatever the previous field had: a scene saved with
        // no sources came back with the last scene's source still pouring into it, and its walls, its wind
        // and its recording still in place.
        emitters = (state.emitters ?? []).map(\.sanitized)
        if let saved = state.emitterTemplate { emitterTemplate = saved.sanitized }
        storedCurrent = state.current ?? ParticleCurrentField()
        if let saved = state.currentSettings { currentSettings = saved }
        // Through the setter, so a hand-edited file's walls are filtered and capped on the way in.
        walls = state.walls ?? []
        if let saved = state.wallSettings { wallSettings = saved }
        if let saved = state.flockSettings { flockSettings = saved }
        if let saved = state.trailSettings { trailSettings = saved }
        if let saved = state.contactSettings { contactSettings = saved }
        if let saved = state.timeline {
            timeline = ParticleTimeline(keyframes: saved.keyframes, loops: saved.loops)
        } else {
            timeline = ParticleTimeline()
        }
        playhead = ParticlePlayhead()
        flowEnabled = state.flowEnabled ?? false
        if let saved = state.flowSettings { flowSettings = saved }
        // Compiled again on the way in rather than trusted. A saved file can be hand-edited, and an
        // expression that no longer makes sense should quietly become no force rather than being carried
        // into the physics as something half-understood.
        if let saved = state.writtenForceAcross,
           case .success(let expression) = ParticleForceExpression.compile(saved)
        {
            writtenForceAcross = expression
        }
        if let saved = state.writtenForceDown,
           case .success(let expression) = ParticleForceExpression.compile(saved)
        {
            writtenForceDown = expression
        }
        if let saved = state.writtenForceStrength, saved.isFinite {
            writtenForceStrength = max(-20, min(20, saved))
        }
        if let saved = state.backdrop, let kind = ParticleBackdrop(rawValue: saved) { backdrop = kind }
        if let saved = state.backdropStrength { backdropStrength = saved }
        if let saved = state.glow { glow = saved.sanitized }
        if let saved = state.fluidSettings { fluidSettings = saved }
        if let saved = state.bodyGravitySettings { bodyGravitySettings = saved }
        flockEnabled = state.flockEnabled ?? false
        nbodyEnabled = state.nbodyEnabled ?? false
        fluidEnabled = state.fluidEnabled ?? false
        _ = setMaxParticles(state.maxParticles)

        // Cleared through the path that drops the springs with the world they belonged to.
        replaceParticles([])
        swarm.removeAll()

        if let record = state.swarm, record.n > 0 {
            restoreSwarm(record)
        }

        // Kept within a generous margin of the world. Only "is it a number" used to be checked, and a finite
        // but enormous position — ten to the twentieth — reached whole-number conversions in the fluid, the
        // gravity grid and the colour-by-crowd pass that cannot hold it, and crashed the first moment after
        // loading. Nothing legitimate is anywhere near these limits.
        let reach = max(width, height) * 4 + 1_000
        func place(_ value: Double) -> Double { max(-reach, min(reach, value)) }
        func speed(_ value: Double) -> Double { value.isFinite ? max(-10_000, min(10_000, value)) : 0 }

        for record in state.particles {
            guard record.x.isFinite, record.y.isFinite else { continue }
            addParticle(
                x: place(record.x),
                y: place(record.y),
                velocityX: speed(record.vx),
                velocityY: speed(record.vy),
                radius: record.r.isFinite ? max(0, min(200, record.r)) : nil,
                mass: record.m.map { $0.isFinite ? $0 : 1 } ?? 1,
                charge: record.q,
                color: PackedColor(hex: record.c) ?? PackedColor(r: 255, g: 255, b: 255),
                lifespan: record.life,
                maxLife: record.maxLife,
                // Pinned from the saved flag, falling back to deriving it from the kind so
                // that a file from an earlier build still loads sensibly.
                isFixed: record.f == 1 || record.t == "blackhole" || record.t == "repulsor",
                ignoresGravity: record.g == 1,
                originX: record.ox.flatMap { $0.isFinite ? place($0) : nil },
                originY: record.oy.flatMap { $0.isFinite ? place($0) : nil },
                latticeBound: record.lat == 1,
                helixStrand: record.helix,
                kind: record.t.flatMap(ParticleKind.init(rawValue:)) ?? .standard
            )
        }

        storedArrangement = state.arrangement.flatMap { ParticleArrangement.named($0)?.id }
        arrangementAge = 0

        // Springs last, once every body they name exists. `setSprings` drops anything that
        // does not name a real pair — a spring pointing past the end of the list, or at
        // itself, cannot be detected once the frame loop is running.
        setSprings(state.springs?.map { Spring(a: $0.a, b: $0.b, rest: $0.rest, k: $0.k) } ?? [])
        return true
    }

    private func restoreSwarm(_ record: SwarmRecord) {
        let taken = min(record.n, record.x.count, record.y.count, record.vx.count, record.vy.count)
        guard taken > 0 else { return }
        var snapshot = Swarm.Snapshot(positions: [], velocities: [], colors: [])
        snapshot.positions.reserveCapacity(taken * 2)
        snapshot.velocities.reserveCapacity(taken * 2)
        snapshot.colors.reserveCapacity(taken)
        for i in 0 ..< taken {
            // Anything unusable is placed at the centre at rest rather than dropped, so the
            // colours stay aligned with the positions.
            let reach = Float(max(width, height) * 4 + 1_000)
            let x = record.x[i].isFinite ? max(-reach, min(reach, record.x[i])) : Float(width / 2)
            let y = record.y[i].isFinite ? max(-reach, min(reach, record.y[i])) : Float(height / 2)
            snapshot.positions.append(x)
            snapshot.positions.append(y)
            snapshot.velocities.append(record.vx[i].isFinite ? max(-10_000, min(10_000, record.vx[i])) : 0)
            snapshot.velocities.append(record.vy[i].isFinite ? max(-10_000, min(10_000, record.vy[i])) : 0)
            snapshot.colors.append(i < record.c.count ? record.c[i] : 0xFFD4_C8C8)
        }
        // Absent means the plain answer — everything weighs one and lives forever — so nothing is built in
        // that case rather than a list of ones being made to say so.
        if let masses = record.m, !masses.isEmpty {
            snapshot.masses.reserveCapacity(taken)
            for i in 0 ..< taken {
                let weight = i < masses.count ? masses[i] : 1
                snapshot.masses.append(weight.isFinite && weight > 0 ? weight : 1)
            }
        }
        if let lives = record.life, !lives.isEmpty {
            snapshot.lives.reserveCapacity(taken)
            for i in 0 ..< taken {
                let left = i < lives.count ? lives[i] : -1
                snapshot.lives.append(left.isFinite ? left : -1)
            }
        }
        if let started = record.maxLife, !started.isEmpty {
            snapshot.maxLives = (0 ..< taken).map { i in
                let value = i < started.count ? started[i] : 1
                return value.isFinite && value > 0 ? value : 1
            }
        }
        if let roles = record.role, !roles.isEmpty {
            snapshot.roles = (0 ..< taken).map { $0 < roles.count ? roles[$0] : 0 }
            let homes = record.home ?? []
            // Positions far outside the world would reach whole-number conversions downstream that cannot
            // hold them, so a home is kept within a generous margin of the world like everything else.
            let limit = Float(max(width, height) * 4 + 1_000)
            snapshot.homes = (0 ..< taken * Swarm.homeStride).map { k in
                let value = k < homes.count ? homes[k] : 0
                return value.isFinite ? max(-limit, min(limit, value)) : 0
            }
        }
        if let saved = record.size, !saved.isEmpty {
            snapshot.sizes = (0 ..< taken).map { i in
                let value = i < saved.count ? saved[i] : 0
                return value.isFinite ? max(0, min(400, value)) : 0
            }
        }
        swarm.restore(from: snapshot, budget: max(0, maxParticles - particles.count))
    }
}
