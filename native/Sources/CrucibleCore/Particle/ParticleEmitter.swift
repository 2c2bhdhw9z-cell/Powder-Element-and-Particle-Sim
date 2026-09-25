/// A source that pours bodies into the world.
///
/// The field already had an emitter tool. It threw in six bodies a frame, in a random direction, at a random
/// speed, for as long as a finger was held down, and not one of those numbers could be changed — so it was
/// the one tool with no character of its own. A source is not an interesting thing because it emits; it is
/// interesting because of *how*: a narrow fast jet, a slow wide plume, a fountain, a drip.
///
/// It also could not be left running. Everything a source is good for — a waterfall that keeps falling, a
/// chimney that keeps smoking, two jets aimed at each other — needs it to stay where it was put.
///
/// ## Why the rate is counted the way it is
///
/// The old one emitted six bodies *per frame*, which means it poured twice as fast on a phone running at a
/// hundred and twenty as on one running at sixty — and slowed down whenever the field got busy, which is
/// exactly when it should not. Here the rate is bodies per second of simulated time, and the fraction left
/// over is carried to the next moment. A rate of ten on a field running at sixty emits one body every six
/// moments, reliably, forever; the same rate on a field struggling at twenty emits one every two.
///
/// This is the one piece of the reference implementation's design that the read called "the right way and
/// worth copying exactly", and then did not copy. See the gap audit in `HELION-MERGE.md`.
public struct ParticleEmitter: Sendable, Hashable, Codable {
    /// Where it is, as a fraction of the world, so it stays put when the world grows.
    public var atFractionX: Double
    public var atFractionY: Double
    /// Which way it points, in radians. Nought is to the right; a quarter turn is downward.
    public var direction: Double
    /// How many bodies a second.
    public var rate: Double
    /// How wide a fan it sprays, in radians. Nought is a perfectly straight line.
    public var spread: Double
    /// How fast the bodies leave, in pixels a moment.
    public var speed: Double
    /// How much that speed varies, as a fraction of it.
    public var speedVariation: Double
    /// How long each body lasts, in moments. Nought or less means forever.
    public var lifespan: Double
    /// How heavy each body is.
    public var weight: Double
    /// How much the weight varies, as a fraction of it.
    public var weightVariation: Double
    /// What colour, as a hue in degrees. Negative means take a random one.
    public var hue: Double
    /// Whether it is pouring.
    public var isRunning: Bool

    /// How much of a body is owed from the moments already passed.
    ///
    /// This is what makes the rate mean bodies a second rather than bodies a frame: a rate that works out to
    /// two-fifths of a body this moment leaves two-fifths owed, and five moments later that is two bodies.
    /// Without it, any rate below one body a moment rounds to nothing and the source never emits at all.
    public var owed: Double = 0

    public init(
        atFractionX: Double,
        atFractionY: Double,
        direction: Double = 1.5707963267948966,
        rate: Double = 90,
        spread: Double = 0.5,
        speed: Double = 4,
        speedVariation: Double = 0.4,
        lifespan: Double = 0,
        weight: Double = 1,
        weightVariation: Double = 0,
        hue: Double = -1,
        isRunning: Bool = true
    ) {
        self.atFractionX = atFractionX
        self.atFractionY = atFractionY
        self.direction = direction
        self.rate = rate
        self.spread = spread
        self.speed = speed
        self.speedVariation = speedVariation
        self.lifespan = lifespan
        self.weight = weight
        self.weightVariation = weightVariation
        self.hue = hue
        self.isRunning = isRunning
    }

    /// The emitter with every number pulled into a range it can work in.
    public var sanitized: ParticleEmitter {
        var out = self
        out.atFractionX = Self.clamp(atFractionX, -0.5, 1.5, fallback: 0.5)
        out.atFractionY = Self.clamp(atFractionY, -0.5, 1.5, fallback: 0.5)
        out.direction = direction.isFinite ? direction : 1.5707963267948966
        out.rate = Self.clamp(rate, 0, 6_000, fallback: 90)
        // Never wider than a full turn: past that the fan overlaps itself and widening it further does
        // nothing, so the slider would have a dead half.
        out.spread = Self.clamp(spread, 0, 3.141592653589793, fallback: 0.5)
        out.speed = Self.clamp(speed, 0, 60, fallback: 4)
        out.speedVariation = Self.clamp(speedVariation, 0, 1, fallback: 0.4)
        out.lifespan = Self.clamp(lifespan, 0, 3_600, fallback: 0)
        out.weight = Self.clamp(weight, 0.05, 20, fallback: 1)
        out.weightVariation = Self.clamp(weightVariation, 0, 1, fallback: 0)
        out.hue = hue.isFinite ? hue : -1
        out.owed = Self.clamp(owed, 0, 1_000, fallback: 0)
        return out
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

    /// A reasonable name for one, for a list in the interface.
    public var summary: String {
        let direction = Self.compass(self.direction)
        return "\(Int(rate.rounded()))/s \(direction)"
    }

    /// Which way an angle points, in words.
    ///
    /// Words rather than degrees, because a list of sources reading "1.57 rad" tells nobody anything, and the
    /// whole reason for the list is telling one source from another at a glance.
    static func compass(_ radians: Double) -> String {
        guard radians.isFinite else { return "—" }
        let turn = 6.283185307179586
        let wrapped = ((radians.truncatingRemainder(dividingBy: turn)) + turn)
            .truncatingRemainder(dividingBy: turn)
        let eighth = Int(((wrapped / turn) * 8).rounded()) % 8
        // The world's vertical axis grows downward, so a quarter turn is down rather than up.
        switch eighth {
        case 0: return "right"
        case 1: return "down and right"
        case 2: return "down"
        case 3: return "down and left"
        case 4: return "left"
        case 5: return "up and left"
        case 6: return "up"
        default: return "up and right"
        }
    }
}

extension ParticleEngine {
    /// How many sources may be running at once.
    ///
    /// Twelve. Not a cost limit — a source is a handful of bodies a moment — but a limit on how much of the
    /// screen can be covered in markers before the markers are the picture.
    public static let emitterLimit = 12

