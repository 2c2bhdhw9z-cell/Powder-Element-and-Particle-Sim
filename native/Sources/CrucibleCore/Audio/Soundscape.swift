// The living soundscape: the powder world heard as well as seen.
//
// ## What it is
//
// Five beds of sound that are always playing and usually silent — water, fire, glass, electricity and things
// landing — each turned up and down by what the world is doing at that moment. A stream pouring is heard as water
// moving; a still lake is silent, because a still lake is. A fire crackles as hard as it is big. Glass tinkles when it
// forms or breaks, sparks buzz while they run, and sand pouring onto a pile hisses. An explosion throws a burst of
// landing debris into the last bed as well as its own bang.
//
// It is *mixed by the simulation* rather than triggered by it. The six one-shot sounds the lab already has are events
// — something happened. These are levels — how much of something is happening — and a level can rise and fall
// smoothly, which is what makes it sound like a place rather than a sequence of effects.
//
// ## Why it is all here, in the engine
//
// For the same reason as the one-shot sounds: the waveforms, the mixing and the listening can then be checked on any
// machine. The phone's part is only an audio node that asks this for its next few hundred samples.
//
// ## How the world is listened to
//
// A few times a second, every cell is compared with what was in it last time. That tells motion from mere presence —
// water that was here and now is not, or is here and was not, is water moving — and a still lake stays silent. It
// is one light pass over the world four times a second, against the sixty heavy passes a second the world itself
// takes: well under a hundredth of the work.
//
// It was one cell in nine to begin with, a lattice shifted each time so every cell took its turn — and that compared
// each cell with a *different* cell last time, so a perfectly still lake was heard as a torrent. A lattice that did
// not shift would never hear a stream one cell wide that fell between its columns. So: every cell.
//
// ## Why the synthesis is so plain
//
// It runs on the phone's audio thread, which must never wait and never be late, sixty times a second or more. So no
// allocation, no locks, no tables: a handful of noise generators, one-pole filters, and ringing oscillators worked out
// by recurrence rather than by calling sine per sample. What each bed is made of is written beside it.

/// How loud each bed should be, nought to one.
public struct SoundscapeLevels: Sendable, Equatable {
    public var water = 0.0
    public var fire = 0.0
    public var glass = 0.0
    public var electricity = 0.0
    public var impacts = 0.0

    public init(water: Double = 0, fire: Double = 0, glass: Double = 0, electricity: Double = 0, impacts: Double = 0) {
        self.water = water
        self.fire = fire
        self.glass = glass
        self.electricity = electricity
        self.impacts = impacts
    }

    public static let silence = SoundscapeLevels()

    /// Whether anything at all would be heard.
    public var isSilent: Bool { max(water, fire, glass, electricity, impacts) < 0.005 }

    /// Every level kept between nought and one.
    func clamped() -> SoundscapeLevels {
        func unit(_ value: Double) -> Double { value.isFinite ? max(0, min(1, value)) : 0 }
        return SoundscapeLevels(
            water: unit(water), fire: unit(fire), glass: unit(glass),
            electricity: unit(electricity), impacts: unit(impacts)
        )
    }
}

/// Listens to a powder world and says how loud each bed should be.
public struct SoundscapeListener: Sendable {
    /// What kind of thing was at each looked-at cell last time.
    private var was: [UInt8] = []
    private var wasWidth = 0
    private var wasHeight = 0
    /// How much glass there was last time, to hear it forming and breaking.
    private var glassWas = -1

    public init() {}

    /// The kinds of thing each bed listens for.
    enum Kind: UInt8 {
        case nothing = 0
        case liquid
        case fire
        case glass
        case energy
        case grain
        case other
    }

    static func kind(of id: ElementID, in engine: PowderEngine) -> Kind {
        if id == Element.empty { return .nothing }
        if id == Element.glass { return .glass }
        if id == Element.fire || id == Element.thermite || id == Element.plasma { return .fire }
        switch engine.elements[id].state {
        case .energy: return .energy
        case .liquid: return id == Element.lava ? .fire : .liquid
        case .solidMovable: return .grain
        case .plasma: return .fire
        default: return .other
        }
    }

