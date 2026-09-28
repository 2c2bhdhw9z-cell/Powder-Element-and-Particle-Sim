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
    /// How far into the screen it is, how fast it is moving that way, and how far in its origin is — for a
    /// field in 3D. Absent on a flat one.
    public var z: Double?
    public var vz: Double?
    public var oz: Double?
    /// Which layer it is on. Absent when it is on the first one, which is everything in a world nobody has
    /// divided up — and in files written before there were layers.
    public var layer: UInt8?
}

/// A spring, as saved: two positions in the body list, a rest length and a stiffness.
/// One ribbon of light, as saved.
public struct RibbonRecord: Codable, Sendable {
    public var x: [Double]
    public var y: [Double]
    public var z: [Double]
    public var c: UInt32
}

/// A recorded finger movement, as saved: the tool, how far and hard it reached, and where it went each moment.
public struct ForceLoopRecord: Codable, Sendable {
    public var mode: String
    public var reach: Double
    public var strength: Double
    public var x: [Double]
    public var y: [Double]
    public var z: [Double]
}

/// A jelly, as saved: which bodies it is made of, by their place in the saved list, and where each belongs in its
/// shape.
public struct JellyRecord: Codable, Sendable {
    public var members: [Int]
    public var x: [Double]
    public var y: [Double]
    public var firmness: Double?
}

/// A creature, as saved: its joints by their place in the saved list, and what is needed to say how it is doing.
public struct CreatureRecord: Codable, Sendable {
    public var members: [Int]
    public var name: String?
    public var startX: Double?
    public var builtHeight: Double?
}

public struct SpringRecord: Codable, Sendable {
    public var a: Int
    public var b: Int
    public var rest: Double
    public var k: Double
    /// A muscle's swell, its cycle and where in the cycle it starts. Absent for a plain spring, which is almost
    /// all of them, so an ordinary cloth's file is exactly the size it always was.
    public var pulse: Double?
    public var beat: Double?
    public var phase: Double?
    /// How hard it pushes while squeezing, and which way. See `Spring.thrust`.
    public var thrust: Double?
    public var tx: Double?
    public var ty: Double?
    public var tz: Double?
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
    /// How far into the screen each body is, how fast it is moving that way, and how far in its place in a
    /// shape is. Absent on a flat field.
    public var z: [Float]?
    public var vz: [Float]?
    public var hz: [Float]?
    /// Which layer each body is on. Absent when every body is on the first one.
    public var layer: [UInt8]?
}

/// A whole particle field, as saved.
public struct ParticleState: Codable, Sendable {
    public var width: Double
    public var height: Double
    public var gravityX: Double
    public var gravityY: Double
    /// Gravity pointing at the middle of the world. Absent in every file written before little round worlds.
    public var gravityToCentre: Double?
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
    /// The movie made of camera stops, when one has been made. Like the camera, applied by the caller.
    public var movie: ParticleMovie?
    /// Which arrangement the field was showing, so its chip lights up again and adding to it still joins it.
    public var arrangement: String?
    /// Whether the field was in 3D, and how deep its box was. Absent in files from before there was depth,
    /// which were all flat.
    public var depthEnabled: Bool?
    public var depthRatio: Double?
    /// Small crowds from older files, kept as readable parallel arrays.
    public var swarm: SwarmRecord?
    /// Large crowds, packed losslessly rather than shortened to fit readable JSON arrays. Optional so every file from
    /// before this format still decodes through ``swarm``.
    public var packedSwarm: PackedSwarmRecord?
    /// Ribbons of light, each as three lists of places and a colour. Absent when none have been drawn.
    public var ribbons: [RibbonRecord]?
    /// How particle life's kinds feel about each other, when the field was showing it. Absent otherwise.
    public var particleLifeRules: [[Double]]?
    /// Finger movements recorded to play on a loop. Absent when there are none.
    public var loops: [ForceLoopRecord]?
    /// Jellies made with the jelly pen. Absent when there are none.
    public var jellies: [JellyRecord]?
    /// Creatures of bones and muscles. Absent when there are none.
    public var creatures: [CreatureRecord]?
    public var springs: [SpringRecord]?
    /// The world's named layers, when it has more than one. Absent otherwise, which is nearly every world.
    public var layers: [ParticleLayer]?
    /// Which layer new bodies were going into.
    public var layerAt: Int?
    public var particles: [ParticleRecord]
}

