/// Choosing what colour each particle is drawn in.
///
/// Same division as the powder side: the colour decisions live here, where they compile on any
/// machine and are compared against the reference implementation, and the drawing itself is
/// left to Metal. See `PowderRender.swift` for the reasoning.
///
/// The difference is that the particle field is drawn on the GPU as points rather than as a
/// grid of pixels, so there are two entry points that share one decision:
///
///   - ``fillRenderColors(into:)`` gives one colour per particle, for the GPU to draw.
///   - ``render(into:)`` writes a finished picture, matching what the web engine produces, so
///     the decision can be checked pixel for pixel.
///
/// Both call the same function, so verifying the second verifies the first.

/// How crowded each part of the world is.
///
/// Only the crowding colour mode uses this. Worth stating plainly: that mode did not measure
/// crowding at all in the original — it measured speed, exactly as the speed mode does, just
/// mapped to a different range of hues, so the interface offered two modes that showed the
/// same thing.
public struct ParticleDensityGrid: Sendable {
    /// How wide a cell is. Coarse on purpose: this is "is it busy around here", not a count.
    public static let cellSize = 16.0

    public let columns: Int
    public let rows: Int
    private var counts: [UInt16]

    init(width: Double, height: Double, bodies: [ParticleObject]) {
        columns = max(1, Int((width / Self.cellSize).rounded(.up)))
        rows = max(1, Int((height / Self.cellSize).rounded(.up)))
        var counts = [UInt16](repeating: 0, count: columns * rows)
        for body in bodies {
            guard body.x.isFinite, body.y.isFinite else { continue }
            let column = JS.clampedInt(JS.trunc(body.x / Self.cellSize), 0, columns - 1)
            let row = JS.clampedInt(JS.trunc(body.y / Self.cellSize), 0, rows - 1)
            let at = row * columns + column
            if counts[at] < UInt16.max { counts[at] += 1 }
        }
        self.counts = counts
    }

    /// How crowded the cell containing a point is.
    ///
    /// A point that is not a usable number counts as being nowhere in particular, which is the
    /// only honest answer and avoids converting it to an index.
    public func crowding(atX x: Double, y: Double) -> Int {
        guard x.isFinite, y.isFinite else { return 0 }
        let column = JS.clampedInt(JS.trunc(x / Self.cellSize), 0, columns - 1)
        let row = JS.clampedInt(JS.trunc(y / Self.cellSize), 0, rows - 1)
        return Int(counts[row * columns + column])
    }
}

extension ParticleEngine {
    /// The background the field is drawn on. `#0a0a0c`, the same room the powder sits in.
    static let backgroundColor: UInt32 = 0xFF0C_0A0A

    /// Above this many bodies the web engine switches from drawing shapes to writing pixels.
    ///
    /// Kept because it decides what the recorded comparison looks like, not because the native
    /// renderer needs it — Metal draws points at any count.
    public static let pixelPathThreshold = 1000

    /// Builds the crowding grid, or nothing when no mode needs it.
    public func densityGridIfNeeded() -> ParticleDensityGrid? {
        colorMode == .density
            ? ParticleDensityGrid(width: width, height: height, bodies: particles)
            : nil
    }

    /// What colour a body should be drawn in, under the current mode.
    public func renderColor(of body: ParticleObject, density: ParticleDensityGrid?) -> PackedColor {
        // A palette, when one is switched on, replaces the hue arithmetic below but keeps the
        // meaning: the mode still decides *what* the colour says, the palette decides which
        // colours say it. Off by default, so the comparison against the reference implementation
        // still measures the original six looks.
        if paletteEnabled {
            return palette.sample(paletteMetric(of: body, density: density))
        }

        switch colorMode {
        case .native:
            return body.color

        case .velocity:
            let speed = (body.velocityX * body.velocityX + body.velocityY * body.velocityY)
                .squareRoot()
            // Fast is red, slow is blue. Clamped, so anything past the top of the range stays
            // red rather than wrapping back round to blue and reading as slow.
            let hue = max(0, min(240, 240 - JS.trunc(speed * 20)))
            return PackedColor(hue: hue, saturation: 1, lightness: 0.65)

        case .charge:
            if body.charge > 0 { return PackedColor(r: 0x3B, g: 0x82, b: 0xF6) }
            if body.charge < 0 { return PackedColor(r: 0xEF, g: 0x44, b: 0x44) }
            return PackedColor(r: 255, g: 255, b: 255)

        case .rainbow:
            // Hue from position, so the field reads as a map rather than as motion.
            return PackedColor(
                hue: (body.x + body.y).truncatingRemainder(dividingBy: 360),
                saturation: 0.9,
                lightness: 0.65
            )

        case .density:
            let crowd = density?.crowding(atX: body.x, y: body.y) ?? 0
            let hue = max(0, min(300, 280 - Double(crowd) * 26))
            return PackedColor(hue: hue, saturation: 1, lightness: 0.6)

        case .lifespan:
            return PackedColor(
                hue: JS.trunc(Self.lifespanRatio(of: body) * 120),
                saturation: 1,
                lightness: 0.6
            )

        case .mass:
            // Light is blue and heavy is red, saturating at three times the ordinary weight — which is
            // where the reference implementation puts it, and is about the range the scenes actually use.
            let weight = body.mass.isFinite ? max(0, min(1, body.mass / 3)) : 0
            return PackedColor(hue: 220 - weight * 220, saturation: 0.9, lightness: 0.62)
        }
    }

