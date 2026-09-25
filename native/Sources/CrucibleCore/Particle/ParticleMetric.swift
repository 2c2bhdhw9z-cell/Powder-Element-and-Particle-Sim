/// Turning a property of a particle into a number between nought and one.
///
/// This is the other half of ``ParticlePaletteSpec``. A palette answers "which colours"; a metric
/// answers "how far along them does this particle sit". Keeping them apart means any of the six
/// meanings can drive any of the ramps, instead of each meaning owning a hard-coded set of hues.
///
/// Each metric needs a point at which it saturates, because a colour ramp has an end and speed does
/// not. Those saturation points are chosen to match the hue arithmetic they replace, so switching a
/// palette on does not also silently change what counts as "fast" or "crowded" — see the notes on
/// each one.

extension ParticleEngine {
    /// The speed at which the speed metric reaches the end of the ramp.
    ///
    /// Twelve, because that is where the hue version already saturated: it ran the hue from 240
    /// degrees down by twenty per unit of speed and clamped at nought, which is reached at exactly
    /// twelve. So a field that looked "all red" before looks "all of the last colour" now, and the
    /// two agree about what fast means.
    public static let paletteSpeedCeiling = 12.0

    /// The crowding at which the crowding metric reaches the end of the ramp.
    ///
    /// Forty bodies in a sixteen-unit cell, taken from the reference implementation. The hue
    /// version saturated at eleven, which on a busy field meant almost everything sat at the end of
    /// the range and the mode stopped distinguishing anything. Forty spreads it out.
    public static let paletteCrowdingCeiling = 40.0

    /// Where along the ramp a body sits, under the current mode.
    public func paletteMetric(of body: ParticleObject, density: ParticleDensityGrid?) -> Double {
        switch colorMode {
        case .native:
            // The body's own colour cannot be expressed as a position along a ramp, so this mode
            // means something different with a palette on: a fixed position per body, giving a
            // field of mixed colours drawn from the chosen ramp. That is the reference
            // implementation's default look.
            return Self.stablePhase(forIdentifier: body.id)

        case .velocity:
            let speed = (body.velocityX * body.velocityX + body.velocityY * body.velocityY)
                .squareRoot()
            guard speed.isFinite else { return 0 }
            return max(0, min(1, speed / Self.paletteSpeedCeiling))

        case .charge:
            // Neutral sits in the middle of the ramp, so a ramp that runs cool to warm reads the
            // way the blue-white-red version did.
            guard body.charge.isFinite else { return 0.5 }
            return 0.5 + max(-0.5, min(0.5, body.charge * 0.5))

        case .rainbow:
            // Distance from the centre of the world, over the radius of the largest circle that
            // fits in it. The hue version swept diagonally across the field, which reads as a
            // gradient laid over the scene; radial reads as belonging to it, and every scene in
            // this half of the app is built around a centre.
            guard body.x.isFinite, body.y.isFinite else { return 0 }
            let dx = body.x - width * 0.5
            let dy = body.y - height * 0.5
            let reach = max(1e-4, 0.5 * min(width, height))
            return max(0, min(1, (dx * dx + dy * dy).squareRoot() / reach))

        case .density:
            let crowd = Double(density?.crowding(atX: body.x, y: body.y) ?? 0)
            return max(0, min(1, crowd / Self.paletteCrowdingCeiling))

        case .lifespan:
            return Self.lifespanRatio(of: body)
        }
    }

    /// A fixed number between nought and one for a given body, the same every time.
    ///
    /// Bodies carry no colour seed of their own, only an identifier, so the number is mixed out of
    /// that identifier. Mixed rather than used directly: identifiers are handed out in order, and a
    /// palette driven by a counter paints the field in bands that march across it as bodies spawn,
    /// which looks like a fault. A hash scatters them.
    ///
    /// This is the standard avalanche mix — multiply, shift, exclusive-or, twice — which spreads a
    /// change in any single bit of the input across all bits of the output. Being a pure function of
    /// the identifier, a saved scene reloads with the same colours.
    public static func stablePhase(forIdentifier identifier: Int) -> Double {
        var x = UInt32(truncatingIfNeeded: identifier) &+ 0x9E37_79B9
        x ^= x >> 16
        x = x &* 0x85EB_CA6B
        x ^= x >> 13
        x = x &* 0xC2B2_AE35
        x ^= x >> 16
        return Double(x) / 4_294_967_296.0
    }
}

