/// Colour ramps for the particle field.
///
/// Until now the field chose colours by arithmetic on a hue: speed became a number between 0 and
/// 240 degrees, position became a number modulo 360, and so on. That gives six looks and no way to
/// ask for a seventh. A palette is the other way round — a short list of colours, and a number
/// between nought and one saying how far along the list to look. The same number can drive any set
/// of colours, so the question "what does the colour mean" is separated from "which colours".
///
/// The seven named ramps, the way a ramp is sampled, and the tint are taken from the reference
/// particle sandbox this was merged from; see `HELION-MERGE.md`, slice A. Two things about that
/// reference are worth stating because they are easy to get wrong by being clever:
///
///   - **Blending is linear in ordinary sRGB, not in light.** Mixing `#000000` and `#ffffff`
///     half-and-half gives `#808080`, which is *not* the colour halfway between them in brightness.
///     Doing it properly (squaring, mixing, square-rooting) makes every ramp read paler in the
///     middle, and the ramps were chosen by eye against the naive blend. So the naive blend is kept
///     deliberately, and this paragraph exists so nobody fixes it by accident.
///   - **Stops are evenly spaced.** A named ramp carries no positions, only colours; the first sits
///     at nought, the last at one, the rest spread evenly between.
///
/// Everything here is arithmetic on numbers. It compiles and is tested on any machine.

// MARK: - The named ramps

/// One of the built-in colour ramps.
public enum ParticlePalette: String, Sendable, Hashable, CaseIterable, Codable {
    case rainbow
    case ember
    case ice
    case aurora
    case solar
    case mono
    case plasma

    /// The colours of the ramp, in order, evenly spaced from nought to one.
    public var stops: [PackedColor] {
        switch self {
        case .rainbow:
            return [
                PackedColor(r: 220, g: 32, b: 64),
                PackedColor(r: 255, g: 128, b: 24),
                PackedColor(r: 255, g: 214, b: 48),
                PackedColor(r: 46, g: 196, b: 92),
                PackedColor(r: 36, g: 156, b: 255),
                PackedColor(r: 92, g: 72, b: 255),
                PackedColor(r: 188, g: 56, b: 210),
            ]
        case .ember:
            return [
                PackedColor(r: 8, g: 4, b: 6),
                PackedColor(r: 92, g: 14, b: 8),
                PackedColor(r: 188, g: 42, b: 10),
                PackedColor(r: 255, g: 118, b: 24),
                PackedColor(r: 255, g: 198, b: 86),
                PackedColor(r: 255, g: 246, b: 220),
            ]
        case .ice:
            return [
                PackedColor(r: 4, g: 10, b: 22),
                PackedColor(r: 12, g: 48, b: 92),
                PackedColor(r: 24, g: 128, b: 186),
                PackedColor(r: 120, g: 210, b: 255),
                PackedColor(r: 236, g: 248, b: 255),
            ]
        case .aurora:
            return [
                PackedColor(r: 4, g: 18, b: 16),
                PackedColor(r: 12, g: 78, b: 68),
                PackedColor(r: 36, g: 168, b: 132),
                PackedColor(r: 140, g: 232, b: 188),
                PackedColor(r: 230, g: 255, b: 242),
            ]
        case .solar:
            return [
                PackedColor(r: 18, g: 8, b: 2),
                PackedColor(r: 160, g: 62, b: 8),
                PackedColor(r: 240, g: 148, b: 28),
                PackedColor(r: 255, g: 214, b: 110),
                PackedColor(r: 255, g: 248, b: 226),
            ]
        case .mono:
            return [
                PackedColor(r: 12, g: 13, b: 16),
                PackedColor(r: 90, g: 94, b: 104),
                PackedColor(r: 188, g: 192, b: 200),
                PackedColor(r: 244, g: 246, b: 248),
            ]
        case .plasma:
            return [
                PackedColor(r: 6, g: 8, b: 28),
                PackedColor(r: 20, g: 64, b: 168),
                PackedColor(r: 48, g: 168, b: 210),
                PackedColor(r: 255, g: 170, b: 70),
                PackedColor(r: 255, g: 244, b: 220),
            ]
        }
    }

