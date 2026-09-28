/// Worlds within worlds: dive into one body of the field and find a whole simulation inside it — and inside one of
/// its bodies, another.
///
/// ## Why the same body always holds the same world
///
/// Because it is a place. Somebody who dives into the third star from the left, backs out, and dives in again should
/// find what they found the first time, or it is a slot machine rather than a world. So what is inside a body is
/// decided from the body itself — its identifier, its colour and how deep it already is — and the inside is laid out
/// from a seed made of the same things. Nothing is stored for a world nobody has visited, and there is no end to how
/// deep it goes.
///
/// ## What is inside
///
/// One of a dozen of the field's own arrangements, the ones that stand on their own in a flat field — a galaxy, a
/// jellyfish, a flock, particle life — tinted towards the colour of the body it is inside, so the inside of a red body
/// is a red world. The atom was on the list and is not: it exists only in 3D, and going inside a body switched the
/// field into depth, which the checks caught.
public struct WorldWithin: Sendable, Equatable {
    /// Which arrangement is inside.
    public var arrangement: String
    /// What it is called, for saying where you are.
    public var name: String
    /// The seed its bodies are laid out from.
    public var seed: UInt32
    /// The colour of the body it is inside, as a hue in degrees.
    public var hue: Double
    /// How far down it is: one for the first world inside the field, two for a world inside that, and so on.
    public var depth: Int
}

extension ParticleEngine {
    /// The arrangements a body can hold: flat, whole on their own, and each clearly a different sort of place.
    public static let insideArrangements = [
        "galaxy", "jellyfish", "life", "solar", "blackhole", "vortex",
        "flock", "synchrotron", "sunflower", "mandala", "lattice", "helix",
    ]

    /// What is inside a body. The same body, at the same depth, always holds the same world.
    ///
    /// - Parameters:
    ///   - bodyID: which body: its identifier in the field itself, and its place in the list in a world within, where
    ///     the bodies are laid out afresh on every visit and so are numbered afresh too, but always in the same order.
    ///   - outerSeed: the seed of the world the body is in, nought for the field itself, so the fifth body of one
    ///     galaxy and the fifth of another hold different worlds.
    public static func worldWithin(bodyID: Int, hue: Double, depth: Int, outerSeed: UInt32 = 0) -> WorldWithin {
        // Mixed well enough that neighbouring bodies hold unrelated worlds, rather than a run of galaxies.
        var mixed = UInt32(truncatingIfNeeded: bodyID &* 0x9E37_79B1)
        mixed ^= UInt32(truncatingIfNeeded: depth &* 0x85EB_CA6B)
        mixed ^= UInt32(truncatingIfNeeded: Int((hue.isFinite ? hue : 0).rounded()) &* 0xC2B2_AE35)
        mixed ^= outerSeed &* 0x27D4_EB2F
        mixed ^= mixed >> 16
        mixed = mixed &* 0x7FEB_352D
        mixed ^= mixed >> 15
        let arrangement = insideArrangements[Int(mixed % UInt32(insideArrangements.count))]
        let name = ParticleArrangement.named(arrangement)?.name ?? arrangement
        return WorldWithin(arrangement: arrangement, name: name, seed: mixed | 1, hue: hue, depth: max(1, depth))
    }

    /// The body nearest a place, within a reach, if there is one. Object bodies only: the crowd's members have no
    /// identity to be the same body tomorrow.
    public func body(nearX x: Double, y: Double, within reach: Double) -> ParticleObject? {
        var best: ParticleObject?
        var bestDistance = Double.infinity
        for body in particles {
            let dx = body.x - x
            let dy = body.y - y
            let distance = dx * dx + dy * dy
            // A big body can be touched at its edge, not only at its middle.
            let allowed = (reach + body.radius) * (reach + body.radius)
            if distance <= allowed, distance < bestDistance {
                best = body
                bestDistance = distance
            }
        }
        return best
    }

    /// Replaces the field with the world inside a body.
    ///
    /// No undo point: the field it replaces is not lost, it is the world outside, and coming back out is how to get
    /// to it — the caller keeps it.
    public func enter(_ world: WorldWithin) {
        let wasSuppressed = undoSuppressed
        undoSuppressed = true
        defer { undoSuppressed = wasSuppressed }
        storedDepthEnabled = false
        rng = Mulberry32(seed: world.seed)
        loadArrangement(world.arrangement)
        tint(towardsHue: world.hue)
    }

    /// Draws every body's colour part of the way towards one hue, keeping how light each was.
    func tint(towardsHue hue: Double) {
        guard hue.isFinite else { return }
        for index in particles.indices {
            let colour = particles[index].color
            let (own, saturation, lightness) = Self.hsl(colour)
            // The short way round the colour wheel, half the way.
            var gap = hue - own
            while gap > 180 { gap -= 360 }
            while gap < -180 { gap += 360 }
            particles[index].color = PackedColor(
                hue: own + gap * 0.6,
                saturation: max(0.35, saturation),
                lightness: lightness
            )
        }
    }

    /// A colour as hue in degrees, saturation and lightness, each nought to one.
    static func hsl(_ colour: PackedColor) -> (hue: Double, saturation: Double, lightness: Double) {
        let r = Double(colour.r) / 255
        let g = Double(colour.g) / 255
        let b = Double(colour.b) / 255
        let high = max(r, g, b)
        let low = min(r, g, b)
        let lightness = (high + low) / 2
        let spread = high - low
        guard spread > 1e-9 else { return (0, 0, lightness) }
        let saturation = spread / (1 - abs(2 * lightness - 1))
        var hue: Double
        if high == r {
            hue = ((g - b) / spread).truncatingRemainder(dividingBy: 6)
        } else if high == g {
            hue = (b - r) / spread + 2
        } else {
            hue = (r - g) / spread + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (hue, min(1, saturation), lightness)
    }
}
