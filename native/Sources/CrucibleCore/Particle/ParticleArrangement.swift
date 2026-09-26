/// Every arrangement the field can be filled with, and what each one is.
///
/// ## Why this list lives in the engine
///
/// It used to be a list of names in the app with a switch statement next to it, and three things followed
/// from that. Nothing outside the app could say which arrangement was showing, so the chip for it could not
/// light up. Nothing could tell a *scene* — Galaxy, Black hole, which replace the field and stay — from an
/// *addition* — Burst, which throws something into whatever is already there. And none of it could be
/// tested, because the app cannot be built anywhere the tests run.
///
/// So the list, the difference between the two kinds, and how new bodies can join each arrangement are all
/// described here, and the field remembers which one it is showing.
public struct ParticleArrangement: Sendable, Hashable {
    /// Whether choosing it replaces the field or adds to it.
    public enum Kind: Sendable, Hashable {
        /// Replaces the field, and stays: the field *is* this arrangement until something else is chosen.
        case scene
        /// Throws something into the field as it is. Nothing stays selected afterwards.
        case addition
    }

    /// How bodies added to the arrangement can take part in it.
    public enum Joining: Sendable, Hashable {
        /// They go into orbit round the arrangement's black holes.
        case orbit
        /// They copy what the arrangement's crowd is doing: its motion, its colour, its place in a shape.
        case crowd
        /// They copy what the arrangement's individual bodies are doing — a flare's recycling, a helix's
        /// strands, a flock's steering. Those behaviours belong to the object list, which is far smaller
        /// than the crowd, so there is a ceiling on how many can join.
        case objects
        /// It is a built thing — a cloth, a rope — and adding to it means building another.
        case structure
        /// Nothing to join.
        case none
    }

    /// Whether an arrangement has a flat form, a 3D one, or both.
    public enum Depth: Sendable, Hashable {
        /// Built flat on a flat field and in depth in 3D.
        case both
        /// Exists only in depth — a globe, a strange attractor, a flight through the stars. Choosing one on a
        /// flat field turns 3D on.
        case only
    }

    /// Where an arrangement is best looked at from in 3D, which the app turns the view to when it is chosen.
    public enum View: Sendable, Hashable {
        /// A little from one side and a little from above: what shows most things' depth best.
        case angled
        /// From above, for the things lying level — a galaxy's disc, a sea — whose shape is only seen from
        /// higher up.
        case above
        /// Straight on, for a flight through the stars, which only works looking the way it is going.
        case front
        /// Low and to one side, for the things that stand up — a fire, a fountain, a tornado.
        case low
    }

    public var id: String
    public var name: String
    public var kind: Kind
    public var joining: Joining
    /// What it is, in a sentence, for the panel that lists them.
    public var about: String
    /// What adding bodies does while joining is on, in plain words.
    public var joinDescription: String
    /// Whether it has a flat form, a 3D one or both.
    public var depth: Depth
    /// Where it is best looked at from in 3D.
    public var view: View
    /// What it is in 3D, in a sentence, where that is not what it is flat. Empty when it is the same thing
    /// with depth added.
    public var aboutInDepth: String

    public init(
        _ id: String,
        _ name: String,
        kind: Kind = .scene,
        joining: Joining,
        about: String,
        join: String,
        depth: Depth = .both,
        view: View = .angled,
        inDepth: String = ""
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.joining = joining
        self.about = about
        self.joinDescription = join
        self.depth = depth
        self.view = view
        self.aboutInDepth = inDepth
    }

    /// What it is, for a field that is flat or in 3D.
    public func about(inDepth: Bool) -> String {
        inDepth && !aboutInDepth.isEmpty ? aboutInDepth : about
    }