// MARK: - The swarm

extension ParticleEngine {
    /// Whether the swarm's colours change from one frame to the next under the current settings.
    ///
    /// Speed and crowding move; a fixed phase per body and a position in a still world do not. This
    /// is what decides whether the recolouring pass has to run every frame or only when something
    /// changes, and with up to a million bodies that distinction is the whole cost.
    public var swarmColorsAreDynamic: Bool {
        guard paletteEnabled else { return false }
        switch colorMode {
        case .velocity, .density: return true
        case .native, .charge, .rainbow, .lifespan: return false
        }
    }

    /// Paints every swarm body from the palette.
    ///
    /// The swarm has no charge, no lifetime and no colour of its own worth reading, so the three
    /// modes that need those fall back to a fixed phase per body — which is the look those modes
    /// produce for the swarm anyway, since every swarm body is identical in all three respects.
    ///
    /// Takes a baked table rather than sampling the palette per body: sampling walks a list of
    /// stops, and at a million bodies that walk is the cost of the pass. Written against the
    /// swarm's buffers directly, for the same reason — a closure per body is not free at this size.
    public func recolorSwarm(using lookup: [UInt32]) {
        let bodies = swarm.count
        guard !lookup.isEmpty, bodies > 0 else { return }
        let last = lookup.count - 1
        let scale = Float(last)
        let positions = swarm.positions
        let velocities = swarm.velocities
        let colors = swarm.colors

        lookup.withUnsafeBufferPointer { table in
            @inline(__always)
            func entry(_ position: Float) -> UInt32 {
                guard position.isFinite else { return table[0] }
                let index = Int((max(0, min(1, position)) * scale).rounded())
                return table[max(0, min(last, index))]
            }

            switch colorMode {
            case .velocity:
                let ceiling = Float(Self.paletteSpeedCeiling)
                for i in 0 ..< bodies {
                    let pair = i * 2
                    let vx = velocities[pair]
                    let vy = velocities[pair + 1]
                    colors[i] = entry((vx * vx + vy * vy).squareRoot() / ceiling)
                }

            case .rainbow:
                let centreX = Float(width * 0.5)
                let centreY = Float(height * 0.5)
                let reach = Float(max(1e-4, 0.5 * min(width, height)))
                for i in 0 ..< bodies {
                    let pair = i * 2
                    let dx = positions[pair] - centreX
                    let dy = positions[pair + 1] - centreY
                    colors[i] = entry((dx * dx + dy * dy).squareRoot() / reach)
                }

            case .density:
                // Crowding for the swarm means the same thing it means for the objects, but the
                // objects' grid is built from the object list. Rather than build a second grid for
                // a million bodies every frame, slowness stands in: what makes a swarm cell
                // crowded is bodies piling up and losing speed, so the two agree closely on a busy
                // field. Stated here rather than hidden, because it is a substitution, not an
                // equality.
                let ceiling = Float(Self.paletteSpeedCeiling)
                for i in 0 ..< bodies {
                    let pair = i * 2
                    let vx = velocities[pair]
                    let vy = velocities[pair + 1]
                    colors[i] = entry(1 - min(1, (vx * vx + vy * vy).squareRoot() / ceiling))
                }

            case .native, .charge, .lifespan:
                // No charge, no lifetime, and no colour of its own worth reading — so all three
                // become a fixed position per body, which is what those modes would show for a
                // swarm anyway, every body being identical in all three respects.
                for i in 0 ..< bodies {
                    colors[i] = entry(Float(Self.stablePhase(forIdentifier: i)))
                }
            }
        }
    }

    /// Paints the swarm from the current palette, baking the table first.
    public func recolorSwarm() {
        guard paletteEnabled else { return }
        recolorSwarm(using: palette.bakeLookup())
    }
}