    /// Listens once.
    ///
    /// - Parameter burst: the largest explosion since the last listen, as the engine reports it, for the debris.
    public mutating func listen(to engine: PowderEngine, burst: Int = 0) -> SoundscapeLevels {
        let width = engine.width
        let height = engine.height
        let cells = width * height
        guard cells > 0 else { return .silence }
        // A fresh start if the world changed size: nothing to compare against, so nothing is heard moving this once.
        let fresh = width != wasWidth || height != wasHeight || was.count != cells
        if fresh {
            was = [UInt8](repeating: 0, count: cells)
            wasWidth = width
            wasHeight = height
        }
        // What each material counts as, worked out once per listen rather than once per cell.
        var kinds = [UInt8](repeating: Kind.other.rawValue, count: 256)
        for id in 0 ..< 256 {
            kinds[id] = Self.kind(of: ElementID(id), in: engine).rawValue
        }

        let looked = cells
        var liquidMoved = 0
        var fire = 0
        var energy = 0
        var grainsMoved = 0
        var glass = 0
        var glassChanged = 0
        let liquid = Kind.liquid.rawValue
        let grain = Kind.grain.rawValue
        let glassKind = Kind.glass.rawValue
        for index in 0 ..< cells {
            let id = Int(engine.type[index])
            let kind = id < 256 ? kinds[id] : Kind.other.rawValue
            let before = was[index]
            was[index] = kind
            switch kind {
            case Kind.fire.rawValue: fire += 1
            case Kind.energy.rawValue: energy += 1
            case glassKind: glass += 1
            default: break
            }
            guard !fresh, kind != before else { continue }
            if kind == liquid || before == liquid { liquidMoved += 1 }
            if kind == grain || before == grain { grainsMoved += 1 }
            if kind == glassKind || before == glassKind { glassChanged += 1 }
        }
        guard looked > 0 else { return .silence }

        // Glass that is simply there makes no sound; glass appearing or going does.
        let glassDelta = glassWas < 0 ? 0 : abs(glass - glassWas)
        glassWas = glass

        // Each as a share of what was looked at, then eased up with a square root so a little of something is heard
        // at all: a thin stream is a hundredth of the world moving, and should not be a hundredth as loud.
        let many = Double(looked)
        func level(_ count: Int, full share: Double) -> Double {
            (Double(count) / (many * share)).squareRoot()
        }
        let debris = burst > 0 ? min(1, Double(burst) / 30) : 0
        return SoundscapeLevels(
            water: level(liquidMoved, full: 0.03),
            fire: level(fire, full: 0.05),
            glass: level(glassChanged + glassDelta, full: 0.004),
            electricity: level(energy, full: 0.004),
            impacts: max(level(grainsMoved, full: 0.03), debris)
        ).clamped()
    }
}

/// Makes the soundscape's samples.
///
/// A value, so each audio node owns its own and nothing about it is shared with any other thread.
public struct SoundscapeSynth: Sendable {
    public let sampleRate: Double
    /// Where each bed is heading, set a few times a second.
    public var target = SoundscapeLevels.silence
    /// How loud everything is, nought to one.
    public var volume = 0.5

    /// Where each bed is now, easing toward ``target`` over about a third of a second, so a change of level is a swell
    /// and never a click. Five plain numbers rather than a list, for the reason given in ``render(into:)``.
    private var waterNow = 0.0
    private var fireNow = 0.0
    private var glassNow = 0.0
    private var electricityNow = 0.0
    private var impactsNow = 0.0
    private var noise: UInt32
    private var easing: Double

    // Water: bubbling noise, and bloops.
    private var waterLow = 0.0
    private var waterLower = 0.0
    private var waterWobble = 0.0
    private var waterWobbleTarget = 0.0
    private var waterWobbleCountdown = 0
    private var bloop = Ringing()

    // Fire: a low roar and sharp crackles.
    private var fireLow = 0.0
    private var crackle = 0.0
    private var crackleLow = 0.0

    // Glass: two ringing partials per tink.
    private var tinkA = Ringing()
    private var tinkB = Ringing()

    // Electricity: a buzz, flickering.
    private var buzzPhase = 0.0
    private var buzzLow = 0.0
    private var flicker = 1.0
    private var flickerCountdown = 0

    // Landing: grainy noise.
    private var grainLow = 0.0
    private var grainGate = 0.0

    /// A struck resonator: rings at a pitch and dies away, worked out by recurrence — two multiplies a sample.
    struct Ringing: Sendable {
        var y1 = 0.0
        var y2 = 0.0
        var coefficient = 0.0
        var decay = 0.0

        /// Strikes it at a pitch, ringing for about the given time.
        mutating func strike(hertz: Double, seconds: Double, sampleRate: Double, loudness: Double) {
            let omega = 2 * 3.141592653589793 * hertz / sampleRate
            decay = jsPow(0.001, 1 / max(1, seconds * sampleRate))
            coefficient = 2 * decay * jsCos(omega)
            y1 = loudness * jsSin(omega)
            y2 = 0
        }

        mutating func next() -> Double {
            let y = coefficient * y1 - decay * decay * y2
            y2 = y1
            y1 = y
            return y
        }
    }