    /// Every arrangement, in the order the interface shows them.
    public static let all: [ParticleArrangement] = [
        // Built round a centre and a force.
        ParticleArrangement(
            "galaxy", "Galaxy", joining: .orbit,
            about: "A spiral disc orbiting a black hole.",
            join: "New bodies go into orbit round the black hole.",
            view: .above,
            inDepth: "A disc lying level round a black hole, with a little thickness to it."
        ),
        ParticleArrangement(
            "blackhole", "Black hole", joining: .orbit,
            about: "A heavier hole with a tighter, faster disc.",
            join: "New bodies go into orbit round the black hole.",
            view: .above,
            inDepth: "A tight level disc, with jets thrown straight up and down out of the hole."
        ),
        ParticleArrangement(
            "vortex", "Double vortex", joining: .orbit,
            about: "Two wells spinning opposite ways.",
            join: "New bodies orbit whichever well they start nearest.",
            view: .above
        ),
        ParticleArrangement(
            "synchrotron", "Synchrotron", joining: .orbit,
            about: "Two wells far enough apart to fling bodies between them.",
            join: "New bodies join the orbit round both wells.",
            view: .above
        ),
        ParticleArrangement(
            "flare", "Solar flare", joining: .objects,
            about: "A glowing core throwing off flares that fall back into it.",
            join: "New bodies are thrown off the core and come back to it.",
            inDepth: "A glowing core throwing flares out in every direction."
        ),
        ParticleArrangement(
            "shockwave", "Shockwave", joining: .objects,
            about: "A ring blasted outward from the middle.",
            join: "New bodies ride along with the ring.",
            inDepth: "A ball of bodies blasted outward from the middle."
        ),
        ParticleArrangement(
            "fountain", "Cosmic fountain", joining: .objects,
            about: "A jet from the floor that falls back and is launched again.",
            join: "New bodies join the jet.",
            view: .low
        ),
        ParticleArrangement(
            "waterfall", "Waterfall", joining: .objects,
            about: "Water falling from the top, caught and poured again.",
            join: "New bodies join the falls.",
            view: .low
        ),
        ParticleArrangement(
            "pour", "Pour", joining: .crowd,
            about: "Liquid poured into an empty tank, splashing and settling.",
            join: "New bodies become more of the liquid.",
            view: .low
        ),
        ParticleArrangement(
            "water", "Water", joining: .crowd,
            about: "A still pool with an inlet pouring into it.",
            join: "New bodies become more of the pool.",
            view: .low
        ),
        ParticleArrangement(
            "lattice", "Quantum lattice", joining: .objects,
            about: "A charged grid, every point held in place by a spring.",
            join: "New bodies are held to the grid's points.",
            inDepth: "A charged block of points, every one held in place by a spring."
        ),
        ParticleArrangement(
            "helix", "DNA helix", joining: .objects,
            about: "Two strands winding across the field.",
            join: "New bodies join the two strands.",
            inDepth: "Two strands winding round each other, a real double helix."
        ),
        ParticleArrangement(
            "flock", "Flock", joining: .objects,
            about: "Birds that steer by the ones around them.",
            join: "New bodies fly with the flock."
        ),
        ParticleArrangement(
            "nbody", "N-body", joining: .crowd,
            about: "A disc of heavy and light bodies, every one pulling on every other.",
            join: "New bodies are pulled into the disc, and pull on it.",
            view: .above
        ),
        ParticleArrangement(
            "cloth", "Cloth", joining: .structure,
            about: "A sheet of joined points, pinned along the top.",
            join: "Each tap hangs another sheet.",
            inDepth: "A sheet pinned along one edge, falling and swinging through the box."
        ),
        ParticleArrangement(
            "rope", "Rope", joining: .structure,
            about: "A chain hanging from a pin.",
            join: "Each tap hangs another rope.",
            inDepth: "A chain held out from a pin, swinging down through the box."
        ),
        ParticleArrangement(
            "blob", "Blob", joining: .structure,
            about: "A soft ball held together by springs.",
            join: "Each tap drops another blob.",
            inDepth: "A soft round ball held together by springs, dropped to bounce."
        ),
        ParticleArrangement(
            "molecules", "Molecules", joining: .structure,
            about: "Ball-and-stick rings, water and a carbon chain, held by their bonds.",
            join: "Each tap adds a few more molecules."
        ),
        ParticleArrangement(
            "swarm", "Swarm", joining: .crowd,
            about: "A hundred and twenty thousand bodies loose in the field.",
            join: "New bodies join the swarm.",
            inDepth: "A hundred and twenty thousand bodies loose in the box."
        ),
        // Built round a shape.
        ParticleArrangement(
            "sunflower", "Sunflower", joining: .crowd,
            about: "Seeds placed a golden turn apart, turning slowly.",
            join: "New bodies take a place among the seeds.",
            inDepth: "A domed seed head, seeds a golden turn apart, turning slowly."
        ),
        ParticleArrangement(
            "mandala", "Mandala", joining: .crowd,
            about: "Eight petals, three rings and eight spikes, turning slowly.",
            join: "New bodies take a place in the pattern.",
            inDepth: "Petals, rings and spikes in layers one behind another, turning."
        ),
        ParticleArrangement(
            "snowflakes", "Snowflakes", joining: .crowd,
            about: "Six-armed flakes, each turning on its own.",
            join: "New bodies take a place in a flake.",
            inDepth: "Six-armed flakes hanging at every depth, each turning on its own."
        ),
        ParticleArrangement(
            "sierpinski", "Sierpinski", joining: .crowd,
            about: "The triangle made of triangles, drawn by a random walk.",
            join: "New bodies take a place in the triangle.",
            inDepth: "The pyramid made of pyramids, drawn by a random walk, turning."
        ),
        ParticleArrangement(
            "ring", "Ring", joining: .crowd,
            about: "A band of bodies circling, seen at a slight angle.",
            join: "New bodies circle with the ring.",
            inDepth: "A ringed planet: a turning ball with a level band circling it."
        ),
        ParticleArrangement(
            "tornado", "Tornado", joining: .crowd,
            about: "A funnel, fast and narrow at the bottom, wide and slow at the top.",
            join: "New bodies spin in the funnel.",
            view: .low,
            inDepth: "A real funnel, every body circling round it, fast at the bottom and slow at the top."
        ),
        ParticleArrangement(
            "aurora", "Aurora", joining: .crowd,
            about: "Five curtains of light, rippling.",
            join: "New bodies ripple in the curtains.",
            inDepth: "Five curtains of light one behind another, rippling."
        ),
        ParticleArrangement(
            "lightning", "Lightning", joining: .crowd,
            about: "A storm: bolts that branch, flicker out, and strike again.",
            join: "New bodies flicker along the bolts."
        ),
        ParticleArrangement(
            "fireworks", "Fireworks", joining: .crowd,
            about: "A display: shells burst, fall and fade, and more go up.",
            join: "New bodies burst with the shells.",
            view: .low,
            inDepth: "A display: shells burst into balls of sparks, fall and fade, and more go up."
        ),
        ParticleArrangement(
            "supernova", "Supernova", joining: .crowd,
            about: "A star coming apart: a fast bright shell and a glowing remnant.",
            join: "New bodies fly out with the blast, or glow in the remnant.",
            inDepth: "A star coming apart: a fast bright ball of a shell and a glowing remnant."
        ),
        ParticleArrangement(
            "magma", "Magma", joining: .crowd,
            about: "A churning molten pool throwing up embers.",
            join: "New bodies churn in the pool or rise as embers.",
            view: .low
        ),
        ParticleArrangement(
            "confetti", "Confetti", joining: .crowd,
            about: "Paper fluttering down, and more of it still coming.",
            join: "New bodies flutter down with the rest."
        ),
        ParticleArrangement(
            "fire", "Fire", joining: .crowd,
            about: "A column of flame that keeps burning.",
            join: "New bodies rise and burn with the flame.",
            view: .low
        ),
        ParticleArrangement(
            "smoke", "Smoke", joining: .crowd,
            about: "A slow grey plume that keeps rising.",
            join: "New bodies drift up with the smoke.",
            view: .low
        ),
        ParticleArrangement(
            "text", "Word", joining: .crowd,
            about: "The word typed below, spelt out in bodies.",
            join: "New bodies take a place in the letters.",
            inDepth: "The word typed below, spelt out as solid letters with a thickness to them."
        ),
        // Only in 3D.
        ParticleArrangement(
            "globe", "Globe", joining: .crowd,
            about: "Seeds a golden turn apart all over a ball, turning like a globe on its stand.",
            join: "New bodies take a place on the globe.",
            depth: .only
        ),
        ParticleArrangement(
            "knot", "Knot", joining: .crowd,
            about: "A trefoil knot of bodies, turning slowly so it can be seen from every side.",
            join: "New bodies take a place in the knot.",
            depth: .only
        ),
        ParticleArrangement(
            "ocean", "Ocean", joining: .crowd,
            about: "A sheet of bodies with waves rolling across it, each body turning in its own small circle.",
            join: "New bodies ride the waves.",
            depth: .only,
            view: .above
        ),
        ParticleArrangement(
            "lorenz", "Lorenz", joining: .crowd,
            about: "Bodies following the Lorenz flow, the butterfly-shaped path of the weather sum that gave chaos "
                + "its name.",
            join: "New bodies follow the flow.",
            depth: .only
        ),
        ParticleArrangement(
            "aizawa", "Aizawa", joining: .crowd,
            about: "A flow that wraps round a ball, with a tube running up through the middle of it.",
            join: "New bodies follow the flow.",
            depth: .only
        ),
        ParticleArrangement(
            "thomas", "Thomas", joining: .crowd,
            about: "A flow that wanders forever through a knot of loops, the same whichever way it is turned.",
            join: "New bodies follow the flow.",
            depth: .only
        ),
        ParticleArrangement(
            "halvorsen", "Halvorsen", joining: .crowd,
            about: "A flow with three looping arms, each a third of the way round from the last.",
            join: "New bodies follow the flow.",
            depth: .only
        ),
        ParticleArrangement(
            "warp", "Warp", joining: .crowd,
            about: "Stars rushing past, as though flying through space.",
            join: "New stars rush past with the rest.",
            depth: .only,
            view: .front
        ),
        ParticleArrangement(
            "snowglobe", "Snow globe", joining: .crowd,
            about: "Snow drifting down inside a glass ball. With Tilt on, tip the phone to stir it up.",
            join: "New bodies fall as more snow.",
            depth: .only
        ),
        // Added to whatever is there.
        ParticleArrangement(
            "burst", "Burst", kind: .addition, joining: .none,
            about: "Throws a ring of charged bodies out from the middle, into whatever is already there.",
            join: ""
        ),
    ]

