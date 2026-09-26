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

    public var id: String
    public var name: String
    public var kind: Kind
    public var joining: Joining
    /// What it is, in a sentence, for the panel that lists them.
    public var about: String
    /// What adding bodies does while joining is on, in plain words.
    public var joinDescription: String

    public init(
        _ id: String,
        _ name: String,
        kind: Kind = .scene,
        joining: Joining,
        about: String,
        join: String
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.joining = joining
        self.about = about
        self.joinDescription = join
    }

    /// Every arrangement, in the order the interface shows them.
    public static let all: [ParticleArrangement] = [
        // Built round a centre and a force.
        ParticleArrangement(
            "galaxy", "Galaxy", joining: .orbit,
            about: "A spiral disc orbiting a black hole.",
            join: "New bodies go into orbit round the black hole."
        ),
        ParticleArrangement(
            "blackhole", "Black hole", joining: .orbit,
            about: "A heavier hole with a tighter, faster disc.",
            join: "New bodies go into orbit round the black hole."
        ),
        ParticleArrangement(
            "vortex", "Double vortex", joining: .orbit,
            about: "Two wells spinning opposite ways.",
            join: "New bodies orbit whichever well they start nearest."
        ),
        ParticleArrangement(
            "synchrotron", "Synchrotron", joining: .orbit,
            about: "Two wells far enough apart to fling bodies between them.",
            join: "New bodies join the orbit round both wells."
        ),
        ParticleArrangement(
            "flare", "Solar flare", joining: .objects,
            about: "A glowing core throwing off flares that fall back into it.",
            join: "New bodies are thrown off the core and come back to it."
        ),
        ParticleArrangement(
            "shockwave", "Shockwave", joining: .objects,
            about: "A ring blasted outward from the middle.",
            join: "New bodies ride along with the ring."
        ),
        ParticleArrangement(
            "fountain", "Cosmic fountain", joining: .objects,
            about: "A jet from the floor that falls back and is launched again.",
            join: "New bodies join the jet."
        ),
        ParticleArrangement(
            "waterfall", "Waterfall", joining: .objects,
            about: "Water falling from the top, caught and poured again.",
            join: "New bodies join the falls."
        ),
        ParticleArrangement(
            "pour", "Pour", joining: .crowd,
            about: "Liquid poured into an empty tank, splashing and settling.",
            join: "New bodies become more of the liquid."
        ),
        ParticleArrangement(
            "water", "Water", joining: .crowd,
            about: "A still pool with an inlet pouring into it.",
            join: "New bodies become more of the pool."
        ),
        ParticleArrangement(
            "lattice", "Quantum lattice", joining: .objects,
            about: "A charged grid, every point held in place by a spring.",
            join: "New bodies are held to the grid's points."
        ),
        ParticleArrangement(
            "helix", "DNA helix", joining: .objects,
            about: "Two strands winding across the field.",
            join: "New bodies join the two strands."
        ),
        ParticleArrangement(
            "flock", "Flock", joining: .objects,
            about: "Birds that steer by the ones around them.",
            join: "New bodies fly with the flock."
        ),
        ParticleArrangement(
            "nbody", "N-body", joining: .crowd,
            about: "A disc of heavy and light bodies, every one pulling on every other.",
            join: "New bodies are pulled into the disc, and pull on it."
        ),
        ParticleArrangement(
            "cloth", "Cloth", joining: .structure,
            about: "A sheet of joined points, pinned along the top.",
            join: "Each tap hangs another sheet."
        ),
        ParticleArrangement(
            "rope", "Rope", joining: .structure,
            about: "A chain hanging from a pin.",
            join: "Each tap hangs another rope."
        ),
        ParticleArrangement(
            "blob", "Blob", joining: .structure,
            about: "A soft ball held together by springs.",
            join: "Each tap drops another blob."
        ),
        ParticleArrangement(
            "molecules", "Molecules", joining: .structure,
            about: "Ball-and-stick rings, water and a carbon chain, held by their bonds.",
            join: "Each tap adds a few more molecules."
        ),
        ParticleArrangement(
            "swarm", "Swarm", joining: .crowd,
            about: "A hundred and twenty thousand bodies loose in the field.",
            join: "New bodies join the swarm."
        ),
        // Built round a shape.
        ParticleArrangement(
            "sunflower", "Sunflower", joining: .crowd,
            about: "Seeds placed a golden turn apart, turning slowly.",
            join: "New bodies take a place among the seeds."
        ),
        ParticleArrangement(
            "mandala", "Mandala", joining: .crowd,
            about: "Eight petals, three rings and eight spikes, turning slowly.",
            join: "New bodies take a place in the pattern."
        ),
        ParticleArrangement(
            "snowflakes", "Snowflakes", joining: .crowd,
            about: "Six-armed flakes, each turning on its own.",
            join: "New bodies take a place in a flake."
        ),
        ParticleArrangement(
            "sierpinski", "Sierpinski", joining: .crowd,
            about: "The triangle made of triangles, drawn by a random walk.",
            join: "New bodies take a place in the triangle."
        ),
        ParticleArrangement(
            "ring", "Ring", joining: .crowd,
            about: "A band of bodies circling, seen at a slight angle.",
            join: "New bodies circle with the ring."
        ),
        ParticleArrangement(
            "tornado", "Tornado", joining: .crowd,
            about: "A funnel, fast and narrow at the bottom, wide and slow at the top.",
            join: "New bodies spin in the funnel."
        ),
        ParticleArrangement(
            "aurora", "Aurora", joining: .crowd,
            about: "Five curtains of light, rippling.",
            join: "New bodies ripple in the curtains."
        ),
        ParticleArrangement(
            "lightning", "Lightning", joining: .crowd,
            about: "A storm: bolts that branch, flicker out, and strike again.",
            join: "New bodies flicker along the bolts."
        ),
        ParticleArrangement(
            "fireworks", "Fireworks", joining: .crowd,
            about: "A display: shells burst, fall and fade, and more go up.",
            join: "New bodies burst with the shells."
        ),
        ParticleArrangement(
            "supernova", "Supernova", joining: .crowd,
            about: "A star coming apart: a fast bright shell and a glowing remnant.",
            join: "New bodies fly out with the blast, or glow in the remnant."
        ),
        ParticleArrangement(
            "magma", "Magma", joining: .crowd,
            about: "A churning molten pool throwing up embers.",
            join: "New bodies churn in the pool or rise as embers."
        ),
        ParticleArrangement(
            "confetti", "Confetti", joining: .crowd,
            about: "Paper fluttering down, and more of it still coming.",
            join: "New bodies flutter down with the rest."
        ),
        ParticleArrangement(
            "fire", "Fire", joining: .crowd,
            about: "A column of flame that keeps burning.",
            join: "New bodies rise and burn with the flame."
        ),
        ParticleArrangement(
            "smoke", "Smoke", joining: .crowd,
            about: "A slow grey plume that keeps rising.",
            join: "New bodies drift up with the smoke."
        ),
        ParticleArrangement(
            "text", "Word", joining: .crowd,
            about: "The word typed below, spelt out in bodies.",
            join: "New bodies take a place in the letters."
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
            span: patternSpan * 0.42
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