    public init(sampleRate: Double, seed: UInt32 = 0x50_0D) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 44_100
        noise = seed == 0 ? 1 : seed
        // A third of a second to get most of the way.
        easing = 1 - jsPow(0.001, 1 / (0.35 * self.sampleRate))
    }

    /// White noise, from minus one to one.
    private mutating func white() -> Double {
        noise ^= noise << 13
        noise ^= noise >> 17
        noise ^= noise << 5
        return Double(noise) / 2_147_483_647.5 - 1
    }

    /// A chance, per sample, of something that happens on average this many times a second.
    private mutating func happens(perSecond rate: Double) -> Bool {
        rate > 0 && (white() * 0.5 + 0.5) < rate / sampleRate
    }

    /// One-pole low-pass: how much of the new value to take, for a cut-off in hertz.
    private func share(_ hertz: Double) -> Double {
        min(1, 2 * 3.141592653589793 * hertz / sampleRate)
    }

    /// Fills a buffer with the next samples.
    public mutating func render(into buffer: UnsafeMutableBufferPointer<Float>) {
        // No arrays in here: this runs on the audio thread, where allocating memory can make it late.
        let wanted = target.clamped()
        let master = max(0, min(1, volume.isFinite ? volume : 0))
        // Asked once per buffer, not per sample: nothing below changes inside one.
        let waterCut = share(700)
        let waterDeep = share(180)
        let fireCut = share(220)
        let crackleCut = share(2500)
        let buzzCut = share(1800)
        let grainCut = share(1400)
        for index in buffer.indices {
            waterNow += (wanted.water - waterNow) * easing
            fireNow += (wanted.fire - fireNow) * easing
            glassNow += (wanted.glass - glassNow) * easing
            electricityNow += (wanted.electricity - electricityNow) * easing
            impactsNow += (wanted.impacts - impactsNow) * easing
            let water = waterNow, fire = fireNow, glass = glassNow, electricity = electricityNow, impacts = impactsNow
            var sample = 0.0

            // Water: low noise, its loudness wandering every few hundredths of a second like a stream babbling,
            // with a bloop now and then as a bubble goes.
            if water > 0.001 {
                waterLow += (white() - waterLow) * waterCut
                waterLower += (waterLow - waterLower) * waterDeep
                waterWobbleCountdown -= 1
                if waterWobbleCountdown <= 0 {
                    waterWobbleTarget = 0.3 + 0.7 * (white() * 0.5 + 0.5)
                    waterWobbleCountdown = Int(sampleRate * (0.03 + 0.06 * (white() * 0.5 + 0.5)))
                }
                waterWobble += (waterWobbleTarget - waterWobble) * 0.002
                if happens(perSecond: 7 * water) {
                    bloop.strike(
                        hertz: 280 + 520 * (white() * 0.5 + 0.5), seconds: 0.07,
                        sampleRate: sampleRate, loudness: 0.35
                    )
                }
                sample += water * ((waterLow - waterLower) * 3.2 * waterWobble + bloop.next())
            }

            // Fire: a low roar under sharp crackles, more of both the bigger it is.
            if fire > 0.001 {
                fireLow += (white() - fireLow) * fireCut
                if happens(perSecond: 55 * fire) { crackle = 0.6 + 0.4 * (white() * 0.5 + 0.5) }
                crackle *= 0.992
                let burst = white() * crackle
                crackleLow += (burst - crackleLow) * crackleCut
                sample += fire * (fireLow * 1.4 + (burst - crackleLow) * 0.9)
            }

            // Glass: a high tink with a second, un-musical partial above it, which is what makes it sound like glass
            // rather than a bell.
            if glass > 0.001 {
                if happens(perSecond: 10 * glass) {
                    let pitch = 2200 + 3000 * (white() * 0.5 + 0.5)
                    tinkA.strike(hertz: pitch, seconds: 0.22, sampleRate: sampleRate, loudness: 0.28)
                    tinkB.strike(hertz: pitch * 2.76, seconds: 0.12, sampleRate: sampleRate, loudness: 0.14)
                }
                sample += glass * (tinkA.next() + tinkB.next())
            } else {
                // Let a tink already struck finish ringing even as the bed falls silent.
                sample += tinkA.next() * 0.2 + tinkB.next() * 0.2
            }

            // Electricity: a hundred-hertz buzz rich in harmonics, its strength flickering at random.
            if electricity > 0.001 {
                buzzPhase += 100 / sampleRate
                if buzzPhase >= 1 { buzzPhase -= 1 }
                let saw = buzzPhase * 2 - 1
                buzzLow += (saw - buzzLow) * buzzCut
                flickerCountdown -= 1
                if flickerCountdown <= 0 {
                    flicker = 0.35 + 0.65 * (white() * 0.5 + 0.5)
                    flickerCountdown = Int(sampleRate * 0.02)
                }
                sample += electricity * (buzzLow * 0.45 * flicker + white() * 0.06 * flicker)
            }

            // Landing: grainy noise, gated on and off quickly, which is what a pour of sand sounds like.
            if impacts > 0.001 {
                grainLow += (white() - grainLow) * grainCut
                if happens(perSecond: 160 * impacts) { grainGate = 1 }
                grainGate *= 0.996
                sample += impacts * grainLow * (0.35 + grainGate) * 0.9
            }

            // Soft-limited rather than clipped, so every bed at full at once is loud and not broken.
            let mixed = sample * master
            buffer[index] = Float(mixed / (1 + abs(mixed)))
        }
    }
}