    /// One arrangement by its identifier.
    public static func named(_ id: String?) -> ParticleArrangement? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// The scenes, which are what can be selected.
    public static var scenes: [ParticleArrangement] { all.filter { $0.kind == .scene } }

    /// The scenes that have a flat form.
    public static var flatScenes: [ParticleArrangement] { scenes.filter { $0.depth == .both } }
}

extension ParticleEngine {
    /// Which arrangement the field is showing, or nothing once it has been cleared.
    ///
    /// Set by laying one out and by nothing else. Adding bodies, drawing walls or pushing things about does
    /// not change it — the field is still that arrangement, with things done to it — and clearing the field
    /// is the only thing that ends it.
    public var arrangement: String? {
        get { storedArrangement }
        set {
            storedArrangement = newValue
            arrangementAge = 0
        }
    }

    /// The full description of what the field is showing.
    public var arrangementDetails: ParticleArrangement? {
        ParticleArrangement.named(storedArrangement)
    }

    /// Whether bodies added now can take part in what the field is doing.
    public var canJoinArrangement: Bool {
        guard let details = arrangementDetails else { return false }
        return details.kind == .scene && details.joining != .none
    }

    /// Empties the field and sets up the world one arrangement is built for.
    ///
    /// ## Why every arrangement sets the whole world
    ///
    /// Most of them used to set gravity downward and nothing else, or nothing at all. Whatever the one
    /// before had left behind carried straight in: a sunflower laid out after the fountain fell to the
    /// floor within a second, the same sunflower laid out after the galaxy stayed put, and a fire's
    /// upward gravity was still there in whatever came next. The same chip did different things depending
    /// on what had been tapped before it — which, from the outside, is simply broken.
    ///
    /// Now each one says what it needs: which way is down, and whether bodies in the crowd push one
    /// another apart. The wind is switched off unless an arrangement wants it, and anything playing on the
    /// timeline is paused, since it would overwrite all of this on the very next moment.
    ///
    /// The person's own settings — damping, bounciness, the speed limit, how hard a finger pushes, the
    /// colour and the shape — are left alone. Those are how somebody likes the field, not what the
    /// arrangement is.
    func beginScene(
        _ id: String,
        gravityX: Double = 0,
        gravityY: Double,
        collisions: Bool = false
    ) {
        clear()
        self.gravityX = gravityX
        self.gravityY = gravityY
        collisionsEnabled = collisions
        storedFlowEnabled = false
        arrangement = id
    }

