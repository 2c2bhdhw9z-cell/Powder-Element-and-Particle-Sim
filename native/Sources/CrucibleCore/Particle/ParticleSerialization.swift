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
            swarm: swarm.count > 0 ? swarmRecord(limit: Self.saveSwarmLimit) : nil,
            // Only springs whose two ends both survived the cap, since a position past the
            // end of what was written is exactly the stale index that makes a reloaded
            // scene shear itself apart.
            springs: springs
                .filter { $0.a < saved.count && $0.b < saved.count }
                .map { SpringRecord(a: $0.a, b: $0.b, rest: $0.rest, k: $0.k) },
            particles: saved.map { body in
                ParticleRecord(
                    x: body.x,
                    y: body.y,
                    vx: body.velocityX,
                    vy: body.velocityY,
                    r: body.radius,
                    c: body.color.hexString,
                    t: body.kind == .standard ? nil : body.kind.rawValue,
                    m: body.mass == 1 ? nil : body.mass,
                    g: body.ignoresGravity ? 1 : nil,
                    q: body.charge == 0 ? nil : body.charge,
                    f: body.isFixed ? 1 : nil,
                    life: body.lifespan,
                    maxLife: body.maxLife,
                    ox: body.originX,
                    oy: body.originY,
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
            x[i] = swarm.positions[pair]
            y[i] = swarm.positions[pair + 1]
            vx[i] = swarm.velocities[pair]
            vy[i] = swarm.velocities[pair + 1]
            colors[i] = swarm.colors[i]
        }
        return SwarmRecord(n: taken, x: x, y: y, vx: vx, vy: vy, c: colors)
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

        for record in state.particles {
            guard record.x.isFinite, record.y.isFinite else { continue }
            addParticle(
                x: record.x,
                y: record.y,
                velocityX: record.vx.isFinite ? record.vx : 0,
                velocityY: record.vy.isFinite ? record.vy : 0,
                radius: record.r.isFinite ? record.r : nil,
                mass: record.m.map { $0.isFinite ? $0 : 1 } ?? 1,
                charge: record.q,
                color: PackedColor(hex: record.c) ?? PackedColor(r: 255, g: 255, b: 255),
                lifespan: record.life,
                maxLife: record.maxLife,
                // Pinned from the saved flag, falling back to deriving it from the kind so
                // that a file from an earlier build still loads sensibly.
                isFixed: record.f == 1 || record.t == "blackhole" || record.t == "repulsor",
                ignoresGravity: record.g == 1,
                originX: record.ox,
                originY: record.oy,
                latticeBound: record.lat == 1,
                helixStrand: record.helix,
                kind: record.t.flatMap(ParticleKind.init(rawValue:)) ?? .standard
            )
        }

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
            let x = record.x[i].isFinite ? record.x[i] : Float(width / 2)
            let y = record.y[i].isFinite ? record.y[i] : Float(height / 2)
            snapshot.positions.append(x)
            snapshot.positions.append(y)
            snapshot.velocities.append(record.vx[i].isFinite ? record.vx[i] : 0)
            snapshot.velocities.append(record.vy[i].isFinite ? record.vy[i] : 0)
            snapshot.colors.append(i < record.c.count ? record.c[i] : 0xFFD4_C8C8)
        }
        swarm.restore(from: snapshot, budget: max(0, maxParticles - particles.count))
    }
}