extension ParticleEngine {
    /// The widest or tallest a saved field may be, in the world's pixels.
    public static let largestWorldSide = 200_000.0

    /// Kept as a public compatibility name for older callers and tests. Object bodies are no longer shortened.
    public static let saveBodyLimit = Swarm.maximumCount
    /// Largest crowd kept in the old readable-array form. Larger crowds use ``PackedSwarmRecord`` without loss.
    public static let saveSwarmLimit = 24_000

    /// Captures the whole field. Every body is kept; a save that quietly loses bodies is not a save.
    public func captureState() -> ParticleState {
        let saved = particles
        let legacySwarm = swarm.count > 0 && swarm.count <= Self.saveSwarmLimit
            ? swarmRecord(limit: swarm.count)
            : nil
        let packedSwarm = swarm.count > Self.saveSwarmLimit
            ? PackedSwarmRecord.capture(swarm, width: width, height: height, depthEnabled: storedDepthEnabled)
            : nil
        return ParticleState(
            width: width,
            height: height,
            gravityX: gravityX,
            gravityY: gravityY,
            gravityToCentre: storedGravityToCentre > 0 ? storedGravityToCentre : nil,
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
            depthEnabled: storedDepthEnabled ? true : nil,
            depthRatio: storedDepthEnabled ? storedDepthRatio : nil,
            swarm: legacySwarm,
            packedSwarm: packedSwarm,
            // Every object body is written, so every valid spring and structure index survives with it.
            ribbons: storedRibbons.isEmpty
                ? nil
                : storedRibbons.map { RibbonRecord(x: $0.pointsX, y: $0.pointsY, z: $0.pointsZ, c: $0.color) },
            particleLifeRules: storedParticleLifeEnabled && !storedParticleLifeRules.isEmpty
                ? storedParticleLifeRules
                : nil,
            loops: storedForceLoops.isEmpty
                ? nil
                : storedForceLoops.map { loop in
                    ForceLoopRecord(
                        mode: loop.mode.rawValue,
                        reach: loop.reach.isFinite ? loop.reach : 1_000_000,
                        strength: loop.strength.isFinite ? loop.strength : 1,
                        x: loop.points.map { $0.x.isFinite ? $0.x : 0 },
                        y: loop.points.map { $0.y.isFinite ? $0.y : 0 },
                        z: loop.points.map { $0.z.isFinite ? $0.z : 0 }
                    )
                },
            jellies: storedJellies.isEmpty ? nil : jellyRecords(savedCount: saved.count),
            creatures: storedCreatures.isEmpty ? nil : creatureRecords(savedCount: saved.count),
            springs: springs
                .filter { $0.a < saved.count && $0.b < saved.count }
                .map {
                    SpringRecord(
                        a: $0.a, b: $0.b, rest: $0.rest, k: $0.k,
                        pulse: $0.isMuscle ? $0.pulse : nil,
                        beat: $0.isMuscle ? $0.beat : nil,
                        phase: $0.isMuscle ? $0.phase : nil,
                        thrust: $0.jets ? $0.thrust : nil,
                        tx: $0.jets ? $0.thrustX : nil,
                        ty: $0.jets ? $0.thrustY : nil,
                        tz: $0.jets ? $0.thrustZ : nil
                    )
                },
            layers: storedLayers.count > 1 ? storedLayers : nil,
            layerAt: storedLayers.count > 1 ? storedCurrentLayer : nil,
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
                    helix: body.helixStrand,
                    z: storedDepthEnabled && body.z.isFinite && body.z != 0 ? body.z : nil,
                    vz: storedDepthEnabled && body.velocityZ.isFinite && body.velocityZ != 0 ? body.velocityZ : nil,
                    oz: storedDepthEnabled && body.originZ.isFinite && body.originZ != 0 ? body.originZ : nil,
                    layer: body.group == 0 ? nil : body.group
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
        var layerTags: [UInt8] = []
        if swarm.hasGroups {
            layerTags = (0 ..< taken).map { swarm.groups[$0] }
        }
        var depths: [Float]?
        var depthVelocities: [Float]?
        var homeDepths: [Float]?
        if storedDepthEnabled, swarm.hasDepth {
            depths = (0 ..< taken).map { swarm.depths[$0].isFinite ? swarm.depths[$0] : 0 }
            depthVelocities = (0 ..< taken).map { swarm.depthVelocities[$0].isFinite ? swarm.depthVelocities[$0] : 0 }
            homeDepths = (0 ..< taken).map { swarm.homeDepths[$0].isFinite ? swarm.homeDepths[$0] : 0 }
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
            size: ownSizes.isEmpty ? nil : ownSizes,
            z: depths,
            vz: depthVelocities,
            hz: homeDepths,
            layer: layerTags.isEmpty ? nil : layerTags
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
        // Nothing the app makes is anywhere near this — zoomed all the way out, a world is a few tens of thousands of
        // pixels across — and a file asking for more is damaged. Taken at its word, the field built grids for a
        // world a million million pixels wide, and the arithmetic for that stopped the app.
        guard state.width <= Self.largestWorldSide, state.height <= Self.largestWorldSide else { return false }

        // A packed crowd is checked completely before this engine is touched. A cut or altered save therefore leaves
        // the world and its history alone rather than loading a believable-looking prefix of the crowd.
        let packedSnapshot: Swarm.Snapshot?
        if let packed = state.packedSwarm {
            guard let decoded = packed.snapshot(width: state.width, height: state.height) else { return false }
            packedSnapshot = decoded
        } else {
            packedSnapshot = nil
        }
        let savedSwarmCount = packedSnapshot?.count ?? state.swarm?.n ?? 0
        let savedLimit = max(1_000, min(Swarm.maximumCount, state.maxParticles))
        guard state.particles.count <= savedLimit, savedSwarmCount >= 0,
              savedSwarmCount <= savedLimit - state.particles.count
        else { return false }

        // The saved canvas size is applied. It was exported and then ignored, so a scene
        // captured on a large display dropped most of its bodies outside a smaller field.
        resize(width: state.width, height: state.height)

        func usable(_ value: Double, _ fallback: Double) -> Double {
            value.isFinite ? value : fallback
        }
        gravityX = usable(state.gravityX, gravityX)
        gravityY = usable(state.gravityY, gravityY)
        // Read with a fallback of nothing rather than of whatever it is now, so loading an ordinary scene over a
        // little round world turns the inward pull off instead of leaving it on.
        gravityToCentre = state.gravityToCentre ?? 0
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

        // Before the bodies, so they are put back into the right kind of world.
        storedDepthEnabled = state.depthEnabled ?? false
        storedDepthRatio = Self.usableDepthRatio(state.depthRatio ?? 1)

        // Cleared through the path that drops the springs with the world they belonged to.
        replaceParticles([])
        swarm.removeAll()

        if let packedSnapshot {
            swarm.restore(from: packedSnapshot, budget: max(0, maxParticles - particles.count))
        } else if let record = state.swarm, record.n > 0 {
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
                kind: record.t.flatMap(ParticleKind.init(rawValue:)) ?? .standard,
                z: storedDepthEnabled ? place(record.z ?? 0) : 0,
                velocityZ: storedDepthEnabled ? speed(record.vz ?? 0) : 0,
                originZ: storedDepthEnabled ? (record.oz.flatMap { $0.isFinite ? place($0) : nil } ?? 0) : 0
            )
        }

        // The layers themselves, before the bodies are asked which one they are on — a body pointing at a layer that
        // does not exist would be a body with nobody's colour and nobody's rules. So the list is read first, and a tag
        // is only kept where there is a layer for it.
        let savedLayers = (state.layers ?? []).prefix(ParticleLayer.most).map(\.sanitized)
        storedLayers = savedLayers.count > 1 ? Array(savedLayers) : []
        storedCurrentLayer = min(max(0, state.layerAt ?? 0), max(0, layers.count - 1))
        if storedLayers.count > 1 {
            let most = UInt8(storedLayers.count)
            for (index, record) in state.particles.enumerated() where index < particles.count {
                let tag = record.layer ?? 0
                particles[index].group = tag < most ? tag : 0
            }
        }
        // Where the hidden bodies are has to be worked out for the loaded crowd, not inherited from whatever the field
        // held before. Without this a world with a hidden layer opened as an empty field: the count of bodies to draw
        // was still nought from before anything was loaded, so the screen drew none of them.
        restackLayers()

        storedArrangement = state.arrangement.flatMap { ParticleArrangement.named($0)?.id }
        arrangementAge = 0

        // What the scene does by itself comes back with it. Only the bodies used to: a saved particle life reopened
        // as five colours of bodies that no longer noticed each other.
        storedParticleLifeEnabled = storedArrangement == "life"
        storedPredatorsEnabled = storedArrangement == "foxes"
        storedChargeIsKind = storedParticleLifeEnabled || storedPredatorsEnabled
        storedDrumEnabled = storedArrangement == "drum"
        storedDrumNoteAge = 0
        storedHerdHistory = []
        storedHerdSampleAge = 0
        if storedParticleLifeEnabled {
            if let rules = state.particleLifeRules { particleLifeRules = rules }
            if storedParticleLifeRules.isEmpty { shuffleParticleLife() }
        }
        // The drag and speed limit in the file are the world's own now, with nothing earlier to give back.
        storedDampingBeforeScene = nil
        storedMaxSpeedBeforeScene = nil
        storedJellyOutline = []
        storedLoopRecording = nil
        // Read with a fallback of nothing, as the ribbons are, so loading a world with no loops stops the last one's.
        storedForceLoops = (state.loops ?? []).prefix(Self.forceLoopLimit).compactMap { record in
            guard let mode = ParticleMouseMode(rawValue: record.mode), ParticleBrush.touchesBodies(mode) else {
                return nil
            }
            let count = min(record.x.count, record.y.count, record.z.count, Self.forceLoopLongest)
            guard count >= Self.forceLoopShortest else { return nil }
            var loop = ParticleForceLoop(
                mode: mode,
                reach: record.reach.isFinite ? max(0, record.reach) : mouseRadius,
                strength: record.strength.isFinite ? max(0, min(8, record.strength)) : 1
            )
            loop.points = (0 ..< count).map { index in
                ParticleFingerPoint(x: place(record.x[index]), y: place(record.y[index]), z: place(record.z[index]))
            }
            return loop
        }

        // Springs last, once every body they name exists. `setSprings` drops anything that
        // does not name a real pair — a spring pointing past the end of the list, or at
        // itself, cannot be detected once the frame loop is running.
        // Read with a fallback of nothing rather than of what is there, so loading a world with no ribbons rubs out
        // whatever was drawn in the last one.
        storedRibbons = (state.ribbons ?? []).prefix(Self.ribbonLimit).compactMap { record in
            let count = min(record.x.count, min(record.y.count, record.z.count))
            guard count > 1 else { return nil }
            var ribbon = ParticleRibbon(color: record.c)
            ribbon.pointsX = Array(record.x.prefix(min(count, Self.ribbonPointLimit)))
            ribbon.pointsY = Array(record.y.prefix(min(count, Self.ribbonPointLimit)))
            ribbon.pointsZ = Array(record.z.prefix(min(count, Self.ribbonPointLimit)))
            return ribbon
        }

        // Jellies once the bodies exist, their members found by place in the list and given the new identifiers.
        storedJellies = (state.jellies ?? []).prefix(Self.jellyLimit).compactMap { record in
            let count = min(record.members.count, record.x.count, record.y.count)
            var ids: [Int] = []
            var restX: [Double] = []
            var restY: [Double] = []
            for at in 0 ..< count {
                let member = record.members[at]
                guard member >= 0, member < particles.count, record.x[at].isFinite, record.y[at].isFinite else { continue }
                ids.append(particles[member].id)
                restX.append(record.x[at])
                restY.append(record.y[at])
            }
            guard ids.count >= 3 else { return nil }
            return ParticleJelly(ids: ids, restX: restX, restY: restY, firmness: record.firmness ?? Self.jellyFirmness)
        }

        // Creatures likewise, by place in the list; their bones and muscles are springs and come back with the rest.
        storedCreatures = (state.creatures ?? []).prefix(Self.creatureLimit).compactMap { record in
            let ids = record.members.filter { $0 >= 0 && $0 < particles.count }.map { particles[$0].id }
            guard ids.count >= 2 else { return nil }
            return ParticleCreature(
                ids: ids,
                name: record.name ?? "Creature",
                startX: record.startX ?? width / 2,
                builtHeight: record.builtHeight ?? 1
            )
        }

        setSprings(
            state.springs?.map {
                Spring(
                    a: $0.a, b: $0.b, rest: $0.rest, k: $0.k,
                    // Absent in every file written before muscles existed, and absent for plain springs now,
                    // which read back as the ordinary spring they are.
                    pulse: $0.pulse ?? 0, beat: $0.beat ?? 60, phase: $0.phase ?? 0,
                    thrust: $0.thrust ?? 0, thrustX: $0.tx ?? 0, thrustY: $0.ty ?? 0, thrustZ: $0.tz ?? 0
                )
            } ?? []
        )
        return true
    }

    /// Every creature as saved, naming its joints by their place among all saved object bodies.
    private func creatureRecords(savedCount: Int) -> [CreatureRecord] {
        var place: [Int: Int] = [:]
        for index in 0 ..< min(savedCount, particles.count) { place[particles[index].id] = index }
        return storedCreatures.compactMap { creature in
            let members = creature.ids.compactMap { place[$0] }
            guard members.count >= 2 else { return nil }
            return CreatureRecord(
                members: members, name: creature.name, startX: creature.startX, builtHeight: creature.builtHeight
            )
        }
    }

    /// Every jelly as saved, naming its bodies by their place among all saved object bodies.
    private func jellyRecords(savedCount: Int) -> [JellyRecord] {
        var place: [Int: Int] = [:]
        for index in 0 ..< min(savedCount, particles.count) { place[particles[index].id] = index }
        return storedJellies.compactMap { jelly in
            var record = JellyRecord(members: [], x: [], y: [], firmness: jelly.firmness)
            for (at, id) in jelly.ids.enumerated() {
                guard let member = place[id] else { continue }
                record.members.append(member)
                record.x.append(jelly.restX[at])
                record.y.append(jelly.restY[at])
            }
            return record.members.count >= 3 ? record : nil
        }
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
        if let saved = record.layer, !saved.isEmpty {
            snapshot.groups = (0 ..< taken).map { $0 < saved.count ? saved[$0] : 0 }
        }
        // Depth only into a field that is in 3D. A flat field reading a 3D file's depths would be drawing flat
        // bodies that behave as though they were somewhere else.
        if storedDepthEnabled {
            let reach = Float(max(width, height) * 4 + 1_000)
            func read(_ saved: [Float]?, limit: Float) -> [Float] {
                guard let saved, !saved.isEmpty else { return [] }
                return (0 ..< taken).map { i in
                    let value = i < saved.count ? saved[i] : 0
                    return value.isFinite ? max(-limit, min(limit, value)) : 0
                }
            }
            snapshot.depths = read(record.z, limit: reach)
            snapshot.depthVelocities = read(record.vz, limit: 10_000)
            snapshot.homeDepths = read(record.hz, limit: reach)
        }
        swarm.restore(from: snapshot, budget: max(0, maxParticles - particles.count))
    }
}