    /// The sources pouring into the world.
    public var emitters: [ParticleEmitter] {
        get { storedEmitters }
        set {
            storedEmitters = newValue.count <= Self.emitterLimit
                ? newValue
                : Array(newValue.suffix(Self.emitterLimit))
        }
    }

    /// What a newly placed source will be like.
    ///
    /// Held separately from the sources themselves, so adjusting the numbers and *then* placing one gives
    /// what was adjusted — rather than placing a default and then having to find it in a list to change it.
    public var emitterTemplate: ParticleEmitter {
        get { storedEmitterTemplate }
        set { storedEmitterTemplate = newValue }
    }

    /// Puts a source at a place in the world, pointing whichever way it was dragged.
    @discardableResult
    public func addEmitter(atX x: Double, y: Double, direction: Double? = nil) -> Bool {
        guard width > 0, height > 0, x.isFinite, y.isFinite else { return false }
        guard storedEmitters.count < Self.emitterLimit else { return false }
        var emitter = storedEmitterTemplate
        emitter.atFractionX = x / width
        emitter.atFractionY = y / height
        if let direction, direction.isFinite { emitter.direction = direction }
        emitter.owed = 0
        emitter.isRunning = true
        storedEmitters.append(emitter.sanitized)
        return true
    }

    /// Removes one source.
    public func removeEmitter(at index: Int) {
        guard index >= 0, index < storedEmitters.count else { return }
        storedEmitters.remove(at: index)
    }

    /// Removes every source.
    public func clearEmitters() {
        storedEmitters.removeAll()
    }

    /// Pours from every running source, for one moment.
    ///
    /// Into the crowd rather than the object list, because a source left running fills a field — and the
    /// object list carries springs, charge and trails per body, none of which a poured body needs and all of
    /// which cap it at a few hundred.
    func stepEmitters() {
        guard !storedEmitters.isEmpty, width > 0, height > 0 else { return }
        let budget = maxParticles - particles.count
        guard budget > swarm.count else { return }

        for index in storedEmitters.indices {
            var emitter = storedEmitters[index].sanitized
            defer { storedEmitters[index] = emitter }
            guard emitter.isRunning, emitter.rate > 0 else { continue }

            // One moment is a sixtieth of a second, which is what every other number in the field is tuned
            // around — the step has no time in it, so one moment *is* the unit of time here.
            emitter.owed += emitter.rate / 60
            var toEmit = Int(emitter.owed)
            guard toEmit > 0 else { continue }
            emitter.owed -= Double(toEmit)
            // Capped per moment, so a rate somebody has dragged to the top cannot spend an unbounded amount
            // of a single frame emitting.
            toEmit = min(toEmit, 400)

            let atX = emitter.atFractionX * width
            let atY = emitter.atFractionY * height

            for _ in 0 ..< toEmit {
                let angle = emitter.direction + (rng.next() - 0.5) * 2 * emitter.spread
                let speed = emitter.speed * (1 + (rng.next() - 0.5) * 2 * emitter.speedVariation)
                let weight = emitter.weight * (1 + (rng.next() - 0.5) * 2 * emitter.weightVariation)
                let hue = emitter.hue >= 0 ? emitter.hue : rng.next() * 360
                let colour = PackedColor(hue: hue, saturation: 0.85, lightness: 0.62)
                let placed = swarm.append(
                    x: atX,
                    y: atY,
                    velocityX: jsCos(angle) * speed,
                    velocityY: jsSin(angle) * speed,
                    color: colour.packedRGBA,
                    budget: budget,
                    mass: weight,
                    life: emitter.lifespan > 0 ? emitter.lifespan : -1
                )
                // Full. Stop, rather than spinning through the rest of the count for nothing — and keep what
                // is owed at nought so it does not build up into a burst the moment room appears.
                guard placed else {
                    emitter.owed = 0
                    break
                }
            }
        }
    }
}