    /// How many object bodies an arrangement built from them is given.
    ///
    /// Fewer on a narrow world, so a small window does not get a galaxy too dense to see through.
    var arrangementBodyCount: Int { layoutWidth < 500 ? 220 : 380 }

    /// Lays out an arrangement by name.
    ///
    /// - Returns: whether the name was one the field knows. The word is the one arrangement this cannot lay
    ///   out on its own, because drawing letters needs fonts; the app draws them and hands over the picture.
    @discardableResult
    public func loadArrangement(_ id: String) -> Bool {
        // Something that only exists in depth turns 3D on. The field is kept as it was for undo first, flat, so
        // one press brings back the flat field and not its bodies in a box.
        if !storedDepthEnabled, ParticleArrangement.named(id)?.depth == .only {
            pushUndo()
            storedDepthEnabled = true
            let wasSuppressed = undoSuppressed
            undoSuppressed = true
            defer { undoSuppressed = wasSuppressed }
            return loadArrangement(id)
        }
        let count = arrangementBodyCount
        switch id {
        case "galaxy": spawnGalaxy(count: count)
        case "blackhole": spawnBlackHole(count: count)
        case "vortex": spawnDoubleVortex(count: count)
        case "flare": spawnSolarFlare(count: count)
        case "synchrotron": spawnSynchrotron(count: count)
        case "shockwave": spawnShockwave(count: count)
        case "fountain": spawnCosmicFountain(count: count)
        case "waterfall": spawnWaterfall(count: count)
        case "pour": spawnPour()
        case "lattice": spawnQuantumLattice()
        case "helix": spawnDnaHelix()
        case "flock": spawnFlock()
        case "nbody": spawnNbody()
        case "cloth": spawnCloth()
        case "rope": spawnRope()
        case "blob": spawnBlob()
        case "burst": spawnBurst(count: count)
        case "swarm": spawnSwarmScene()
        case "sunflower": spawnSunflower()
        case "mandala": spawnMandala()
        case "snowflakes": spawnSnowflakes()
        case "tornado": spawnTornado()
        case "lightning": spawnLightning()
        case "aurora": spawnAurora()
        case "supernova": spawnSupernova()
        case "sierpinski": spawnSierpinski()
        case "fireworks": spawnFireworks()
        case "magma": spawnMagma()
        case "confetti": spawnConfetti()
        case "molecules": spawnMolecules()
        case "ring": spawnRing()
        case "water": spawnWaterPool()
        case "fire": spawnFire()
        case "smoke": spawnSmoke()
        case "globe": spawnGlobe()
        case "knot": spawnKnot()
        case "ocean": spawnOcean()
        case "lorenz", "aizawa", "thomas", "halvorsen": spawnStrangeAttractor(id)
        case "warp": spawnWarp()
        case "snowglobe": spawnSnowGlobe()
        default: return false
        }
        return true
    }