    /// A name for the interface.
    public var displayName: String {
        switch self {
        case .rainbow: return "Rainbow"
        case .ember: return "Ember"
        case .ice: return "Ice"
        case .aurora: return "Aurora"
        case .solar: return "Solar"
        case .mono: return "Mono"
        case .plasma: return "Plasma"
        }
    }

    /// The colour at `position` along the ramp, where nought is the first stop and one the last.
    ///
    /// Anything outside that range, and anything that is not a usable number, is pulled back into
    /// it — a particle whose speed has gone to not-a-number still gets a colour rather than
    /// bringing the frame down.
    public func sample(_ position: Double) -> PackedColor {
        ParticlePalette.sample(stops: stops, at: position)
    }

    /// Samples an evenly spaced list of colours.
    ///
    /// Shared with the two-colour gradient below, which is the same thing with two entries.
    static func sample(stops: [PackedColor], at position: Double) -> PackedColor {
        guard let first = stops.first else { return PackedColor(r: 0, g: 0, b: 0) }
        guard stops.count > 1 else { return first }

        let t = position.isFinite ? max(0, min(1, position)) : 0
        let scaled = t * Double(stops.count - 1)
        // The floor is capped one short of the end so that a position of exactly one lands on the
        // last pair with a fraction of one, rather than on a pair that does not exist.
        let index = min(stops.count - 2, max(0, Int(scaled)))
        let fraction = scaled - Double(index)

        let low = stops[index]
        let high = stops[index + 1]
        return PackedColor(
            r: Self.mix(low.r, high.r, fraction),
            g: Self.mix(low.g, high.g, fraction),
            b: Self.mix(low.b, high.b, fraction)
        )
    }

    /// Blends two channel values. Plain linear, in sRGB — see the note at the top of the file.
    @inlinable
    static func mix(_ low: UInt8, _ high: UInt8, _ fraction: Double) -> UInt8 {
        let a = Double(low)
        let b = Double(high)
        let value = a + (b - a) * fraction
        return UInt8(max(0, min(255, value.rounded())))
    }
}

// MARK: - Hand-made gradients

/// One colour placed somewhere along a hand-made gradient.
public struct ParticleGradientStop: Sendable, Hashable, Codable {
    /// Where the colour sits, from nought to one.
    public var position: Double
    /// The colour.
    public var color: PackedColor

    public init(position: Double, color: PackedColor) {
        self.position = position
        self.color = color
    }
}

extension ParticleGradientStop {
    /// Puts a list of stops into a usable state, or reports that it cannot be used.
    ///
    /// Stops arrive from saved files and from the editor, so they may be out of order, may sit
    /// outside the range, and may be too few to describe a gradient at all. This drops what cannot
    /// be used, pulls positions into range, and sorts.
    ///
    /// The sort keeps the original order of stops that share a position. Swift's own sort does not
    /// promise that, so the index is carried along and used to break ties — otherwise two stops
    /// dropped at the same place could swap on any given run and the gradient would flicker between
    /// launches for no visible reason.
    public static func normalized(_ stops: [ParticleGradientStop]) -> [ParticleGradientStop] {
        var keyed: [(stop: ParticleGradientStop, order: Int)] = []
        keyed.reserveCapacity(stops.count)
        for (order, stop) in stops.enumerated() {
            guard stop.position.isFinite else { continue }
            keyed.append(
                (
                    ParticleGradientStop(
                        position: max(0, min(1, stop.position)),
                        color: stop.color
                    ),
                    order
                )
            )
        }
        keyed.sort { left, right in
            left.stop.position == right.stop.position
                ? left.order < right.order
                : left.stop.position < right.stop.position
        }
        return keyed.map(\.stop)
    }

    /// Whether a list of stops describes a gradient. Fewer than two colours does not.
    public static func describesGradient(_ stops: [ParticleGradientStop]) -> Bool {
        normalized(stops).count >= 2
    }