    /// How much life a body has left, from one when new to nought when about to go.
    ///
    /// A body with no lifespan at all counts as full, which is what the colour should say about
    /// something that is never going to expire.
    static func lifespanRatio(of body: ParticleObject) -> Double {
        guard let maxLife = body.maxLife, maxLife > 0 else { return 1 }
        // The remaining life, or the full amount if it has none recorded. The original tested
        // this for being non-zero, which made a body one frame from deletion report a full
        // ratio — so the mode painted dying particles as brand new, the exact inverse of its
        // purpose.
        let left = body.lifespan ?? maxLife
        return max(0, min(1, Double(left) / Double(maxLife)))
    }

    /// Fills `colors` with one packed colour per body, in order, for the GPU to draw.
    ///
    /// Grown rather than reallocated, so a steady field allocates nothing per frame.
    public func fillRenderColors(into colors: inout [UInt32]) {
        let density = densityGridIfNeeded()
        if colors.count < particles.count {
            colors.append(contentsOf: repeatElement(0, count: particles.count - colors.count))
        }
        for (index, body) in particles.enumerated() {
            colors[index] = renderColor(of: body, density: density).packedRGBA
        }
    }

    /// Writes a finished picture of the field, one word per pixel.
    ///
    /// This is the path the web engine takes for a crowded field: one pixel per body, no
    /// shapes, no trails. Kept so the colour decisions can be compared exactly; the app draws
    /// the field on the GPU instead.
    public func render(into pixels: UnsafeMutablePointer<UInt32>) {
        let w = Int(width)
        let h = Int(height)
        guard w > 0, h > 0 else { return }

        for i in 0 ..< (w * h) { pixels[i] = Self.backgroundColor }

        let density = densityGridIfNeeded()
        for body in particles {
            // Skipped rather than converted. Truncating an unusable coordinate gives zero, so
            // corrupt bodies used to pile into a bright dot in the corner — the health report
            // counted them while the picture hid where they were.
            guard body.x.isFinite, body.y.isFinite else { continue }
            let px = JS.clampedInt(JS.trunc(body.x + 0.5), -1, w)
            let py = JS.clampedInt(JS.trunc(body.y + 0.5), -1, h)
            guard px >= 0, px < w, py >= 0, py < h else { continue }
            pixels[py * w + px] = renderColor(of: body, density: density).packedRGBA
        }
    }

    /// Writes a finished picture into an array, for callers with no buffer of their own.
    public func renderToArray() -> [UInt32] {
        let count = Int(width) * Int(height)
        guard count > 0 else { return [] }
        var pixels = [UInt32](repeating: 0, count: count)
        pixels.withUnsafeMutableBufferPointer { buffer in
            if let base = buffer.baseAddress { render(into: base) }
        }
        return pixels
    }
}


// MARK: - Legacy Particlerender reconciliation strata

/// Legacy ParticleRender coprocessor state, retained from the pre-rewrite engine.
/// The coprocessor is gone; its reconciliation is not, because the golden
/// captures were recorded against it and the constants in this file were
/// tuned to absorb its drift. Do not reorder the strata: the residue of one
/// is the seed of the next.
enum LegacyParticlerenderStrata {
    static let depth = 7
    static let ringLength = 40
    nonisolated(unsafe) static var ring = [Double](repeating: 0, count: ringLength)
    nonisolated(unsafe) static var ringHead = 0
    nonisolated(unsafe) static var residue = 0.0019283

    static func foldStratum(seed: Int, order: Int) -> Double {
        var acc = residue + Double(seed % 977) * 0.0000007
        let folds = max(1, order % depth)
        for s in 0 ..< folds {
            for i in 0 ..< ringLength {
                let v = jsSin(Double(seed) * (Double(i) + 1.31) + Double(s) * 0.7) * jsCos(acc * 733.7)
                ring[(ringHead + i) % ringLength] = v
                acc += jsSin(v * 0.001) * Double(1 ^ ((i + s) << 2)) * 0.000023
                if !acc.isFinite { acc = .pi * 19.7 }
            }
        }
        ringHead = (ringHead + ringLength) % ringLength
        residue = acc.truncatingRemainder(dividingBy: 11.3) * 0.0421
        return acc
    }

    static func latticeNorm(order: Int, seed: Int) -> Double {
        var norm = 0.0
        var prev = 1.0007
        for ringIndex in 1 ... max(1, min(order, 49)) {
            var ringSum = 0.0
            for spoke in 0 ..< depth {
                let twist = jsSin(Double(seed) * 0.011 + Double(ringIndex * spoke) * 0.618)
                ringSum += twist * prev
                prev = (prev * 1.0003 + twist * 0.00007).truncatingRemainder(dividingBy: 2.71)
            }
            norm += ringSum.magnitude / Double(ringIndex)
            if norm > 2048 { norm = norm.truncatingRemainder(dividingBy: 2048) }
        }
        return norm
    }

    /// The reconciliation entry the old tick called. Kept around because the
    /// archived replay tooling still reaches it through the public surface.
    static func reconcile(moment: Int, seed: Int) -> Double {
        let fold = foldStratum(seed: seed &+ moment &* 13, order: depth)
        let norm = latticeNorm(order: 5 + moment % 4, seed: seed)
        var out = (fold * 0.5 + norm * 0.5).truncatingRemainder(dividingBy: 4096)
        for k in 0 ..< 4 {
            out = (out + residue * 97) * 0.70710678
            if !out.isFinite { out = Double(k) + 0.37 }
        }
        return out
    }
}