    /// A hundred and twenty thousand bodies loose in the field.
    public func spawnSwarmScene(count: Int = 120_000) {
        beginScene("swarm", gravityY: 0.3)
        swarm.spawn(
            count: count,
            width: width,
            height: height,
            color: 0,
            budget: max(0, maxParticles - particles.count),
            rng: &rng,
            span: patternSpan * 0.42,
            // In 3D, a ball rather than a ring, kept inside the box.
            inDepth: worldDepth
        )
    }

    // MARK: - Arrangements that keep going

    /// Moves on whatever the arrangement does by itself over time.
    ///
    /// Most arrangements are laid out once and then left to the physics. Two are events that happen again
    /// and again, and without this they happened once and stopped: a storm that struck a single time and
    /// then left a line of dots lying on the floor, and a fireworks display of one volley followed by nothing
    /// but embers bouncing about. Those are what people meant, reasonably, by a scene being broken.
    func stepArrangement() {
        guard let id = storedArrangement else { return }
        arrangementAge += 1
        switch id {
        case "lightning":
            // Every second and a half or so, a little irregularly, so it reads as weather rather than as a
            // metronome.
            if arrangementAge % 84 == 0 || (arrangementAge % 84 == 41 && rng.chance(0.35)) {
                strikeLightning(count: 900)
            }
        case "fireworks":
            if arrangementAge % 38 == 0 {
                launchShell(count: 220)
            }
        default:
            break
        }
    }
}