    /// The colour at `position` along an already-normalised list of stops.
    ///
    /// Before the first stop and after the last, the end colour holds. It is not extrapolated:
    /// continuing the last pair's slope past the end would run the colour off into a channel clamp
    /// and read as a flat block of red or white, which looks like a fault rather than a choice.
    public static func sample(normalized stops: [ParticleGradientStop], at position: Double) -> PackedColor {
        guard let first = stops.first else { return PackedColor(r: 0, g: 0, b: 0) }
        guard let last = stops.last, stops.count > 1 else { return first.color }

        let t = position.isFinite ? max(0, min(1, position)) : 0
        if t <= first.position { return first.color }
        if t >= last.position { return last.color }

        for index in 0 ..< (stops.count - 1) {
            let low = stops[index]
            let high = stops[index + 1]
            guard t >= low.position, t <= high.position else { continue }
            let span = high.position - low.position
            let fraction = span <= 1e-9 ? 0 : (t - low.position) / span
            return PackedColor(
                r: ParticlePalette.mix(low.color.r, high.color.r, fraction),
                g: ParticlePalette.mix(low.color.g, high.color.g, fraction),
                b: ParticlePalette.mix(low.color.b, high.color.b, fraction)
            )
        }
        return last.color
    }

    /// Spreads a list of colours evenly into stops.
    public static func evenlySpaced(_ colors: [PackedColor]) -> [ParticleGradientStop] {
        guard colors.count > 1 else {
            return colors.first.map { [ParticleGradientStop(position: 0, color: $0)] } ?? []
        }
        return colors.enumerated().map { index, color in
            ParticleGradientStop(position: Double(index) / Double(colors.count - 1), color: color)
        }
    }
}

// MARK: - Which colours, all together

/// The full description of what colours the field is drawn in.
///
/// Three ways to say it, in order of precedence: a hand-made gradient of any number of stops, a
/// simple fade between two colours, or one of the named ramps. Whichever applies, the result is
/// then multiplied by a tint.
///
/// Precedence rather than a mode flag, because that is how the interface behaves: dropping a second
/// stop into the editor should start using the gradient without also having to find a switch.
public struct ParticlePaletteSpec: Sendable, Hashable, Codable {
    /// The named ramp, used when neither of the other two applies.
    public var palette: ParticlePalette
    /// A hand-made gradient. Used when it has two or more usable stops.
    public var stops: [ParticleGradientStop]
    /// The start of a simple two-colour fade. Used when it differs from ``fadeTo``.
    public var fadeFrom: PackedColor
    /// The end of a simple two-colour fade.
    public var fadeTo: PackedColor
    /// Multiplied into the result, channel by channel. White leaves the colours alone.
    public var tint: PackedColor

    public init(
        palette: ParticlePalette = .rainbow,
        stops: [ParticleGradientStop] = [],
        fadeFrom: PackedColor = PackedColor(r: 255, g: 255, b: 255),
        fadeTo: PackedColor = PackedColor(r: 255, g: 255, b: 255),
        tint: PackedColor = PackedColor(r: 255, g: 255, b: 255)
    ) {
        self.palette = palette
        self.stops = stops
        self.fadeFrom = fadeFrom
        self.fadeTo = fadeTo
        self.tint = tint
    }

    /// The default: the rainbow ramp, no gradient, no fade, no tint.
    public static let `default` = ParticlePaletteSpec()

    /// How many entries a baked lookup has. A palette is a smooth thing being sampled by a number
    /// between nought and one; 256 steps is finer than a screen can show at any one brightness.
    public static let lookupSize = 256

    /// The colour at `position`, with the tint applied.
    public func sample(_ position: Double) -> PackedColor {
        let base: PackedColor
        let normalizedStops = ParticleGradientStop.normalized(stops)
        if normalizedStops.count >= 2 {
            base = ParticleGradientStop.sample(normalized: normalizedStops, at: position)
        } else if fadeFrom != fadeTo {
            base = ParticlePalette.sample(stops: [fadeFrom, fadeTo], at: position)
        } else {
            base = palette.sample(position)
        }
        return Self.tinted(base, by: tint)
    }

    /// Multiplies a colour by a tint, channel by channel.
    ///
    /// Each channel is treated as a fraction of full, so a tint of white changes nothing and a tint
    /// of half-grey halves everything. Alpha is left alone; a tint is about colour, not opacity.
    static func tinted(_ color: PackedColor, by tint: PackedColor) -> PackedColor {
        guard tint.r != 255 || tint.g != 255 || tint.b != 255 else { return color }
        func scale(_ channel: UInt8, _ by: UInt8) -> UInt8 {
            UInt8((Double(channel) * Double(by) / 255).rounded())
        }
        return PackedColor(
            r: scale(color.r, tint.r),
            g: scale(color.g, tint.g),
            b: scale(color.b, tint.b),
            a: color.a
        )
    }

