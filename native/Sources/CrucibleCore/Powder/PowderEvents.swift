// The four set-piece events: a meteor, a blast, a surge of water, and a deep freeze.
//
// Ported from web/src/sim/powder-events.ts.
//
// Those rules used to live inside the web version's canvas component, tangled up with sound
// calls and screen-shake state, where nothing could test them and nothing could compare them
// against this. Extracting them on that side is what made this port checkable, and the two are
// now compared cell for cell like everything else.

/// One of the four set-piece events.
public enum PowderEventID: String, CaseIterable, Sendable, Hashable, Codable {
    /// A ball of lava and fire dropped from above, detonating when it lands.
    case meteor
    /// One large explosion at the centre, then two flanking it.
    case blast
    /// A wall of water down the left side, already moving.
    case surge
    /// Everything chilled at once: liquids to ice, lava to stone.
    case freeze
}

/// A noise an event wants made. The engine does not make it.
public enum PowderEventSound: String, Sendable, Hashable, Codable {
    case meteor
    case explosion
}

/// One explosion, as an event schedules it.
public struct PowderEventBlast: Sendable, Hashable, Codable {
    public var x: Int
    public var y: Int
    public var radius: Int
    public var force: Double
    public var heat: Double

    public init(x: Int, y: Int, radius: Int, force: Double, heat: Double) {
        self.x = x
        self.y = y
        self.radius = radius
        self.force = force
        self.heat = heat
    }
}

/// The delayed second half of an event.
///
/// The delay is part of the event's definition rather than a detail of how it is presented: a
/// meteor that detonates the instant it appears does not read as a meteor. So it is described
/// here and the app runs the timer.
public struct PowderEventFollowUp: Sendable, Hashable, Codable {
    public var delaySeconds: Double
    public var blasts: [PowderEventBlast]
    public var shake: Double
    public var sound: PowderEventSound?
    public var soundIntensity: Double
}

/// What accompanied the immediate half of an event, and what is still to come.
///
/// Shaking the screen and making a noise are not the simulation's business — the same division
/// the engine already makes for explosions through ``PowderEngine/onBurst`` — so they are
/// reported for the caller to act on.
public struct PowderEventStart: Sendable, Hashable, Codable {
    public var shake: Double
    public var sound: PowderEventSound?
    public var soundIntensity: Double
    public var followUp: PowderEventFollowUp?
}

extension PowderEngine {
    /// Runs the immediate half of an event.
    ///
    /// - Returns: what should accompany it, including the delayed half where it has one.
    @discardableResult
    public func start(_ event: PowderEventID) -> PowderEventStart {
        switch event {
        case .meteor: return startMeteor()
        case .blast: return startBlast()
        case .surge: return startSurge()
        case .freeze: return startFreeze()
        }
    }

    /// Runs the delayed half of an event.
    public func finish(_ followUp: PowderEventFollowUp) {
        for blast in followUp.blasts {
            triggerExplosion(
                centerX: blast.x,
                centerY: blast.y,
                radius: blast.radius,
                shockwaveForce: blast.force,
                maxHeat: blast.heat
            )
        }
    }

    // MARK: Meteor

    private func startMeteor() -> PowderEventStart {
        let centerX = width / 2
        let radius = 10
        // Dropped at a fixed depth from the top rather than at the top edge, so the ball is
        // fully inside the world and falls as one mass.
        let centerY = 14

        for dy in -radius ... radius {
            for dx in -radius ... radius {
                // A disc, compared without a square root.
                if dx * dx + dy * dy > radius * radius { continue }
                let x = centerX + dx
                let y = centerY + dy
                // Checked *before* the draw below. A meteor in a narrow world must consume
                // exactly one random number per cell it can actually fill, or every later
                // decision in the world shifts — which the recorded comparison would catch as a
                // mismatched draw count.
                guard isValid(x, y) else { continue }
                setElement(x, y, rng.next() < 0.8 ? Element.lava : Element.fire, temp: 2800)
                velocityY[index(x, y)] = 18
            }
        }

        return PowderEventStart(
            shake: 16,
            sound: .meteor,
            soundIntensity: 1,
            followUp: PowderEventFollowUp(
                delaySeconds: 0.18,
                // Placed at a fixed fraction of the world's height rather than wherever the
                // material actually reached, because it may not reach anywhere — it can land on
                // a ceiling someone built. Fixing it up front means the event always reads the
                // same.
                blasts: [
                    PowderEventBlast(
                        x: centerX,
                        y: Int((Double(height) * 0.65).rounded(.down)),
                        radius: 28,
                        force: 18,
                        heat: 3000
                    )
                ],
                shake: 22,
                sound: .explosion,
                soundIntensity: 2
            )
        )
    }

    // MARK: Blast

    private func startBlast() -> PowderEventStart {
        let centerX = width / 2
        let centerY = height / 2
        triggerExplosion(
            centerX: centerX,
            centerY: centerY,
            radius: 36,
            shockwaveForce: 22,
            maxHeat: 3500
        )

        return PowderEventStart(
            shake: 24,
            sound: .explosion,
            soundIntensity: 3,
            followUp: PowderEventFollowUp(
                delaySeconds: 0.12,
                blasts: [
                    PowderEventBlast(x: centerX - 22, y: centerY - 14, radius: 22, force: 16, heat: 2800),
                    PowderEventBlast(x: centerX + 22, y: centerY + 14, radius: 22, force: 16, heat: 2800),
                ],
                shake: 16,
                sound: nil,
                soundIntensity: 1
            )
        )
    }

    // MARK: Surge

    private func startSurge() -> PowderEventStart {
        let startY = Int((Double(height) * 0.28).rounded(.down))
        let endX = min(28, width - 4)
        let endY = height - 2

        // Written as a pair of while loops rather than over ranges. In a world too small or too
        // narrow for the band, the bounds cross over — and a Swift range whose end is below its
        // start is a crash, where JavaScript's loop simply does not run. A surge in a thirty-cell
        // world should do nothing, not bring the app down.
        var y = startY
        while y < endY {
            var x = 2
            while x < endX {
                setElement(x, y, Element.water, temp: 12)
                velocityX[index(x, y)] = 14
                x += 1
            }
            y += 1
        }

        return PowderEventStart(shake: 0, sound: nil, soundIntensity: 1, followUp: nil)
    }

    // MARK: Freeze

    private func startFreeze() -> PowderEventStart {
        // Writes the grid directly rather than going through `setElement`, which is deliberate
        // and load-bearing: it leaves each cell's lifetime and momentum alone, so a freeze stops
        // a world without also resetting everything that was moving through it.
        let chilled = JS.toFloat32(-200)
        for i in 0 ..< cellCount {
            let cellType = type[i]
            // Air has no temperature worth setting, and bedrock is the world's container.
            if cellType == Element.empty || cellType == Element.bedrock { continue }
            temperature[i] = chilled
            // Separate tests rather than a chain, matching the original. Both read the element
            // as it was before either could have changed it, so nothing is converted twice.
            if cellType == Element.water || cellType == Element.acid
                || cellType == Element.oil || cellType == Element.saltWater
            {
                type[i] = Element.ice
            }
            if cellType == Element.lava {
                type[i] = Element.stone
            }
        }

        return PowderEventStart(shake: 0, sound: nil, soundIntensity: 1, followUp: nil)
    }
}