    /// Bakes the whole ramp into a fixed-size table of packed colours.
    ///
    /// The drawing path wants a colour many times a frame for many particles. Sampling walks a list
    /// of stops each time; a table is one index. This is the form the GPU takes as a texture, and
    /// the form the swarm recolouring pass reads.
    public func bakeLookup(size: Int = ParticlePaletteSpec.lookupSize) -> [UInt32] {
        let count = max(2, size)
        var table = [UInt32](repeating: 0, count: count)
        for index in 0 ..< count {
            table[index] = sample(Double(index) / Double(count - 1)).packedRGBA
        }
        return table
    }
}

// MARK: - Turning a picture into a palette

extension ParticlePaletteSpec {
    /// Picks the most-used colours out of an image.
    ///
    /// This is what lets a photograph become a palette. Colours are lumped together by throwing
    /// away the low bits of each channel — with the default four bits that is sixteen levels per
    /// channel, so near-identical shades count as one colour — then the buckets are ordered by how
    /// many pixels landed in each, and the average of each of the most popular buckets is returned.
    ///
    /// The average rather than the bucket's nominal centre, so the result is a colour that actually
    /// occurs in the picture rather than a rounded-off approximation of one.
    ///
    /// Fully transparent pixels are skipped: a cut-out on a transparent background would otherwise
    /// come back as a palette of one colour, and that colour would be invisible.
    ///
    /// - Parameters:
    ///   - pixels: Packed colours, as ``PackedColor/packedRGBA`` produces them.
    ///   - count: How many colours to return.
    ///   - bits: How many of the top bits of each channel to keep, one to eight.
    public static func colors(
        inImage pixels: [UInt32],
        count: Int,
        bits: Int = 4
    ) -> [PackedColor] {
        guard count > 0, !pixels.isEmpty else { return [] }
        let shift = 8 - max(1, min(8, bits))

        // Sums are kept per bucket so the average can be taken at the end. A dictionary rather
        // than a dense table: with four bits there are 4,096 possible buckets and a photograph
        // touches a small fraction of them.
        struct Bucket {
            var red = 0
            var green = 0
            var blue = 0
            var population = 0
        }
        var buckets: [Int: Bucket] = [:]
        var order: [Int] = []

        for packed in pixels {
            let color = PackedColor(packedRGBA: packed)
            guard color.a != 0 else { continue }
            let key = (Int(color.r) >> shift) << 16
                | (Int(color.g) >> shift) << 8
                | (Int(color.b) >> shift)
            if buckets[key] == nil {
                buckets[key] = Bucket()
                order.append(key)
            }
            buckets[key]!.red += Int(color.r)
            buckets[key]!.green += Int(color.g)
            buckets[key]!.blue += Int(color.b)
            buckets[key]!.population += 1
        }

        // Ordered by population, and by first appearance when two buckets tie, so the same picture
        // always yields the same palette.
        let ranked = order.sorted { left, right in
            let leftBucket = buckets[left]!
            let rightBucket = buckets[right]!
            if leftBucket.population != rightBucket.population {
                return leftBucket.population > rightBucket.population
            }
            return (order.firstIndex(of: left) ?? 0) < (order.firstIndex(of: right) ?? 0)
        }

        return ranked.prefix(count).map { key in
            let bucket = buckets[key]!
            let population = max(1, bucket.population)
            return PackedColor(
                r: UInt8(max(0, min(255, (Double(bucket.red) / Double(population)).rounded()))),
                g: UInt8(max(0, min(255, (Double(bucket.green) / Double(population)).rounded()))),
                b: UInt8(max(0, min(255, (Double(bucket.blue) / Double(population)).rounded())))
            )
        }
    }

    /// Builds a gradient from the most-used colours in an image.
    public static func fromImage(_ pixels: [UInt32], stopCount: Int = 5, bits: Int = 4) -> ParticlePaletteSpec {
        let colors = Self.colors(inImage: pixels, count: stopCount, bits: bits)
        var spec = ParticlePaletteSpec()
        spec.stops = ParticleGradientStop.evenlySpaced(colors)
        return spec
    }
}
